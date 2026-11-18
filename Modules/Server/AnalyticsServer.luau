--!strict
--[[
    AnalyticsServer
    ---------------
    The only place analytics are logged. Every event must be declared in
    Config/AnalyticsConfig. Client UI events arrive through one rate-limited
    remote and are validated (must be ClientAllowed).

    Usage (server):
        Analytics:Log(player, "missile_fired", { weapon = "IR" })
        Analytics:Economy(player, "Source", "Cash", 150, balance, "Kill", "kill")
        Analytics:Progression(player, "Rank", 7)
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local AnalyticsConfig = require(ReplicatedStorage.Config.AnalyticsConfig)

local tFunnelSession: { [Player]: string } = {}
local tLoggedOnce: { [Player]: { [string]: boolean } } = {}
local oLimiter = ModuleUtil.RateLimiter(AnalyticsConfig.ClientRateLimit.Count, AnalyticsConfig.ClientRateLimit.Window)

local Analytics = ModuleUtil.New({})

local function safe(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then warn("[Analytics]", err) end
end

local function toFields(tData: { [string]: any }?): { [string]: any }?
	if not tData then return nil end
	local t = {}
	local n = 0
	for k, v in pairs(tData) do
		n += 1
		if n > 3 then break end -- AnalyticsService supports up to 3 custom fields
		t[k] = tostring(v)
	end
	return t
end

function Analytics.Log(self, oPlayer: Player, sEvent: string, tData: { [string]: any }?, nValue: number?)
	local def = AnalyticsConfig.Events[sEvent]
	if not def then
		warn(`[Analytics] unknown event "{sEvent}" (add it to AnalyticsConfig)`)
		return
	end
	safe(function()
		if def.Kind == "Onboarding" then
			-- onboarding steps are logged once per player per step
			tLoggedOnce[oPlayer] = tLoggedOnce[oPlayer] or {}
			if tLoggedOnce[oPlayer][sEvent] then return end
			tLoggedOnce[oPlayer][sEvent] = true
			AnalyticsService:LogOnboardingFunnelStepEvent(oPlayer, def.Step :: number, sEvent, toFields(tData))
		elseif def.Kind == "Funnel" then
			local sSession = tFunnelSession[oPlayer] or tostring(oPlayer.UserId)
			AnalyticsService:LogFunnelStepEvent(oPlayer, def.Funnel :: string, sSession, def.Step :: number, sEvent, toFields(tData))
		else
			AnalyticsService:LogCustomEvent(oPlayer, sEvent, nValue or 1, toFields(tData))
		end
	end)
end

-- Session funnel steps are only meaningful once per session.
function Analytics.LogOnce(self, oPlayer: Player, sEvent: string, tData: { [string]: any }?)
	tLoggedOnce[oPlayer] = tLoggedOnce[oPlayer] or {}
	if tLoggedOnce[oPlayer][sEvent] then return end
	tLoggedOnce[oPlayer][sEvent] = true
	self:Log(oPlayer, sEvent, tData)
end

function Analytics.Economy(self, oPlayer: Player, sFlow: "Source" | "Sink", sCurrency: string, nAmount: number, nBalance: number, sTxType: string, sSku: string?)
	safe(function()
		local eFlow = if sFlow == "Source" then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
		local eTx = Enum.AnalyticsEconomyTransactionType.Gameplay
		if sTxType == "Shop" then eTx = Enum.AnalyticsEconomyTransactionType.Shop
		elseif sTxType == "IAP" then eTx = Enum.AnalyticsEconomyTransactionType.IAP
		elseif sTxType == "Onboarding" then eTx = Enum.AnalyticsEconomyTransactionType.Onboarding end
		AnalyticsService:LogEconomyEvent(oPlayer, eFlow, sCurrency, math.floor(nAmount), math.floor(nBalance), eTx.Name, sSku)
	end)
end

function Analytics.Progression(self, oPlayer: Player, sPath: string, nLevel: number, sName: string?)
	safe(function()
		-- levelName must be non-empty or AnalyticsService rejects the event
		AnalyticsService:LogProgressionEvent(oPlayer, sPath, Enum.AnalyticsProgressionType.Complete, nLevel, sName or `{sPath} {nLevel}`)
	end)
end

function Analytics.StartAsync(self)
	local oRemote = Remote:GetEvent("AnalyticsUI")
	oRemote:OnServerEvent(function(oPlayer: Player, tPayload: any)
		if typeof(tPayload) ~= "table" or typeof(tPayload.e) ~= "string" then return end
		local def = AnalyticsConfig.Events[tPayload.e]
		if not def or not def.ClientAllowed then return end
		if not oLimiter:Check(oPlayer) then return end
		local tData = if typeof(tPayload.d) == "table" then tPayload.d else nil
		self:Log(oPlayer, tPayload.e, tData)
	end)
end

function Analytics.PlayerAdded(self, oPlayer: Player)
	tFunnelSession[oPlayer] = `{oPlayer.UserId}-{os.time()}`
	self:LogOnce(oPlayer, "session_join")
end

function Analytics.ProfileReleased(self, oPlayer: Player)
	tFunnelSession[oPlayer] = nil
	tLoggedOnce[oPlayer] = nil
end

Players.PlayerRemoving:Connect(function(oPlayer)
	task.delay(5, function()
		tFunnelSession[oPlayer] = nil
		tLoggedOnce[oPlayer] = nil
	end)
end)

return Analytics
