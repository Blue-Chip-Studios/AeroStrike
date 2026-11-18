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
