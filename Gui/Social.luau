--!strict
--[[
    Social: invite toast, squad roster + squad screen, Daily Sortie Pay modal,
    Formation indicator. Deck UI style.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

local Children, OnEvent = Fusion.Children, Fusion.OnEvent
local V = Store.Values

return function(scope: any, props: { [string]: any })
	local Social = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("SocialClient")) :: any

	local function smallBtn(text: string, color: Color3, onClick: () -> (), size: UDim2?, pos: UDim2?)
		return scope:New("TextButton")({
			Size = size or UDim2.fromOffset(110, 34), Position = pos, BackgroundColor3 = color, FontFace = Theme.Body, TextSize = 17,
			TextColor3 = Color3.fromRGB(16, 22, 29), Text = text, Selectable = true, AutoButtonColor = true,
			[OnEvent("Activated")] = onClick,
			[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
		})
	end

	-- daily track cells
	local dayCells = {}
	for i, cash in ipairs(EconomyConfig.DailyTrack) do
		table.insert(dayCells, scope:New("Frame")({
			LayoutOrder = i, Size = UDim2.fromOffset(70, 78),
			BackgroundColor3 = Theme.Raised,
			BackgroundTransparency = scope:Computed(function(use) local d = use(V.tDaily) return if i < d.day then 0.6 else 0 end),
			[Children] = {
				scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				scope:New("UIStroke")({ Thickness = 2, Color = scope:Computed(function(use) local d = use(V.tDaily) return if i == d.day then Theme.Amber else Theme.Line end) }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 18), FontFace = Theme.Display, TextSize = 12,
					TextColor3 = if i == 7 then Theme.Gold else Theme.Mute, Text = "D" .. i }),
				scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 26), FontFace = Theme.Mono, TextSize = 18,
					TextColor3 = if i == 7 then Theme.Gold else Theme.Ink, Text = tostring(cash) }),
			},
		}))
	end

	return scope:New("ScreenGui")({
		Name = "Social", Parent = props.Parent, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		[Children] = {
			-- squad roster (left, under the feed)
			scope:New("Frame")({
				Name = "Roster", Position = UDim2.new(0, 20, 0, 230), Size = UDim2.fromOffset(240, 120), BackgroundTransparency = 1,
				Visible = scope:Computed(function(use) return #use(V.tSquad) > 0 end),
				[Children] = {
					scope:New("UIListLayout")({ Padding = UDim.new(0, 3) }),
					C.HudText(scope, { Text = "WINGMEN", Font = Theme.Display, TextSize = 12, Color = Theme.Squad, AnchorPoint = Vector2.zero,
						XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(240, 16) }),
					scope:ForValues(V.tSquad, function(use, s2, m: any)
						return C.HudText(s2, { Text = "▲ " .. m.name, Font = Theme.Body, TextSize = 16, Color = Theme.Squad, AnchorPoint = Vector2.zero,
							XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(240, 20) })
					end),
					C.HudText(scope, { Text = "FORMATION · REFUELLING", Font = Theme.Display, TextSize = 11, Color = Theme.Hud, AnchorPoint = Vector2.zero,
						XAlign = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(240, 16), Visible = V.bFormation }),
				},
			}),

			-- incoming invite toast
			scope:New("Frame")({
				Name = "Invite", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(440, 96),
				BackgroundColor3 = Theme.Panel, Visible = scope:Computed(function(use) return use(V.tInvite) ~= false end),
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					scope:New("UIStroke")({ Color = Theme.Squad, Thickness = 2 }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 26), FontFace = Theme.Body,
						TextSize = 19, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left,
						Text = scope:Computed(function(use) local i = use(V.tInvite) return if i then `{i.name} wants you as a wingman` else "" end) }),
					smallBtn("ACCEPT", Theme.Squad, function() Social:Accept() end, UDim2.fromOffset(130, 36), UDim2.fromOffset(16, 48)),
					smallBtn("DECLINE", Theme.Raised, function() Social:Decline() end, UDim2.fromOffset(130, 36), UDim2.fromOffset(156, 48)),
				},
			}),

			-- squad screen
			scope:New("Frame")({
				Name = "SquadScreen", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(480, 460),
				BackgroundColor3 = Theme.Panel, Visible = V.bSquadOpen,
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					scope:New("UIStroke")({ Color = Theme.Squad, Thickness = 2 }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -36, 0, 30), FontFace = Theme.Display,
						TextSize = 20, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left, Text = "WINGMAN SQUAD" }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 44), Size = UDim2.new(1, -36, 0, 38), FontFace = Theme.Body,
						TextSize = 15, TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
						Text = "Squadmates can't lock each other, share mission credit and earn up to ×1.3 Cash. Fly close to refuel." }),
					scope:New("ScrollingFrame")({
						Position = UDim2.fromOffset(18, 90), Size = UDim2.new(1, -36, 1, -150), BackgroundTransparency = 1, BorderSizePixel = 0,
						AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 4,
						[Children] = {
							scope:New("UIListLayout")({ Padding = UDim.new(0, 6) }),
							scope:ForValues(V.tPlayerList, function(use, s2, p: any)
								return s2:New("Frame")({
									Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = Theme.Raised,
									[Children] = {
										s2:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
										s2:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -140, 1, 0), FontFace = Theme.Body,
											TextSize = 17, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left,
											Text = (if p.friend then "★ " else "") .. p.name }),
										s2:New("TextButton")({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 32),
											BackgroundColor3 = Theme.Squad, FontFace = Theme.Body, TextSize = 16, TextColor3 = Color3.fromRGB(10, 20, 30), Text = "INVITE",
											Selectable = true, [OnEvent("Activated")] = function() Social:Invite(p.id) end,
											[Children] = { s2:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) } }),
									},
								})
							end),
						},
					}),
					smallBtn("LEAVE SQUAD", Theme.Raised, function() Social:Leave() end, UDim2.fromOffset(150, 38), UDim2.new(0, 18, 1, -52)),
					smallBtn("DONE", Theme.Amber, function() Social:CloseSquad() end, UDim2.fromOffset(150, 38), UDim2.new(1, -168, 1, -52)),
				},
			}),

			-- daily sortie pay
			scope:New("Frame")({
				Name = "Daily", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(600, 250),
				BackgroundColor3 = Theme.Panel, Visible = V.bDailyOpen,
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					scope:New("Frame")({ Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Theme.Raised, BorderSizePixel = 0,
						[Children] = {
							scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -36, 1, 0), FontFace = Theme.Display,
								TextSize = 18, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left, Text = "DAILY SORTIE PAY" }),
							scope:New("Frame")({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Theme.Amber, BorderSizePixel = 0 }),
						} }),
					scope:New("TextLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 58), Size = UDim2.new(1, -36, 0, 20), FontFace = Theme.Body, TextSize = 15,
						TextColor3 = Theme.Mute, TextXAlignment = Enum.TextXAlignment.Left, Text = "Fly every day for bigger rewards. Miss a day and the streak resets." }),
					scope:New("Frame")({ Position = UDim2.fromOffset(18, 86), Size = UDim2.new(1, -36, 0, 80), BackgroundTransparency = 1,
						[Children] = { scope:New("UIListLayout")({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }), dayCells } }),
					C.PrimaryButton(scope, { Name = "Claim", AnchorPoint = Vector2.zero, Position = UDim2.fromOffset(18, 182), Size = UDim2.new(1, -170, 0, 50), TextSize = 20,
						Text = scope:Computed(function(use)
							local d = use(V.tDaily)
							return if d.claimable then `CLAIM +{EconomyConfig.DailyTrack[d.day] or 0}` else "COME BACK TOMORROW"
						end),
						OnClick = function() Social:ClaimDaily() end }),
					smallBtn("LATER", Theme.Raised, function() Social:CloseDaily() end, UDim2.fromOffset(130, 50), UDim2.new(1, -148, 0, 182)),
				},
			}),
		},
	})
end
