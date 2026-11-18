--!strict
--[[
    Theme: the UI design system (Docs/UI/DesignSystem.html) as code.
    Colour meaning is fixed: amber = action/money, green = info, red = danger,
    blue = squad, gold = prestige.
]]

local Theme = {
	Night = Color3.fromRGB(11, 18, 26),
	Panel = Color3.fromRGB(19, 29, 40),
	Raised = Color3.fromRGB(26, 38, 51),
	Line = Color3.fromRGB(46, 65, 83),
	Ink = Color3.fromRGB(232, 238, 244),
	Mute = Color3.fromRGB(143, 161, 179),
	Hud = Color3.fromRGB(92, 255, 143),
	HudStroke = Color3.fromRGB(6, 17, 10),
	Amber = Color3.fromRGB(255, 194, 61),
	Threat = Color3.fromRGB(255, 75, 62),
	Squad = Color3.fromRGB(79, 169, 255),
	Gold = Color3.fromRGB(255, 216, 107),

	Display = Font.new("rbxasset://fonts/families/Michroma.json"),
	Body = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
}

return Theme
