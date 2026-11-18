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
	-- Further jets (Viper IX, Rhino HX, Wraith-X) are added as their Blender
	-- models are produced; stats are in the GDD §10.
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
