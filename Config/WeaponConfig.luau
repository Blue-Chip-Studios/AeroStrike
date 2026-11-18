--!strict
--[[
    WeaponConfig: the combat triangle. Damage is vs 100 HP jets.
]]

return {
	Gun = {
		FireRate = 18, -- rounds/s
		Damage = 8,
		Range = 850,
		Spread = math.rad(0.6),
		ConeTolerance = math.rad(14), -- server: target must be within this of the nose
		HeatPerShot = 0.018, -- ~3 s of fire to overheat
		CoolRate = 0.45, -- per second when not firing
		OverheatLock = 1.6, -- seconds locked out at 100%
		TracerEvery = 3,
		MuzzleSpeed = 1400, -- visual tracer speed
	},
	Missile = {
		Damage = 70,
		Speed = 330,
		Boost = 1.2, -- s of extra accel at launch
		TurnRate = 2.4, -- rad/s
		NavGain = 3.2, -- proportional navigation constant
		Lifetime = 7,
		Fuse = 20, -- proximity fuse radius
		LockCone = math.rad(18),
		LockRange = 2600,
		ReloadInterval = 0.8, -- min seconds between shots
		RearmTime = 0, -- missiles refill only by touch-and-go / respawn
	},
	MultiLock = { Targets = 4, Damage = 40, LockTime = 1.8 },
	Flare = {
		Cooldown = 2,
		DecoyChance = 0.7,
		AceWindow = 0.6, -- s before impact
		AceChance = 0.9,
		Burst = 4, -- visual flares per press
	},
	LockAnnounceRate = { Count = 12, Window = 4 },
	AssistWindow = 15, -- seconds damage counts toward an assist
}
