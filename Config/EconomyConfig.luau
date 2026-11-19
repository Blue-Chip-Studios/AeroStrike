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
		InterceptorKill = { Cash = 120, XP = 80 }, -- they fight back
		BotKill = { Cash = 130, XP = 90 }, -- AI pilot (fills quiet servers)
		FortressShare = { Cash = 0, XP = 200 }, -- cash = share of MissionConfig.Boss.Pool
		Challenge = { Cash = 0, XP = 60 }, -- cash from ChallengeConfig per challenge
		SeasonTier = { Cash = 0, XP = 0 }, -- cash from SeasonConfig tiers
		Code = { Cash = 0, XP = 0 },
		GroupReward = { Cash = 0, XP = 100 },
		Invite = { Cash = 0, XP = 50 },
		ChallengeSet = { Cash = 200, XP = 100 }, -- all three done
		FortressTopGun = { Cash = 500, XP = 150 },
		SquadronCleared = { Cash = 300, XP = 150 },
		DestroyerSunk = { Cash = 600, XP = 300 },
		CanyonRun = { Cash = 250, XP = 150 },
		CanyonGold = { Cash = 150, XP = 50 },
		AceEvade = { Cash = 40, XP = 25 },
		PerfectLaunch = { Cash = 10, XP = 5 },
		DroneTraining = { Cash = 0, XP = 20 },
		BountyClaim = { Cash = 0, XP = 300 }, -- cash comes from the bounty value
		Daily = { Cash = 0, XP = 50 },
		MultiKill = { Cash = 0, XP = 60 }, -- cash scales with the chain (MultiKill.CashPerStep)
		Landing = { Cash = 40, XP = 30 }, -- land at the airfield and stop
		CarrierTrap = { Cash = 80, XP = 60 }, -- harder: short deck, arrestor wire
		SonicBoom = { Cash = 0, XP = 15 }, -- first Mach 1 each sortie
		PlaytimeGift = { Cash = 0, XP = 25 }, -- cash from RetentionConfig.Playtime
		MasteryLevel = { Cash = 0, XP = 0 }, -- cash from MasteryConfig.Rewards
	},
	-- quick kills chain: each kill within ChainWindow of the previous one extends it
	MultiKill = {
		ChainWindow = 8,
		CashPerStep = 75, -- double +75, triple +150, quad +225, ...
		Names = { "SPLASH!", "DOUBLE SPLASH!", "TRIPLE SPLASH!", "QUAD SPLASH!", "RAMPAGE!" },
	},
	DailyTrack = { 100, 150, 250, 400, 600, 900, 1500 },
	FormationRange = 150,
	LandingMinFlight = 30, -- seconds airborne before a landing pays the landing bonus again
	AssistThreshold = 0.25,
	NerveKillMult = 1.5,
	RevengeMult = 2.0,

	-- Bank It
	BankBonus = 1.25,
	KeepOnDeath = 0.75,
	KeepOnEject = 1.0, -- eject before you are shot down and you keep ALL your unbanked Sortie Cash (death keeps 75%)
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
