--!strict
--[[
    ChallengeServer: 3 sortie challenges per pilot (ChallengeConfig), advanced by real game
    events on the server (kills, landings, evades, banking...). Completing one pays its cash
    (banked); completing the set pays a bonus and deals a new set after a short pause.

    S->C ChallengeEvent { a = "Set", list = { { Id, Text, Goal, Progress, Cash, Done } } }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local ChallengeConfig = require(ReplicatedStorage.Config.ChallengeConfig)

local Challenge = ModuleUtil.New({})
local oEvent = Remote:GetEvent("ChallengeEvent")

type Entry = { Id: string, Text: string, Event: string, Goal: number, Progress: number, Cash: number, Done: boolean }
local tSets: { [Player]: { Entry } } = {}
local Economy: any, Analytics: any

local function send(p: Player)
	local list = {}
	for _, e in ipairs(tSets[p] or {}) do
		table.insert(list, { Id = e.Id, Text = e.Text, Goal = e.Goal, Progress = e.Progress, Cash = e.Cash, Done = e.Done })
	end
	oEvent:FireClient(p, { a = "Set", list = list })
end

local function deal(p: Player)
	local pool = table.clone(ChallengeConfig.Pool)
	local set: { Entry } = {}
	for _ = 1, ChallengeConfig.Active do
		if #pool == 0 then break end
		local c = table.remove(pool, math.random(1, #pool)) :: any
		table.insert(set, { Id = c.Id, Text = c.Text, Event = c.Event, Goal = c.Goal, Progress = 0, Cash = c.Cash, Done = false })
	end
	tSets[p] = set
	send(p)
end

function Challenge.Advance(self, p: Player, sEvent: string, n: number?)
	local set = tSets[p]
	if not set then return end
	local changed = false
	for _, e in ipairs(set) do
		if not e.Done and e.Event == sEvent then
			e.Progress = math.min(e.Goal, e.Progress + (n or 1))
			changed = true
			if e.Progress >= e.Goal then
				e.Done = true
				Economy:Reward(p, "Challenge", { Bank = true, Cash = e.Cash, Label = "CHALLENGE: " .. string.upper(e.Text) })
				Analytics:Log(p, "challenge_done", { id = e.Id })
			end
		end
	end
	if not changed then return end
	send(p)
	local all = true
	for _, e in ipairs(set) do if not e.Done then all = false end end
	if all then
		Economy:Reward(p, "ChallengeSet", { Bank = true, Label = "ALL CHALLENGES DONE! NEW SET INCOMING" })
		task.delay(ChallengeConfig.NewSetDelay, function()
			if p.Parent and tSets[p] == set then deal(p) end
		end)
	end
end

function Challenge.StartAsync(self)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	local Combat = require(ServerStorage.ServerModules.CombatServer)
	local Flight = require(ServerStorage.ServerModules.FlightServer)

	Combat.OnKill.Event:Connect(function(killer: Player?, victim: Model, sWeapon: string)
		if not killer or victim:GetAttribute("Friendly") then return end
		local kind = victim:GetAttribute("NpcKind")
		if kind == "Drone" then return end
		self:Advance(killer, "Kill")
		local w = sWeapon or ""
		if string.find(w, "Missile") then self:Advance(killer, "MissileKill") end
		if w == "Cannon" then self:Advance(killer, "GunKill") end
		if kind == nil or kind == "BotPilot" or kind == "Interceptor" then self:Advance(killer, "PilotKill") end
		if kind == "Bomber" then self:Advance(killer, "BomberKill") end
	end)
	Combat.OnDamage.Event:Connect(function(attacker: Player?, victim: Model)
		if attacker and victim:GetAttribute("NpcKind") == "Fortress" then self:Advance(attacker, "BossHit") end
	end)
	Combat.OnEvade.Event:Connect(function(p: Player) self:Advance(p, "Evade") end)
	Flight.OnResupply.Event:Connect(function(p: Player, where: string)
		if where == "Airfield" then self:Advance(p, "LandAirfield") elseif where == "Carrier" then self:Advance(p, "Trap") end
	end)
	Flight.OnSonicBoom.Event:Connect(function(p: Player) self:Advance(p, "SonicBoom") end)
	Economy.OnBanked.Event:Connect(function(p: Player, amount: number) self:Advance(p, "Bank", amount) end)
	Economy.OnMultiKill.Event:Connect(function(p: Player) self:Advance(p, "MultiKill") end)
end

function Challenge.InitProfileAsync(self, p: Player)
	task.delay(3, function() if p.Parent then deal(p) end end)
end

function Challenge.PlayerRemoving(self, p: Player)
	tSets[p] = nil
end

Players.PlayerRemoving:Connect(function(p) tSets[p] = nil end)

return Challenge
