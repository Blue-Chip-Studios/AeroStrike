--!strict
--[[
    JetConfig
    ---------
    Every jet's identity, stats and art. Data-driven: add a jet by adding an
    entry here (and its Blender model asset id); no gameplay code changes.

    Units: studs (1 Blender metre = 1 stud), studs/s, radians/s. HUD shows
    speed as km/h = studs/s * 3.6.
]]

export type Paint = { [string]: { Color: Color3, Material: Enum.Material } }

export type Jet = {
	Id: string,
	DisplayName: string,
	Role: string,
	Order: number,
	ModelAssetId: number,
	RankRequired: number,
	CashPrice: number, -- 0 = free / starter
	GamepassKey: string?, -- MonetizationConfig key that unlocks it with Robux
	Stats: {
		MinSpeed: number, CruiseSpeed: number, MaxSpeed: number,
		Accel: number, TurnRate: number, CornerSpeed: number,
		RollRate: number, Health: number, Fuel: number,
		FuelBurn: number, BoostBurn: number,
		Missiles: number, Flares: number, LockTime: number,
		GTolerance: number, -- G before vignette/stiffening
	},
	Special: string?,
	Paints: { [string]: Paint },
	DefaultPaint: string,
}

local GUNMETAL = Color3.fromRGB(96, 108, 122)
local STEEL = Color3.fromRGB(140, 150, 160)
local AMBER = Color3.fromRGB(255, 150, 20)
local TRIM = Color3.fromRGB(34, 38, 42)
local GLASS = Color3.fromRGB(40, 90, 80)
local GLOW = Color3.fromRGB(255, 96, 24)

-- Part names come from the Blender export (one MeshPart per material).
local function standardPaint(body: Color3, accent: Color3, intakes: Color3): Paint
	return {
		Body = { Color = body, Material = Enum.Material.SmoothPlastic },
		Intakes = { Color = intakes, Material = Enum.Material.SmoothPlastic },
		Accents = { Color = accent, Material = Enum.Material.SmoothPlastic },
		Trim = { Color = TRIM, Material = Enum.Material.Metal },
		Canopy = { Color = GLASS, Material = Enum.Material.Glass },
		Glow = { Color = GLOW, Material = Enum.Material.Neon },
	}
end

local Jets: { [string]: Jet } = {
	SparrowT2 = {
		Id = "SparrowT2",
		DisplayName = "Sparrow T-2",
		Role = "Starter Trainer",
		Order = 1,
		ModelAssetId = 124123626039280,
		RankRequired = 1,
		CashPrice = 0,
		Stats = {
			MinSpeed = 70, CruiseSpeed = 160, MaxSpeed = 250,
			Accel = 45, TurnRate = 1.55, CornerSpeed = 165,
			RollRate = 4.0, Health = 100, Fuel = 100,
			FuelBurn = 0.25, BoostBurn = 2.0,
			Missiles = 2, Flares = 4, LockTime = 1.2,
			GTolerance = 6,
		},
		Paints = {
			Standard = standardPaint(GUNMETAL, AMBER, STEEL),
			Arctic = standardPaint(Color3.fromRGB(200, 208, 216), Color3.fromRGB(255, 75, 62), Color3.fromRGB(150, 158, 166)),
		},
		DefaultPaint = "Standard",
	},
	ViperIX = {
		Id = "ViperIX",
		DisplayName = "Viper IX",
		Role = "Agile Interceptor",
		Order = 2,
		ModelAssetId = 90543401942532,
		RankRequired = 3,
		CashPrice = 6000,
		Stats = {
			MinSpeed = 75, CruiseSpeed = 175, MaxSpeed = 292,
			Accel = 52, TurnRate = 1.8, CornerSpeed = 180,
			RollRate = 4.6, Health = 100, Fuel = 110,
			FuelBurn = 0.25, BoostBurn = 2.0,
			Missiles = 2, Flares = 6, LockTime = 1.1,
			GTolerance = 6.5,
		},
		Paints = {
			Standard = standardPaint(Color3.fromRGB(78, 92, 106), AMBER, STEEL),
			Nightfall = standardPaint(Color3.fromRGB(32, 36, 44), Color3.fromRGB(92, 255, 143), Color3.fromRGB(60, 66, 74)),
		},
		DefaultPaint = "Standard",
	},
	RhinoHX = {
		Id = "RhinoHX",
		DisplayName = "Rhino HX",
		Role = "Heavy Strike Fighter",
		Order = 3,
		ModelAssetId = 96342508757142,
		RankRequired = 8,
		CashPrice = 18000,
		Stats = {
			MinSpeed = 80, CruiseSpeed = 170, MaxSpeed = 278,
			Accel = 44, TurnRate = 1.35, CornerSpeed = 175,
			RollRate = 3.4, Health = 130, Fuel = 130,
			FuelBurn = 0.28, BoostBurn = 2.1,
			Missiles = 6, Flares = 8, LockTime = 1.2,
			GTolerance = 6,
		},
		Special = "TwinLock",
		Paints = {
			Standard = (function()
				local p = standardPaint(Color3.fromRGB(92, 100, 84), AMBER, Color3.fromRGB(128, 134, 120))
				p.Missiles = { Color = Color3.fromRGB(220, 222, 226), Material = Enum.Material.SmoothPlastic }
				return p
			end)(),
		},
		DefaultPaint = "Standard",
	},
	WraithX = {
		Id = "WraithX",
		DisplayName = "Wraith-X",
		Role = "Premium Stealth Ace",
		Order = 4,
		ModelAssetId = 131181747205851,
		RankRequired = 15,
		CashPrice = 60000,
		GamepassKey = "WraithX",
		Stats = {
			MinSpeed = 80, CruiseSpeed = 190, MaxSpeed = 347,
			Accel = 58, TurnRate = 1.65, CornerSpeed = 190,
			RollRate = 4.4, Health = 100, Fuel = 120,
			FuelBurn = 0.24, BoostBurn = 1.9,
			Missiles = 4, Flares = 8, LockTime = 1.1,
			GTolerance = 6.5,
		},
		Special = "LowObservable",
		Paints = {
			Standard = {
				Body = { Color = Color3.fromRGB(34, 37, 44), Material = Enum.Material.SmoothPlastic },
				Accents = { Color = Color3.fromRGB(255, 196, 80), Material = Enum.Material.Metal },
				Trim = { Color = TRIM, Material = Enum.Material.Metal },
				Canopy = { Color = Color3.fromRGB(150, 110, 30), Material = Enum.Material.Glass },
				Glow = { Color = GLOW, Material = Enum.Material.Neon },
			},
		},
		DefaultPaint = "Standard",
	},
}

local function GetOrdered(): { Jet }
	local t = {}
	for _, j in pairs(Jets) do table.insert(t, j) end
	table.sort(t, function(a, b) return a.Order < b.Order end)
	return t
end

return {
	Jets = Jets,
	StarterJet = "SparrowT2",
	GetOrdered = GetOrdered,
	KmhPerStud = 3.6,
}
