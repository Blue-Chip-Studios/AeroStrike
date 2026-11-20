--!strict
--[[
    NpcConfig: Red Talon AI aircraft (all Blender models).
]]

local CHAR = Color3.fromRGB(44, 46, 50)
local CRIMSON = Color3.fromRGB(150, 24, 22)

return {
	Kinds = {
		Bomber = {
			AssetId = 132659361677014,
			Health = 180,
			Speed = 105,
			TurnRate = 0.35,
			Paint = {
				Body = { Color = CHAR, Material = Enum.Material.SmoothPlastic },
				Markings = { Color = CRIMSON, Material = Enum.Material.SmoothPlastic },
				Canopy = { Color = Color3.fromRGB(30, 50, 45), Material = Enum.Material.Glass },
				Trim = { Color = Color3.fromRGB(24, 26, 28), Material = Enum.Material.Metal },
				Glow = { Color = Color3.fromRGB(255, 96, 24), Material = Enum.Material.Neon },
			},
			TailGun = { Range = 520, Rate = 5, Damage = 3, Cone = math.rad(70), HitChance = 0.45 },
			FlareChance = 0.35,
			-- lock difficulty: x lock time for the attacker; Evasion = how the pilot fights back once tracked
			LockTimeMult = 1.15,
			Evasion = { React = 0.8, Jink = 240, Period = 1.6, Duration = 4, Cooldown = 5, FlareOnLock = 0.45, Tactics = { "Jink", "Break" } },
			MinAGL = 120,
		},
		-- Red Talon interceptor: a nimble AI fighter (Viper airframe in Talon colours) that escorts
		-- bombers, hunts players and uses every defensive trick when locked (see NpcServer tactics)
		Interceptor = {
			AssetId = 90543401942532,
			Skin = "ViperIX", -- reuse the Viper PBR airframe skin (tinted Talon charcoal)
			Health = 70,
			Speed = 150,
			ChaseSpeed = 205, -- matches military power: you need the afterburner or a turn to shake one
			TurnRate = 0.95,
			MinAGL = 45,
			Paint = {
				Body = { Color = Color3.fromRGB(52, 50, 54), Material = Enum.Material.SmoothPlastic },
				Accents = { Color = CRIMSON, Material = Enum.Material.SmoothPlastic },
				Intakes = { Color = Color3.fromRGB(30, 30, 33), Material = Enum.Material.Metal },
				Trim = { Color = Color3.fromRGB(24, 26, 28), Material = Enum.Material.Metal },
				Canopy = { Color = Color3.fromRGB(60, 20, 18), Material = Enum.Material.Glass },
				Glow = { Color = Color3.fromRGB(255, 96, 24), Material = Enum.Material.Neon },
			},
			FlareChance = 0.6,
			LockTimeMult = 1.25,
			Evasion = { React = 0.5, Jink = 300, Period = 1.1, Duration = 4.5, Cooldown = 3.5, FlareOnLock = 0.35, MaskAGL = 60,
				Tactics = { "Jink", "Mask", "Vertical", "Break" } },
			Dogfight = { Range = 2600 },
			NoseGun = { Range = 750, Rate = 5, Damage = 3, Cone = math.rad(12), HitChance = 0.25 }, -- ~3 dps on a steady target close in, much less against hard breaks
			-- heat-seeker: hold you in a 22 deg cone for 2.6 s (you hear the lock tone) -> missile; flares / break / terrain defeat it
			Missile = { Range = 1700, Cone = math.rad(22), LockTime = 2.6, Cooldown = 15, Count = 2, Damage = 34 },
		},
		-- Flying Fortress: the server-wide boss (BossServer). A giant armoured Talon bomber with
		-- turrets covering every angle; everyone's damage counts toward a shared payout.
		Fortress = {
			AssetId = 132659361677014, -- Talon bomber airframe, scaled up
			Scale = 2.6,
			PilotName = "FLYING FORTRESS",
			Persistent = true, -- streamed to every client (HUD health bar + marker from anywhere)
			Health = 2400,
			Speed = 85,
			TurnRate = 0.12,
			MinAGL = 500,
			Paint = {
				Body = { Color = Color3.fromRGB(30, 31, 34), Material = Enum.Material.Metal },
				Markings = { Color = Color3.fromRGB(200, 150, 40), Material = Enum.Material.SmoothPlastic },
				Canopy = { Color = Color3.fromRGB(60, 16, 14), Material = Enum.Material.Glass },
				Trim = { Color = Color3.fromRGB(110, 20, 18), Material = Enum.Material.Metal },
				Glow = { Color = Color3.fromRGB(255, 70, 30), Material = Enum.Material.Neon },
			},
			TailGun = { Range = 750, Rate = 9, Damage = 3, Cone = math.pi, HitChance = 0.26 }, -- turrets all round
			FlareChance = 0.7,
			LockTimeMult = 1.6,
		},
		-- Bot pilots: AI "players" in real player airframes and liveries, with player-style callsigns,
		-- so a quiet server still has dogfights; they bow out as real players join (Population)
		BotPilot = {
			Bot = true,
			Jets = { "SparrowT2", "ViperIX", "RhinoHX", "MakoSR9" }, -- bots show off the newest jet too
			Health = 100,
			Speed = 165,
			ChaseSpeed = 198, -- a touch slower than a player at full power: you can disengage
			TurnRate = 0.85,
			MinAGL = 50,
			FlareChance = 0.5,
			LockTimeMult = 1.1,
			Evasion = { React = 0.7, Jink = 260, Period = 1.3, Duration = 4, Cooldown = 5, FlareOnLock = 0.3, MaskAGL = 70,
				Tactics = { "Jink", "Mask", "Vertical", "Break" } },
			Dogfight = { Range = 2400 },
			NoseGun = { Range = 700, Rate = 5, Damage = 3, Cone = math.rad(10), HitChance = 0.2 },
			Missile = { Range = 1600, Cone = math.rad(20), LockTime = 3.0, Cooldown = 18, Count = 2, Damage = 30 },
		},
		-- Aerial refuelling tanker: friendly, untargetable, flies a wide orbit near the carrier.
		-- Slower than military power on purpose: docking means throttling back to match it.
		Tanker = {
			AssetId = 101573077056365, -- Blender tanker (Assets/Models/NPC_Tanker.fbx)
			Friendly = true,
			Health = 1,
			Speed = 125,
			TurnRate = 0.12,
			MinAGL = 400,
			Paint = {
				Body = { Color = Color3.fromRGB(196, 202, 208), Material = Enum.Material.SmoothPlastic },
				Accents = { Color = Color3.fromRGB(46, 108, 158), Material = Enum.Material.SmoothPlastic },
				Trim = { Color = Color3.fromRGB(42, 44, 48), Material = Enum.Material.Metal },
				Canopy = { Color = Color3.fromRGB(16, 26, 30), Material = Enum.Material.Glass },
				Glow = { Color = Color3.fromRGB(255, 150, 70), Material = Enum.Material.Neon },
				Drogue = { Color = Color3.fromRGB(255, 196, 40), Material = Enum.Material.Neon },
			},
			Refuel = { Radius = 45, SpeedMatch = 35, Rate = 18, LowFuel = 0.3 }, -- zone is centred on the Drogue basket part
			Orbit = { Offset = Vector3.new(1800, 1000, -1200), Radius = 1300 }, -- relative to the carrier; stays well inside the arena bounds
		},
		Drone = {
			AssetId = 108502697873184,
			Health = 24,
			Speed = 70,
			TurnRate = 0.5,
			LockTimeMult = 0.75, -- training target: easy lock, no evasion
			Paint = {
				Body = { Color = Color3.fromRGB(225, 225, 228), Material = Enum.Material.SmoothPlastic },
				Markings = { Color = Color3.fromRGB(255, 90, 20), Material = Enum.Material.SmoothPlastic },
				Glow = { Color = Color3.fromRGB(255, 96, 24), Material = Enum.Material.Neon },
			},
		},
		Destroyer = {
			AssetId = 138333943956584,
			Health = 700,
			Speed = 22,
			TurnRate = 0.06,
			Ship = true,
			LockTimeMult = 1.3, -- big but well-protected: hold the lock longer
			Paint = {
				Hull = { Color = Color3.fromRGB(58, 62, 68), Material = Enum.Material.Metal },
				Deck = { Color = Color3.fromRGB(36, 38, 42), Material = Enum.Material.Asphalt },
				Markings = { Color = CRIMSON, Material = Enum.Material.SmoothPlastic },
				Trim = { Color = Color3.fromRGB(24, 26, 28), Material = Enum.Material.Metal },
				Boot = { Color = Color3.fromRGB(110, 26, 22), Material = Enum.Material.SmoothPlastic },
				Lights = { Color = Color3.fromRGB(255, 60, 40), Material = Enum.Material.Neon },
			},
			Flak = { Range = 750, Rate = 3, Damage = 5, HitChance = 0.3 },
		},
		SAMSite = {
			AssetId = 70584784403870,
			Health = 120,
			Speed = 0,
			TurnRate = 0,
			Static = true,
			LockTimeMult = 1.0,
			Paint = {
				Hull = { Color = Color3.fromRGB(70, 74, 64), Material = Enum.Material.Metal },
				Markings = { Color = CRIMSON, Material = Enum.Material.SmoothPlastic },
				Trim = { Color = Color3.fromRGB(24, 26, 28), Material = Enum.Material.Metal },
				Lights = { Color = Color3.fromRGB(255, 60, 40), Material = Enum.Material.Neon },
			},
			Sam = { Range = 1500, Cooldown = 7, Damage = 35 },
		},
	},
	MaxNpcs = 24,
	-- keep every server feeling busy: top up with bot pilots to TargetPilots (players + bots)
	Population = { TargetPilots = 8, MaxBots = 6, RespawnDelay = 20, Centre = Vector3.new(0, 700, 0), Radius = { 1100, 1900 } },
	Callsigns = {
		Prefix = { "Sky", "Nova", "Thunder", "Ghost", "Viper", "Blaze", "Storm", "Jet", "Rogue", "Falcon", "Shadow", "Turbo", "Iron", "Neon", "Frost", "Rapid", "Sonic", "Hawk", "Cyber", "Lunar" },
		Suffix = { "Ace", "Hunter", "Wing", "Pilot", "Strike", "Fang", "Bolt", "Rider", "Maverick", "Racer", "Blade", "Knight", "Fox", "Raptor", "Jet", "X" },
	},
	-- standing Red Talon patrol: interceptors always hunting over the island (outside the carrier umbrella)
	Patrol = { Kind = "Interceptor", Count = 2, Respawn = 40, Centre = Vector3.new(0, 650, 0), Radius = 1500 },
	TickRate = 15, -- AI updates per second
	-- Engagement manager (NpcServer): who the AI fighters may attack, so a busy sky never becomes a pile-on.
	-- Each fighter gets ONE target. A player is attacked by at most Cap[tier] AI at once, none during the calm
	-- window after a launch, and a newly assigned AI holds fire for HoldFire seconds (time to see it coming).
	-- A bot a player attacks fights back regardless of the cap. Unassigned bots dogfight each other (two sides).
	Engagement = {
		Interval = 1.5, -- seconds between re-assignments
		MidRank = 10, -- tiers: Rookie = rank <= FlightConfig.RookieMaxRank, Mid = rank <= MidRank, else Vet
		Cap = { Rookie = 1, Mid = 2, Vet = 3 },
		Calm = { Rookie = 20, Mid = 12, Vet = 6 }, -- seconds after launch before any AI fighter engages
		HoldFire = 3,
		SelfDefence = 10, -- a bot hit by a player within this many seconds targets that player
		BotDogfights = true,
		BotVsBotDamage = 0.4, -- bot-on-bot gun damage multiplier (fights last and look busy)
		SamTrack = 1.2, -- seconds a SAM tracks (lock tone) before firing
		SamTrackRookie = 3.2, -- ... at ranks 1-5
		BotArena = 2700, -- bot-on-bot fights only within this distance of Population.Centre (then back to patrol)
	},
}
