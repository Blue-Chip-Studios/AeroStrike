--!strict
--[[
    Hangar: jets, specs, upgrades, buy/equip. Deck UI style (gunmetal panels,
    amber primary action). Mounted on demand by HangarClient. Every action
    goes to the server Shop remote; the UI only reflects replicated state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local JetConfig = require(ReplicatedStorage.Config.JetConfig)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local JetStats = require(ReplicatedStorage.Shared.JetStats)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek
local V = Store.Values

local TRACKS = {
	{ Key = "Engine", Label = "ENGINE", Desc = "+3% top speed" },
	{ Key = "Fuel", Label = "FUEL TANKS", Desc = "+10% fuel" },
	{ Key = "GSuit", Label = "G-SUIT", Desc = "+0.4 G tolerance" },
	{ Key = "Flares", Label = "FLARE POD", Desc = "+1 flare" },
	{ Key = "Seeker", Label = "SEEKER", Desc = "-6% lock time" },
}

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

return function(scope: any, props: { [string]: any })
	local Hangar = props.Controller

	local selected = V.sHangarSelected
	local jetCfg = scope:Computed(function(use) return JetConfig.Jets[use(selected)] or JetConfig.Jets.SparrowT2 end)
	local owned = scope:Computed(function(use)
		local h = use(V.tHangar)
		return h.OwnedJets and h.OwnedJets[use(selected)] == true
	end)
	local equipped = scope:Computed(function(use) return (use(V.tHangar).EquippedJet or "SparrowT2") == use(selected) end)
	local ups = scope:Computed(function(use)
		local h = use(V.tHangar)
		return (h.Upgrades and h.Upgrades[use(selected)]) or {}
	end)
	local stats = scope:Computed(function(use) return JetStats.Compute(use(selected), use(ups), nil) end)

	local function statRow(label: string, value: (any) -> number, max: number, order: number)
		return scope:New("Frame")({
			LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22),
			[Children] = {
				scope:New("TextLabel")({ BackgroundTransparency = 1, Size = UDim2.new(0, 120, 1, 0), FontFace = Theme.Body, TextSize = 16,
					TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, Text = label }),
				scope:New("Frame")({ Position = UDim2.new(0, 124, 0.5, -4), Size = UDim2.new(1, -190, 0, 8), BackgroundColor3 = Theme.Raised, BorderSizePixel = 0,
					[Children] = { scope:New("Frame")({ BorderSizePixel = 0, BackgroundColor3 = Theme.Hud,
						Size = scope:Computed(function(use) return UDim2.fromScale(math.clamp(value(use(stats)) / max, 0, 1), 1) end) }) } }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 60, 1, 0),
					FontFace = Theme.Mono, TextSize = 15, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Right,
					Text = scope:Computed(function(use) return tostring(math.floor(value(use(stats)) + 0.5)) end) }),
			},
		})
	end

	local jetCards = {}
	for i, j in ipairs(JetConfig.GetOrdered()) do
		table.insert(jetCards, scope:New("TextButton")({
			Name = j.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 84),
			AutoButtonColor = false,
			Text = "",
			Selectable = true,
			BackgroundColor3 = scope:Computed(function(use) return if use(selected) == j.Id then Theme.Raised else Theme.Panel end),
			[OnEvent("Activated")] = function() selected:set(j.Id) end,
			[Children] = {
				scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				scope:New("Frame")({ Size = UDim2.new(0, 4, 1, 0), BorderSizePixel = 0,
					BackgroundColor3 = scope:Computed(function(use) return if use(selected) == j.Id then Theme.Amber else Theme.Line end) }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -24, 0, 16), FontFace = Theme.Display,
					TextSize = 11, TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, Text = `TIER {j.Order} · {string.upper(j.Role)}` }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 26), Size = UDim2.new(1, -24, 0, 26), FontFace = Theme.Body,
					TextSize = 22, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left, Text = string.upper(j.DisplayName) }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -24, 0, 20), FontFace = Theme.Mono,
					TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = scope:Computed(function(use) local h = use(V.tHangar) return if h.OwnedJets and h.OwnedJets[j.Id] then Theme.Hud else Theme.Amber end),
					Text = scope:Computed(function(use)
						local h = use(V.tHangar)
						if (h.EquippedJet or "SparrowT2") == j.Id then return "EQUIPPED" end
						if h.OwnedJets and h.OwnedJets[j.Id] then return "OWNED" end
						if j.CashPrice <= 0 then return "FREE" end
						return `◉ {fmt(j.CashPrice)}  ·  RANK {j.RankRequired}`
					end) }),
			},
		}))
	end

	local upgradeRows = {}
	for i, tr in ipairs(TRACKS) do
		table.insert(upgradeRows, scope:New("Frame")({
			LayoutOrder = i, BackgroundColor3 = Theme.Panel, Size = UDim2.new(1, 0, 0, 44),
			[Children] = {
				scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 3), Size = UDim2.new(0, 200, 0, 20), FontFace = Theme.Body,
					TextSize = 17, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left, Text = tr.Label }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 22), Size = UDim2.new(0, 200, 0, 18), FontFace = Theme.Body,
					TextSize = 14, TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, Text = tr.Desc }),
				-- level pips
				scope:New("Frame")({ BackgroundTransparency = 1, Position = UDim2.new(0, 220, 0.5, -6), Size = UDim2.fromOffset(110, 12),
					[Children] = (function()
						local pips = { scope:New("UIListLayout")({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }) }
						for p = 1, EconomyConfig.MaxUpgradeLevel do
							table.insert(pips, scope:New("Frame")({ LayoutOrder = p, Size = UDim2.fromOffset(18, 12), BorderSizePixel = 0,
								BackgroundColor3 = scope:Computed(function(use) return if (use(ups)[tr.Key] or 0) >= p then Theme.Hud else Theme.Raised end) }))
						end
						return pips
					end)() }),
				scope:New("TextButton")({
					Name = "Buy", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 36),
					BackgroundColor3 = scope:Computed(function(use)
						local lvl = use(ups)[tr.Key] or 0
						return if not use(owned) or lvl >= EconomyConfig.MaxUpgradeLevel then Theme.Raised else Theme.Amber
					end),
					AutoButtonColor = true, Selectable = true, FontFace = Theme.Mono, TextSize = 15,
					TextColor3 = scope:Computed(function(use) return if not use(owned) then Theme.Mute else Color3.fromRGB(16, 22, 29) end),
					Text = scope:Computed(function(use)
						local lvl = use(ups)[tr.Key] or 0
						if lvl >= EconomyConfig.MaxUpgradeLevel then return "MAX" end
						return "◉ " .. fmt(EconomyConfig.UpgradeCosts[tr.Key][lvl + 1])
					end),
					[OnEvent("Activated")] = function() Hangar:Upgrade(peek(selected), tr.Key) end,
					[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
				}),
			},
		}))
	end

	local primaryText = scope:Computed(function(use)
		local j = use(jetCfg)
		if use(equipped) then return "EQUIPPED" end
		if use(owned) then return "EQUIP" end
		if use(V.nRank) < j.RankRequired then return `RANK {j.RankRequired} REQUIRED` end
		return `BUY  ◉ {fmt(j.CashPrice)}`
	end)

	local root = scope:New("ScreenGui")({
		Name = "Hangar",
		Parent = props.Parent,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		[Children] = {
			scope:New("Frame")({ Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.25, BorderSizePixel = 0 }),
			scope:New("Frame")({
				Name = "Window",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.92, 0.88),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New("UISizeConstraint")({ MaxSize = Vector2.new(1280, 760) }),
					-- header
					scope:New("TextLabel")({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), FontFace = Theme.Display, TextSize = 26,
						TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left, Text = "HANGAR" }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 4), Size = UDim2.fromOffset(240, 34),
						FontFace = Theme.Mono, TextSize = 22, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Right,
						Text = scope:Computed(function(use) return "◉ " .. fmt(use(V.nCash)) end) }),
					C.PrimaryButton(scope, { Name = "Close", Text = "LAUNCH ›", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
						Size = UDim2.fromOffset(140, 40), TextSize = 18, OnClick = function() Hangar:Close() end }),
					-- jet list
					scope:New("ScrollingFrame")({
						Name = "Jets", Position = UDim2.fromOffset(0, 56), Size = UDim2.new(0.34, -10, 1, -56),
						BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
						[Children] = { scope:New("UIListLayout")({ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }), jetCards },
					}),
					-- detail panel
					scope:New("Frame")({
						Name = "Detail", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 56), Size = UDim2.new(0.66, -10, 1, -56),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1,
						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
							scope:New("UIPadding")({ PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }),
							scope:New("UIListLayout")({ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
							scope:New("TextLabel")({ LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), FontFace = Theme.Display, TextSize = 12,
								TextColor3 = Theme.Hud, TextXAlignment = Enum.TextXAlignment.Left,
								Text = scope:Computed(function(use) return string.upper(use(jetCfg).Role) end) }),
							scope:New("TextLabel")({ LayoutOrder = 2, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), FontFace = Theme.Body, TextSize = 34,
								TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left,
								Text = scope:Computed(function(use) return string.upper(use(jetCfg).DisplayName) end) }),
							statRow("TOP SPEED", function(s) return s.MaxSpeed * JetConfig.KmhPerStud end, 1300, 3),
							statRow("TURN", function(s) return s.TurnRate * 100 end, 200, 4),
							statRow("FUEL", function(s) return s.Fuel end, 200, 5),
							statRow("MISSILES", function(s) return s.Missiles end, 8, 6),
							statRow("FLARES", function(s) return s.Flares end, 14, 7),
							scope:New("TextLabel")({ LayoutOrder = 8, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), FontFace = Theme.Display, TextSize = 12,
								TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, Text = "UPGRADES" }),
							scope:New("Frame")({ LayoutOrder = 9, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 5 * 49),
								[Children] = { scope:New("UIListLayout")({ Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }), upgradeRows } }),
							C.PrimaryButton(scope, { Name = "Primary", Size = UDim2.new(1, 0, 0, 50), AnchorPoint = Vector2.zero, TextSize = 22, Text = primaryText,
								OnClick = function()
									if peek(owned) then Hangar:Equip(peek(selected)) else Hangar:Buy(peek(selected)) end
								end }),
							scope:New("TextLabel")({ LayoutOrder = 11, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), FontFace = Theme.Body, TextSize = 15,
								TextColor3 = Theme.Amber, Text = V.sHangarMsg }),
						},
					}),
				},
			}),
		},
	})
	-- controller: focus the first jet card
	task.defer(function()
		local first = root:FindFirstChild("SparrowT2", true)
		if first and props.Gamepad then GuiService.SelectedObject = first end
	end)
	return root
end
