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
	TurnLowSpeedMult = 0.45, -- slow = sluggish: keep your energy up
	TurnHighSpeedMult = 0.5, -- too fast = wide turns: the corner speed is the sweet spot
	AngAccel = 3.2, -- x TurnRate per second: turns take a moment to bite (lead your target)
	CornerBand = 0.12, -- +-12% of corner speed shows as CORNER on the HUD

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
	DiveGain = 22, -- studs/s^2 per 1.0 of nose-down: dive to trade height for speed (Mach 1 in a steep dive)
	OverspeedDrag = 9, -- studs/s^2 bleed when faster than the throttle setting (idle = speedbrake)
	FlameoutDrag = 6, -- studs/s^2 lost with the engine out: trade height for speed and glide it in
	AccelStall = 0.05, -- stall speed rises with G (x per G above 1): yanking hard when slow stalls you

	-- G-force (arcade)
	GScale = 0.032, -- G = 1 + omega * speed * GScale (max-rate cruise turn ~6.5G)
	GMax = 11,
	-- G strain: pulling above your G tolerance fills a strain meter (tunnel vision);
	-- full = G-LOC blackout (no control). Pulse your turns instead of holding max G.
	StrainRate = 0.7, -- per second at full over-G (GMax); ~2 s of max pull to black out
	StrainRecover = 0.33, -- per second once below tolerance
	GreyoutAt = 0.35, -- strain where the screen starts to tunnel
	GLocDuration = 2.2, -- seconds blacked out
	GLocAfterStrain = 0.55, -- strain left after waking up (you can't pull hard straight away)
	GStiffen = 0.35, -- turn rate lost at full over-G

	-- Landing gear + ground ops
	RideClearance = 2.4, -- studs between belly and ground with gear down
	GearSpeedMult = 0.78, -- gear-down top speed (x CruiseSpeed)
	TouchdownMaxSink = 16, -- studs/s descent rate at contact (more = hard landing)
	TouchdownMaxSpeedMult = 1.7, -- x MinSpeed at contact (below the gear-down top speed: throttle back to land)
	TouchdownMinPitch = -0.3, -- nose can't be pointing down harder than this
	GroundBrake = 34, -- studs/s^2 with throttle at idle
	GroundFriction = 4,
	GroundTurnRate = 0.9, -- rad/s taxi steering
	RotateSpeedMult = 1.25, -- x MinSpeed: lift off when pulling up past this
	TrapStopDistance = 70, -- carrier arrestor wire stops you in this many studs
	ResupplyMaxSpeed = 12, -- studs/s: stop (almost) to resupply

	-- Rookie assists (ranks 1..RookieMaxRank): no G-LOC, automatic gear, forgiving touchdowns
	RookieMaxRank = 5,
	RookieStrainCap = 0.9, -- strain stops short of a blackout (the warning still shows)
	RookieTouchdownSpeed = 1.5, -- x the normal touchdown speed limit (was 1.2: 90 rookie hard-landing deaths in a day)
	RookieTouchdownSink = 2.4, -- x the normal sink limit (was 1.6)
	-- Rookie survival (ranks 1..RookieMaxRank). Two thirds of rookie deaths were self-inflicted:
	-- ejecting when the HUD told them to (32%), flying into the sea / terrain (24%), hard landings (8%).
	RookieHullRegen = { Delay = 6, PerSec = 0.05, Cap = 0.6 }, -- out of combat for Delay s: +5%/s up to 60%
	AutoPullUp = { LookAhead = 1.6, SeaMargin = 25, Climb = 0.65 }, -- auto ground-collision avoidance

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
	-- LAUNCH INTO THE FIGHT (death screen): respawn in the air on the edge of the dogfight instead of the
	-- carrier (half of all leavers quit within 25 s of dying; the carrier relaunch took ~30 s to get back in)
	AirStart = { Radius = 2300, Alt = 760, Shield = 4 },

	-- Server validation
	ValidateInterval = 0.5,
	SpeedTolerance = 1.35, -- x MaxSpeed (perfect launch + dive headroom)
	MaxStrikes = 4,
}
