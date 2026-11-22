--!strict
--[[
    CosmeticsConfig: paid cosmetic liveries (Robux developer products in MonetizationConfig).
    Paints are merged into EVERY jet (JetConfig), like the mastery schemes, and are locked
    until owned (profile key ShopPaints). Trails live in SeasonConfig.Trails like the others
    and unlock through the profile key Trails. Cosmetic only: no combat power.
]]

export type ShopPaint = { Name: string, Body: Color3, Accents: Color3, Intakes: Color3?, Material: Enum.Material?, Product: string }

local Paints: { [string]: ShopPaint } = {
	Hornet = { Name = "Hornet", Body = Color3.fromRGB(255, 190, 20), Accents = Color3.fromRGB(20, 20, 24), Intakes = Color3.fromRGB(28, 28, 32), Product = "HornetPaint" },
	Nightshade = { Name = "Night Shade", Body = Color3.fromRGB(58, 20, 96), Accents = Color3.fromRGB(125, 255, 90), Intakes = Color3.fromRGB(26, 10, 44), Product = "AcePack" },
}

-- trail id -> the cheapest product that unlocks it (for "buy" prompts)
local Trails: { [string]: string } = {
	Phoenix = "PhoenixTrail",
}

return {
	Paints = Paints,
	Trails = Trails,
}
