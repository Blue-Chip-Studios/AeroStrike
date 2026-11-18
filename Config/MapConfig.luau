--!strict
--[[
    MapConfig: carrier placement, catapults, zones. Offsets are in the
    carrier model's local space (pivot = waterline centre; bow = -Z), measured
    from the Blender export (Blender +X -> Roblox -X, Blender Y -> Roblox Z).
]]

local CARRIER_CF = CFrame.new(-3200, 0, 0) * CFrame.Angles(0, math.rad(-90), 0) -- bow points +X (toward the island)

local DECK_Y = 26.2

local function catapult(x: number): { Start: CFrame, End: CFrame }
	return {
		Start = CFrame.lookAt(Vector3.new(x, DECK_Y + 3.2, -68), Vector3.new(x, DECK_Y + 3.2, -200)),
		End = CFrame.lookAt(Vector3.new(x, DECK_Y + 3.2, -148), Vector3.new(x, DECK_Y + 3.2, -300)),
	}
end

return {
	Carrier = {
		AssetId = 126040939111225,
		CFrame = CARRIER_CF,
		DeckY = DECK_Y,
		Catapults = { catapult(9), catapult(-9) },
		-- simple invisible colliders (meshes have CanCollide off)
		Colliders = {
			{ Name = "DeckMain", CFrame = CFrame.new(0, DECK_Y - 0.6, 0), Size = Vector3.new(52, 1.2, 304) },
			{ Name = "DeckAngled", CFrame = CFrame.new(20, DECK_Y - 0.6, 30) * CFrame.Angles(0, math.rad(9), 0), Size = Vector3.new(26, 1.2, 180) },
			{ Name = "Island", CFrame = CFrame.new(-19, 38, 35), Size = Vector3.new(8, 25, 34) },
			{ Name = "Hull", CFrame = CFrame.new(0, 12, 0), Size = Vector3.new(44, 24, 296) },
		},
		Paint = {
			Hull = { Color = Color3.fromRGB(62, 70, 78), Material = Enum.Material.Metal },
			Boot = { Color = Color3.fromRGB(110, 26, 22), Material = Enum.Material.SmoothPlastic },
			Deck = { Color = Color3.fromRGB(34, 37, 40), Material = Enum.Material.Asphalt },
			Markings = { Color = Color3.fromRGB(225, 225, 215), Material = Enum.Material.SmoothPlastic },
			Amber = { Color = Color3.fromRGB(255, 150, 20), Material = Enum.Material.Neon },
			Island = { Color = Color3.fromRGB(78, 86, 94), Material = Enum.Material.Metal },
			Trim = { Color = Color3.fromRGB(22, 24, 26), Material = Enum.Material.Metal },
		},
		SafeRadius = 1200, -- CIWS/SAM umbrella
		BankRadius = 260,
	},
	MapCentre = Vector3.new(0, 0, 0),
}
