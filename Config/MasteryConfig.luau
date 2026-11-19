--!strict
--[[
    MasteryConfig: per-jet mastery. Every XP you earn while flying a jet also goes into that
    jet's mastery. Levels unlock paint schemes (JetConfig merges these into every jet's Paints),
    cash, and at level 10 the Master Aviator badge. Gives owned jets a reason to keep flying.
]]

export type Scheme = { Body: Color3, Accents: Color3, Intakes: Color3?, Material: Enum.Material? }

-- cumulative mastery XP needed for each level (level 1 = 0)
local Levels = { 0, 400, 1000, 1800, 2900, 4300, 6100, 8400, 11200, 14600 }

-- paint schemes unlocked by level (applied on top of each jet's Standard paint)
local Schemes: { [string]: Scheme & { Name: string, Level: number } } = {
	Splinter = { Name = "Splinter Camo", Level = 2, Body = Color3.fromRGB(122, 128, 104), Accents = Color3.fromRGB(70, 74, 58), Intakes = Color3.fromRGB(96, 100, 82) },
	Desert = { Name = "Desert Strike", Level = 4, Body = Color3.fromRGB(196, 168, 120), Accents = Color3.fromRGB(140, 104, 64), Intakes = Color3.fromRGB(170, 146, 104) },
	NightOps = { Name = "Night Ops", Level = 6, Body = Color3.fromRGB(28, 30, 36), Accents = Color3.fromRGB(255, 60, 60), Intakes = Color3.fromRGB(44, 46, 54) },
	RedTalon = { Name = "Red Talon", Level = 8, Body = Color3.fromRGB(170, 30, 34), Accents = Color3.fromRGB(240, 240, 240), Intakes = Color3.fromRGB(120, 24, 28) },
	GoldAce = { Name = "Gold Ace", Level = 10, Body = Color3.fromRGB(212, 168, 64), Accents = Color3.fromRGB(30, 30, 34), Intakes = Color3.fromRGB(176, 136, 48), Material = Enum.Material.Metal },
}

-- other rewards by level
local Rewards: { [number]: { Cash: number? } } = {
	[3] = { Cash = 500 },
	[5] = { Cash = 1000 },
	[7] = { Cash = 1500 },
	[9] = { Cash = 2500 },
}

local function LevelFor(xp: number): number
	local lvl = 1
	for i, need in ipairs(Levels) do
		if xp >= need then lvl = i end
	end
	return lvl
end

return {
	Levels = Levels,
	MaxLevel = #Levels,
	Schemes = Schemes,
	Rewards = Rewards,
	LevelFor = LevelFor,
}
