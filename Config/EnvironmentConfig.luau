--!strict
--[[
    EnvironmentConfig: Blender environment kit placement on the island.
    Deterministic (fixed seed) so every server builds the same map.
]]

return {
	Seed = 20261118,
	Kit = {
		Arch = { AssetId = 82352055139067, Collide = true },
		Spire = { AssetId = 126749124565558, Collide = true },
		Pine = { AssetId = 133068541795509, Collide = false },
		Boulder = { AssetId = 136834958822591, Collide = true },
	},
	Paint = {
		Rock = { Color = Color3.fromRGB(168, 84, 54), Material = Enum.Material.Sandstone },
		RockDark = { Color = Color3.fromRGB(96, 46, 32), Material = Enum.Material.Slate },
		Leaves = { Color = Color3.fromRGB(46, 98, 58), Material = Enum.Material.Grass },
		Bark = { Color = Color3.fromRGB(70, 46, 30), Material = Enum.Material.Wood },
	},
	-- arches over the canyon at these x positions (scaled to span the canyon)
	ArchX = { -1250, -300, 650 },
	ArchScale = 1.45,
	Spires = 16,
	Pines = 240,
	Boulders = 50,
}
