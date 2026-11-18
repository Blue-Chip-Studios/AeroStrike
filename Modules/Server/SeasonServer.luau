--!strict
--[[
    SeasonServer: free season track, smoke trails, codes, group and invite rewards.
      - every XP award also fills the season track; each tier pays cash or unlocks a trail
      - EquippedTrail goes on your jet (attribute "Trail") so everyone sees your smoke
      - codes (SeasonConfig.Codes), once per account
      - joining the Blue Chip group: one-time cash + exclusive trail
      - invites: when a friend joins through your invite you both get cash (capped)

    C->S SeasonRequest { a = "Equip", trail } | { a = "Code", code } | { a = "CheckGroup" }
    S->C SeasonEvent   { a = "Msg", text, ok }
    Season / Trails / EquippedTrail / Rewards replicate through the HangarReplica.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local SeasonConfig = require(ReplicatedStorage.Config.SeasonConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)

local Season = ModuleUtil.New({})
local oEvent = Remote:GetEvent("SeasonEvent")
local oRequest = Remote:GetEvent("SeasonRequest")
local oLimiter = ModuleUtil.RateLimiter(6, 3)
local Economy: any, Analytics: any

local function msg(p: Player, text: string, ok: boolean)
	oEvent:FireClient(p, { a = "Msg", text = text, ok = ok })
end

local function grantTrail(p: Player, id: string)
	Economy:SetProfileKey(p, "Trails", function(t) t = t or {}; t[id] = true; return t end)
	-- first trail you earn is equipped automatically (instant payoff)
	if (mProfile:GetAsync(p, "EquippedTrail") or "") == "" then
		Economy:SetProfileKey(p, "EquippedTrail", function() return id end)
	end
end

local function addSeasonXP(p: Player, n: number)
	local S = SeasonConfig.Season
	local s = mProfile:GetAsync(p, "Season")
	if not s then return end
	if s.Id ~= S.Id then s = { Id = S.Id, XP = 0, Tier = 0 } end
	local xp = s.XP + n
	local tier = math.min(#S.Tiers, math.floor(xp / S.XPPerTier))
	local fromTier = s.Tier
	Economy:SetProfileKey(p, "Season", function() return { Id = S.Id, XP = xp, Tier = tier } end)
	for t = fromTier + 1, tier do
		local r = S.Tiers[t]
		if r.Cash then
			Economy:Reward(p, "SeasonTier", { Bank = true, Cash = r.Cash, Label = `SEASON TIER {t}!` })
		elseif r.Trail then
			grantTrail(p, r.Trail)
			Economy:Reward(p, "SeasonTier", { Bank = true, Label = `SEASON TIER {t}: {string.upper(SeasonConfig.Trails[r.Trail].Name)} TRAIL` })
		end
		Analytics:Log(p, "season_tier", { tier = t })
	end
end

local function checkGroup(p: Player, bQuiet: boolean?)
	local rw = mProfile:GetAsync(p, "Rewards") or {}
	if rw.Group then
		if not bQuiet then msg(p, "Group reward already claimed. Thanks, wingman!", true) end
		return
	end
	local ok, inGroup = pcall(p.IsInGroup, p, SeasonConfig.GroupId)
	if ok and inGroup then
		Economy:SetProfileKey(p, "Rewards", function(r) r = r or {}; r.Group = true; return r end)
		local g = SeasonConfig.GroupReward
		Economy:Reward(p, "GroupReward", { Bank = true, Cash = g.Cash, Label = "GROUP REWARD: BLUE CHIP SQUADRON" })
		grantTrail(p, g.Trail)
		Analytics:Log(p, "group_reward")
		msg(p, "Group reward claimed: cash + Blue Chip Squadron trail!", true)
	elseif not bQuiet then
		msg(p, "Join the Blue Chip Games group, then check again.", false)
	end
end

local function redeem(p: Player, code: any)
	if typeof(code) ~= "string" or #code > 24 then return end
	code = string.upper((code:gsub("%s", "")))
	local c = SeasonConfig.Codes[code]
	if not c or (c.Expires and os.time() > c.Expires) then
		msg(p, "That code isn't valid (or has expired).", false)
		return
	end
	local rw = mProfile:GetAsync(p, "Rewards") or {}
	if rw.Codes and rw.Codes[code] then
		msg(p, "You've already used that code.", false)
		return
	end
	Economy:SetProfileKey(p, "Rewards", function(r) r = r or {}; r.Codes = r.Codes or {}; r.Codes[code] = true; return r end)
	if c.Cash then Economy:Reward(p, "Code", { Bank = true, Cash = c.Cash, Label = `CODE {code}` }) end
	if c.Trail then grantTrail(p, c.Trail) end
	Analytics:Log(p, "code_redeemed", { code = code })
	msg(p, `Code redeemed: {code}!`, true)
end

local function onInvited(p: Player)
	local ok, data = pcall(p.GetJoinData, p)
	local refId = ok and data and data.ReferredByPlayerId
	if not refId or refId == 0 or refId == p.UserId then return end
	local ref = Players:GetPlayerByUserId(refId)
	local I = SeasonConfig.Invite
	local mine = mProfile:GetAsync(p, "Rewards") or {}
	if not mine.WelcomedBy then
		Economy:SetProfileKey(p, "Rewards", function(r) r = r or {}; r.WelcomedBy = refId; return r end)
		Economy:Reward(p, "Invite", { Bank = true, Cash = I.NewPilotCash, Label = "WELCOME, WINGMAN! INVITE BONUS" })
	end
	if ref then
		local theirs = mProfile:GetAsync(ref, "Rewards") or {}
		local list = theirs.Referrals or {}
		local count = 0
		for _ in pairs(list) do count += 1 end
		if not list[tostring(p.UserId)] and count < I.MaxReferrals then
			Economy:SetProfileKey(ref, "Rewards", function(r) r = r or {}; r.Referrals = r.Referrals or {}; r.Referrals[tostring(p.UserId)] = true; return r end)
			Economy:Reward(ref, "Invite", { Bank = true, Cash = I.ReferrerCash, Label = `{string.upper(p.DisplayName)} JOINED FROM YOUR INVITE!` })
			Analytics:Log(ref, "invite_reward")
		end
	end
end

function Season.StartAsync(self)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	Economy.OnXP.Event:Connect(function(p: Player, n: number) addSeasonXP(p, n) end)
	oRequest:OnServerEvent(function(p: Player, t: any)
		if typeof(t) ~= "table" or not oLimiter:Check(p) then return end
		if t.a == "Equip" and typeof(t.trail) == "string" then
			local owned = mProfile:GetAsync(p, "Trails") or {}
			if t.trail == "" or owned[t.trail] then
				Economy:SetProfileKey(p, "EquippedTrail", function() return t.trail end)
				msg(p, if t.trail == "" then "Trail off." else "Trail equipped: it shows on your next launch.", true)
			end
		elseif t.a == "Code" then
			redeem(p, t.code)
		elseif t.a == "CheckGroup" then
			checkGroup(p)
		end
	end)
end

function Season.InitProfileAsync(self, p: Player)
	task.delay(4, function()
		if not p.Parent then return end
		-- new season: reset track progress (earned trails stay)
		local s = mProfile:GetAsync(p, "Season")
		if not s or s.Id ~= SeasonConfig.Season.Id then
			Economy:SetProfileKey(p, "Season", function() return { Id = SeasonConfig.Season.Id, XP = 0, Tier = 0 } end)
		end
		checkGroup(p, true)
		onInvited(p)
	end)
end

return Season
