--!strict
--[[
    Components: reusable Fusion building blocks following the design system.
    Every function takes (scope, props) and returns an Instance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Theme = require(script.Parent.Theme)

local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local C = {}

-- HUD text: telemetry green, outlined so bright skies never wash it out.
function C.HudText(scope: any, p: { [string]: any })
	return scope:New("TextLabel")({
		Name = p.Name or "HudText",
		BackgroundTransparency = 1,
		AnchorPoint = p.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = p.Position,
		Size = p.Size or UDim2.fromOffset(200, 24),
		FontFace = p.Font or Theme.Mono,
		Text = p.Text,
		TextSize = p.TextSize or 18,
		TextColor3 = p.Color or Theme.Hud,
		TextXAlignment = p.XAlign or Enum.TextXAlignment.Center,
		TextTransparency = p.Transparency or 0,
		Visible = p.Visible,
		ZIndex = p.ZIndex or 2,
		[Children] = {
			scope:New("UIStroke")({ Color = Theme.HudStroke, Thickness = 1.5, Transparency = 0.35 }),
		},
	})
end

-- Thin HUD bar (fuel, heat, lock progress)
function C.HudBar(scope: any, p: { [string]: any })
	return scope:New("Frame")({
		Name = p.Name or "HudBar",
		AnchorPoint = p.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = p.Position,
		Size = p.Size or UDim2.fromOffset(140, 8),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Visible = p.Visible,
		[Children] = {
			scope:New("UIStroke")({ Color = p.Color or Theme.Hud, Thickness = 1, Transparency = 0.4 }),
			scope:New("Frame")({
				Name = "Fill",
				BorderSizePixel = 0,
				BackgroundColor3 = p.FillColor or p.Color or Theme.Hud,
				Size = scope:Computed(function(use)
					return UDim2.fromScale(math.clamp(use(p.Fill), 0, 1), 1)
				end),
			}),
		},
	})
end

-- Chamfer-style touch button (bottom-right thumb arc). Holds report down/up.
function C.TouchButton(scope: any, p: { [string]: any })
	local held = scope:Value(false)
	local color = p.Color or Theme.Hud
	return scope:New("TextButton")({
		Name = p.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = p.Position,
		Size = UDim2.fromOffset(p.SizePx or 104, p.SizePx or 104),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = scope:Computed(function(use) return if use(held) then 0.15 else 0.35 end),
		AutoButtonColor = false,
		Text = "",
		Visible = p.Visible,
		Selectable = false,
		[OnEvent("InputBegan")] = function(inp: InputObject)
			if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
				held:set(true)
				p.OnDown()
			end
		end,
		[OnEvent("InputEnded")] = function(inp: InputObject)
			if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
				held:set(false)
				if p.OnUp then p.OnUp() end
			end
		end,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0, 10) }),
			scope:New("UIStroke")({ Color = color, Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			scope:New("Frame")({ -- cooldown fill, bottom-up
				Name = "Cooldown",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				BackgroundTransparency = 0.8,
				Size = scope:Computed(function(use)
					return UDim2.fromScale(1, if p.Cooldown then math.clamp(use(p.Cooldown), 0, 1) else 0)
				end),
				[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 10) }) },
			}),
			C.HudText(scope, {
				Text = p.Label,
				Font = Theme.Body,
				TextSize = p.TextSize or 18,
				Color = color,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 0.5),
			}),
		},
	})
end

-- Amber primary action button (Deck UI)
function C.PrimaryButton(scope: any, p: { [string]: any })
	return scope:New("TextButton")({
		Name = p.Name or "Primary",
		AnchorPoint = p.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = p.Position,
		Size = p.Size or UDim2.fromOffset(260, 60),
		BackgroundColor3 = Theme.Amber,
		AutoButtonColor = true,
		FontFace = Theme.Body,
		Text = p.Text,
		TextSize = p.TextSize or 24,
		TextColor3 = Color3.fromRGB(16, 22, 29),
		Visible = p.Visible,
		Selectable = true,
		[OnEvent("Activated")] = p.OnClick,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			scope:New("UIStroke")({ Color = Theme.Hud, Thickness = 3, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Name = "Focus" }),
		},
	})
end

return C
