--!strict
--[[
    BossServer: the Flying Fortress, a server-wide event on a timer (MissionConfig.Boss).
    Everyone on the server fights the same giant armoured bomber and its escorts; the cash
    pool is split by damage dealt (minimum share for anyone who hit it) and the top gun gets
    a bonus. The countdown keeps sessions going ("2:30 until the Fortress").

    Replicates through workspace attributes (read by BossClient):
        BossAt      server time the Fortress arrives (next event)
        BossModel   name of the live Fortress model under workspace.NPC ("" when none)
        BossEndsAt  server time it escapes if not shot down
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)

local Boss = ModuleUtil.New({})

local Npc: any, Combat: any, Economy: any, Analytics: any
local tDamage: { [Player]: number } = {}
local oFortress: Model? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function payOut()
	local B = MissionConfig.Boss
	local total = 0
	for _, d in pairs(tDamage) do total += d end
	if total <= 0 then return end
	local top, topD = nil, 0
	for p, d in pairs(tDamage) do
		if p.Parent and d > topD then top, topD = p, d end
	end
	for p, d in pairs(tDamage) do
		if p.Parent then
			local share = math.max(B.MinShare, math.floor(B.Pool * d / total))
			local pct = math.floor(d / total * 100 + 0.5)
			Economy:Reward(p, "FortressShare", { Bank = true, Cash = share, Label = `FORTRESS DOWN! {pct}% OF THE DAMAGE` })
			if p == top then Economy:Reward(p, "FortressTopGun", { Bank = true, Label = "TOP GUN: MOST FORTRESS DAMAGE" }) end
			Analytics:Log(p, "boss_kill", { share = share, pct = pct })
		end
	end
end

local function runEvent()
	local B = MissionConfig.Boss
	table.clear(tDamage)
	local c = B.Orbit.Centre
	local a = math.random() * math.pi * 2
	local start = c + Vector3.new(math.cos(a) * (B.Orbit.Radius + 1500), 0, math.sin(a) * (B.Orbit.Radius + 1500))
	local m = Npc:Spawn("Fortress", CFrame.lookAt(start, c), { Orbit = { Centre = c, Radius = B.Orbit.Radius }, Tag = "Boss" })
	if not m then return end
	oFortress = m
	for i = 1, B.Escorts do
		local off = Vector3.new(math.random(-160, 160), math.random(40, 120), math.random(-160, 160))
		Npc:Spawn("Interceptor", CFrame.lookAt(start + off, c), { Orbit = { Centre = c, Radius = B.Orbit.Radius + 200 * i }, Tag = "Boss" })
	end
	workspace:SetAttribute("BossModel", m.Name)
	workspace:SetAttribute("BossEndsAt", now() + B.Duration)
	for _, p in ipairs(Players:GetPlayers()) do Analytics:Log(p, "boss_spawn") end
	-- wait for the kill or the escape
	local t0 = os.clock()
	while m.Parent and not m:GetAttribute("Dead") and os.clock() - t0 < B.Duration do task.wait(1) end
	local killed = m:GetAttribute("Dead") == true
	if killed then
		payOut()
	else
		if m.Parent then Npc:Remove(m, false) end
	end
	Npc:RemoveTag("Boss")
	oFortress = nil
	workspace:SetAttribute("BossModel", "")
	workspace:SetAttribute("BossResult", if killed then "Down" else "Escaped")
	workspace:SetAttribute("BossResultAt", now())
end

function Boss.StartAsync(self)
	Npc = require(ServerStorage.ServerModules.NpcServer)
	Combat = require(ServerStorage.ServerModules.CombatServer)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	local B = MissionConfig.Boss
	if not B then return end
	workspace:SetAttribute("BossModel", "")
	Combat.OnDamage.Event:Connect(function(attacker: Player?, victim: Model, nDmg: number)
		if attacker and victim == oFortress then
			tDamage[attacker] = (tDamage[attacker] or 0) + (nDmg or 0)
		end
	end)
	task.spawn(function()
		local wait = B.FirstAt
		while true do
			workspace:SetAttribute("BossAt", now() + wait)
			task.wait(wait)
			if #Players:GetPlayers() > 0 then runEvent() end
			wait = B.Interval
		end
	end)
end

return Boss
