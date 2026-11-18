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
		},
		Drone = {
			AssetId = 108502697873184,
			Health = 24,
			Speed = 70,
			TurnRate = 0.5,
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
