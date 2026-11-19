--!strict
--[[
    Settings: steering sensitivity, invert Y, camera view (Chase / Close / Nose) and the
    missile kill cam. Mounted by SettingsClient; values live in the profile ("Settings"),
    so they follow the player to every device and server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Children, OnEvent = Fusion.Children, Fusion.OnEvent
local V = Store.Values

local CAMERA_TEXT = { Chase = "CHASE", Close = "CLOSE CHASE", Nose = "NOSE (HUD ONLY)" }

return function(scope: any, props: { [string]: any })
	local S = props.Controller
	local settings = scope:Computed(function(use) return (use(V.tHangar) :: any).Settings or {} end)

	local function row(order: number, label: string, desc: string, value: any, buttons: { any })
		local kids: { any } = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 6), Size = UDim2.new(0.5, -16, 0, 24), FontFace = Theme.Body,
				TextSize = 20, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left, Text = label }),
			scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 32), Size = UDim2.new(0.5, -16, 0, 20), FontFace = Theme.Body,
				TextSize = 15, TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = desc }),
			scope:New("TextLabel")({ BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16 - #buttons * 70, 0.5, 0), Size = UDim2.fromOffset(220, 30),
				FontFace = Theme.Mono, TextSize = 20, TextColor3 = Theme.Hud, TextXAlignment = Enum.TextXAlignment.Right, Text = value }),
		}
		for i, b in ipairs(buttons) do
			table.insert(kids, scope:New("TextButton")({
				Name = b.Name, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16 - (#buttons - i) * 70, 0.5, 0), Size = UDim2.fromOffset(62, 44),
				BackgroundColor3 = Theme.Amber, AutoButtonColor = true, Selectable = true, FontFace = Theme.Body, TextSize = 20,
				TextColor3 = Color3.fromRGB(16, 22, 29), Text = b.Text,
				[OnEvent("Activated")] = b.OnClick,
				[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
			}))
		end
		return scope:New("Frame")({ LayoutOrder = order, BackgroundColor3 = Theme.Panel, Size = UDim2.new(1, 0, 0, 62), [Children] = kids })
	end

	return scope:New("ScreenGui")({
		Name = "Settings",
		Parent = props.Parent,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 12,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		[Children] = {
			scope:New("Frame")({ Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.25, BorderSizePixel = 0 }),
			scope:New("Frame")({
				Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.8), BackgroundTransparency = 1,
				[Children] = {
					scope:New("UISizeConstraint")({ MaxSize = Vector2.new(820, 560) }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Size = UDim2.new(1, -150, 0, 40), FontFace = Theme.Display, TextSize = 26, TextColor3 = Theme.Ink,
						TextXAlignment = Enum.TextXAlignment.Left, Text = "SETTINGS" }),
					C.PrimaryButton(scope, { Name = "Close", Text = "DONE ›", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(130, 40),
						TextSize = 18, OnClick = function() S:Close() end }),
					scope:New("Frame")({
						Name = "Rows", Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -56), BackgroundTransparency = 1,
						[Children] = {
							scope:New("UIListLayout")({ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
							row(1, "STEERING SENSITIVITY", "How fast the aim follows your mouse / finger / stick",
								scope:Computed(function(use) return string.format("%.1f", use(settings).Sensitivity or 1) end), {
									{ Name = "Less", Text = "−", OnClick = function() S:Nudge("Sensitivity", -0.1) end },
									{ Name = "More", Text = "+", OnClick = function() S:Nudge("Sensitivity", 0.1) end },
								}),
							row(2, "INVERT Y", "Pull back to climb (flight-sim style)",
								scope:Computed(function(use) return if use(settings).InvertY then "ON" else "OFF" end), {
									{ Name = "Toggle", Text = "⇄", OnClick = function() S:Toggle("InvertY") end },
								}),
							row(3, "CAMERA", "Chase, a tighter chase, or a HUD-only nose view",
								scope:Computed(function(use) return CAMERA_TEXT[use(settings).Camera or "Chase"] or "CHASE" end), {
									{ Name = "Cycle", Text = "⇄", OnClick = function() S:CycleCamera() end },
								}),
							row(4, "MISSILE KILL CAM", "A quick look at your missile kills (never while you're locked)",
								scope:Computed(function(use) return if use(settings).KillCam == false then "OFF" else "ON" end), {
									{ Name = "Toggle", Text = "⇄", OnClick = function() S:Toggle("KillCam") end },
								}),
						},
					}),
				},
			}),
		},
	})
end
