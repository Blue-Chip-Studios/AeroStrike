--!strict
--[[
    HUD: the in-flight fighter HUD + deck launch overlay + death relaunch.
    Reads Store values only (written by Flight/Weapons/Economy controllers).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Children = Fusion.Children
local V = Store.Values

return function(scope: any, props: { [string]: any })
	local ClientModules = ReplicatedStorage:WaitForChild("ClientModules")
	local Input = require(ClientModules:WaitForChild("InputController")) :: any
	local Flight = require(ClientModules:WaitForChild("FlightController")) :: any

	local flying = scope:Computed(function(use) local p = use(V.sPhase) return p == "Flying" or p == "Catapult" end)
	local onDeck = scope:Computed(function(use) local p = use(V.sPhase) return p == "Deck" or p == "Launching" end)
	local dead = scope:Computed(function(use) return use(V.sPhase) == "Dead" end)
	local touch = V.bTouch

	local function screenPos(val: any)
		return scope:Computed(function(use)
			local v = use(val) :: Vector2
			return UDim2.fromOffset(v.X, v.Y)
		end)
	end

	return scope:New("ScreenGui")({
		Name = "HUD",
		Parent = props.Parent,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.None, -- vignette must cover the full screen; controls add their own safe margins
		[Children] = {
			-- G-force vignette: four gradient edges, darker red as G climbs
			(function()
				local strength = scope:Computed(function(use)
					local g = use(V.nG) :: number
					return math.clamp((g - 5) / 4, 0, 0.9)
				end)
				local edges = {}
				for _, e in ipairs({
					{ "L", UDim2.fromScale(0, 0), UDim2.fromScale(0.28, 1), 0 },
					{ "R", UDim2.fromScale(0.72, 0), UDim2.fromScale(0.28, 1), 180 },
					{ "T", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.3), 90 },
					{ "B", UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.3), 270 },
				}) do
					table.insert(edges, scope:New("Frame")({
						Name = "V" .. e[1],
						Position = e[2],
						Size = e[3],
						BorderSizePixel = 0,
						BackgroundColor3 = Color3.fromRGB(40, 0, 0),
						BackgroundTransparency = scope:Computed(function(use) return 1 - use(strength) end),
						[Children] = {
							scope:New("UIGradient")({
								Rotation = e[4],
								Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
							}),
						},
					}))
				end
				return scope:New("Folder")({ Name = "Vignette", [Children] = edges })
			end)(),

			-- FLIGHT HUD ------------------------------------------------------
			scope:New("Frame")({
				Name = "Flight",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = flying,
				[Children] = {
					-- nose marker (small cross) and aim circle
					C.HudText(scope, { Name = "Nose", Text = "+", TextSize = 28, Position = screenPos(V.tNoseScreen), Size = UDim2.fromOffset(30, 30) }),
					scope:New("Frame")({
						Name = "Aim",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = screenPos(V.tAimScreen),
						Size = UDim2.fromOffset(34, 34),
						BackgroundTransparency = 1,
						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
							scope:New("UIStroke")({ Color = Theme.Hud, Thickness = 2, Transparency = 0.15 }),
						},
					}),
					-- speed (left) and altitude (right)
					C.HudText(scope, { Name = "SpdLbl", Text = "SPD KM/H", Font = Theme.Display, TextSize = 12, Position = UDim2.new(0.24, 0, 0.42, 0) }),
					C.HudText(scope, { Name = "Spd", TextSize = 30, Position = UDim2.new(0.24, 0, 0.47, 0),
						Text = scope:Computed(function(use) return tostring(use(V.nSpeedKmh)) end) }),
					C.HudText(scope, { Name = "AltLbl", Text = "ALT", Font = Theme.Display, TextSize = 12, Position = UDim2.new(0.76, 0, 0.42, 0) }),
					C.HudText(scope, { Name = "Alt", TextSize = 30, Position = UDim2.new(0.76, 0, 0.47, 0),
						Text = scope:Computed(function(use) return tostring(use(V.nAltitude)) end) }),
					-- heading
					C.HudText(scope, { Name = "Hdg", TextSize = 16, Position = UDim2.new(0.5, 0, 0.06, 0),
						Text = scope:Computed(function(use) return string.format("%03d", math.floor(use(V.nHeading))) end) }),
					-- G meter
					C.HudText(scope, { Name = "G", TextSize = 26, Position = UDim2.new(0.24, 0, 0.56, 0),
						Color = scope:Computed(function(use) return if use(V.nG) > 6 then Theme.Amber else Theme.Hud end),
						Text = scope:Computed(function(use) return string.format("%.1f G", use(V.nG)) end) }),
					-- fuel
					C.HudText(scope, { Name = "FuelLbl", Text = "FUEL", Font = Theme.Display, TextSize = 12, Position = UDim2.new(0.76, 0, 0.555, 0) }),
					C.HudBar(scope, { Name = "Fuel", Position = UDim2.new(0.76, 0, 0.585, 0), Size = UDim2.fromOffset(150, 10),
						Fill = V.nFuel, FillColor = Theme.Amber,
						Color = scope:Computed(function(use) return if use(V.nFuel) < 0.2 then Theme.Threat else Theme.Hud end) }),
					-- shield
					C.HudText(scope, { Name = "Shield", Text = "SPAWN SHIELD", Font = Theme.Display, TextSize = 14, Color = Theme.Squad,
						Position = UDim2.new(0.5, 0, 0.7, 0), Visible = V.bShield }),
					-- launch result toast
					C.HudText(scope, { Name = "LaunchResult", Font = Theme.Display, TextSize = 34, Color = Theme.Amber,
						Position = UDim2.new(0.5, 0, 0.3, 0), Size = UDim2.fromOffset(700, 50), Text = V.sLaunchResult }),
					-- objective / prompt
					C.HudText(scope, { Name = "Prompt", Font = Theme.Body, TextSize = 24, Color = Theme.Ink,
						Position = UDim2.new(0.5, 0, 0.18, 0), Size = UDim2.fromOffset(800, 40), Text = V.sPrompt }),
				},
			}),

			-- DECK / LAUNCH OVERLAY ---------------------------------------------
			scope:New("Frame")({
				Name = "Deck",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = onDeck,
				[Children] = {
					C.HudText(scope, { Text = "CATAPULT READY", Font = Theme.Display, TextSize = 22, Color = Theme.Ink, Position = UDim2.fromScale(0.5, 0.62) }),
					-- timing bar with the perfect window highlighted
					scope:New("Frame")({
						Name = "LaunchBar",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.68),
						Size = UDim2.fromOffset(420, 18),
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.45,
						BorderSizePixel = 0,
						[Children] = {
							scope:New("UIStroke")({ Color = Theme.Line, Thickness = 1 }),
							scope:New("Frame")({ Name = "Perfect", BorderSizePixel = 0, BackgroundColor3 = Theme.Hud, BackgroundTransparency = 0.55,
								Position = UDim2.fromScale(0.62, 0), Size = UDim2.fromScale(0.16, 1) }),
							scope:New("Frame")({ Name = "Needle", AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundColor3 = Theme.Amber,
								Size = UDim2.new(0, 5, 1, 10),
								Position = scope:Computed(function(use) return UDim2.fromScale(use(V.nLaunchBar), 0.5) end) }),
						},
					}),
					C.HudText(scope, { Font = Theme.Body, TextSize = 20, Color = Theme.Mute, Position = UDim2.fromScale(0.5, 0.735), Size = UDim2.fromOffset(700, 30),
						Text = scope:Computed(function(use)
							if use(touch) then return "Tap BOOST in the green zone for a Perfect Launch" end
							if use(V.bGamepad) then return "Press RT / A in the green zone for a Perfect Launch" end
							return "Press W, Shift or Enter in the green zone for a Perfect Launch"
						end) }),
				},
			}),

			-- DEATH / RELAUNCH -------------------------------------------------
			scope:New("Frame")({
				Name = "Dead",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = dead,
				[Children] = {
					C.HudText(scope, { Text = "SHOT DOWN", Font = Theme.Display, TextSize = 34, Color = Theme.Threat, Position = UDim2.fromScale(0.5, 0.38) }),
					C.PrimaryButton(scope, { Name = "Relaunch", Text = "RELAUNCH", Position = UDim2.fromScale(0.5, 0.62),
						OnClick = function() Flight:Relaunch() end }),
				},
			}),

			-- TOUCH CONTROLS (thumb arc, bottom-right) --------------------------
			scope:New("Frame")({
				Name = "Touch",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -24, 1, -24),
				Size = UDim2.fromOffset(300, 300),
				Visible = scope:Computed(function(use) return use(touch) and (use(flying) or use(onDeck)) end),
				[Children] = {
					C.TouchButton(scope, { Name = "Boost", Label = "BOOST", Color = Theme.Amber, SizePx = 132, Position = UDim2.fromOffset(222, 222),
						OnDown = function() Input:SetTouch("Boost", true) end, OnUp = function() Input:SetTouch("Boost", false) end }),
					C.TouchButton(scope, { Name = "Guns", Label = "GUNS", Position = UDim2.fromOffset(222, 70),
						OnDown = function() Input:SetTouch("Guns", true) end, OnUp = function() Input:SetTouch("Guns", false) end }),
					C.TouchButton(scope, { Name = "Missile", Label = "MISSILE", Color = Theme.Threat, Position = UDim2.fromOffset(92, 92),
						OnDown = function() Input:SetTouch("Missile", true) end, OnUp = function() Input:SetTouch("Missile", false) end }),
					C.TouchButton(scope, { Name = "Flare", Label = "FLARE", Position = UDim2.fromOffset(70, 222), Cooldown = V.nFlareCooldown,
						OnDown = function() Input:SetTouch("Flare", true) end, OnUp = function() Input:SetTouch("Flare", false) end }),
				},
			}),
		},
	})
end
