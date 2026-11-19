--!strict
--[[
    EconomyServer
    -------------
    Rewards, Bank It and the hangar shop. Server-only authority over Cash
    (BCDK SMCurrency) and Ace XP (BCDK SMXP).

    Bank It: kill/combat Cash is held as Sortie Cash until the player touches
    down on the carrier (x BankBonus). Shot down -> keep KeepOnDeath. Mission
    and onboarding rewards bank immediately.

    Remotes
      S->C EconomyEvent { a="Sortie", v } | { a="Toast", text, cash, xp, kind } | { a="Banked", v } | { a="RankUp", rank }
      C<->S Shop (RemoteFunction) { a="BuyJet", jet } | { a="Equip", jet } | { a="Upgrade", jet, track } -> { ok, err? }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local CurrencyConfig = require(ReplicatedStorage.Config.CurrencyConfig)
local JetConfig = require(ReplicatedStorage.Config.JetConfig)
local XPConfig = require(ReplicatedStorage.Config.XPConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)
local mCurrency = require(ServerStorage.BCDKServer.SMCurrency)
local mXP = require(ServerStorage.BCDKServer.SMXP)

local Economy = ModuleUtil.New({
	OnBanked = Instance.new("BindableEvent"),
	OnMultiKill = Instance.new("BindableEvent"), -- (player, chainLength)
	OnXP = Instance.new("BindableEvent"), -- (player, amount) every XP award (season track)
	OnReward = Instance.new("BindableEvent"), -- (player, rewardKey, cash) every Economy:Reward (badges, prompts)
	OnRankUp = Instance.new("BindableEvent"), -- (player, newRank)
	OnJetUnlocked = Instance.new("BindableEvent"), -- (player, jetId)
})

local oEvent = Remote:GetEvent("EconomyEvent")
local oShop = Remote:GetFunction("Shop")
local tSortie: { [Player]: number } = {}
local tShopLimiter = ModuleUtil.RateLimiter(8, 2)

local Analytics: any
local function analytics()
	Analytics = Analytics or require(ServerStorage.ServerModules.AnalyticsServer)
	return Analytics
end

local function cash(oPlayer: Player): number
	return mProfile:GetAsync(oPlayer, "Cash") or 0
end

local function rank(oPlayer: Player): number
	return XPConfig.fXPToLevel(mProfile:GetAsync(oPlayer, "XP") or 0)
end

local function cashMult(oPlayer: Player): number
	local m = 1
	local ok, Mon = pcall(require, ServerStorage.ServerModules:FindFirstChild("MonetizationServer") :: any)
	if ok and Mon and Mon.GetPasses then
		local p = Mon:GetPasses(oPlayer)
		if p.DoubleCash then m *= 2 end
	end
	local ok2, Squad = pcall(require, ServerStorage.ServerModules:FindFirstChild("SocialServer") :: any)
	if ok2 and Squad and Squad.SquadSize then
		m *= EconomyConfig.SquadMult[math.clamp(Squad:SquadSize(oPlayer), 1, 4)] or 1
	end
	return m
end

local function addXP(oPlayer: Player, nXP: number, sSource: string)
	if nXP <= 0 then return end
	local before = rank(oPlayer)
	local ok, Mon = pcall(require, ServerStorage.ServerModules:FindFirstChild("MonetizationServer") :: any)
	if ok and Mon and Mon.GetPasses and Mon:GetPasses(oPlayer).VIP then nXP = math.floor(nXP * 1.1) end
	mXP:Add(oPlayer, nXP)
	Economy.OnXP:Fire(oPlayer, nXP)
	local after = rank(oPlayer)
	if after > before then
		oEvent:FireClient(oPlayer, { a = "RankUp", rank = after })
		Economy.OnRankUp:Fire(oPlayer, after)
		analytics():Progression(oPlayer, "AceRank", after)
	end
end

local function addCash(oPlayer: Player, nCash: number, sSku: string, sTx: string)
	if nCash <= 0 then return end
	mCurrency:Add(oPlayer, CurrencyConfig.eCurrency.Cash, nCash)
	analytics():Economy(oPlayer, "Source", "Cash", nCash, cash(oPlayer), sTx, sSku)
end

--[[ Grant a reward from EconomyConfig.Rewards.
     opts.Mult: extra multiplier (Nerve, Revenge, bounty...)
     opts.Bank: true = straight to Cash (missions/onboarding), else Sortie Cash
     opts.Label: toast text override
     opts.Cash: absolute cash override (bounties) ]]
function Economy.Reward(self, oPlayer: Player, sKey: string, opts: { Mult: number?, Bank: boolean?, Label: string?, Cash: number? }?)
	local r = EconomyConfig.Rewards[sKey]
	local o = opts or {}
	local nCash = math.floor(((o.Cash or (r and r.Cash) or 0)) * (o.Mult or 1) * cashMult(oPlayer))
	local nXP = math.floor(((r and r.XP) or 0) * (o.Mult or 1))
	if o.Bank then
		addCash(oPlayer, nCash, sKey, "Gameplay")
	elseif nCash > 0 then
		tSortie[oPlayer] = (tSortie[oPlayer] or 0) + nCash
		oEvent:FireClient(oPlayer, { a = "Sortie", v = tSortie[oPlayer] })
	end
	addXP(oPlayer, nXP, sKey)
	oEvent:FireClient(oPlayer, { a = "Toast", text = o.Label or sKey, cash = nCash, xp = nXP, kind = sKey })
	self.OnReward:Fire(oPlayer, sKey, nCash)
end

function Economy.Bank(self, oPlayer: Player)
	local v = tSortie[oPlayer] or 0
	if v <= 0 then return end
	local banked = math.floor(v * EconomyConfig.BankBonus)
	tSortie[oPlayer] = 0
	addCash(oPlayer, banked, "BankIt", "Gameplay")
	oEvent:FireClient(oPlayer, { a = "Banked", v = banked })
	oEvent:FireClient(oPlayer, { a = "Sortie", v = 0 })
	analytics():Log(oPlayer, "bank", { amount = banked })
	analytics():LogOnce(oPlayer, "session_first_bank")
	self.OnBanked:Fire(oPlayer, banked)
end

-- REVIVE HERE: give back what the last shoot-down cost you (as banked cash)
local tLost: { [Player]: { Amount: number, T: number } } = {}
function Economy.RestoreLoss(self, oPlayer: Player)
	local l = tLost[oPlayer]
	tLost[oPlayer] = nil
	if l and l.Amount > 0 and os.clock() - l.T < 60 then
		addCash(oPlayer, l.Amount, "Revive", "IAP")
		oEvent:FireClient(oPlayer, { a = "Toast", text = `REVIVED: +{l.Amount} lost cash restored`, cash = 0, xp = 0, kind = "Revive" })
	end
end

function Economy.LoseOnDeath(self, oPlayer: Player, bKeepAll: boolean?, bEjected: boolean?)
	local v = tSortie[oPlayer] or 0
	if v <= 0 then return end
	local keep = if bEjected then EconomyConfig.KeepOnEject else EconomyConfig.KeepOnDeath
	local kept = if bKeepAll then v else math.floor(v * keep)
	tLost[oPlayer] = { Amount = v - kept, T = os.clock() }
	tSortie[oPlayer] = 0
	addCash(oPlayer, kept, "SortieKept", "Gameplay")
	oEvent:FireClient(oPlayer, { a = "Sortie", v = 0 })
	oEvent:FireClient(oPlayer, { a = "Toast", text = `Kept {kept} of {v} Sortie Cash`, cash = 0, xp = 0, kind = "Kept" })
end

function Economy.Spend(self, oPlayer: Player, nAmount: number, sSku: string): boolean
	if nAmount <= 0 then return true end
	local ok = mCurrency:Remove(oPlayer, CurrencyConfig.eCurrency.Cash, nAmount)
	if ok then analytics():Economy(oPlayer, "Sink", "Cash", nAmount, cash(oPlayer), "Shop", sSku) end
	return ok
end

-- Profile helpers (replicated to the client through the "HangarReplica")
local HANGAR_TOKEN = "HangarReplica"
local HANGAR_KEYS = { "OwnedJets", "EquippedJet", "EquippedPaint", "Upgrades", "FTUE", "Stats", "Season", "Trails", "EquippedTrail", "Rewards", "Mastery", "Prompts" }

local function setKey(oPlayer: Player, sKey: string, fn: (any) -> any)
	-- only hangar keys replicate to the client; receipts etc. stay server-only
	local bReplicated = table.find(HANGAR_KEYS, sKey) ~= nil
	mProfile:ModifyAsync(oPlayer, sKey, fn, if bReplicated then HANGAR_TOKEN else "__none", function(oReplica: any, v: any)
		oReplica:Set({ sKey }, v)
	end)
end
Economy.SetProfileKey = function(_self, oPlayer: Player, sKey: string, fn: (any) -> any) setKey(oPlayer, sKey, fn) end

local function shop(oPlayer: Player, t: any): any
	if typeof(t) ~= "table" or not tShopLimiter:Check(oPlayer) then return { ok = false, err = "busy" } end
	if t.a == "BuyJet" then
		local j = JetConfig.Jets[t.jet]
		if not j then return { ok = false, err = "unknown" } end
		local owned = mProfile:GetAsync(oPlayer, "OwnedJets") or {}
		if owned[j.Id] then return { ok = false, err = "owned" } end
		if rank(oPlayer) < j.RankRequired then return { ok = false, err = "rank" } end
		if j.CashPrice <= 0 and j.GamepassKey then return { ok = false, err = "robux" } end
		if not Economy:Spend(oPlayer, j.CashPrice, "Jet_" .. j.Id) then return { ok = false, err = "cash" } end
		setKey(oPlayer, "OwnedJets", function(v) v = v or {}; v[j.Id] = true; return v end)
		analytics():Progression(oPlayer, "JetUnlock", j.Order, j.Id)
		Economy.OnJetUnlocked:Fire(oPlayer, j.Id)
		return { ok = true }
	elseif t.a == "Equip" then
		local owned = mProfile:GetAsync(oPlayer, "OwnedJets") or {}
		if not owned[t.jet] then return { ok = false, err = "notowned" } end
		setKey(oPlayer, "EquippedJet", function() return t.jet end)
		return { ok = true }
	elseif t.a == "Paint" then
		-- liveries: a jet's own paints are free; mastery schemes need the mastery level
		local j = JetConfig.Jets[t.jet]
		local owned = mProfile:GetAsync(oPlayer, "OwnedJets") or {}
		if not j or typeof(t.paint) ~= "string" or not j.Paints[t.paint] then return { ok = false, err = "invalid" } end
		if not owned[j.Id] then return { ok = false, err = "notowned" } end
		if JetConfig.IsMasteryPaint(t.paint) then
			local MasteryConfig = require(ReplicatedStorage.Config.MasteryConfig)
			local m = (mProfile:GetAsync(oPlayer, "Mastery") or {})[j.Id] or 0
			if MasteryConfig.LevelFor(m) < MasteryConfig.Schemes[t.paint].Level then return { ok = false, err = "mastery" } end
		end
		setKey(oPlayer, "EquippedPaint", function(v) v = v or {}; v[j.Id] = t.paint; return v end)
		analytics():Log(oPlayer, "paint_equip", { jet = j.Id, paint = t.paint })
		return { ok = true }
	elseif t.a == "Upgrade" then
		local track = t.track
		local costs = EconomyConfig.UpgradeCosts[track]
		local owned = mProfile:GetAsync(oPlayer, "OwnedJets") or {}
		if not costs or not owned[t.jet] then return { ok = false, err = "invalid" } end
		local ups = mProfile:GetAsync(oPlayer, "Upgrades") or {}
		local lvl = (ups[t.jet] and ups[t.jet][track]) or 0
		if lvl >= EconomyConfig.MaxUpgradeLevel then return { ok = false, err = "max" } end
		if not Economy:Spend(oPlayer, costs[lvl + 1], `Upg_{t.jet}_{track}_{lvl + 1}`) then return { ok = false, err = "cash" } end
		setKey(oPlayer, "Upgrades", function(v)
			v = v or {}
			v[t.jet] = v[t.jet] or {}
			v[t.jet][track] = lvl + 1
			return v
		end)
		analytics():LogOnce(oPlayer, "session_first_upgrade")
		analytics():Progression(oPlayer, "Upgrade_" .. track, lvl + 1, t.jet)
		return { ok = true, level = lvl + 1 }
	end
	return { ok = false, err = "unknown" }
end

function Economy.StartAsync(self)
	oShop:OnServerInvoke(function(oPlayer: Player, t: any)
		local r = shop(oPlayer, t)
		-- equip/upgrade on the deck takes effect immediately (fresh jet on the catapult)
		if r.ok and typeof(t) == "table" and (t.a == "Equip" or t.a == "Upgrade" or t.a == "Paint") then
			local Flight = require(ServerStorage.ServerModules.FlightServer)
			local s = Flight:GetSortie(oPlayer)
			if s and s.Phase == "Deck" then task.defer(function() Flight:Spawn(oPlayer) end) end
		end
		return r
	end)
	local Flight = require(ServerStorage.ServerModules.FlightServer)
	local Combat = require(ServerStorage.ServerModules.CombatServer)

	-- multi-kill chains: every kill within ChainWindow of the last one extends the chain
	local tChain: { [Player]: { N: number, T: number } } = {}
	local function chainKill(killer: Player)
		local now = os.clock()
		local c = tChain[killer]
		if c and now - c.T <= EconomyConfig.MultiKill.ChainWindow then c.N += 1; c.T = now else c = { N = 1, T = now } end
		tChain[killer] = c
		if c.N >= 2 then
			local names = EconomyConfig.MultiKill.Names
			local label = names[math.min(c.N, #names)] or `x{c.N} SPLASH!`
			local step = EconomyConfig.MultiKill
			self:Reward(killer, "MultiKill", { Label = label, Cash = step.CashPerStep * (c.N - 1), Mult = 1 })
			self.OnMultiKill:Fire(killer, c.N)
			analytics():Log(killer, "multi_kill", { n = c.N })
		end
	end

	Combat.OnKill.Event:Connect(function(killer: Player?, victim: Model, sWeapon: string, info: any)
		if killer and not victim:GetAttribute("Friendly") and victim:GetAttribute("NpcKind") ~= "Drone" then chainKill(killer) end
		local victimId = victim:GetAttribute("OwnerUserId")
		local victimPlayer = if victimId then Players:GetPlayerByUserId(victimId) else nil
		if victimPlayer then
			mProfile:ModifyAsync(victimPlayer, "Stats", function(s) s.Deaths += 1; return s end, HANGAR_TOKEN, function(r, v) r:Set({ "Stats" }, v) end)
		end
		if not killer then return end
		if victimPlayer then
			local mult = 1
			local nerve = killer:GetAttribute("NerveFull")
			if nerve then mult *= EconomyConfig.NerveKillMult; killer:SetAttribute("NerveFull", nil) end
			if killer:GetAttribute("RevengeOn") == victimPlayer.UserId then
				mult *= EconomyConfig.RevengeMult
				killer:SetAttribute("RevengeOn", nil)
			end
			self:Reward(killer, "Kill", { Mult = mult, Label = `SPLASH! {victimPlayer.DisplayName}` })
			mProfile:ModifyAsync(killer, "Stats", function(s) s.Kills += 1; return s end, HANGAR_TOKEN, function(r, v) r:Set({ "Stats" }, v) end)
			analytics():LogOnce(killer, "session_first_kill")
			-- revenge mark for the victim
			victimPlayer:SetAttribute("RevengeOn", killer.UserId)
			task.delay(90, function()
				if victimPlayer:GetAttribute("RevengeOn") == killer.UserId then victimPlayer:SetAttribute("RevengeOn", nil) end
			end)
		else
			local kind = victim:GetAttribute("NpcKind")
			if kind == "Destroyer" then
				-- the sink reward is shared by every participant (MissionServer)
				self:Reward(killer, "BomberKill", { Bank = true, Label = "FINAL BLOW: DESTROYER SUNK" })
			else
				local key = if kind == "Drone" then "DroneTraining" elseif kind == "Interceptor" then "InterceptorKill" elseif kind == "BotPilot" then "BotKill" else "BomberKill"
				local label = if kind == "SAMSite" then "SAM SITE DESTROYED" elseif kind == "Interceptor" then "RED TALON DOWN"
					elseif kind == "BotPilot" then `SPLASH! {victim:GetAttribute("Pilot")}` elseif kind == "Fortress" then "FINAL BLOW: FLYING FORTRESS" else `{string.upper(kind or "TARGET")} DOWN`
				self:Reward(killer, key, { Bank = true, Label = label })
			end
		end
		for _, p in ipairs(info.Assists or {}) do
			self:Reward(p, "Assist", { Label = "ASSIST" })
		end
	end)

	Combat.OnEvade.Event:Connect(function(oPlayer: Player, bAce: boolean)
		if bAce then
			self:Reward(oPlayer, "AceEvade", { Label = "ACE EVADE!" })
			analytics():Log(oPlayer, "ace_evade")
		end
		analytics():Log(oPlayer, "missile_evaded", { ace = bAce })
	end)

	Flight.OnTouchAndGo.Event:Connect(function(oPlayer: Player)
		self:Bank(oPlayer)
	end)

	-- a safe landing banks your cash too, plus a landing bonus (once per flight: you have to take off again)
	local tLandedSince: { [Player]: number } = {}
	Flight.OnLaunched.Event:Connect(function(oPlayer: Player) tLandedSince[oPlayer] = os.clock() end)
	Flight.OnResupply.Event:Connect(function(oPlayer: Player, where: string)
		self:Bank(oPlayer)
		local since = tLandedSince[oPlayer]
		if since and os.clock() - since > EconomyConfig.LandingMinFlight then
			tLandedSince[oPlayer] = nil
			if where == "Carrier" then
				self:Reward(oPlayer, "CarrierTrap", { Bank = true, Label = "CARRIER TRAP!" })
			else
				self:Reward(oPlayer, "Landing", { Bank = true, Label = "SAFE LANDING" })
			end
			analytics():Log(oPlayer, "landing", { where = where })
		end
	end)
	-- airfield take-offs count as a new flight for the landing bonus
	Flight.OnSonicBoom.Event:Connect(function(oPlayer: Player, bFirst: boolean)
		if bFirst then
			self:Reward(oPlayer, "SonicBoom", { Bank = true, Label = "MACH 1!" })
			analytics():Log(oPlayer, "sonic_boom")
		end
	end)
	task.spawn(function()
		-- mark airborne-again after an airfield take-off (no launch event there)
		while true do
			task.wait(2)
			for p, s in pairs(Flight.Sorties) do
				if s.Phase == "Flying" and not tLandedSince[p] and s.Jet.PrimaryPart and s.Jet.PrimaryPart.AssemblyLinearVelocity.Magnitude > 60 then
					tLandedSince[p] = os.clock()
				end
			end
		end
	end)

	Flight.OnLaunched.Event:Connect(function(oPlayer: Player, bPerfect: boolean)
		analytics():LogOnce(oPlayer, "session_launched")
		mProfile:ModifyAsync(oPlayer, "Stats", function(s)
			s.Sorties += 1
			if bPerfect then s.PerfectLaunches += 1 end
			return s
		end, HANGAR_TOKEN, function(r, v) r:Set({ "Stats" }, v) end)
		if bPerfect then
			self:Reward(oPlayer, "PerfectLaunch", { Bank = true, Label = "PERFECT LAUNCH" })
			analytics():Log(oPlayer, "perfect_launch")
		end
	end)

	Flight.OnJetDestroyed.Event:Connect(function(oPlayer: Player, sCause: string)
		local ok, Mon = pcall(require, ServerStorage.ServerModules:FindFirstChild("MonetizationServer") :: any)
		local keepAll = false
		if ok and Mon and Mon.ConsumeBountyShield then keepAll = Mon:ConsumeBountyShield(oPlayer) end
		self:LoseOnDeath(oPlayer, keepAll, sCause == "eject")
		analytics():Log(oPlayer, "sortie_end", { cause = sCause })
	end)
end

function Economy.InitProfileAsync(self, oPlayer: Player, tProfile)
	-- schema guard + replicate hangar data to the owning client
	local d = tProfile.Data
	d.SchemaVersion = d.SchemaVersion or 1
	if typeof(d.OwnedJets) ~= "table" then d.OwnedJets = { SparrowT2 = true } end
	d.OwnedJets.SparrowT2 = true
	if not JetConfig.Jets[d.EquippedJet] or not d.OwnedJets[d.EquippedJet] then d.EquippedJet = "SparrowT2" end
	mProfile:CreateReplica(oPlayer, HANGAR_TOKEN, HANGAR_KEYS)
	tSortie[oPlayer] = 0
	analytics():LogOnce(oPlayer, "session_loaded")
end

function Economy.PlayerRemoving(self, oPlayer: Player)
	-- unbanked Sortie Cash is kept (75%) on leave so nobody feels robbed
	self:LoseOnDeath(oPlayer, false)
	tSortie[oPlayer] = nil
end

return Economy
