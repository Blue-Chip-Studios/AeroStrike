--!strict
--[[
    Season: the free season track (20 tiers filled by all XP you earn), smoke trails to
    equip, plus codes, friend invites and the group reward. Deck UI style.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local SeasonConfig = require(ReplicatedStorage.Config.SeasonConfig)

local Children, OnEvent = Fusion.Children, Fusion.OnEvent
local V = Store.Values
local S = SeasonConfig.Season

local function swatch(scope: any, colors: { Color3 }, size: UDim2, pos: UDim2?)
	local kp = {}
	for i, c in ipairs(colors) do table.insert(kp, ColorSequenceKeypoint.new(if #colors == 1 then (i - 1) else (i - 1) / (#colors - 1), c)) end
	if #colors == 1 then table.insert(kp, ColorSequenceKeypoint.new(1, colors[1])) end
	return scope:New("Frame")({
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }), scope:New("UIGradient")({ Color = ColorSequence.new(kp) }) },
	})
end

return function(scope: any, props: { [string]: any })
	local Ctl = props.Controller
	local season = scope:Computed(function(use) local h = use(V.tHangar) :: any return (h and h.Season) or { Id = S.Id, XP = 0, Tier = 0 } end)
	local owned = scope:Computed(function(use) local h = use(V.tHangar) :: any return (h and h.Trails) or {} end)
	local equipped = scope:Computed(function(use) local h = use(V.tHangar) :: any return (h and h.EquippedTrail) or "" end)

	-- tier tiles
	local tiles = {}
	for t, r in ipairs(S.Tiers) do
		local got = scope:Computed(function(use) return (use(season) :: any).Tier >= t end)
		table.insert(tiles, scope:New("Frame")({
			Name = "T" .. t, LayoutOrder = t, BackgroundColor3 = Theme.Panel,
			[Children] = {
				scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
				scope:New("UIStroke")({ Color = scope:Computed(function(use) return if use(got) then Theme.Hud else Theme.Line end), Thickness = 1.5 }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 16), FontFace = Theme.Display, TextSize = 12,
					TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, Text = "TIER " .. t }),
				(if r.Trail then swatch(scope, SeasonConfig.Trails[r.Trail].Colors, UDim2.new(1, -16, 0, 14), UDim2.fromOffset(8, 30)) else
					scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 24), Size = UDim2.new(1, -12, 0, 26), FontFace = Theme.Mono, TextSize = 18,
						TextColor3 = Theme.Amber, Text = "◉" .. tostring(r.Cash) })),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.new(0, 6, 1, -22), Size = UDim2.new(1, -12, 0, 18), FontFace = Theme.Body, TextSize = 12,
					TextColor3 = scope:Computed(function(use) return if use(got) then Theme.Hud else Theme.Ink end), TextTruncate = Enum.TextTruncate.AtEnd,
					Text = scope:Computed(function(use)
						local label = if r.Trail then SeasonConfig.Trails[r.Trail].Name else "Cash"
						return if use(got) then "✓ " .. label else label
					end) }),
			},
		}))
	end

	-- trail buttons (owned ones; "NO TRAIL" first)
	local trailBtns = {}
	local order = { "", "BlueChip", "Crimson", "Sky", "Emerald", "Solar", "Violet", "Arctic", "Inferno", "Spectrum" }
	for i, id in ipairs(order) do
		local def = SeasonConfig.Trails[id]
		table.insert(trailBtns, scope:New("TextButton")({
			Name = "Trail_" .. (if id == "" then "None" else id), LayoutOrder = i, Size = UDim2.fromOffset(150, 44), BackgroundColor3 = Theme.Panel, AutoButtonColor = true, Selectable = true,
			Visible = scope:Computed(function(use) return id == "" or (use(owned) :: any)[id] == true end),
			FontFace = Theme.Body, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = scope:Computed(function(use) return if use(equipped) == id then Theme.Hud else Theme.Ink end),
			Text = scope:Computed(function(use) local n = if def then def.Name else "No trail" return "      " .. (if use(equipped) == id then "✓ " .. n else n) end),
			[OnEvent("Activated")] = function() Ctl:Equip(id) end,
			[Children] = {
				scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				scope:New("UIStroke")({ Color = scope:Computed(function(use) return if use(equipped) == id then Theme.Hud else Theme.Line end), Thickness = 1.5 }),
				(if def then swatch(scope, def.Colors, UDim2.fromOffset(16, 28), UDim2.fromOffset(8, 8)) else nil) :: any,
			},
		}))
	end

	local codeText = scope:Value("")
	local daysLeft = math.max(0, math.ceil((S.EndsAt - os.time()) / 86400))

	return scope:New("ScreenGui")({
		Name = "Season", Parent = props.Parent, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 11,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		[Children] = {
			scope:New("Frame")({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.2, BorderSizePixel = 0 }),
			scope:New("Frame")({
				Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.92, 0.9), BackgroundTransparency = 1,
				[Children] = {
					scope:New("UISizeConstraint")({ MaxSize = Vector2.new(1180, 820) }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Size = UDim2.new(1, -150, 0, 34), FontFace = Theme.Display, TextSize = 24, TextColor3 = Theme.Ink,
						TextXAlignment = Enum.TextXAlignment.Left, Text = S.Name }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, -150, 0, 20), FontFace = Theme.Body, TextSize = 15,
						TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, Text = `Free track · every XP you earn counts · {daysLeft} days left` }),
					C.PrimaryButton(scope, { Name = "Close", Text = "BACK ›", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(130, 40),
						TextSize = 18, OnClick = function() Ctl:Close() end }),
					scope:New("ScrollingFrame")({
						Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5,
						AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
						[Children] = {
							scope:New("UIListLayout")({ Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }),
							-- progress
							C.HudText(scope, { LayoutOrder = 1, Font = Theme.Display, TextSize = 16, Color = Theme.Amber, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
								Size = UDim2.new(1, 0, 0, 22),
								Text = scope:Computed(function(use)
									local s = use(season) :: any
									if s.Tier >= #S.Tiers then return "TRACK COMPLETE! ALL 20 TIERS EARNED" end
									local into = s.XP - s.Tier * S.XPPerTier
									return string.format("TIER %d / %d   ·   %d / %d XP TO TIER %d", s.Tier, #S.Tiers, into, S.XPPerTier, s.Tier + 1)
								end) }),
							C.HudBar(scope, { LayoutOrder = 2, AnchorPoint = Vector2.zero, Size = UDim2.new(1, 0, 0, 8), FillColor = Theme.Amber,
								Fill = scope:Computed(function(use) local s = use(season) :: any return if s.Tier >= #S.Tiers then 1 else (s.XP - s.Tier * S.XPPerTier) / S.XPPerTier end) }),
							scope:New("Frame")({ LayoutOrder = 3, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0),
								[Children] = { scope:New("UIGridLayout")({ CellSize = UDim2.fromOffset(104, 84), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }), tiles } }),
							-- trails
							scope:New("TextLabel")({ LayoutOrder = 4, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), FontFace = Theme.Display, TextSize = 13,
								TextColor3 = Theme.Hud, TextXAlignment = Enum.TextXAlignment.Left, Text = "SMOKE TRAILS · EVERYONE SEES YOURS" }),
							scope:New("Frame")({ LayoutOrder = 5, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0),
								[Children] = { scope:New("UIGridLayout")({ CellSize = UDim2.fromOffset(150, 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }), trailBtns } }),
							-- codes, invites, group
							scope:New("TextLabel")({ LayoutOrder = 6, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), FontFace = Theme.Display, TextSize = 13,
								TextColor3 = Theme.Hud, TextXAlignment = Enum.TextXAlignment.Left, Text = "CODES · FRIENDS · GROUP" }),
							scope:New("Frame")({ LayoutOrder = 7, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44),
								[Children] = {
									scope:New("UIListLayout")({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
									scope:New("TextBox")({ LayoutOrder = 1, Size = UDim2.fromOffset(220, 44), BackgroundColor3 = Theme.Panel, FontFace = Theme.Mono, TextSize = 18,
										TextColor3 = Theme.Ink, PlaceholderText = "ENTER CODE", PlaceholderColor3 = Theme.Mute, Text = "", ClearTextOnFocus = false,
										[Fusion.Out("Text")] = codeText,
										[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }), scope:New("UIStroke")({ Color = Theme.Line, Thickness = 1.5 }) } }),
									C.PrimaryButton(scope, { LayoutOrder = 2, Name = "Redeem", Text = "REDEEM", AnchorPoint = Vector2.zero, Size = UDim2.fromOffset(130, 44), TextSize = 17,
										OnClick = function() Ctl:Redeem(Fusion.peek(codeText)) end }),
									C.PrimaryButton(scope, { LayoutOrder = 3, Name = "Invite", Text = "INVITE FRIENDS (+500 EACH)", AnchorPoint = Vector2.zero, Size = UDim2.fromOffset(290, 44), TextSize = 16,
										OnClick = function() Ctl:Invite() end }),
									C.PrimaryButton(scope, { LayoutOrder = 4, Name = "Group", Text = "GROUP REWARD", AnchorPoint = Vector2.zero, Size = UDim2.fromOffset(190, 44), TextSize = 16,
										OnClick = function() Ctl:CheckGroup() end }),
								} }),
							scope:New("TextLabel")({ LayoutOrder = 8, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), FontFace = Theme.Body, TextSize = 14,
								TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left,
								Text = "Join the Blue Chip Games group for 1,000 Cash + the exclusive Blue Chip Squadron trail." }),
							scope:New("TextLabel")({ LayoutOrder = 9, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), FontFace = Theme.Body, TextSize = 17,
								TextColor3 = Theme.Amber, TextXAlignment = Enum.TextXAlignment.Left, Text = V.sSeasonMsg }),
						},
					}),
				},
			}),
		},
	})
end
