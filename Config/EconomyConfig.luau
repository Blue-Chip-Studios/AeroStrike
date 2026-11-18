--!strict
--[[
    EconomyConfig: every Cash/XP source and sink. Tune from analytics.
    See GDD §16 for pacing targets (Viper IX ~25 min for a free player).
]]

return {
	Rewards = {
		Kill = { Cash = 150, XP = 100 },
		Assist = { Cash = 50, XP = 40 }, -- dealt >= AssistThreshold of victim max HP
		BomberKill = { Cash = 60, XP = 40 },
		SquadronCleared = { Cash = 300, XP = 150 },
		DestroyerSunk = { Cash = 600, XP = 300 },
		CanyonRun = { Cash = 250, XP = 150 },
		CanyonGold = { Cash = 150, XP = 50 },
		AceEvade = { Cash = 40, XP = 25 },
		PerfectLaunch = { Cash = 10, XP = 5 },
		DroneTraining = { Cash = 0, XP = 20 },
	},
	AssistThreshold = 0.25,
	NerveKillMult = 1.5,
	RevengeMult = 2.0,

	-- Bank It
	BankBonus = 1.25,
	KeepOnDeath = 0.75,
	BankRadius = 260, -- studs from carrier deck centre, below BankMaxAltitude
	BankMaxAltitude = 120,

	-- Squads
	SquadMult = { [1] = 1.0, [2] = 1.2, [3] = 1.3, [4] = 1.3 },

	-- Ace Bounty
	BountyStreak = 5,
	BountyBase = 500,
	BountyPerKill = 250,
	BountyMax = 2000,
	GiantSlayerRankGap = 8,
	GiantSlayerMult = 1.5,

	-- Upgrades: per-track costs L1..L5 and per-level effects
	UpgradeCosts = {
		Engine = { 400, 900, 1800, 3200, 5500 },
		Fuel = { 300, 700, 1400, 2600, 4500 },
		GSuit = { 350, 800, 1600, 3000, 5000 },
		Flares = { 250, 600, 1200, 2400, 4000 },
		Seeker = { 450, 1000, 2000, 3600, 6000 },
	},
	UpgradeEffects = {
		Engine = { MaxSpeedPct = 0.03, AccelPct = 0.04 },
		Fuel = { FuelPct = 0.10, BoostBurnPct = -0.04 },
		GSuit = { GTolerance = 0.4, GLocDelay = 0.4 },
		Flares = { Flares = 1 },
		Seeker = { LockTimePct = -0.06, MissileTurnPct = 0.04 },
	},
	MaxUpgradeLevel = 5,

	-- FTUE reward: free first Flare Pod level
	FTUEReward = { Upgrade = "Flares" },
}
