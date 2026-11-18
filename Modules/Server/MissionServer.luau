--!strict
--[[
    MissionServer
    -------------
    Live, in-world missions on a rotation, plus FTUE training drones.
    Missions spawn in the airspace with no menus; the client shows an
    objective marker and banner (MissionEvent).

      S->C MissionEvent { a="Start", id, name, brief, pos } | { a="Update", left, pos } | { a="End", id, success }

    Rewards: per-kill (EconomyServer, banked) + SquadronCleared bonus for every
    player who damaged a mission unit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)

local Mission = ModuleUtil.New({
	Current = nil :: { Id: string, Tag: string, Units: { [Model]: boolean }, Left: number, Participants: { [Player]: boolean }, Ends: number }?,
})

local oEvent = Remote:GetEvent("MissionEvent")
local Npc: any, Combat: any, Economy: any, Analytics: any
local nMissionSeq = 0

local function unitCentre(units: { [Model]: boolean }): Vector3?
	local sum, n = Vector3.zero, 0
	for m in pairs(units) do
		if m.Parent and m.PrimaryPart then
			sum += m.PrimaryPart.Position
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end

local function startBomberSquadron()
	local cfg = MissionConfig.Missions.BomberSquadron
	nMissionSeq += 1
	local tag = "M" .. nMissionSeq
	-- spawn on the far side from the carrier, fly across the island toward it
	local carrierPos = MapConfig.Carrier.CFrame.Position
	local away = (MapConfig.MapCentre - carrierPos)
	away = Vector3.new(away.X, 0, away.Z).Unit
	local side = Vector3.new(-away.Z, 0, away.X)
	local spread = (math.random() - 0.5) * 2400
	local alt = math.random(cfg.Altitude[1], cfg.Altitude[2])
	local spawnPos = MapConfig.MapCentre + away * cfg.SpawnRadius + side * spread + Vector3.new(0, alt, 0)
	local route = {
		MapConfig.MapCentre + side * spread * 0.4 + Vector3.new(0, alt, 0),
		carrierPos + away * 1600 + side * (spread * 0.2) + Vector3.new(0, alt * 0.8, 0),
		MapConfig.MapCentre - side * spread + Vector3.new(0, alt, 0),
		MapConfig.MapCentre + away * cfg.SpawnRadius - side * spread + Vector3.new(0, alt, 0),
	}
	local heading = CFrame.lookAt(spawnPos, route[1])
	local units = {}
	for i = 1, cfg.Bombers do
		local off = heading * CFrame.new((i - 2) * cfg.FormationSpacing, (i % 2) * 12, math.abs(i - 2) * cfg.FormationSpacing * 0.6)
		local r = {}
		for _, wp in ipairs(route) do table.insert(r, wp + (off.Position - spawnPos)) end
		local m = Npc:Spawn("Bomber", off, { Route = r, Tag = tag })
		if m then units[m] = true end
	end
	for i = 1, cfg.Escorts do
		local off = heading * CFrame.new((i == 1 and -1 or 1) * cfg.FormationSpacing * 2, 40, -60)
		local r = {}
		for _, wp in ipairs(route) do table.insert(r, wp + (off.Position - spawnPos)) end
		local m = Npc:Spawn("Drone", off, { Route = r, Tag = tag })
		if m then units[m] = true end
	end
	local left = 0
	for _ in pairs(units) do left += 1 end
	Mission.Current = { Id = "BomberSquadron", Tag = tag, Units = units, Left = left, Participants = {}, Ends = os.clock() + MissionConfig.RotationTime }
	oEvent:FireAllClients({ a = "Start", id = "BomberSquadron", name = cfg.Name, brief = cfg.Brief, pos = spawnPos, left = left })
end

local function endMission(bSuccess: boolean)
	local cur = Mission.Current
	if not cur then return end
	Mission.Current = nil
	Npc:RemoveTag(cur.Tag)
	if bSuccess then
		for p in pairs(cur.Participants) do
			if p.Parent then
				Economy:Reward(p, "SquadronCleared", { Bank = true, Label = "SQUADRON CLEARED" })
				Analytics:Log(p, "mission_complete", { id = cur.Id })
			end
		end
	end
	oEvent:FireAllClients({ a = "End", id = cur.Id, success = bSuccess })
end

local function spawnTraining()
	local cfg = MissionConfig.Training
	local centre = (MapConfig.Carrier.CFrame * CFrame.new(cfg.Offset)).Position
	for i = 1, cfg.Drones do
		local cf = CFrame.new(centre + Vector3.new(cfg.Orbit * (i == 1 and 1 or -1), 0, 0))
		Npc:Spawn("Drone", cf, { Orbit = { Centre = centre, Radius = cfg.Orbit }, Tag = "Training" })
	end
end

function Mission.StartAsync(self)
	Npc = require(ServerStorage.ServerModules.NpcServer)
	Combat = require(ServerStorage.ServerModules.CombatServer)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)

	Combat.OnDamage.Event:Connect(function(attacker: Player?, victim: Model)
		local cur = self.Current
		if attacker and cur and cur.Units[victim] then
			if not cur.Participants[attacker] then
				cur.Participants[attacker] = true
				Analytics:Log(attacker, "mission_join", { id = cur.Id })
			end
		end
	end)

	Npc.OnRemoved.Event:Connect(function(m: Model, sTag: string, bKilled: boolean)
		local cur = self.Current
		if sTag == "Training" then
			task.delay(6, function()
				-- keep two training drones alive at all times
				local n = 0
				for mm, nn in pairs(Npc.Active) do if nn.Tag == "Training" then n += 1 end end
				if n < MissionConfig.Training.Drones then spawnTraining() end
			end)
			return
		end
		if cur and cur.Tag == sTag and cur.Units[m] then
			cur.Units[m] = nil
			cur.Left -= 1
			oEvent:FireAllClients({ a = "Update", left = cur.Left, pos = unitCentre(cur.Units) })
			if cur.Left <= 0 then endMission(bKilled) end
		end
	end)

	task.spawn(function()
		local World = require(ServerStorage.ServerModules.WorldServer)
		while not World.Ready do task.wait() end
		spawnTraining()
		while true do
			task.wait(MissionConfig.Gap)
			startBomberSquadron()
			while self.Current and os.clock() < self.Current.Ends do
				task.wait(2)
				local cur = self.Current
				if cur then
					local c = unitCentre(cur.Units)
					if c then oEvent:FireAllClients({ a = "Update", left = cur.Left, pos = c }) end
				end
			end
			if self.Current then endMission(false) end
		end
	end)
end

-- late joiners see the current mission
function Mission.PlayerAdded(self, oPlayer: Player)
	local cur = self.Current
	if cur then
		task.delay(3, function()
			local c = unitCentre(cur.Units)
			oEvent:FireClient(oPlayer, { a = "Start", id = cur.Id, name = MissionConfig.Missions[cur.Id].Name, brief = MissionConfig.Missions[cur.Id].Brief, pos = c or Vector3.zero, left = cur.Left })
		end)
	end
end

return Mission
