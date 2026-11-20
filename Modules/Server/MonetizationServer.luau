--!strict
--[[
    MonetizationServer
    ------------------
    The ONLY place purchases are granted.

    - Game passes: ownership checked on join (UserOwnsGamePassAsync) and
      updated live on PromptGamePassPurchaseFinished. Mon:GetPasses(player)
      feeds JetStats / Economy (2x cash, VIP XP).
    - Developer products: MarketplaceService.ProcessReceipt. Idempotent:
      each PurchaseId is recorded in the profile (ProcessedPurchases) inside
      the same mutation as the grant, and PurchaseGranted is only returned
      once the profile holds both. A receipt is never granted twice.
    - Analytics: prompt / success / fail / cancel for every product.

    C->S MonRequest { a="Prompted", key } (analytics only)
    S->C MonEvent   { a="Passes", passes } | { a="Granted", key } | { a="OfferStarter" }
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local MonetizationConfig = require(ReplicatedStorage.Config.MonetizationConfig)
local FlightConfig = require(ReplicatedStorage.Config.FlightConfig)
local CurrencyConfig = require(ReplicatedStorage.Config.CurrencyConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)
local mCurrency = require(ServerStorage.BCDKServer.SMCurrency)

local Mon = ModuleUtil.New({
	OnPassesChanged = Instance.new("BindableEvent"), -- (player, passes)
})
local oEvent = Remote:GetEvent("MonEvent")
local oRequest = Remote:GetEvent("MonRequest")
local tFreeReviveOffered: { [Player]: number? } = {}
local tFreeReviveUsed: { [Player]: boolean } = {}
local tPasses: { [Player]: { [string]: boolean } } = {}
local tBountyShield: { [Player]: boolean } = {}
local tDeaths: { [Player]: number } = {}
local tOffered: { [Player]: boolean } = {}
local oLimiter = ModuleUtil.RateLimiter(10, 5)

local tProductById: { [number]: string } = {}
for k, p in pairs(MonetizationConfig.Products) do tProductById[p.Id] = k end
local tPassById: { [number]: string } = {}
for k, p in pairs(MonetizationConfig.Passes) do tPassById[p.Id] = k end

local Analytics: any, Economy: any, Combat: any, Flight: any

function Mon.GetPasses(self, oPlayer: Player): { [string]: boolean }
	return tPasses[oPlayer] or {}
end

function Mon.ConsumeBountyShield(self, oPlayer: Player): boolean
	if tBountyShield[oPlayer] then
		tBountyShield[oPlayer] = nil
		oPlayer:SetAttribute("BountyShield", nil)
		return true
	end
	return false
end

local function refreshPasses(oPlayer: Player)
	local t = {}
	for k, p in pairs(MonetizationConfig.Passes) do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, oPlayer.UserId, p.Id)
		t[k] = ok and owns == true
	end
	tPasses[oPlayer] = t
	-- passes that unlock jets
	if t.WraithX then
		Economy:SetProfileKey(oPlayer, "OwnedJets", function(v) v = v or {}; v.WraithX = true; return v end)
	end
	if t.VIP then oPlayer:SetAttribute("VIP", true) end
	oEvent:FireClient(oPlayer, { a = "Passes", passes = t })
	Mon.OnPassesChanged:Fire(oPlayer, t)
end

-- Apply a product's grant. Called inside the profile-recorded path only.
local function grant(oPlayer: Player, sKey: string): boolean
	local p = MonetizationConfig.Products[sKey]
	if not p then return false end
	local g = p.Grant
	if p.OneTime then
		local once = mProfile:GetAsync(oPlayer, "OneTimeProducts") or {}
		if once[sKey] then
			-- already owned (shouldn't be prompted); convert to its cash value so nobody loses Robux
			mCurrency:Add(oPlayer, CurrencyConfig.eCurrency.Cash, (g.Cash or 0) + 6000)
			return true
		end
		Economy:SetProfileKey(oPlayer, "OneTimeProducts", function(v) v = v or {}; v[sKey] = true; return v end)
	end
	if g.Jet then
		Economy:SetProfileKey(oPlayer, "OwnedJets", function(v) v = v or {}; v[g.Jet] = true; return v end)
	end
	if g.Cash then
		mCurrency:Add(oPlayer, CurrencyConfig.eCurrency.Cash, g.Cash)
		Analytics:Economy(oPlayer, "Source", "Cash", g.Cash, mProfile:GetAsync(oPlayer, "Cash") or 0, "IAP", sKey)
	end
	if g.Rearm then
		Combat:Rearm(oPlayer)
		Remote:GetEvent("FlightEvent"):FireClient(oPlayer, { a = "Resupplied", where = "Purchase" }) -- client refuel path
	end
	if g.BountyShield then
		tBountyShield[oPlayer] = true
		oPlayer:SetAttribute("BountyShield", true)
	end
	if g.Revive then
		-- back in the air where you went down, with the cash you lost restored
		if not Flight:Revive(oPlayer) then
			mCurrency:Add(oPlayer, CurrencyConfig.eCurrency.Cash, MonetizationConfig.ReviveFallbackCash)
			oEvent:FireClient(oPlayer, { a = "Granted", key = "ReviveFallback" })
		end
	end
	return true
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local oPlayer = Players:GetPlayerByUserId(info.PlayerId)
	if not oPlayer then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local processed = mProfile:GetAsync(oPlayer, "ProcessedPurchases")
	if processed == nil then return Enum.ProductPurchaseDecision.NotProcessedYet end -- profile not loaded yet
	if processed[info.PurchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local sKey = tProductById[info.ProductId]
	if not sKey then
		warn("[Mon] unknown product", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(grant, oPlayer, sKey)
	if not ok then
		warn("[Mon] grant failed", sKey, err)
		Analytics:Log(oPlayer, "purchase_failed", { sku = sKey })
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- record the receipt (kept to the last 200 to bound profile size)
	Economy:SetProfileKey(oPlayer, "ProcessedPurchases", function(v)
		v = v or {}
		v[info.PurchaseId] = os.time()
		local n = 0
		for _ in pairs(v) do n += 1 end
		if n > 200 then
			local oldestK, oldestT = nil, math.huge
			for k, t in pairs(v) do if t < oldestT then oldestK, oldestT = k, t end end
			if oldestK then v[oldestK] = nil end
		end
		return v
	end)
	Analytics:Log(oPlayer, "shop_purchase_success", { sku = sKey })
	oEvent:FireClient(oPlayer, { a = "Granted", key = sKey })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Mon.StartAsync(self)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Combat = require(ServerStorage.ServerModules.CombatServer)
	Flight = require(ServerStorage.ServerModules.FlightServer)

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(oPlayer: Player, nId: number, bPurchased: boolean)
		local k = tPassById[nId]
		if not k then return end
		if bPurchased then
			tPasses[oPlayer] = tPasses[oPlayer] or {}
			tPasses[oPlayer][k] = true
			if k == "WraithX" then
				Economy:SetProfileKey(oPlayer, "OwnedJets", function(v) v = v or {}; v.WraithX = true; return v end)
			end
			if k == "VIP" then oPlayer:SetAttribute("VIP", true) end
			oEvent:FireClient(oPlayer, { a = "Passes", passes = tPasses[oPlayer] })
			Mon.OnPassesChanged:Fire(oPlayer, tPasses[oPlayer])
			oEvent:FireClient(oPlayer, { a = "Granted", key = k })
			Analytics:Log(oPlayer, "shop_purchase_success", { sku = k })
		else
			Analytics:Log(oPlayer, "purchase_cancelled", { sku = k })
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(nUserId: number, nId: number, bPurchased: boolean)
		local p = Players:GetPlayerByUserId(nUserId)
		if p and not bPurchased and tProductById[nId] then
			Analytics:Log(p, "purchase_cancelled", { sku = tProductById[nId] })
		end
	end)

	oRequest:OnServerEvent(function(oPlayer: Player, t: any)
		if typeof(t) ~= "table" or not oLimiter:Check(oPlayer) then return end
		if t.a == "Prompted" and typeof(t.key) == "string" and (MonetizationConfig.Passes[t.key] or MonetizationConfig.Products[t.key]) then
			Analytics:Log(oPlayer, "shop_purchase_prompt", { sku = t.key })
		elseif t.a == "FreeRevive" then
			local untilT = tFreeReviveOffered[oPlayer]
			if untilT and os.clock() <= untilT and not tFreeReviveUsed[oPlayer] then
				tFreeReviveOffered[oPlayer] = nil
				if Flight:Revive(oPlayer) then
					tFreeReviveUsed[oPlayer] = true
					Analytics:Log(oPlayer, "revive_free")
					oEvent:FireClient(oPlayer, { a = "Granted", key = "ReviveHere" })
				end
			end
		end
	end)

	-- STARTER ACE offer right after a high (double kill or reaching rank 3), once per session, if not owned.
	-- (it used to follow the 3rd death: 119 offers, 0 buys - nobody buys at their lowest moment)
	local function offerStarterOnHigh(p: Player)
		if tOffered[p] or not p.Parent then return end
		local once = mProfile:GetAsync(p, "OneTimeProducts") or {}
		if once.StarterAce then return end
		tOffered[p] = true
		task.delay(2.5, function() if p.Parent then oEvent:FireClient(p, { a = "OfferStarter" }) end end)
	end
	Economy.OnMultiKill.Event:Connect(function(p: Player, n: number) if n >= 2 then offerStarterOnHigh(p) end end)
	Economy.OnRankUp.Event:Connect(function(p: Player, r: number) if r >= 3 then offerStarterOnHigh(p) end end)

	-- starter bundle offer on the Nth shoot-down (once per session, only if not owned)
	Flight.OnJetDestroyed.Event:Connect(function(oPlayer: Player, sCause: string)
		-- REVIVE HERE: an impulse offer on the death screen after a real sortie
		local s = Flight:GetSortie(oPlayer)
		if s and sCause ~= "reset" and sCause ~= "eject" and os.clock() - (s.LaunchedAt or 0) >= MonetizationConfig.ReviveMinFlight
			and MonetizationConfig.Products.ReviveHere.Id ~= 0 then
			-- rookies get one FREE revive per session instead of a Robux prompt (half of all leavers quit
			-- within 25 s of a death; a paywall at that moment pushed them out)
			local ls = oPlayer:FindFirstChild("leaderstats")
			local rv = ls and ls:FindFirstChild("Rank")
			local rank = if rv then tonumber((rv :: any).Value) or 1 else 1
			local free = rank <= FlightConfig.RookieMaxRank and not tFreeReviveUsed[oPlayer]
			tFreeReviveOffered[oPlayer] = if free then os.clock() + MonetizationConfig.ReviveWindow else nil
			oEvent:FireClient(oPlayer, { a = "OfferRevive", secs = MonetizationConfig.ReviveWindow, free = free })
		end
		tDeaths[oPlayer] = (tDeaths[oPlayer] or 0) + 1
		if false then -- (starter offer now follows a high, see offerStarterOnHigh below)
			local once = mProfile:GetAsync(oPlayer, "OneTimeProducts") or {}
			if not once.StarterAce then
				tOffered[oPlayer] = true
				task.delay(2.5, function() oEvent:FireClient(oPlayer, { a = "OfferStarter" }) end)
			end
		end
	end)
end

function Mon.InitProfileAsync(self, oPlayer: Player)
	task.spawn(refreshPasses, oPlayer)
end

function Mon.PlayerRemoving(self, oPlayer: Player)
	tFreeReviveOffered[oPlayer] = nil
	tFreeReviveUsed[oPlayer] = nil
	tPasses[oPlayer] = nil
	tBountyShield[oPlayer] = nil
	tDeaths[oPlayer] = nil
	tOffered[oPlayer] = nil
end

return Mon
