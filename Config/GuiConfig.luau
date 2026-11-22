--[[
    GuiConfig
    ---------
    What LMGui mounts on startup and the shared Fusion Store values every
    screen can read (Store.Values.<Name>). Gameplay controllers write these
    values; screens only read them (one-way data flow).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Screens auto-mounted on client start: [sGuiName] = tProps
local tConstantGuis = {
	HUD = {},
	CombatHUD = {},
	Social = {},
}

local tValues = {
	-- flight telemetry (written by FlightController every frame)
	nSpeedKmh = 0,
	nAltitude = 0,
	nFuel = 1, -- 0..1
	nG = 1,
	nGLoc = 0, -- 0..1 grey-out
	nHeading = 0, -- degrees
	sPhase = "Loading", -- Loading | Deck | Catapult | Flying | Dead
	nLaunchBar = 0, -- 0..1 timing bar
	sLaunchResult = "", -- "PERFECT LAUNCH!" etc.
	bShield = false,
	tAimScreen = Vector2.new(-1000, -1000), -- where the player is steering
	tNoseScreen = Vector2.new(-1000, -1000), -- where the nose points now
	bBoost = false,

	-- weapons (WeaponsController)
	nGunHeat = 0,
	nMissiles = 0,
	nMissilesMax = 0,
	nFlares = 0,
	nFlaresMax = 0,
	nFlareCooldown = 0, -- 0..1
	sLockState = "None", -- None | Seeking | Locked
	nLockProgress = 0,
	sLockHint = "", -- lock coaching: GET ON THEIR SIX / EASE OFF THE G / FLARES! RE-ACQUIRE
	tLockScreen = Vector2.new(-1000, -1000),
	tLeadScreen = Vector2.new(-1000, -1000),
	sThreat = "None", -- None | Locked | Inbound
	tTargets = {}, -- { {Pos=Vector2, Name=string, Kind="Enemy"|"Squad"|"Ace"|"Mission", Dist=number} }

	-- economy (EconomyClient)
	nCash = 0,
	nSortieCash = 0,
	nRank = 1,
	nRankProgress = 0,
	tToasts = {}, -- recent reward popups
	tKillCard = false, -- false | { Killer, Weapon, KillerId }

	-- objective / FTUE prompt
	sObjective = "",
	sPrompt = "",
	bFTUESkippable = false,
	bFTUEActive = false,
	tHangar = {}, -- replicated hangar profile data (OwnedJets, EquippedJet, Upgrades, ...)
	bHangarOpen = false,
	sHangarSelected = "SparrowT2",
	sHangarMsg = "",
	tPasses = {}, -- owned game passes {Key=true}
	tShopInfo = {}, -- [key] = { Icon = "rbxassetid://..", Price = n }
	bShopOpen = false,
	bStarterOffer = false,
	tInvite = false, -- false | { from, name }
	tSquad = {}, -- { {id, name} }
	tDaily = { day = 1, streak = 0, claimable = false },
	bDailyOpen = false,
	bSquadOpen = false,
	tPlayerList = {}, -- for the squad screen
	bFormation = false,
	tObjectiveScreen = Vector2.new(-1000, -1000),
	bPullUp = false, -- ground-proximity warning
	nThrottle = 0.75, -- 0..1 set-and-hold throttle
	bStall = false,
	nStrain = 0, -- 0..1 G strain (tunnel vision; 1 = G-LOC)
	bGLoc = false, -- blacked out
	bCorner = false, -- at corner speed (best turn)
	bFlameout = false, -- out of fuel: engine dead
	bGearDown = true,
	bRookie = false, -- rookie assists active (ranks 1-3)
	sBossBar = "", -- Flying Fortress countdown / status line
	tChallenges = {} :: { any }, -- { { Id, Text, Goal, Progress, Cash, Done } } x3
	sNextJet = "", -- NEXT JET: VIPER IX  1,240 / 6,000
	nNextJetFrac = 0,
	sRankLine = "", -- ACE RANK 3 · 340 XP TO RANK 4
	bSeasonOpen = false,
	bReviveOffer = false, -- REVIVE HERE button on the death screen
	bReviveFree = false,
	bFlareNow = false,
	bRookieJet = false,
	sGiftNext = "",
	nXPToNext = 0, -- XP left to the next rank
	sNextGoal = "", -- "NEXT GOAL: RANK 2 IN 160 XP (~2 KILLS) · UNLOCKS THE VIPER IX" -- "NEXT GIFT IN 1:12 · +300" (death screen)
	nMyKills = 0, -- kills this session (hangar nudge after the first)
	bHangarVisited = false, -- opened the hangar this session -- flying a rookie-assisted jet (no eject push; the hull repairs out of combat) -- a missile is about to hit: flash the FLARE button / cue -- that offer is the free rookie revive (no Robux)
	bSettingsOpen = false, -- Settings screen (SettingsClient)
	tStickBase = Vector2.new(-1000, -1000), -- touch Stick steering: where the thumb went down (screen px)
	tStickKnob = Vector2.new(-1000, -1000), -- ... and where it is now (clamped to the ring)
	bCompact = false, -- small screen (phone): ResponsiveUIController hides secondary flight HUD
	sGiftLine = "", -- playtime gift countdown chip (RetentionClient)
	nGiftFrac = 0, -- 0..1 progress to the next gift
	sBoardLine = "", -- daily Top Aces position on the progress card
	sSeasonMsg = "",
	nBossHp = -1, -- 0..1 while the Fortress is up, -1 otherwise
	sGroundHint = "", -- landing / taxi / gear prompts
	sRtbHint = "", -- return-to-base guidance (rearm / repair / glide)
	sMach = "", -- sonic boom banner
	bHideKillCard = false, -- briefly hides the death card after an eject
	bHitMarker = false, -- server-confirmed gun hit (flash)
	nHull = 1, -- own jet health 0..1
	bHullCritical = false,
	nHurt = 0, -- red edge flash strength when hit
	tTargetHp = false, -- false | { Pos: Vector2, Frac: number } health bar under the focused target
	sRefuelHint = "", -- tanker guidance: REFUELLING 64% / TOO FAST - THROTTLE BACK / LOW FUEL ...
	nPullUpBlink = true,

	-- platform
	bTouch = false,
	bGamepad = false,
}

export type Values = { [string]: any }

return {
	ConstantGuis = tConstantGuis,
	Values = tValues,
	GuiFolder = ReplicatedStorage.Gui,
}
