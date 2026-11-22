--!strict
--[[
    CombatHUD: targets, lock, lead pip, threat, ammo, cash, toasts, kill card.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.fusion)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Children = Fusion.Children
local V = Store.Values

local KIND_COLOR = {
	Enemy = Theme.Threat,
	Ace = Theme.Gold,
	Mission = Color3.fromRGB(255, 150, 60),
	Revenge = Color3.fromRGB(255, 60, 120),
}

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return function(scope: any, props: { [string]: any })
	local flying = scope:Computed(function(use) return use(V.sPhase) == "Flying" end)

	local function pos(val: any, off: Vector2?)
		return scope:Computed(function(use)
			local v = use(val) :: Vector2
			local o = off or Vector2.zero
			return UDim2.fromOffset(v.X + o.X, v.Y + o.Y)
		end)
	end

	-- target boxes (rebuilt per frame list; capped at 12 for perf)
	local targetBoxes = scope:ForValues(scope:Computed(function(use)
		local t = use(V.tTargets) :: { any }
		local out = {}
		for i = 1, math.min(#t, 12) do out[i] = t[i] end
		return out
	end), function(use, scope2, tgt: any)
		local col = KIND_COLOR[tgt.Kind] or Theme.Threat
		local size = math.clamp(4000 / math.max(tgt.Dist, 1), 22, 64)
		return scope2:New("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(tgt.Pos.X, tgt.Pos.Y),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			[Children] = {
				scope2:New("UIStroke")({ Color = col, Thickness = if tgt.Kind == "Ace" then 2.5 else 1.5, Transparency = 0.1 }),
				C.HudText(scope2, {
					Text = string.format("%s  %.1fkm", tgt.Name, tgt.Dist / 1000),
					TextSize = 12, Color = col, Font = Theme.Mono,
					Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(220, 16),
				}),
			},
		})
	end)

	local threatText = scope:Computed(function(use)
		local t = use(V.sThreat)
		if t == "Inbound" then return "MISSILE INBOUND — FLARE!" end
		if t == "Locked" then return "LOCKED ON" end
		return ""
	end)

	return scope:New("ScreenGui")({
		Name = "CombatHUD",
		Parent = props.Parent,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		[Children] = {
			scope:New("Frame")({
				Name = "Combat",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = flying,
				[Children] = {
					scope:New("Folder")({ Name = "Targets", [Children] = targetBoxes }),
					-- lock reticle: closes in as lock progresses, red when locked
					scope:New("Frame")({
						Name = "Lock",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = pos(V.tLockScreen),
						BackgroundTransparency = 1,
						Size = scope:Computed(function(use)
							local p = use(V.nLockProgress) :: number
							local s = 90 - 46 * math.clamp(p, 0, 1)
							return UDim2.fromOffset(s, s)
						end),
						Visible = scope:Computed(function(use) return use(V.sLockState) ~= "None" end),
						[Children] = {
							scope:New("UIStroke")({ Thickness = 3,
								Color = scope:Computed(function(use) return if use(V.sLockState) == "Locked" then Theme.Threat else Theme.Hud end) }),
							C.HudText(scope, { Font = Theme.Display, TextSize = 13, Position = UDim2.new(0.5, 0, 1, 14), Size = UDim2.fromOffset(120, 16),
								Color = scope:Computed(function(use) return if use(V.sLockState) == "Locked" then Theme.Threat else Theme.Hud end),
								Text = scope:Computed(function(use)
									local st = use(V.sLockState)
									if st == "Locked" then return "LOCK" end
									if st == "Seeking" then return string.format("SEEKING %d%%", math.floor((use(V.nLockProgress) :: number) * 100)) end
									return ""
								end) }),
						},
					}),
					-- gun lead pip
					scope:New("Frame")({
						Name = "Lead",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = pos(V.tLeadScreen),
						Size = UDim2.fromOffset(12, 12),
						BackgroundColor3 = Theme.Hud,
						BackgroundTransparency = 0.2,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(1, 0) }) },
					}),
					-- live event banner (e.g. DOUBLE CASH WEEKEND)
					C.HudText(scope, { Name = "EventLine", Font = Theme.Display, TextSize = 15, Color = Color3.fromRGB(255, 205, 60),
						Position = UDim2.fromScale(0.5, 0.075), Size = UDim2.fromOffset(600, 20), Text = V.sEventLine,
						Visible = scope:Computed(function(use) return use(V.sEventLine) ~= "" end) }),
					-- mission objective marker (clamped to screen edge) + banner
					scope:New("Frame")({
						Name = "Objective",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = pos(V.tObjectiveScreen),
						Size = UDim2.fromOffset(26, 26),
						Rotation = 45,
						BackgroundTransparency = 1,
						[Children] = { scope:New("UIStroke")({ Color = Color3.fromRGB(255, 150, 60), Thickness = 3 }) },
					}),
					C.HudText(scope, { Name = "ObjectiveDist", Font = Theme.Display, TextSize = 13, Color = Color3.fromRGB(255, 150, 60),
						AnchorPoint = Vector2.new(0.5, 0),
						Position = scope:Computed(function(use)
							local p = use(V.tObjectiveScreen) :: Vector2
							return UDim2.fromOffset(p.X, p.Y + 22)
						end),
						Size = UDim2.fromOffset(120, 16), Text = V.sObjectiveDist,
						Visible = scope:Computed(function(use) return use(V.sObjectiveDist) ~= "" and (use(V.tObjectiveScreen) :: Vector2).X > -500 end) }),
					C.HudText(scope, { Name = "ObjectiveText", Font = Theme.Display, TextSize = 14, Color = Color3.fromRGB(255, 150, 60),
						Position = UDim2.fromScale(0.5, 0.11), Size = UDim2.fromOffset(600, 20), Text = V.sObjective,
						Visible = scope:Computed(function(use) return not use(V.bFTUEActive) end) }),
					-- threat banner
					C.HudText(scope, { Name = "Threat", Font = Theme.Display, TextSize = 26, Color = Theme.Threat,
						Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.fromOffset(520, 40), Text = threatText }),
					-- hit marker: white X flash on the reticle for every server-confirmed hit
					C.HudText(scope, { Name = "HitMarker", Font = Theme.Display, TextSize = 34, Color = Color3.fromRGB(255, 255, 255), Text = "X",
						Position = scope:Computed(function(use) local v = use(V.tAimScreen) :: Vector2 return UDim2.fromOffset(v.X, v.Y) end),
						Size = UDim2.fromOffset(40, 40), Visible = V.bHitMarker }),
					-- target health bar
					scope:New("Frame")({
						Name = "TargetHp", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(74, 7),
						BackgroundColor3 = Color3.fromRGB(10, 14, 18), BackgroundTransparency = 0.3, BorderSizePixel = 0,
						Position = scope:Computed(function(use) local t = use(V.tTargetHp) return if t then UDim2.fromOffset(t.Pos.X, t.Pos.Y + 62) else UDim2.fromOffset(-500, -500) end),
						Visible = scope:Computed(function(use) return use(V.tTargetHp) ~= false end),
						[Children] = {
							scope:New("Frame")({
								BorderSizePixel = 0,
								Size = scope:Computed(function(use) local t = use(V.tTargetHp) return UDim2.fromScale(if t then t.Frac else 0, 1) end),
								BackgroundColor3 = scope:Computed(function(use) local t = use(V.tTargetHp) local f = if t then t.Frac else 1 return if f <= 0.35 then Theme.Threat elseif f <= 0.65 then Theme.Amber else Theme.Hud end),
							}),
						},
					}),
					-- lock coaching (heat-seeker mechanic): GET ON THEIR SIX / TERRAIN MASKING / LOST IN THE SUN ...
					C.HudText(scope, { Name = "LockHint", Font = Theme.Display, TextSize = 16, Color = Theme.Amber,
						Position = UDim2.fromScale(0.5, 0.345), Size = UDim2.fromOffset(420, 22), Text = V.sLockHint }), -- above the reticle, clear of the lock box
					-- ammo panel (right of centre, above touch controls)
					scope:New("Frame")({
						Name = "Ammo",
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -24, 0.45, 0), -- above the thumb-button arc on every device
						Size = UDim2.fromOffset(190, 96),
						BackgroundTransparency = 1,
						[Children] = {
							C.HudText(scope, { Font = Theme.Mono, TextSize = 18, XAlign = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
								Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(190, 24),
								Text = scope:Computed(function(use) return `MSL {use(V.nMissiles)}/{use(V.nMissilesMax)}` end) }),
							C.HudText(scope, { Font = Theme.Mono, TextSize = 18, XAlign = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
								Position = UDim2.new(1, 0, 0, 26), Size = UDim2.fromOffset(190, 24),
								Text = scope:Computed(function(use) return `FLR {use(V.nFlares)}/{use(V.nFlaresMax)}` end) }),
							C.HudText(scope, { Font = Theme.Display, TextSize = 11, XAlign = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
								Position = UDim2.new(1, 0, 0, 56), Size = UDim2.fromOffset(190, 14), Text = "GUN HEAT" }),
							C.HudBar(scope, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 74), Size = UDim2.fromOffset(150, 8), Fill = V.nGunHeat,
								FillColor = scope:Computed(function(use) return if use(V.nGunHeat) > 0.8 then Theme.Threat else Theme.Hud end) }),
						},
					}),
				},
			}),

			-- PLAYTIME GIFT (under the cash: countdown to the next free gift) ---------
			scope:New("Frame")({
				Name = "Gift",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -20, 0, 66),
				Size = UDim2.fromOffset(250, 34),
				BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.25,
				Visible = scope:Computed(function(use) return use(V.sGiftLine) ~= "" end),
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
					scope:New("UIStroke")({ Color = Theme.Hud, Thickness = 1, Transparency = 0.4 }),
					scope:New("TextLabel")({ Name = "Text", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 0, 24),
						FontFace = Theme.Mono, TextSize = 16, TextColor3 = Theme.Hud, TextXAlignment = Enum.TextXAlignment.Right, Text = V.sGiftLine }),
					scope:New("Frame")({ Name = "Bar", Position = UDim2.new(0, 10, 1, -6), Size = UDim2.new(1, -20, 0, 3), BackgroundColor3 = Theme.Raised, BorderSizePixel = 0,
						[Children] = { scope:New("Frame")({ BorderSizePixel = 0, BackgroundColor3 = Theme.Hud,
							Size = scope:Computed(function(use) return UDim2.fromScale(math.clamp(use(V.nGiftFrac) :: number, 0, 1), 1) end) }) } }),
				},
			}),

			-- CASH (top-right, always on) ----------------------------------------
			scope:New("Frame")({
				Name = "Cash",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -20, 0, 16),
				Size = UDim2.fromOffset(380, 44),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New("UIListLayout")({ FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
					-- SETTINGS (deck / relaunch screen only)
					scope:New("TextButton")({
						Name = "SettingsBtn", LayoutOrder = 0, Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.15,
						FontFace = Theme.Body, TextSize = 24, TextColor3 = Theme.Ink, Text = "⚙", Selectable = true, AutoButtonColor = true,
						Visible = scope:Computed(function(use) local p = use(V.sPhase) return p == "Deck" or p == "Dead" end),
						[Fusion.OnEvent("Activated")] = function()
							(require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("SettingsClient")) :: any):Open()
						end,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
					}),
					scope:New("TextLabel")({
						Name = "Sortie", LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.15, FontFace = Theme.Mono, TextSize = 18,
						TextColor3 = Theme.Amber,
						Visible = scope:Computed(function(use) return use(V.nSortieCash) > 0 end),
						Text = scope:Computed(function(use) return `  SORTIE +{fmt(use(V.nSortieCash))}  ` end),
						[Children] = { scope:New("UIStroke")({ Color = Theme.Amber, Thickness = 1 }), scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
					}),
					scope:New("TextLabel")({
						Name = "Bank", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.15, FontFace = Theme.Mono, TextSize = 20,
						TextColor3 = Theme.Ink,
						Text = scope:Computed(function(use) return `  ◉ {fmt(use(V.nCash))}  ` end),
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
					}),
					scope:New("TextButton")({
						Name = "Plus", LayoutOrder = 3, Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Theme.Amber, FontFace = Theme.Body,
						TextSize = 26, TextColor3 = Color3.fromRGB(16, 22, 29), Text = "+", Selectable = true,
						[Fusion.OnEvent("Activated")] = function()
							(require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("ShopClient")) :: any):Open()
						end,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
					}),
					scope:New("TextLabel")({
						Name = "Rank", LayoutOrder = 4, Size = UDim2.fromOffset(64, 40),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.15, FontFace = Theme.Mono, TextSize = 20,
						TextColor3 = Theme.Gold,
						Text = scope:Computed(function(use) return string.format("R%02d", use(V.nRank)) end),
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
					}),
				},
			}),

			-- TOASTS / KILL FEED (left) -----------------------------------------
			scope:New("Frame")({
				Name = "Feed",
				Position = UDim2.new(0, 20, 0, 70),
				Size = UDim2.fromOffset(360, 140), -- clears the threat banner even on the smallest phones
				BackgroundTransparency = 1,
				[Children] = {
					scope:New("UIListLayout")({ Padding = UDim.new(0, 4) }),
					scope:ForValues(V.tToasts, function(use, scope2, t: any)
						return C.HudText(scope2, { Text = t.Text, Font = Theme.Body, TextSize = 18, Color = t.Color or Theme.Ink,
							AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 24) })
					end),
				},
			}),

			-- STARTER ACE OFFER (one-time, after a few shoot-downs) --------------
			scope:New("Frame")({
				Name = "StarterOffer",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(520, 250),
				BackgroundColor3 = Theme.Panel,
				ZIndex = 20,
				-- only on the deck / relaunch screen: never over the reticle in flight
				Visible = scope:Computed(function(use)
					local p = use(V.sPhase)
					return use(V.bStarterOffer) and (p == "Deck" or p == "Dead")
				end),
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					scope:New("UIStroke")({ Color = Theme.Amber, Thickness = 2 }),
					scope:New("ImageLabel")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 30), Size = UDim2.fromOffset(170, 170), ZIndex = 21,
						Image = scope:Computed(function(use) local i = use(V.tShopInfo).StarterAce return if i then i.Icon else "" end) }),
					C.HudText(scope, { Text = "STARTER ACE BUNDLE", Font = Theme.Display, TextSize = 18, Color = Theme.Amber, AnchorPoint = Vector2.zero,
						XAlign = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(200, 34), Size = UDim2.fromOffset(300, 24), ZIndex = 21 }),
					C.HudText(scope, { Text = "Viper IX interceptor + 5,000 Cash. One time only.", Font = Theme.Body, TextSize = 17,
						Color = Theme.Ink, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(200, 64),
						Size = UDim2.fromOffset(300, 70), ZIndex = 21 }),
					C.PrimaryButton(scope, { Name = "BuyStarter", AnchorPoint = Vector2.zero, Position = UDim2.fromOffset(200, 150), Size = UDim2.fromOffset(300, 48),
						TextSize = 20, Text = scope:Computed(function(use) local i = use(V.tShopInfo).StarterAce return "GET IT · R$ " .. tostring(if i then i.Price else 99) end),
						OnClick = function() (require(ReplicatedStorage.ClientModules.ShopClient) :: any):Buy("StarterAce") end }),
					scope:New("TextButton")({ BackgroundTransparency = 1, Position = UDim2.fromOffset(200, 204), Size = UDim2.fromOffset(300, 30), ZIndex = 21,
						FontFace = Theme.Body, TextSize = 15, TextColor3 = Theme.Mute, Text = "No thanks",
						[Fusion.OnEvent("Activated")] = function() (require(ReplicatedStorage.ClientModules.ShopClient) :: any):DismissOffer() end }),
				},
			}),

			-- KILL CARD (shown while dead) ---------------------------------------
			scope:New("Frame")({
				Name = "KillCard",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.44),
				Size = UDim2.fromOffset(460, 92),
				BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = 0.05,
				Visible = scope:Computed(function(use) return use(V.sPhase) == "Dead" and use(V.tKillCard) ~= false and not use(V.bHideKillCard) end),
				[Children] = {
					scope:New("Frame")({ Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Theme.Threat, BorderSizePixel = 0 }),
					C.HudText(scope, { Font = Theme.Display, TextSize = 12, Color = Theme.Threat, AnchorPoint = Vector2.zero,
						Text = scope:Computed(function(use)
							local k = use(V.tKillCard)
							if k and k.Weapon == "Eject" then return if (k.Killer or "") ~= "" then "FORCED TO EJECT BY" else "YOU EJECTED" end
							return "SHOT DOWN BY"
						end),
						XAlign = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(300, 16) }),
					C.HudText(scope, { Font = Theme.Body, TextSize = 26, Color = Theme.Ink, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
						Position = UDim2.fromOffset(18, 32), Size = UDim2.fromOffset(420, 30),
						Text = scope:Computed(function(use) local k = use(V.tKillCard) -- no player killer: name the AI/hazard that did it (Red Talon, SAM, Tail Gunner) unless it was a crash
							if not k then return "" end
							if k.Killer ~= "" then return k.Killer end
							if k.Weapon == "Eject" then return "Unbanked cash saved" end
							if k.Weapon == "Bounds" then return "Out of the combat zone" end
							if k.Weapon and k.Weapon ~= "" and k.Weapon ~= "Crash" then return string.upper(k.Weapon) end
							if k.Reason == "BellyLanding" then return "Forgot the landing gear" end
							if k.Reason == "HardLanding" then return "Came in too hot" end
							return "The ground"
						end) }),
					C.HudText(scope, { Font = Theme.Body, TextSize = 15, Color = Theme.Mute, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
						Position = UDim2.fromOffset(18, 62), Size = UDim2.fromOffset(420, 20),
						Text = scope:Computed(function(use)
							local k = use(V.tKillCard)
							if not k then return "" end
							return if k.Killer ~= "" then `{k.Weapon} · Revenge Mark on them for 90 s (2× Cash)` else k.Weapon
						end) }),
				},
			}),
		},
	})
end
