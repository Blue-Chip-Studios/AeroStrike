--!strict
--[[
    ChallengeConfig: sortie challenges. Every pilot always has 3 short goals (drawn from the
    pool, no repeats in a set); finishing all three pays a set bonus and deals a fresh set,
    so there's always a "one more" reason to keep flying. Session-scoped (not saved).

    Event = what advances it (ChallengeServer maps game events to these names).
]]

export type Challenge = { Id: string, Text: string, Event: string, Goal: number, Cash: number }

local Pool: { Challenge } = {
	{ Id = "Kills3", Text = "Shoot down 3 enemies", Event = "Kill", Goal = 3, Cash = 150 },
	{ Id = "Missile2", Text = "Get 2 missile kills", Event = "MissileKill", Goal = 2, Cash = 200 },
	{ Id = "Gun1", Text = "Get a cannon kill", Event = "GunKill", Goal = 1, Cash = 150 },
	{ Id = "Pilot2", Text = "Down 2 enemy pilots", Event = "PilotKill", Goal = 2, Cash = 220 },
	{ Id = "Bomber2", Text = "Down 2 Talon bombers", Event = "BomberKill", Goal = 2, Cash = 200 },
	{ Id = "Land", Text = "Land at the airfield", Event = "LandAirfield", Goal = 1, Cash = 150 },
	{ Id = "Trap", Text = "Trap on the carrier", Event = "Trap", Goal = 1, Cash = 250 },
	{ Id = "Mach", Text = "Break the sound barrier", Event = "SonicBoom", Goal = 1, Cash = 100 },
	{ Id = "Evade2", Text = "Dodge 2 missiles", Event = "Evade", Goal = 2, Cash = 200 },
	{ Id = "Bank300", Text = "Bank 300 cash", Event = "Bank", Goal = 300, Cash = 150 },
	{ Id = "Double", Text = "Get a double splash", Event = "MultiKill", Goal = 1, Cash = 250 },
	{ Id = "Fortress", Text = "Hit the Flying Fortress", Event = "BossHit", Goal = 1, Cash = 150 },
}

return {
	Pool = Pool,
	Active = 3,
	SetBonus = { Cash = 200, XP = 100 }, -- all three done
	NewSetDelay = 4,
}
