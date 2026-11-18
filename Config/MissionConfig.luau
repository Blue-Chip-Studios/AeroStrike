--!strict
--[[
    MissionConfig: live in-world missions (no menus), on a rotation. Each
    mission ends on success or timeout; then a short gap; then the next.
]]

return {
	RotationTime = 180, -- seconds a mission stays live
	Gap = 8, -- seconds between missions
	Missions = {
		BomberSquadron = {
			Name = "BOMBER SQUADRON",
			Brief = "Intercept the Red Talon bombers",
			Reward = "SquadronCleared",
			Bombers = 3,
			Escorts = 2,
			Altitude = { 900, 1600 },
			SpawnRadius = 4200,
			FormationSpacing = 70,
		},
		DestroyerStrike = {
			Name = "DESTROYER STRIKE",
			Brief = "Sink the Red Talon destroyer. Watch the flak!",
			Reward = "DestroyerSunk",
			Time = 210,
			-- patrol east of the island, out at sea
			Route = { Vector3.new(3000, 0, -1800), Vector3.new(3400, 0, 0), Vector3.new(3000, 0, 1800), Vector3.new(2600, 0, 0) },
			Escorts = 2,
		},
		CanyonRun = {
			Name = "CANYON RUN",
			Brief = "Fly the canyon through every gate. Beat the gold time!",
			Reward = "CanyonRun",
			GoldReward = "CanyonGold",
			Time = 180,
			StartX = -2150, EndX = 2150, -- west -> east along IslandShape.CanyonZ
			Gates = 11,
			GateHeight = 55, -- above the canyon floor
			GateRadius = 48,
			GoldTime = 32, -- seconds from first to last gate
			SamSites = 4,
		},
	},
	Rotation = { "BomberSquadron", "DestroyerStrike", "CanyonRun" },
	-- FTUE training drones (near the carrier, inside its safe umbrella)
	Training = {
		Drones = 2,
		Offset = Vector3.new(900, 260, -400), -- from carrier pivot, in carrier space
		Orbit = 160,
	},
}
