--!strict
--[[
    TipsClient: just-in-time coaching. The tutorial only teaches launch, guns and missiles
    (action within ~90 s); everything else is taught the first time it matters, as a
    one-line tip in the prompt bar (6 s, once per session, ranks 1-5 only):
      enemy lock, incoming missile (flares), G strain, afterburner fuel, low fuel (tanker),
      unbanked cash (Bank It), out of missiles (land to rearm), gear.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Fusion = require(ReplicatedStorage.Packages.fusion)
local peek = Fusion.peek

local Tips = ModuleUtil.New({})

local MAX_RANK = 5
local SHOW_TIME = 6

type Tip = { Id: string, Text: { Touch: string, Pad: string, Mouse: string } }
local TIPS: { [string]: Tip } = {
	Lock = { Id = "Lock", Text = {
		Touch = "ENEMY LOCK! Turn hard or dive behind a hill to break it",
		Pad = "ENEMY LOCK! Turn hard or dive behind a hill to break it",
		Mouse = "ENEMY LOCK! Turn hard or dive behind a hill to break it" } },
	Inbound = { Id = "Inbound", Text = {
		Touch = "MISSILE INBOUND! Tap FLARE when it's close, then turn hard",
		Pad = "MISSILE INBOUND! Press B for flares when it's close, then turn hard",
		Mouse = "MISSILE INBOUND! Press F for flares when it's close, then turn hard" } },
	Strain = { Id = "Strain", Text = {
		Touch = "Easy! Hold max G too long and you'll black out - pulse your turns",
		Pad = "Easy! Hold max G too long and you'll black out - pulse your turns",
		Mouse = "Easy! Hold max G too long and you'll black out - pulse your turns" } },
	Boost = { Id = "Boost", Text = {
		Touch = "Afterburner is fast but drinks fuel - use it in bursts",
		Pad = "Afterburner is fast but drinks fuel - use it in bursts",
		Mouse = "Afterburner is fast but drinks fuel - use it in bursts" } },
	Fuel = { Id = "Fuel", Text = {
		Touch = "Fuel at half: the TANKER refuels you in the air, or land at a runway",
		Pad = "Fuel at half: the TANKER refuels you in the air, or land at a runway",
		Mouse = "Fuel at half: the TANKER refuels you in the air, or land at a runway" } },
	Bank = { Id = "Bank", Text = {
		Touch = "Fly low over the carrier deck to BANK your cash (you lose some if shot down)",
		Pad = "Fly low over the carrier deck to BANK your cash (you lose some if shot down)",
		Mouse = "Fly low over the carrier deck to BANK your cash (you lose some if shot down)" } },
	Stick = { Id = "Stick", Text = { -- tablets only (big touch screens, still on Swipe steering)
		Touch = "Tablet tip: try STICK steering in ⚙ Settings - hold and push to keep turning",
		Pad = "", Mouse = "" } },
	-- pilots who skipped the tutorial (or are in the 50/50 "Direct" group) learn the two weapons here
	Guns = { Id = "Guns", Text = {
		Touch = "Hold GUNS to fire - put the green pip on an enemy jet",
		Pad = "Hold RT to fire - put the green pip on an enemy jet",
		Mouse = "Hold LEFT MOUSE to fire - put the green pip on an enemy jet" } },
	Missile = { Id = "Missile", Text = {
		Touch = "Keep the enemy in the circle until LOCK - tap MISSILE (it fires on lock)",
		Pad = "Keep the enemy in the circle until LOCK - pull LT (it fires on lock)",
		Mouse = "Keep the enemy in the circle until LOCK - right-click (it fires on lock)" } },
	RearmRookie = { Id = "RearmRookie", Text = {
		Touch = "Out of missiles: they reload by themselves when you break away from the fight",
		Pad = "Out of missiles: they reload by themselves when you break away from the fight",
		Mouse = "Out of missiles: they reload by themselves when you break away from the fight" } },
	Rearm = { Id = "Rearm", Text = {
		Touch = "Out of missiles: tap GEAR, land at the AIRFIELD or CARRIER and stop to rearm",
		Pad = "Out of missiles: D-pad down for gear, land at the AIRFIELD or CARRIER and stop",
		Mouse = "Out of missiles: press G for gear, land at the AIRFIELD or CARRIER and stop" } },
}

local tSeen: { [string]: boolean } = {}
local nFlyingFor = 0 -- seconds flown this session (tablet Stick tip after a minute)
local tQueue: { string } = {}
local nShowingUntil = 0
local sShowing: string? = nil

local function push(id: string)
	if tSeen[id] then return end
	tSeen[id] = true
	table.insert(tQueue, id)
end

-- NEXT GOAL: right after your first kill (38% of new players' last milestone) and on every rank-up,
-- say exactly what's next and what it unlocks
local function nextGoalText(): string
	local JetConfig = require(ReplicatedStorage.Config.JetConfig)
	local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
	local rank = peek(Store.Values.nRank) :: number
	local xp = peek(Store.Values.nXPToNext) :: number
	local perKill = (EconomyConfig.Rewards and EconomyConfig.Rewards.BotKill and EconomyConfig.Rewards.BotKill.XP) or 90
	local kills = math.max(1, math.ceil(xp / perKill))
	local h = peek(Store.Values.tHangar) :: any
	local owned = (h and h.OwnedJets) or {}
	local unlock = ""
	for id, j in pairs(JetConfig.Jets) do
		if not owned[id] and j.RankRequired == rank + 1 and (j.CashPrice or 0) > 0 then
			unlock = " · UNLOCKS THE " .. string.upper(j.DisplayName or id)
		end
	end
	return string.format("NEXT GOAL: RANK %d IN %d XP (~%d KILL%s)%s", rank + 1, xp, kills, if kills == 1 then "" else "S", unlock)
end

local nGoalToken = 0
local function showGoal()
	nGoalToken += 1
	local token = nGoalToken
	task.delay(1.6, function() -- after the kill / rank-up banner
		if token ~= nGoalToken then return end
		Store.Values.sNextGoal:set(nextGoalText())
		task.delay(6, function() if token == nGoalToken then Store.Values.sNextGoal:set("") end end)
	end)
end

function Tips.StartAsync(self)
	local gscope = Fusion.scoped(Fusion)
	local lastRank = peek(Store.Values.nRank) :: number
	gscope:Observer(Store.Values.nMyKills):onChange(function()
		local k = peek(Store.Values.nMyKills) :: number
		if k == 1 or k == 3 then showGoal() end
	end)
	gscope:Observer(Store.Values.nRank):onChange(function()
		local r = peek(Store.Values.nRank) :: number
		if r > lastRank and lastRank > 0 then showGoal() end
		lastRank = r
	end)
	local Flight = require(script.Parent.FlightController) :: any
	local Input = require(script.Parent.InputController) :: any
	local FTUE = require(script.Parent.FTUEClient) :: any
	local function device(): string
		return if Input.LastDevice == "Touch" then "Touch" elseif Input.LastDevice == "Gamepad" then "Pad" else "Mouse"
	end
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		if Flight.Phase == "Flying" then nFlyingFor += dt end
		if sShowing and now >= nShowingUntil then
			if peek(Store.Values.sPrompt) == sShowing then Store.Values.sPrompt:set("") end
			sShowing = nil
		end
		if FTUE.Active or (peek(Store.Values.nRank) :: number) > MAX_RANK then return end
		local st, stats, jet = Flight.State, Flight.Stats, Flight.Jet
		if Flight.Phase == "Flying" and st and stats and jet then
			local threat = peek(Store.Values.sThreat)
			if threat == "Inbound" then push("Inbound") elseif threat == "Locked" then push("Lock") end
			local h = peek(Store.Values.tHangar) :: any
			if h and h.FTUE and h.FTUE.Skipped then
				if nFlyingFor > 3 then push("Guns") end
				if peek(Store.Values.sLockState) == "Seeking" then push("Missile") end
			end
			if (st.Strain or 0) > 0.45 then push("Strain") end
			if Input.State.Boost then push("Boost") end
			if st.Fuel / stats.Fuel < 0.5 then push("Fuel") end
			if (peek(Store.Values.nSortieCash) :: number) >= 150 then push("Bank") end
			if (jet:GetAttribute("Missiles") :: number? or 1) <= 0 then push(if jet:GetAttribute("Rookie") then "RearmRookie" else "Rearm") end
			local vp = workspace.CurrentCamera.ViewportSize
			if nFlyingFor > 60 and device() == "Touch" and math.min(vp.X, vp.Y) >= 700 and Input.State.TouchMode ~= "Stick" then push("Stick") end
		end
		-- urgent tips jump the queue
		if not sShowing and #tQueue > 0 then
			local idx = table.find(tQueue, "Inbound") or 1
			local id = table.remove(tQueue, idx) :: string
			local tip = TIPS[id]
			if tip then
				sShowing = (tip.Text :: any)[device()]
				nShowingUntil = now + SHOW_TIME
				Store.Values.sPrompt:set(sShowing :: string)
			end
		end
	end)
end

return Tips
