--!strict
--[[
    Shop: game passes (owned state) and developer products in the Deck UI
    style. Live icons/prices from MarketplaceService (ShopClient).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local MonetizationConfig = require(ReplicatedStorage.Config.MonetizationConfig)

local Children, OnEvent = Fusion.Children, Fusion.OnEvent
local V = Store.Values

local DESC = {
	WraithX = "Stealth fighter · 1,250 km/h · hard to lock",
	MultiLock = "Lock 4 targets · +25% tracking",
	DoubleCash = "2× Cash from everything",
	Afterburner = "Afterburner burns 60% less",
	GSuitPro = "+3G · no blackout",
	VIP = "Gold tag · contrail · +10% XP",
	FlarePod = "+4 flares on every jet",
	StarterAce = "Viper IX + 5,000 Cash · once only",
	CashS = "5,000 Cash",
	CashM = "25,000 Cash",
	CashL = "100,000 Cash",
	Rearm = "Refill missiles, flares, fuel now",
	BountyShield = "Keep 100% Sortie Cash on next shoot-down",
}

local function sorted(t: { [string]: any }): { string }
	local keys = {}
	for k in pairs(t) do table.insert(keys, k) end
	table.sort(keys, function(a, b) return t[a].Order < t[b].Order end)
	return keys
end

return function(scope: any, props: { [string]: any })
	local Shop = props.Controller

	local function tile(sKey: string, def: any, isPass: boolean, order: number)
		local owned = scope:Computed(function(use) return isPass and use(V.tPasses)[sKey] == true end)
		return scope:New("Frame")({
			Name = sKey, LayoutOrder = order, BackgroundColor3 = Theme.Panel, Size = UDim2.fromOffset(196, 262),
			[Children] = {
				scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
				scope:New("UIStroke")({ Color = scope:Computed(function(use) return if use(owned) then Theme.Hud else Theme.Line end), Thickness = 1.5 }),
				scope:New("ImageLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(160, 160),
					Image = scope:Computed(function(use) local i = use(V.tShopInfo)[sKey] return if i then i.Icon else "" end) }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 174), Size = UDim2.new(1, -20, 0, 22), FontFace = Theme.Body,
					TextSize = 17, TextColor3 = Theme.Ink, TextTruncate = Enum.TextTruncate.AtEnd, Text = string.upper(def.Name) }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 196), Size = UDim2.new(1, -20, 0, 18), FontFace = Theme.Body,
					TextSize = 13, TextColor3 = Theme.Mute, TextTruncate = Enum.TextTruncate.AtEnd, Text = DESC[sKey] or "" }),
				scope:New("TextButton")({
					Name = "Buy", Position = UDim2.new(0, 10, 1, -42), Size = UDim2.new(1, -20, 0, 34), Selectable = true, AutoButtonColor = true,
					BackgroundColor3 = scope:Computed(function(use) return if use(owned) then Theme.Raised else Theme.Hud end),
					FontFace = Theme.Mono, TextSize = 16,
					TextColor3 = scope:Computed(function(use) return if use(owned) then Theme.Hud else Color3.fromRGB(11, 26, 16) end),
					Text = scope:Computed(function(use)
						if use(owned) then return "OWNED" end
						local i = use(V.tShopInfo)[sKey]
						return "R$ " .. tostring(if i then i.Price else def.Price)
					end),
					[OnEvent("Activated")] = function() Shop:Buy(sKey) end,
					[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
				}),
			},
		})
	end

	local passTiles, prodTiles = {}, {}
	for i, k in ipairs(sorted(MonetizationConfig.Passes)) do table.insert(passTiles, tile(k, MonetizationConfig.Passes[k], true, i)) end
	for i, k in ipairs(sorted(MonetizationConfig.Products)) do table.insert(prodTiles, tile(k, MonetizationConfig.Products[k], false, i)) end

	local function section(title: string, order: number, tiles: { any })
		return scope:New("Frame")({
			LayoutOrder = order, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0),
			[Children] = {
				scope:New("UIListLayout")({ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
				scope:New("TextLabel")({ LayoutOrder = 0, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), FontFace = Theme.Display, TextSize = 13,
					TextColor3 = Theme.Hud, TextXAlignment = Enum.TextXAlignment.Left, Text = title }),
				scope:New("Frame")({ LayoutOrder = 1, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0),
					[Children] = { scope:New("UIGridLayout")({ CellSize = UDim2.fromOffset(196, 262), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }), tiles } }),
			},
		})
	end

	return scope:New("ScreenGui")({
		Name = "Shop", Parent = props.Parent, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 11,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		[Children] = {
			scope:New("Frame")({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.2, BorderSizePixel = 0 }),
			scope:New("Frame")({
				Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.92, 0.9), BackgroundTransparency = 1,
				[Children] = {
					scope:New("UISizeConstraint")({ MaxSize = Vector2.new(1320, 820) }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), FontFace = Theme.Display, TextSize = 26, TextColor3 = Theme.Ink,
						TextXAlignment = Enum.TextXAlignment.Left, Text = "SHOP" }),
					C.PrimaryButton(scope, { Name = "Close", Text = "BACK ›", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(130, 40),
						TextSize = 18, OnClick = function() Shop:Close() end }),
					scope:New("ScrollingFrame")({
						Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5,
						AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
						[Children] = {
							scope:New("UIListLayout")({ Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }),
							section("GAME PASSES · PERMANENT", 1, passTiles),
							section("PACKS & BOOSTS", 2, prodTiles),
						},
					}),
				},
			}),
		},
	})
end
