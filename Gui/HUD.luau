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

	local flying = scope:Computed(function(use) local p = use(V.sPhase) return p == "Flying" or p == "Catapult" or p == "Ground" end)
	local onDeck = scope:Computed(function(use) local p = use(V.sPhase) return p == "Deck" or p == "Launching" end)
	local dead = scope:Computed(function(use) return use(V.sPhase) == "Dead" end)
	local touch = V.bTouch

	-- readout columns sit closer to the reticle on touch screens (clear of the thumb buttons)
	local function colL(y: number) return scope:Computed(function(use) return UDim2.new(if use(V.bTouch) then 0.38 else 0.24, 0, y, 0) end) end
	local function colR(y: number) return scope:Computed(function(use) return UDim2.new(if use(V.bTouch) then 0.62 else 0.76, 0, y, 0) end) end

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
					-- G strain tunnels the view in from the edges; the red "you've been hit" flash shares them
					local s = use(V.nStrain) :: number
					return math.max(math.clamp((s - 0.25) / 0.75, 0, 0.95), (use(V.nHurt) :: number) * 0.85)
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

				-- G-LOC: blacked out (no control) until the pilot comes round
			scope:New("Frame")({
				Name = "Blackout", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 5,
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = scope:Computed(function(use) return if use(V.bGLoc) then 0.04 else 1 end),
				[Children] = {
					C.HudText(scope, { Text = "G-LOC - BLACKED OUT", Font = Theme.Display, TextSize = 26, Color = Color3.fromRGB(150, 40, 40),
						Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 40), Visible = V.bGLoc }),
					C.HudText(scope, { Text = "Don't hold max G - pulse your turns", Font = Theme.Body, TextSize = 18, Color = Color3.fromRGB(150, 150, 150),
						Position = UDim2.new(0.5, 0, 0.5, 34), Size = UDim2.fromOffset(500, 30), Visible = V.bGLoc }),
				},
			}),

			-- PROGRESS CARD (deck + death screen): rank, next jet, sortie challenges
			(function()
				local function row(i: number)
					return C.HudText(scope, { Name = "Ch" .. i, Font = Theme.Body, TextSize = 16, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
						Position = UDim2.fromOffset(14, 70 + (i - 1) * 20), Size = UDim2.new(1, -28, 0, 20),
						Color = scope:Computed(function(use) local c = (use(V.tChallenges) :: any)[i] return if c and c.Done then Theme.Hud else Theme.Ink end),
						Text = scope:Computed(function(use)
							local c = (use(V.tChallenges) :: any)[i]
							if not c then return "" end
							if c.Done then return "✓  " .. c.Text end
							return string.format("•  %s   %d/%d   +%d", c.Text, c.Progress, c.Goal, c.Cash)
						end) })
				end
				return scope:New("Frame")({
					Name = "ProgressCard", Size = UDim2.fromOffset(560, 158),
					-- phones: under the relaunch buttons on the death screen (the top half holds the title +
					-- killer card), just below the boss bar on the deck
					AnchorPoint = scope:Computed(function(use)
						return if use(V.bCompact) and use(V.sPhase) == "Dead" then Vector2.new(0.5, 1) else Vector2.new(0.5, 0)
					end),
					Position = scope:Computed(function(use)
						if use(V.bCompact) then
							return if use(V.sPhase) == "Dead" then UDim2.new(0.5, 0, 1, -6) else UDim2.new(0.5, 0, 0, 100)
						end
						return UDim2.new(0.5, 0, 0, 124)
					end),
					BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.35,
					Visible = scope:Computed(function(use) local p = use(V.sPhase) return p == "Deck" or p == "Launching" or p == "Dead" end),
					[Children] = {
						scope:New("UICorner")({ CornerRadius = UDim.new(0, 8) }),
						scope:New("UIStroke")({ Color = Theme.Amber, Thickness = 1, Transparency = 0.5 }),
						C.HudText(scope, { Name = "RankLine", Font = Theme.Display, TextSize = 15, Color = Theme.Amber, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
							Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 18), Text = V.sRankLine }),
						C.HudText(scope, { Name = "NextJet", Font = Theme.Display, TextSize = 14, Color = Theme.Ink, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
							Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 18), Text = V.sNextJet }),
						C.HudBar(scope, { Name = "NextJetBar", AnchorPoint = Vector2.zero, Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 6),
							Fill = V.nNextJetFrac, FillColor = Theme.Amber }),
						row(1), row(2), row(3),
						C.HudText(scope, { Name = "Board", Font = Theme.Display, TextSize = 13, Color = Theme.Hud, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
							Position = UDim2.fromOffset(14, 134), Size = UDim2.new(1, -28, 0, 18), Text = V.sBoardLine }),
					},
				})
			end)(),

			-- FLYING FORTRESS: countdown, then health bar (shown in flight, on deck and when dead)
			scope:New("Frame")({
				Name = "BossBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 74), Size = UDim2.fromOffset(460, 40),
				BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.4,
				Visible = scope:Computed(function(use) return use(V.sBossBar) ~= "" end),
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					scope:New("UIStroke")({ Color = Theme.Threat, Thickness = 1.5, Transparency = 0.3 }),
					C.HudText(scope, { Name = "BossText", Font = Theme.Display, TextSize = 15, Color = Color3.fromRGB(255, 120, 100),
						Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(1, -10, 0, 18), Text = V.sBossBar }),
					C.HudBar(scope, { Name = "BossHp", Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.new(1, -24, 0, 6), Fill = scope:Computed(function(use) return math.max(0, use(V.nBossHp) :: number) end),
						FillColor = Theme.Threat, Visible = scope:Computed(function(use) return (use(V.nBossHp) :: number) >= 0 end) }),
				},
			}),

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
					C.HudText(scope, { Name = "SpdLbl", Text = "SPD KM/H", Font = Theme.Display, TextSize = 12, Position = colL(0.42) }),
					C.HudText(scope, { Name = "Spd", TextSize = 30, Position = colL(0.47),
						Text = scope:Computed(function(use) return tostring(use(V.nSpeedKmh)) end) }),
						C.HudText(scope, { Name = "Corner", Text = "CORNER", Font = Theme.Display, TextSize = 12, Color = Theme.Hud, Position = colL(0.5),
						Visible = V.bCorner }),
					C.HudText(scope, { Name = "AltLbl", Text = "ALT", Font = Theme.Display, TextSize = 12, Position = colR(0.42) }),
					C.HudText(scope, { Name = "Alt", TextSize = 30, Position = colR(0.47),
						Text = scope:Computed(function(use) return tostring(use(V.nAltitude)) end) }),
					-- heading
					C.HudText(scope, { Name = "Hdg", TextSize = 16, Position = UDim2.new(0.5, 0, 0.06, 0),
						Text = scope:Computed(function(use) return string.format("%03d", math.floor(use(V.nHeading))) end) }),
					-- G meter
					C.HudText(scope, { Name = "G", TextSize = 26, Position = colL(0.56),
						Color = scope:Computed(function(use) local s = use(V.nStrain) :: number return if s > 0.6 then Theme.Threat elseif s > 0.2 then Theme.Amber else Theme.Hud end),
						Text = scope:Computed(function(use) return string.format("%.1f G", use(V.nG)) end) }),
					C.HudBar(scope, { Name = "Strain", Position = colL(0.583), Size = UDim2.fromOffset(90, 5), Fill = V.nStrain,
						FillColor = scope:Computed(function(use) return if (use(V.nStrain) :: number) > 0.6 then Theme.Threat else Theme.Amber end),
						Visible = scope:Computed(function(use) return (use(V.nStrain) :: number) > 0.02 end) }),
					C.HudText(scope, { Name = "Rookie", Text = "ROOKIE ASSISTS ON", Font = Theme.Display, TextSize = 11, Color = Theme.Squad,
						Position = colL(0.70), Visible = V.bRookie }),
					-- sortie challenges (compact, left edge)
					(function()
						local rows = {}
						for i = 1, 3 do
							table.insert(rows, C.HudText(scope, { Name = "FCh" .. i, Font = Theme.Body, TextSize = 13, AnchorPoint = Vector2.zero, XAlign = Enum.TextXAlignment.Left,
								Position = UDim2.fromOffset(8, 22 + (i - 1) * 17), Size = UDim2.new(1, -12, 0, 17),
								Color = scope:Computed(function(use) local c = (use(V.tChallenges) :: any)[i] return if c and c.Done then Theme.Hud else Theme.Ink end),
								Text = scope:Computed(function(use)
									local c = (use(V.tChallenges) :: any)[i]
									if not c then return "" end
									return if c.Done then "✓ " .. c.Text else string.format("%s  %d/%d", c.Text, c.Progress, c.Goal)
								end) }))
						end
						table.insert(rows, C.HudText(scope, { Text = "CHALLENGES", Font = Theme.Display, TextSize = 11, Color = Theme.Amber, AnchorPoint = Vector2.zero,
							XAlign = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -12, 0, 16) }))
						table.insert(rows, scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }))
						return scope:New("Frame")({
							Name = "Challenges", Position = UDim2.new(0, 16, 0.2, 0), Size = UDim2.fromOffset(236, 80),
							BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.55,
							-- phones: hidden in flight (it's on the deck / relaunch card) so the left side stays clear
							Visible = scope:Computed(function(use) return #(use(V.tChallenges) :: any) > 0 and not use(V.bCompact) end),
							[Children] = rows,
						})
					end)(),
					-- landing gear state
					C.HudText(scope, { Name = "GearState", Font = Theme.Display, TextSize = 13, Position = colL(0.672),
						Color = scope:Computed(function(use) return if use(V.bGearDown) then Theme.Hud else Theme.Mute end),
						Text = scope:Computed(function(use) return if use(V.bGearDown) then "GEAR DOWN  v v v" else "GEAR UP" end) }),
					-- fuel
					C.HudText(scope, { Name = "FuelLbl", Text = "FUEL", Font = Theme.Display, TextSize = 12, Position = colR(0.555) }),
					C.HudBar(scope, { Name = "Fuel", Position = colR(0.585), Size = UDim2.fromOffset(150, 10),
						Fill = V.nFuel, FillColor = Theme.Amber,
						Color = scope:Computed(function(use) return if use(V.nFuel) < 0.2 then Theme.Threat else Theme.Hud end) }),
					-- shield
					C.HudText(scope, { Name = "Shield", Text = "SPAWN SHIELD", Font = Theme.Display, TextSize = 14, Color = Theme.Squad,
						Position = UDim2.new(0.5, 0, 0.775, 0), Visible = V.bShield }),
					-- throttle gauge (left of the speed column): green fill = throttle, AB segment glows on afterburner
					scope:New("Frame")({
						Name = "Throttle", AnchorPoint = Vector2.new(0.5, 0.5),
						Position = scope:Computed(function(use) return UDim2.new(if use(V.bTouch) then 0.38 else 0.24, -112, 0.5, 0) end),
						Size = UDim2.fromOffset(16, 150), BackgroundColor3 = Color3.fromRGB(10, 16, 20), BackgroundTransparency = 0.45, BorderSizePixel = 0,
						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(0, 3) }),
							scope:New("UIStroke")({ Color = Theme.Hud, Transparency = 0.5, Thickness = 1 }),
							scope:New("Frame")({ -- throttle fill (bottom 80% of the bar)
								AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BorderSizePixel = 0,
								BackgroundColor3 = Theme.Hud, BackgroundTransparency = 0.15,
								Size = scope:Computed(function(use) return UDim2.fromScale(1, 0.8 * (use(V.nThrottle) :: number)) end),
							}),
							scope:New("Frame")({ -- afterburner detent segment (top 20%)
								Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.2), BorderSizePixel = 0,
								BackgroundColor3 = Theme.Amber,
								BackgroundTransparency = scope:Computed(function(use) return if use(V.bBoost) then 0 else 0.85 end),
							}),
							C.HudText(scope, { Font = Theme.Display, TextSize = 11, Position = UDim2.new(0.5, 0, 0, -10), Size = UDim2.fromOffset(60, 14),
								Color = scope:Computed(function(use) return if use(V.bBoost) then Theme.Amber else Theme.Hud end),
								Text = scope:Computed(function(use) return if use(V.bBoost) then "AB" else string.format("%d%%", math.floor((use(V.nThrottle) :: number) * 100 + 0.5)) end) }),
							C.HudText(scope, { Font = Theme.Display, TextSize = 10, Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(60, 14),
								Text = "THR" }),
						},
					}),
					-- stall warning
					C.HudText(scope, { Name = "Stall", Text = "STALL - LOWER THE NOSE, ADD THROTTLE", Font = Theme.Display, TextSize = 20, Color = Theme.Threat,
						Position = UDim2.new(0.5, 0, 0.665, 0), Size = UDim2.fromOffset(460, 28), Visible = V.bStall }),
					-- hull integrity (left column, mirrors FUEL)
					C.HudText(scope, { Name = "HullLbl", Text = "HULL", Font = Theme.Display, TextSize = 12, Position = colL(0.605),
						Color = scope:Computed(function(use) return if use(V.bHullCritical) then Theme.Threat else Theme.Hud end) }),
					C.HudBar(scope, { Name = "Hull", Position = colL(0.635), Size = UDim2.fromOffset(150, 10), Fill = V.nHull,
						Color = scope:Computed(function(use) local h = use(V.nHull) :: number return if h <= 0.35 then Theme.Threat elseif h <= 0.65 then Theme.Amber else Theme.Hud end) }),
						scope:New("Frame")({
						Name = "EjectPrompt", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.745, 0), Size = UDim2.fromOffset(620, 40),
						BackgroundColor3 = Color3.fromRGB(90, 8, 8),
						BackgroundTransparency = scope:Computed(function(use) return if use(V.nPullUpBlink) then 0.2 else 0.5 end),
						Visible = scope:Computed(function(use) return use(V.bHullCritical) or use(V.bFlameout) end),
						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
							scope:New("UIStroke")({ Color = Theme.Threat, Thickness = 2 }),
							C.HudText(scope, { Name = "HullCritical", Font = Theme.Display, TextSize = 24, Color = Color3.fromRGB(255, 235, 230),
								Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
								Text = scope:Computed(function(use)
									local what = if use(V.bFlameout) then "FLAMEOUT" else "HULL CRITICAL"
									if use(V.bTouch) then return what .. " - TAP THE RED EJECT BUTTON" end
									if use(V.bGamepad) then return what .. " - HOLD [Y] TO EJECT" end
									return what .. " - HOLD [X] TO EJECT"
								end) }),
						},
					}),
					-- return-to-base guidance and landing / taxi prompts
					C.HudText(scope, { Name = "RtbHint", Font = Theme.Display, TextSize = 17, Color = Theme.Amber,
						Position = UDim2.new(0.5, 0, 0.79, 0), Size = UDim2.fromOffset(820, 24), Text = V.sRtbHint }),
					scope:New("Frame")({
						Name = "GroundHintBack", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.83, 0), Size = UDim2.fromOffset(760, 32),
						BackgroundColor3 = Theme.Night, BackgroundTransparency = 0.45,
						Visible = scope:Computed(function(use) return use(V.sGroundHint) ~= "" end),
						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
							C.HudText(scope, { Name = "GroundHint", Font = Theme.Display, TextSize = 17, Color = Theme.Hud,
								Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Text = V.sGroundHint }),
						},
					}),
					-- controls legend (keyboard / pad): every key the cockpit has, small, bottom centre
					C.HudText(scope, { Name = "Legend", Font = Theme.Body, TextSize = 14, Color = Theme.Mute,
						Position = UDim2.new(0.5, 0, 0.965, 0), Size = UDim2.fromOffset(1100, 20),
						Visible = scope:Computed(function(use) return not use(V.bTouch) end),
						Text = scope:Computed(function(use)
							if use(V.bGamepad) then
								return "RT/LT THROTTLE   R1 GUNS   L1 MISSILE   B FLARES   D-PAD DOWN GEAR   HOLD Y EJECT   R3 LOOK"
							end
							return "W/S THROTTLE   SHIFT AFTERBURNER   LMB GUNS   RMB/SPACE MISSILE   F FLARES   G GEAR   HOLD X EJECT   C LOOK"
						end) }),
					-- tanker / fuel guidance
					C.HudText(scope, { Name = "RefuelHint", Font = Theme.Display, TextSize = 18, Color = Theme.Hud,
						Position = UDim2.new(0.5, 0, 0.705, 0), Size = UDim2.fromOffset(520, 26), Text = V.sRefuelHint }),
					-- touch throttle slider (left edge; touches here don't steer)
					scope:New("Frame")({
						Name = "ThrottleSlider", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 18, 0.55, 0),
						Size = UDim2.fromOffset(56, 230), BackgroundColor3 = Color3.fromRGB(10, 16, 20), BackgroundTransparency = 0.4,
						Visible = V.bTouch, Active = true,

						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(0, 10) }),
							scope:New("UIStroke")({ Color = Theme.Hud, Transparency = 0.4, Thickness = 2 }),
							scope:New("Frame")({ -- knob
								AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 8, 0, 22), BackgroundColor3 = Theme.Hud,
								Position = scope:Computed(function(use) return UDim2.fromScale(0.5, 1 - (use(V.nThrottle) :: number)) end),
								[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }) },
							}),
							C.HudText(scope, { Font = Theme.Display, TextSize = 11, Position = UDim2.new(0.5, 0, 1, 12), Size = UDim2.fromOffset(80, 14), Text = "THROTTLE" }),
						},
					}),
					-- ground-proximity warning (flashes)
					C.HudText(scope, { Name = "PullUp", Text = "PULL UP", Font = Theme.Display, TextSize = 30, Color = Theme.Threat,
						Position = UDim2.new(0.5, 0, 0.62, 0), Size = UDim2.fromOffset(320, 40),
						Visible = scope:Computed(function(use) return use(V.bPullUp) and use(V.nPullUpBlink) end) }),
					-- launch result toast
					C.HudText(scope, { Name = "LaunchResult", Font = Theme.Display, TextSize = 34, Color = Theme.Amber,
						Position = UDim2.new(0.5, 0, 0.3, 0), Size = UDim2.fromOffset(700, 50), Text = V.sLaunchResult }),
					-- objective / prompt (FTUE coaching line on a soft backing so it reads on any sky)
					scope:New("Frame")({
						Name = "PromptBack",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.18, 0),
						Size = UDim2.fromOffset(820, 44),
						BackgroundColor3 = Theme.Night,
						BackgroundTransparency = 0.45,
						Visible = scope:Computed(function(use) return use(V.sPrompt) ~= "" end),
						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
							C.HudText(scope, { Name = "Prompt", Font = Theme.Body, TextSize = 24, Color = Theme.Ink,
								Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Text = V.sPrompt }),
						},
					}),
					scope:New("TextButton")({
						Name = "SkipTutorial",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0.18, 30),
						Size = UDim2.fromOffset(150, 28),
						BackgroundTransparency = 1,
						FontFace = Theme.Body,
						TextSize = 16,
						TextColor3 = Theme.Ink,
						TextTransparency = 0.15,
						Text = "Skip tutorial ›",
						Visible = V.bFTUESkippable,
						[Fusion.OnEvent("Activated")] = function()
							local FTUE = require(ClientModules:WaitForChild("FTUEClient")) :: any
							FTUE:Skip()
						end,
					}),
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
					-- one row that scales as a unit (ResponsiveUIController), so buttons never collide or drift apart
					scope:New("Frame")({
						Name = "DeckButtons", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24),
						Size = UDim2.fromOffset(626, 52), BackgroundTransparency = 1,
						[Children] = {
						scope:New("UIListLayout")({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }),
					scope:New("TextButton")({
						Name = "HangarBtn", LayoutOrder = 1, Size = UDim2.fromOffset(170, 52),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1, FontFace = Theme.Body, TextSize = 20, TextColor3 = Theme.Ink,
						Text = "HANGAR", Selectable = true,
						[Fusion.OnEvent("Activated")] = function() (require(ClientModules:WaitForChild("HangarClient")) :: any):Open() end,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }), scope:New("UIStroke")({ Color = Theme.Amber, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) },
					}),
					scope:New("TextButton")({
						Name = "ShopBtn", LayoutOrder = 2, Size = UDim2.fromOffset(140, 52),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1, FontFace = Theme.Body, TextSize = 20, TextColor3 = Theme.Hud,
						Text = "SHOP", Selectable = true,
						[Fusion.OnEvent("Activated")] = function() (require(ClientModules:WaitForChild("ShopClient")) :: any):Open() end,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }), scope:New("UIStroke")({ Color = Theme.Hud, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) },
					}),
					scope:New("TextButton")({
						Name = "SquadBtn", LayoutOrder = 3, Size = UDim2.fromOffset(140, 52),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1, FontFace = Theme.Body, TextSize = 20, TextColor3 = Theme.Squad,
						Text = "SQUAD", Selectable = true,
						[Fusion.OnEvent("Activated")] = function() (require(ClientModules:WaitForChild("SocialClient")) :: any):OpenSquad() end,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }), scope:New("UIStroke")({ Color = Theme.Squad, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) },
					}),
					scope:New("TextButton")({
						Name = "SeasonBtn", LayoutOrder = 4, Size = UDim2.fromOffset(140, 52),
						BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1, FontFace = Theme.Body, TextSize = 20, TextColor3 = Theme.Amber,
						Text = "SEASON", Selectable = true,
						[Fusion.OnEvent("Activated")] = function() (require(ClientModules:WaitForChild("SeasonClient")) :: any):Open() end,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }), scope:New("UIStroke")({ Color = Theme.Amber, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) },
					}),
						},
					}),
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
					C.HudText(scope, { Font = Theme.Display, TextSize = 34, Color = Theme.Threat, Position = UDim2.fromScale(0.5, 0.405),
						Text = scope:Computed(function(use)
							local k = use(V.tKillCard)
							if k and k.Weapon == "Eject" then return "EJECTED" end
							if k and k.Weapon == "Bounds" then return "LEFT THE COMBAT ZONE" end
							if k and k.Weapon == "Crash" and (k.Killer or "") == "" then
								if k.Reason == "BellyLanding" then return "BELLY LANDING - GEAR WAS UP" end
								if k.Reason == "HardLanding" then return "HARD LANDING - TOO FAST OR TOO STEEP" end
								return "CRASHED"
							end
							return "SHOT DOWN"
						end) }),
					-- while the REVIVE offer is up the two sit side by side (never over the killer card)
					C.PrimaryButton(scope, { Name = "Relaunch", Text = "RELAUNCH",
						Position = scope:Computed(function(use) return UDim2.fromScale(if use(V.bReviveOffer) then 0.36 else 0.5, 0.62) end),
						OnClick = function() Flight:Relaunch() end }),
					-- REVIVE HERE (Robux impulse offer for a few seconds after a real sortie)
					scope:New("TextButton")({
						Name = "Revive", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.66, 0.62), Size = UDim2.fromOffset(360, 60),
						BackgroundColor3 = Theme.Hud, AutoButtonColor = true, Selectable = true, FontFace = Theme.Body, TextSize = 19,
						TextColor3 = Color3.fromRGB(11, 26, 16), Text = "REVIVE HERE · KEEP YOUR CASH   R$ 25", Visible = V.bReviveOffer,
						[Fusion.OnEvent("Activated")] = function() (require(ClientModules:WaitForChild("ShopClient")) :: any):Buy("ReviveHere") end,
						[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }) },
					}),
					scope:New("TextButton")({
						Name = "HangarBtn", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 40), Size = UDim2.fromOffset(200, 44),
						BackgroundTransparency = 1, FontFace = Theme.Body, TextSize = 19, TextColor3 = Theme.Amber, Text = "UPGRADE IN HANGAR ›", Selectable = true,
						[Fusion.OnEvent("Activated")] = function() (require(ClientModules:WaitForChild("HangarClient")) :: any):Open() end,
					}),
				},
			}),

			-- TOUCH STICK (Stick steering mode): ring where your thumb went down + knob
			scope:New("Frame")({
				Name = "StickRing", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(280, 280), BackgroundTransparency = 1,
				Position = screenPos(V.tStickBase),
				Visible = scope:Computed(function(use) return (use(V.tStickBase) :: Vector2).X > -500 and use(flying) end),
				[Children] = {
					scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
					scope:New("UIStroke")({ Color = Theme.Hud, Thickness = 2, Transparency = 0.45 }),
				},
			}),
			scope:New("Frame")({
				Name = "StickKnob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = Theme.Hud, BackgroundTransparency = 0.6,
				Position = screenPos(V.tStickKnob),
				Visible = scope:Computed(function(use) return (use(V.tStickKnob) :: Vector2).X > -500 and use(flying) end),
				[Children] = { scope:New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }) },
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
					-- appears only when the hull is critical (a single tap ejects)
						C.TouchButton(scope, { Name = "Gear", Label = "GEAR", SizePx = 72, Position = UDim2.fromOffset(92, -20),
						Visible = scope:Computed(function(use) local p = use(V.sPhase) return p == "Flying" end),
						OnDown = function() Input:SetTouch("Gear", true) end, OnUp = function() Input:SetTouch("Gear", false) end }),
					-- EJECT: only when the jet is about to be lost (hull critical / flameout). Big, solid red and
					-- flashing with a pulsing halo so it is found instantly; ejecting saves the unbanked cash.
					scope:New("Frame")({
						Name = "EjectHalo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(118, -122), BackgroundTransparency = 1,
						Size = scope:Computed(function(use) return if use(V.nPullUpBlink) then UDim2.fromOffset(150, 150) else UDim2.fromOffset(134, 134) end),
						Visible = scope:Computed(function(use) return use(V.bHullCritical) or use(V.bFlameout) end),
						[Children] = {
							scope:New("UICorner")({ CornerRadius = UDim.new(0, 18) }),
							scope:New("UIStroke")({ Color = Theme.Threat, Thickness = 4,
								Transparency = scope:Computed(function(use) return if use(V.nPullUpBlink) then 0.05 else 0.6 end) }),
						},
					}),
					C.TouchButton(scope, { Name = "Eject", Label = "EJECT", Color = Color3.fromRGB(255, 245, 240), TextSize = 26, SizePx = 118,
						Position = UDim2.fromOffset(118, -122),
						Fill = scope:Computed(function(use) return if use(V.nPullUpBlink) then Theme.Threat else Color3.fromRGB(120, 10, 10) end),
						Visible = scope:Computed(function(use) return use(V.bHullCritical) or use(V.bFlameout) end),
						OnDown = function() Input:SetTouch("Eject", true) end, OnUp = function() Input:SetTouch("Eject", false) end }),
				},
			}),
		},
	})
end
