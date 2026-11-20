--!strict
--[[
    MissionConfig: live in-world missions (no menus), on a rotation. Each
    mission ends on success or timeout; then a short gap; then the next.
]]

return {
	-- Flying Fortress server event (BossServer): first one 5 min after the server starts, then every 9 min
	Boss = {
		FirstAt = 300,
		Interval = 540,
		Duration = 240, -- seconds before it escapes
		Pool = 3000, -- cash split by damage share
		MinShare = 100, -- anyone who hit it gets at least this
		Escorts = 3,
		Orbit = { Centre = Vector3.new(0, 850, 0), Radius = 1300 },
	},
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
		-- straight off the bow, near the climb-out level-off height: a new pilot launches and the
		-- drone is right in front of them (it used to circle 900 studs off to the side)
		Offset = Vector3.new(0, 420, -1150), -- from carrier pivot, in carrier space (bow = -Z); high: chasing it low ended in the sea
		Orbit = 420, -- wide, gentle circle a rookie can follow (was a tight 160)
		HitboxScale = 3.0, -- training drones are easier to hit while players learn to aim
	},
}
