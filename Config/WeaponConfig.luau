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
		AssistTouch = math.rad(4.5), -- client aim assist: rounds bend onto a target this close to the nose (touch / gamepad)
		AssistMouse = math.rad(1.5),
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
		UnguidedLifetime = 4.5, -- no-lock dumb-fire: flies straight
		UnguidedFuseMult = 1.8, -- proximity fuse radius x Fuse for unguided shots
		Fuse = 20, -- proximity fuse radius
		LockCone = math.rad(18),
		LockRange = 2600,
		ReloadInterval = 0.8, -- min seconds between shots
		RearmTime = 0, -- missiles refill only by touch-and-go / respawn
	},
	MultiLock = { Targets = 4, Damage = 40, LockTime = 1.8 },
	-- Heat-seeker lock: progress rate = 1/LockTime x aspect x range x boresight x G x target
	Lock = {
		TailAspect = 1.6, -- right behind the hot exhaust
		HeadOn = 0.6, -- nose-to-nose: slower, but still lockable
		RangeNear = 1.35, -- rate multiplier at point blank ...
		RangeFar = 0.75, -- ... and at max lock range
		BoresightEdge = 0.7, -- rate at the edge of the lock cone (1 at the centre)
		GStart = 4, GPenalty = 0.09, GMin = 0.55, -- hard turns shake the seeker
		Evading = 0.7, -- target is jinking
		Decay = 0.6, -- progress lost per second (x lock time) when the target leaves the cone
		FlareKnock = 0.55, -- fraction of the lock lost when the target pops flares
		MinRate = 0.3, -- floor (outside terrain/sun masking): worst normal lock is ~4 s
		PoorAspectHint = 0.85, -- show "GET ON THEIR SIX" below this aspect factor
		ClutterAGL = 140, Clutter = 0.5, -- target hugging the ground while you look down on it
		SunCone = 12, Sun = 0.2, -- target within this many degrees of the sun
	},
	Flare = {
		Cooldown = 2,
		DecoyChance = 0.7,
		AceWindow = 0.6, -- s before impact
		AceChance = 0.9,
		Burst = 4, -- visual flares per press
	},
	LockAnnounceRate = { Count = 12, Window = 4 },
	AssistWindow = 15, -- seconds damage counts toward an assist
	CrashCreditWindow = 10, -- a crash counts as a kill only if an enemy hit you this recently
}
