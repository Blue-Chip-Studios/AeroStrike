--!strict
--[[
    SocialServer: Ace Bounty, Wingman squads and the daily reward track.

    ACE BOUNTY: kill streaks of BountyStreak+ make a player an Ace: a gold
      marker for everyone (jet attribute Bounty = value). Whoever shoots them
      down claims the bounty (Giant Slayer +50% if far lower rank).
    SQUADS: invite -> accept, max 4. Squadmates can't lock/hurt each other
      (CombatServer asks AreSquadmates), share the Economy multiplier, and get
      the Formation fuel bonus (client, within FormationRange).
    DAILY: one claim per UTC day; streak continues on consecutive days.

    C->S SocialRequest { a="Invite", userId } | { a="Accept", from } | { a="Decline", from } | { a="Leave" } | { a="ClaimDaily" }
    S->C SocialEvent   { a="Invite", from, name } | { a="Squad", members={ {id,name} } } | { a="Bounty", name, value, userId }
                       { a="BountyClaimed", killer, victim, value } | { a="Daily", day, streak, claimable }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local XPConfig = require(ReplicatedStorage.Config.XPConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)

local Social = ModuleUtil.New({})
local oEvent = Remote:GetEvent("SocialEvent")
local oRequest = Remote:GetEvent("SocialRequest")
local oLimiter = ModuleUtil.RateLimiter(8, 4)

local tStreak: { [Player]: number } = {}
local tSquadOf: { [Player]: { Player } } = {}
local tInvites: { [Player]: { [Player]: number } } = {} -- [invitee][inviter] = time
local Economy: any, Analytics: any, Flight: any, Combat: any

local MAX_SQUAD = 4

-- ============ SQUADS ============
function Social.AreSquadmates(self, a: Player, b: Player): boolean
	local s = tSquadOf[a]
	return s ~= nil and s == tSquadOf[b]
end

function Social.SquadSize(self, p: Player): number
	local s = tSquadOf[p]
	return if s then #s else 1
end

local function broadcastSquad(squad: { Player })
	local members = {}
	for _, m in ipairs(squad) do table.insert(members, { id = m.UserId, name = m.DisplayName }) end
	local sid = if #squad > 1 then tostring(squad[1].UserId) else nil
	for _, m in ipairs(squad) do
		m:SetAttribute("SquadId", sid)
		local jet = Flight:GetJetOf(m)
		if jet then jet:SetAttribute("SquadId", sid) end
		oEvent:FireClient(m, { a = "Squad", members = if #squad > 1 then members else {} })
	end
end

local function leave(p: Player)
	local s = tSquadOf[p]
	if not s then return end
	local i = table.find(s, p)
	if i then table.remove(s, i) end
	tSquadOf[p] = nil
	p:SetAttribute("SquadId", nil)
	local jet = Flight:GetJetOf(p)
	if jet then jet:SetAttribute("SquadId", nil) end
	oEvent:FireClient(p, { a = "Squad", members = {} })
	if #s == 1 then
		tSquadOf[s[1]] = nil
		broadcastSquad(s)
	elseif #s > 1 then
		broadcastSquad(s)
	end
end

local function join(inviter: Player, invitee: Player)
	if tSquadOf[invitee] then leave(invitee) end
	local s = tSquadOf[inviter]
	if not s then
		s = { inviter }
		tSquadOf[inviter] = s
		Analytics:Log(inviter, "squad_create")
	end
	if #s >= MAX_SQUAD then return end
	table.insert(s, invitee)
	tSquadOf[invitee] = s
	Analytics:Log(invitee, "squad_join")
	broadcastSquad(s)
end

-- ============ BOUNTY ============
local function bountyValue(streak: number): number
	return math.min(EconomyConfig.BountyMax, EconomyConfig.BountyBase + EconomyConfig.BountyPerKill * (streak - EconomyConfig.BountyStreak))
end

local function setBounty(p: Player, value: number?)
	p:SetAttribute("Bounty", value)
	local jet = Flight:GetJetOf(p)
	if jet then jet:SetAttribute("Bounty", value) end
end

local function rankOf(p: Player): number
	return XPConfig.fXPToLevel(mProfile:GetAsync(p, "XP") or 0)
end

-- ============ DAILY ============
local function today(): number
	return math.floor(os.time() / 86400)
end

local function dailyState(p: Player): (number, number, boolean)
	local d = mProfile:GetAsync(p, "Daily") or { LastClaimDay = 0, Streak = 0 }
	local t = today()
	local claimable = d.LastClaimDay < t
	local streak = d.Streak or 0
	if claimable and d.LastClaimDay < t - 1 then streak = 0 end
	local dayIndex = (streak % #EconomyConfig.DailyTrack) + 1 -- next day to claim (1..7)
	return dayIndex, streak, claimable
end

local function sendDaily(p: Player)
	local day, streak, claimable = dailyState(p)
	oEvent:FireClient(p, { a = "Daily", day = day, streak = streak, claimable = claimable })
end

local function claimDaily(p: Player)
	local day, streak, claimable = dailyState(p)
	if not claimable then return end
	local cash = EconomyConfig.DailyTrack[day]
	Economy:SetProfileKey(p, "Daily", function(d)
		d = d or {}
		d.LastClaimDay = today()
		d.Streak = streak + 1
		return d
	end)
	Economy:Reward(p, "Daily", { Bank = true, Cash = cash, Label = `DAILY SORTIE PAY · DAY {day}` })
	Analytics:Log(p, "ui_daily_open", { day = day })
	sendDaily(p)
end

function Social.StartAsync(self)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	Flight = require(ServerStorage.ServerModules.FlightServer)
	Combat = require(ServerStorage.ServerModules.CombatServer)

	oRequest:OnServerEvent(function(p: Player, t: any)
		if typeof(t) ~= "table" or not oLimiter:Check(p) then return end
		if t.a == "Invite" and typeof(t.userId) == "number" then
			local target = Players:GetPlayerByUserId(t.userId)
			if not target or target == p or Social:AreSquadmates(p, target) then return end
			if tSquadOf[p] and #tSquadOf[p] >= MAX_SQUAD then return end
			tInvites[target] = tInvites[target] or {}
			tInvites[target][p] = os.clock()
			oEvent:FireClient(target, { a = "Invite", from = p.UserId, name = p.DisplayName })
		elseif t.a == "Accept" and typeof(t.from) == "number" then
			local inviter = Players:GetPlayerByUserId(t.from)
			local inv = tInvites[p] and inviter and tInvites[p][inviter]
			if inviter and inv and os.clock() - inv < 60 then
				tInvites[p][inviter] = nil
				join(inviter, p)
			end
		elseif t.a == "Decline" and typeof(t.from) == "number" then
			local inviter = Players:GetPlayerByUserId(t.from)
			if inviter and tInvites[p] then tInvites[p][inviter] = nil end
		elseif t.a == "Leave" then
			leave(p)
		elseif t.a == "ClaimDaily" then
			claimDaily(p)
		end
	end)

	-- streaks and bounties
	Combat.OnKill.Event:Connect(function(killer: Player?, victim: Model)
		local vid = victim:GetAttribute("OwnerUserId")
		local vp = if vid then Players:GetPlayerByUserId(vid) else nil
		if vp then
			local bounty = vp:GetAttribute("Bounty")
			if bounty and killer and killer ~= vp then
				local mult = if rankOf(vp) - rankOf(killer) >= EconomyConfig.GiantSlayerRankGap then EconomyConfig.GiantSlayerMult else 1
				local value = math.floor(bounty * mult)
				Economy:Reward(killer, "BountyClaim", { Cash = value, Label = if mult > 1 then "GIANT SLAYER! BOUNTY CLAIMED" else "ACE BOUNTY CLAIMED" })
				oEvent:FireAllClients({ a = "BountyClaimed", killer = killer.DisplayName, victim = vp.DisplayName, value = value })
				Analytics:Log(killer, "bounty_claimed", { value = value })
			end
			tStreak[vp] = 0
			setBounty(vp, nil)
		end
		if killer and vp then
			local s = (tStreak[killer] or 0) + 1
			tStreak[killer] = s
			Economy:SetProfileKey(killer, "Stats", function(st) st.BestStreak = math.max(st.BestStreak or 0, s); return st end)
			if s >= EconomyConfig.BountyStreak then
				local value = bountyValue(s)
				local was = killer:GetAttribute("Bounty")
				setBounty(killer, value)
				oEvent:FireAllClients({ a = "Bounty", name = killer.DisplayName, value = value, userId = killer.UserId })
				if not was then Analytics:Log(killer, "bounty_start", { streak = s }) end
			end
		end
	end)

	-- keep squad/bounty attributes on freshly spawned jets
	Flight.OnLaunched.Event:Connect(function(p: Player)
		local jet = Flight:GetJetOf(p)
		if jet then
			jet:SetAttribute("SquadId", p:GetAttribute("SquadId"))
			jet:SetAttribute("Bounty", p:GetAttribute("Bounty"))
			jet:SetAttribute("VIP", p:GetAttribute("VIP"))
		end
	end)
end

function Social.InitProfileAsync(self, p: Player)
	task.delay(4, function() if p.Parent then sendDaily(p) end end)
end

function Social.PlayerRemoving(self, p: Player)
	leave(p)
	tStreak[p] = nil
	tInvites[p] = nil
	for _, inv in pairs(tInvites) do inv[p] = nil end
end

return Social
