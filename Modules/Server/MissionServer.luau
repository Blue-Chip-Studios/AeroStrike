--!strict
--[[
    MissionServer
    -------------
    Live, in-world missions on a rotation (Bomber Squadron -> Destroyer
    Strike -> Canyon Run), plus FTUE training drones. No menus: units spawn
    in the airspace and the client shows a banner + objective marker.

      S->C MissionEvent { a="Start", id, name, brief, pos, left, gates? }
                        { a="Update", left, pos } | { a="End", id, success }
                        { a="Gate", next, total, time? } | { a="CanyonDone", time, gold }

    Rewards: per-kill (EconomyServer) + the mission's completion reward for
    every participant; Canyon Run pays per finished run (+ gold time bonus).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)

type Mission = {
	Id: string, Tag: string, Units: { [Model]: boolean }, Left: number,
	Participants: { [Player]: boolean }, Ends: number,
	Gates: { Vector3 }?, Progress: { [Player]: { Next: number, Start: number, Last: Vector3? } }?,
}

local Mission = ModuleUtil.New({
	Current = nil :: Mission?,
})

local oEvent = Remote:GetEvent("MissionEvent")
local Npc: any, Combat: any, Economy: any, Analytics: any, Flight: any
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

local function count(units: { [Model]: boolean }): number
	local n = 0
	for _ in pairs(units) do n += 1 end
	return n
end

local function begin(id: string, tag: string, units: { [Model]: boolean }, pos: Vector3, extra: { [string]: any }?)
	local cfg = MissionConfig.Missions[id]
	local cur: Mission = {
		Id = id, Tag = tag, Units = units, Left = count(units), Participants = {},
		Ends = os.clock() + (cfg.Time or MissionConfig.RotationTime),
	}
	if extra then for k, v in pairs(extra) do (cur :: any)[k] = v end end
	Mission.Current = cur
	oEvent:FireAllClients({ a = "Start", id = id, name = cfg.Name, brief = cfg.Brief, pos = pos, left = cur.Left, gates = cur.Gates })
end

-- ====================== BOMBER SQUADRON ======================
local function startBomberSquadron(tag: string)
	local cfg = MissionConfig.Missions.BomberSquadron
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
	local function addUnit(kind: string, off: CFrame)
		local r = {}
		for _, wp in ipairs(route) do table.insert(r, wp + (off.Position - spawnPos)) end
		local m = Npc:Spawn(kind, off, { Route = r, Tag = tag })
		if m then units[m] = true end
	end
	for i = 1, cfg.Bombers do
		addUnit("Bomber", heading * CFrame.new((i - 2) * cfg.FormationSpacing, (i % 2) * 12, math.abs(i - 2) * cfg.FormationSpacing * 0.6))
	end
	for i = 1, cfg.Escorts do
		addUnit(cfg.EscortKind or "Interceptor", heading * CFrame.new((i == 1 and -1 or 1) * cfg.FormationSpacing * 2, 40, -60))
	end
	begin("BomberSquadron", tag, units, spawnPos)
end

-- ====================== DESTROYER STRIKE ======================
local function startDestroyer(tag: string)
	local cfg = MissionConfig.Missions.DestroyerStrike
	local start = cfg.Route[1]
	local ship = Npc:Spawn("Destroyer", CFrame.lookAt(start, cfg.Route[2]), { Route = cfg.Route, Loop = true, Tag = tag })
	local units = {}
	if ship then units[ship] = true end
	-- escort drones circle the ship (not required for success)
	for i = 1, cfg.Escorts do
		Npc:Spawn("Drone", CFrame.new(start + Vector3.new(i * 120, 220, 0)), { Orbit = { Centre = start + Vector3.new(0, 220, 0), Radius = 260 }, Tag = tag .. "_esc" })
	end
	begin("DestroyerStrike", tag, units, start)
end

-- ====================== CANYON RUN ======================
local function canyonGates(): { Vector3 }
	local cfg = MissionConfig.Missions.CanyonRun
	local gates = {}
	for i = 0, cfg.Gates - 1 do
		local x = cfg.StartX + (cfg.EndX - cfg.StartX) * i / (cfg.Gates - 1)
		local z = IslandShape.CanyonZ(x)
		local floor = math.max(IslandShape.Height(x, z), 0)
		table.insert(gates, Vector3.new(x, floor + cfg.GateHeight, z))
	end
	return gates
end

local function startCanyon(tag: string)
	local cfg = MissionConfig.Missions.CanyonRun
	local gates = canyonGates()
	-- SAM sites on the canyon rims (destroyable)
	local units = {}
	for i = 1, cfg.SamSites do
		local x = cfg.StartX + (cfg.EndX - cfg.StartX) * (i / (cfg.SamSites + 1))
		local side = if i % 2 == 0 then 1 else -1
		local z = IslandShape.CanyonZ(x) + side * IslandShape.CanyonHalfWidth * 2.1
		local h = IslandShape.Height(x, z)
		local m = Npc:Spawn("SAMSite", CFrame.new(x, h, z), { Tag = tag })
		if m then units[m] = true end
	end
	begin("CanyonRun", tag, units, gates[1], { Gates = gates, Progress = {} })
end

local STARTERS = { BomberSquadron = startBomberSquadron, DestroyerStrike = startDestroyer, CanyonRun = startCanyon }

local function endMission(bSuccess: boolean)
	local cur = Mission.Current
	if not cur then return end
	Mission.Current = nil
	Npc:RemoveTag(cur.Tag)
	Npc:RemoveTag(cur.Tag .. "_esc")
	local cfg = MissionConfig.Missions[cur.Id]
	if bSuccess and cur.Id ~= "CanyonRun" then
		for p in pairs(cur.Participants) do
			if p.Parent then
				Economy:Reward(p, cfg.Reward, { Bank = true, Label = cfg.Name .. " COMPLETE" })
				Analytics:Log(p, "mission_complete", { id = cur.Id })
			end
		end
	end
	oEvent:FireAllClients({ a = "End", id = cur.Id, success = bSuccess })
end

-- closest distance from point c to segment a-b (fast jets can't skip a gate between ticks)
local function segDist(a: Vector3, b: Vector3, c: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then return (c - a).Magnitude end
	local t = math.clamp((c - a):Dot(ab) / len2, 0, 1)
	return (a + ab * t - c).Magnitude
end

local function tickCanyon(cur: Mission)
	local cfg = MissionConfig.Missions.CanyonRun
	local gates = cur.Gates :: { Vector3 }
	local prog = cur.Progress :: { [Player]: any }
	for _, p in ipairs(Players:GetPlayers()) do
		local jet = Flight:GetJetOf(p)
		local s = Flight:GetSortie(p)
		if not jet or not jet.PrimaryPart or not s or s.Phase ~= "Flying" then
			prog[p] = nil
			continue
		end
		local pos = jet.PrimaryPart.Position
		local st = prog[p] or { Next = 1, Start = 0, Last = pos }
		prog[p] = st
		local g = gates[st.Next]
		if g and segDist(st.Last or pos, pos, g) < cfg.GateRadius then
			if st.Next == 1 then
				st.Start = os.clock()
				cur.Participants[p] = true
				Analytics:Log(p, "mission_join", { id = "CanyonRun" })
			end
			st.Next += 1
			if st.Next > #gates then
				local t = os.clock() - st.Start
				local gold = t <= cfg.GoldTime
				Economy:Reward(p, cfg.Reward, { Bank = true, Label = string.format("CANYON RUN %.1fs", t) })
				if gold then Economy:Reward(p, cfg.GoldReward, { Bank = true, Label = "GOLD TIME!" }) end
				Analytics:Log(p, "mission_complete", { id = "CanyonRun", time = math.floor(t * 10) / 10 })
				oEvent:FireClient(p, { a = "CanyonDone", time = t, gold = gold })
				prog[p] = nil
				st = nil :: any
			else
				oEvent:FireClient(p, { a = "Gate", next = st.Next, total = #gates, time = if st.Start > 0 then os.clock() - st.Start else 0 })
			end
		end
		if st then st.Last = pos end
	end
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
	Flight = require(ServerStorage.ServerModules.FlightServer)

	-- the aerial refuelling tanker is always on station (respawned if it ever goes missing)
	task.spawn(function()
		local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)
		local cfg = NpcConfig.Kinds.Tanker
		if not cfg or cfg.AssetId == 0 then return end
		local tanker: Model? = nil
		while true do
			if not (tanker and tanker.Parent) then
				local centre = MapConfig.Carrier.CFrame.Position + cfg.Orbit.Offset
				tanker = Npc:Spawn("Tanker", CFrame.new(centre + Vector3.new(cfg.Orbit.Radius, 0, 0)), {
					Orbit = { Centre = centre, Radius = cfg.Orbit.Radius }, Tag = "Tanker" })
			end
			task.wait(5)
		end
	end)

	-- bot pilots: top every server up to Population.TargetPilots; they bow out as players join
	task.spawn(function()
		local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)
		local P = NpcConfig.Population
		if not P then return end
		local bots: { Model } = {}
		local lastDeath = -math.huge
		while true do
			task.wait(5)
			for i = #bots, 1, -1 do
				if not bots[i].Parent then table.remove(bots, i); lastDeath = os.clock() end
			end
			local players = #Players:GetPlayers()
			local want = if players == 0 then 0 else math.clamp(P.TargetPilots - players, 0, P.MaxBots)
			if #bots < want and os.clock() - lastDeath > P.RespawnDelay / math.max(1, want - #bots) then
				local a = math.random() * math.pi * 2
				local r = P.Radius[1] + math.random() * (P.Radius[2] - P.Radius[1])
				local pos = P.Centre + Vector3.new(math.cos(a) * r, math.random(-150, 250), math.sin(a) * r)
				local m = Npc:Spawn("BotPilot", CFrame.lookAt(pos, Vector3.new(P.Centre.X, pos.Y, P.Centre.Z)),
					{ Orbit = { Centre = P.Centre, Radius = r }, Tag = "Bot" })
				if m then table.insert(bots, m) end
			elseif #bots > want then
				-- remove the bot furthest from every player (nobody sees it vanish)
				local worst, wd = nil, -1
				for _, b in ipairs(bots) do
					local bp = b:GetPivot().Position
					local nd = math.huge
					for _, j in ipairs(workspace.Jets:GetChildren()) do
						if j:IsA("Model") then nd = math.min(nd, (j:GetPivot().Position - bp).Magnitude) end
					end
					if nd > wd then worst, wd = b, nd end
				end
				if worst and wd > 1500 then
					Npc:Remove(worst, false)
					table.remove(bots, table.find(bots, worst) :: number)
				end
			end
		end
	end)

	-- standing Red Talon patrol: there is always someone out there hunting you
	task.spawn(function()
		local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)
		local P = NpcConfig.Patrol
		if not P then return end
		local slots: { { M: Model?, DeadAt: number } } = {}
		for i = 1, P.Count do slots[i] = { M = nil, DeadAt = -math.huge } end
		while true do
			task.wait(3)
			local anyFlying = false
			for _, s in pairs(Flight.Sorties) do if s.Phase == "Flying" then anyFlying = true break end end
			for i, slot in ipairs(slots) do
				if slot.M and not slot.M.Parent then slot.M = nil; slot.DeadAt = os.clock() end
				if not slot.M and anyFlying and os.clock() - slot.DeadAt > P.Respawn then
					local a = (i / P.Count) * math.pi * 2 + math.random()
					local pos = P.Centre + Vector3.new(math.cos(a) * P.Radius, 0, math.sin(a) * P.Radius)
					slot.M = Npc:Spawn(P.Kind, CFrame.lookAt(pos, Vector3.new(P.Centre.X, pos.Y, P.Centre.Z)),
						{ Orbit = { Centre = P.Centre, Radius = P.Radius }, Tag = "Patrol" })
				end
			end
		end
	end)

	Combat.OnDamage.Event:Connect(function(attacker: Player?, victim: Model)
		local cur = self.Current
		if attacker and cur and cur.Units[victim] and not cur.Participants[attacker] then
			cur.Participants[attacker] = true
			Analytics:Log(attacker, "mission_join", { id = cur.Id })
		end
	end)

	Npc.OnRemoved.Event:Connect(function(m: Model, sTag: string, bKilled: boolean)
		local cur = self.Current
		if sTag == "Training" then
			task.delay(6, function()
				local n = 0
				for _, nn in pairs(Npc.Active) do if nn.Tag == "Training" then n += 1 end end
				if n < MissionConfig.Training.Drones then spawnTraining() end
			end)
			return
		end
		if cur and cur.Tag == sTag and cur.Units[m] then
			cur.Units[m] = nil
			cur.Left -= 1
			oEvent:FireAllClients({ a = "Update", left = cur.Left, pos = unitCentre(cur.Units) })
			-- canyon SAMs are optional; other missions end when every unit is down
			if cur.Left <= 0 and cur.Id ~= "CanyonRun" then endMission(bKilled) end
		end
	end)

	task.spawn(function()
		local World = require(ServerStorage.ServerModules.WorldServer)
		while not World.Ready do task.wait() end
		spawnTraining()
		local idx = 0
		while true do
			task.wait(MissionConfig.Gap)
			idx = idx % #MissionConfig.Rotation + 1
			nMissionSeq += 1
			local id = MissionConfig.Rotation[idx]
			local ok, err = pcall(STARTERS[id], "M" .. nMissionSeq)
			if not ok then warn("[Mission] start failed", id, err) end
			while self.Current and os.clock() < self.Current.Ends do
				local cur = self.Current
				if cur.Id == "CanyonRun" then
					task.wait(0.2)
					tickCanyon(cur)
				else
					task.wait(2)
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
	task.delay(3, function()
		local cur = self.Current
		if not cur then return end
		local cfg = MissionConfig.Missions[cur.Id]
		local pos = if cur.Gates then cur.Gates[1] else unitCentre(cur.Units)
		oEvent:FireClient(oPlayer, { a = "Start", id = cur.Id, name = cfg.Name, brief = cfg.Brief, pos = pos or Vector3.zero, left = cur.Left, gates = cur.Gates })
	end)
end

-- QA hook (Studio only, via DebugServer): force a mission now
function Mission.ForceStart(self, id: string)
	if self.Current then endMission(false) end
	nMissionSeq += 1
	STARTERS[id]("M" .. nMissionSeq)
end

return Mission
