--!strict
--[[
    FlightConfig
    ------------
    Global flight, launch, G-force and validation tuning. Live-ops friendly:
    everything that feels "too hard / too easy" is here.
]]

return {
	-- Aim-to-fly
	AimDistance = 600, -- studs ahead the aim point is projected
	MaxAimAngle = math.rad(55), -- aim point can't be further than this from the nose (less snap-aiming)
	BankFactor = 1.1, -- how strongly the jet banks into a turn
	MaxBank = math.rad(80),

	-- Turn curve: turn rate peaks at CornerSpeed, falls off above/below
	TurnLowSpeedMult = 0.55,
	TurnHighSpeedMult = 0.6,

	-- Energy / throttle (the skill layer: simple to fly, rewarding to fly well)
	MilPowerMult = 1.15, -- 100% throttle = CruiseSpeed x this; afterburner = MaxSpeed
	DefaultThrottle = 0.75,
	IdleSpeedMult = 1.08, -- idle throttle settles just above stall: climbs and hard turns at low throttle stall you
	TurnBleed = 9, -- studs/s^2 of speed lost per G above BleedStartG (sustained 8G outpaces military thrust)
	BleedStartG = 2.5,
	RollInMin = 0.45, -- turn rate fraction before the jet has banked into a hard turn
	StallMult = 1.0, -- stall below MinSpeed x this
	StallAuthority = 0.4, -- turn rate while stalled
	StallNoseDrop = 0.35, -- how hard the nose falls in a stall
	FloorSpeedMult = 0.7, -- absolute minimum speed (deep stall)
	ClimbDrag = 18, -- studs/s^2 lost per 1.0 of nose-up
	DiveGain = 14,
	NoFuelSpeedCap = 0.55, -- top speed fraction with empty tank (no flame-out)

	-- G-force (arcade)
	GScale = 0.032, -- G = 1 + omega * speed * GScale (max-rate cruise turn ~6.5G)
	GMax = 11,
	GLocThreshold = 8.5, -- sustained above this -> grey-out (needs boost + tight turn)
	GLocTime = 2.0,
	GLocDuration = 1.5,
	GStiffen = 0.35, -- turn rate lost at full over-G

	-- Launch
	CatapultTime = 1.1, -- seconds on the catapult before free flight
	LaunchSpeedFrac = 0.85, -- of CruiseSpeed
	PerfectLaunchBonus = 1.3,
	PerfectLaunchFreeBoost = 3, -- seconds of free afterburner
	LaunchCountdown = 2.2, -- seconds the timing bar runs before auto-launch
	PerfectWindow = { 0.62, 0.78 }, -- fraction of the bar that counts as "perfect"

	-- Safety
	SpawnShield = 6,
	WaterLevel = 0,
	PullUpSeconds = 3, -- ground-proximity warning look-ahead
	CeilingY = 3200,
	BoundsRadius = 5200, -- from map centre; beyond = warning, then turn back

	-- Server validation
	ValidateInterval = 0.5,
	SpeedTolerance = 1.35, -- x MaxSpeed (perfect launch + dive headroom)
	MaxStrikes = 4,
}
