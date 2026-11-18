--!strict
--[[
    MissionConfig: live in-world missions (no menus). A rotation picks the
    next mission when the current one ends or times out. The vertical slice
    ships Bomber Squadron; Destroyer Strike and Canyon Run follow (GDD §13).
]]

return {
	RotationTime = 180, -- seconds a mission stays live
	Gap = 8, -- seconds between missions
	Missions = {
		BomberSquadron = {
			Name = "BOMBER SQUADRON",
			Brief = "Intercept the Red Talon bombers",
			Bombers = 3,
			Escorts = 2, -- drones flying with them
			Altitude = { 900, 1600 },
			SpawnRadius = 4200, -- from map centre, on the far side from the carrier
			FormationSpacing = 70,
		},
	},
	Rotation = { "BomberSquadron" },
	-- FTUE training drones (near the carrier, inside its safe umbrella)
	Training = {
		Drones = 2,
		Offset = Vector3.new(900, 260, -400), -- from carrier pivot, in carrier space
		Orbit = 160,
	},
}
