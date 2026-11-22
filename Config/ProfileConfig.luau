--[[
    ProfileConfig
    -------------
    ProfileStore settings and the saved-data template used by BCDK SMProfile.
    Every key in ProfileTemplate is created for new players and reconciled
    into existing profiles. Bump SchemaVersion when a key changes meaning and
    migrate in ProgressionServer.InitProfileAsync.
]]

return {
	StoreName = "AeroStrike_Store",
	Prefix = "P_",
	SchemaVersion = 1,
	ProfileTemplate = {
		SchemaVersion = 1,
		-- Cash / XP keys are created by SMCurrency / SMXP from their configs.
		OwnedJets = { SparrowT2 = true },
		EquippedJet = "SparrowT2",
		EquippedPaint = { SparrowT2 = "Standard" },
		Upgrades = {}, -- [jetId] = { Engine = 0, Fuel = 0, GSuit = 0, Flares = 0, Seeker = 0 }
		FTUE = { Step = 0, Done = false, Skipped = false }, -- (+ Variant = "Tutorial" | "Direct" for the 50/50 test)
		Stats = { Kills = 0, Deaths = 0, Sorties = 0, MissionsDone = 0, AceEvades = 0, BestStreak = 0, PerfectLaunches = 0 },
		Daily = { LastClaimDay = 0, Streak = 0 },
		ProcessedPurchases = {}, -- [PurchaseId] = os.time() (idempotent receipts)
		OneTimeProducts = {}, -- [productKey] = true (e.g. StarterAceBundle)
		Settings = { Sensitivity = 1, InvertY = false, ManualRoll = false, Camera = "Chase", KillCam = true, TouchSteer = "Swipe" }, -- SettingsClient
		Season = { Id = 0, XP = 0, Tier = 0 }, -- free season track (SeasonServer)
		Trails = {}, -- [trailId] = true (smoke-trail cosmetics)
		EquippedTrail = "",
		Rewards = { Codes = {}, Group = false, Referrals = {} }, -- one-time codes / group / invite rewards
		Mastery = {}, -- [jetId] = mastery XP (MasteryServer)
		Prompts = { Fav = 0, Notif = 0 }, -- os.time of the last favourite / notification prompt
		ShopPaints = {}, -- [paintId] = true (Robux cosmetic paints, CosmeticsConfig)
		Badges = {}, -- [badgeKey] = true once awarded (saves BadgeService calls)
		Meta = { FirstDay = 0, LastDay = 0, DaysPlayed = 0, Sessions = 0 }, -- MetricsServer (UTC day numbers)
	},
}
