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
			NoseGun = { Range = 650, Rate = 5, Damage = 3, Cone = math.rad(8), HitChance = 0.25 }, -- ~2.6 dps at close range: dangerous, beatable
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
	MaxNpcs = 18,
	TickRate = 15, -- AI updates per second
}
