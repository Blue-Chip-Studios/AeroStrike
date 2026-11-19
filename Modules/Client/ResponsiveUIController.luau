--!strict
--[[
    ResponsiveUIController: makes the GUI fit every screen and every device.

    SCALE:   every fixed-size panel / button cluster gets a UIScale driven by
             screen height (720p = 1.0, a landscape phone ~0.6, big screens up to
             1.15). Full-screen layers (vignette, HUD roots) are never scaled;
             their fixed-size children are. Re-applied on resize / rotation and
             whenever a GUI is mounted.
    GAMEPAD: on the deck or the death screen, Y = Hangar, X = Shop,
             D-pad up = Squad; B closes whatever menu is open. Opening a menu
             with a pad selects its first button. Deck buttons show the glyph.
    TOUCH:   Roblox's default movement thumbstick / jump button are disabled
             (pilots have no character; the left side of the screen is our
             steering drag zone).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Fusion = require(ReplicatedStorage.Packages.fusion)
local peek = Fusion.peek

local LocalPlayer = Players.LocalPlayer
local Responsive = ModuleUtil.New({ Scale = 1 })

local UserInputService = game:GetService("UserInputService")

local GAME_GUIS = { HUD = true, CombatHUD = true, Hangar = true, Shop = true, Social = true, Season = true, Settings = true }
local MIN_SCALE, MAX_SCALE, REF_HEIGHT = 0.58, 1.15, 720
-- LEGIBILITY: after scaling, no text renders smaller than this many pixels (phones need more)
local MIN_TEXT_TOUCH, MIN_TEXT = 11, 10
local tScales: { UIScale } = {}
local tTexts: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any -- text object -> authored TextSize

local function effectiveScale(o: Instance): number
	local s = 1
	local a: Instance? = o
	while a and not a:IsA("ScreenGui") do
		local u = a:FindFirstChild("AS_Scale")
		if u and u:IsA("UIScale") then s *= u.Scale end
		a = a.Parent
	end
	return s
end

local function fitText(t: Instance)
	local base = tTexts[t]
	if not base or not t.Parent then tTexts[t] = nil; return end
	local floor = if UserInputService.TouchEnabled then MIN_TEXT_TOUCH else MIN_TEXT
	local s = effectiveScale(t)
	local want = if base * s < floor then math.ceil(floor / s) else base
	if (t :: any).TextSize ~= want then (t :: any).TextSize = want end
end

local function trackText(t: Instance)
	if not (t:IsA("TextLabel") or t:IsA("TextButton") or t:IsA("TextBox")) or (t :: any).TextScaled or tTexts[t] then return end
	tTexts[t] = (t :: any).TextSize
	task.defer(fitText, t) -- after the UIScale above it exists
end

local function isFixed(g: GuiObject): boolean
	local s = g.Size
	return s.X.Scale == 0 and s.Y.Scale == 0 and (s.X.Offset > 0 or g.AutomaticSize ~= Enum.AutomaticSize.None)
end

local function addScale(g: GuiObject)
	if g:FindFirstChild("AS_Scale") then return end
	local u = Instance.new("UIScale")
	u.Name = "AS_Scale"
	u.Scale = Responsive.Scale
	u.Parent = g
	table.insert(tScales, u)
end

-- Menu windows (Hangar / Shop / Season: a screen-fraction "Window") scale as one unit: the
-- window gets a UIScale and a proportionally bigger logical size, so on a phone it keeps the
-- desktop layout instead of showing three oversized cards and a long scroll.
local tBoxes: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
local function windowScale(): number
	return math.clamp(Responsive.Scale, 0.62, 1)
end
local function fitBox(w: GuiObject)
	local base = tBoxes[w]
	if not base or not w.Parent then tBoxes[w] = nil; return end
	local s = windowScale()
	local u = w:FindFirstChild("AS_Scale") :: UIScale?
	if not u then
		local nu = Instance.new("UIScale")
		nu.Name = "AS_Scale"
		nu.Parent = w
		u = nu
	end
	(u :: UIScale).Scale = s
	w.Size = UDim2.new(base.X.Scale / s, base.X.Offset, base.Y.Scale / s, base.Y.Offset)
end

-- Fixed-size top-level panels get scaled; full-screen roots pass it down one level.
local function processGui(gui: ScreenGui)
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("GuiObject") and c.Name == "Window" and not isFixed(c) then
			if not tBoxes[c] then tBoxes[c] = c.Size; fitBox(c) end
		elseif c:IsA("GuiObject") then
			if isFixed(c) then
				addScale(c)
			else
				for _, cc in ipairs(c:GetChildren()) do
					if cc:IsA("GuiObject") and isFixed(cc) then addScale(cc) end
				end
			end
		end
	end
end

local function computeScale(): number
	local vp = Workspace.CurrentCamera.ViewportSize
	-- height limits on landscape phones; width limits on narrow portrait-ish windows
	local s = math.min(vp.Y / REF_HEIGHT, vp.X / 1100)
	return math.clamp(s, MIN_SCALE, MAX_SCALE)
end

local function rescale()
	Responsive.Scale = computeScale()
	for i = #tScales, 1, -1 do
		local u = tScales[i]
		if u.Parent then u.Scale = Responsive.Scale else table.remove(tScales, i) end
	end
	for w in pairs(tBoxes) do fitBox(w) end
	for t in pairs(tTexts) do fitText(t) end
	if Store.Values.bCompact then Store.Values.bCompact:set(Responsive.Scale < 0.75) end
end

local function watchGui(gui: Instance)
	if not gui:IsA("ScreenGui") or not GAME_GUIS[gui.Name] then return end
	processGui(gui)
	gui.ChildAdded:Connect(function() task.defer(processGui, gui) end)
	for _, d in ipairs(gui:GetDescendants()) do trackText(d) end
	gui.DescendantAdded:Connect(trackText)
	gui.DescendantRemoving:Connect(function(d) tTexts[d] = nil end)
end

-- ===== gamepad menus =====
local function firstSelectable(root: Instance?): GuiObject?
	if not root then return nil end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiButton") and d.Selectable and d.Visible and d.AbsoluteSize.X > 0 then
			-- every ancestor up to the ScreenGui must be visible too
			local ok, a = true, d.Parent
			while a and a:IsA("GuiObject") do
				if not a.Visible then ok = false break end
				a = a.Parent
			end
			if ok then return d end
		end
	end
	return nil
end

local function focus(guiName: string, child: string?)
	if not Store.Values.bGamepad or not peek(Store.Values.bGamepad) then return end
	task.delay(0.15, function()
		local gui = LocalPlayer.PlayerGui:FindFirstChild(guiName)
		local root = if gui and child then gui:FindFirstChild(child, true) else gui
		local b = firstSelectable(root)
		if b then GuiService.SelectedObject = b end
	end)
end

function Responsive.StartAsync(self)
	-- default touch controls off (no character; left half is our steering zone)
	task.spawn(function()
		local pm = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if pm then
			pcall(function() (require(pm :: ModuleScript) :: any):GetControls():Disable() end)
		end
	end)

	rescale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		rescale()
	end)
	for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do watchGui(g) end
	LocalPlayer.PlayerGui.ChildAdded:Connect(watchGui)

	local Flight = require(script.Parent.FlightController) :: any
	local Hangar = require(script.Parent.HangarClient) :: any
	local Shop = require(script.Parent.ShopClient) :: any
	local Social = require(script.Parent.SocialClient) :: any

	local function anyMenu(): boolean
		return peek(Store.Values.bHangarOpen) or peek(Store.Values.bShopOpen)
			or peek(Store.Values.bSquadOpen) or peek(Store.Values.bDailyOpen) or peek(Store.Values.bSettingsOpen)
	end
	local function onGround(): boolean
		return Flight.Phase == "Deck" or Flight.Phase == "Dead"
	end

	ContextActionService:BindAction("AS_PadMenus", function(_, state, inp)
		if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		local k = inp.KeyCode
		if k == Enum.KeyCode.ButtonB and anyMenu() then
			if peek(Store.Values.bHangarOpen) then Hangar:Close() end
			if peek(Store.Values.bSettingsOpen) then (require(script.Parent.SettingsClient) :: any):Close() end
			if peek(Store.Values.bShopOpen) then Shop:Close() end
			if peek(Store.Values.bSquadOpen) then Social:CloseSquad() end
			if peek(Store.Values.bDailyOpen) then Social:CloseDaily() end
			GuiService.SelectedObject = nil
			return Enum.ContextActionResult.Sink
		end
		if not onGround() or anyMenu() then return Enum.ContextActionResult.Pass end
		if k == Enum.KeyCode.ButtonY then Hangar:Open()
		elseif k == Enum.KeyCode.ButtonX then Shop:Open(); focus("Shop")
		elseif k == Enum.KeyCode.DPadUp then Social:OpenSquad(); focus("Social", "SquadScreen")
		else return Enum.ContextActionResult.Pass end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonX, Enum.KeyCode.DPadUp, Enum.KeyCode.ButtonB)

	-- the daily panel pops up by itself: give a pad player focus on it
	local scope = Fusion.scoped(Fusion)
	scope:Observer(Store.Values.bDailyOpen):onChange(function()
		if peek(Store.Values.bDailyOpen) then focus("Social", "Daily") end
	end)

	-- glyph hints on the deck buttons while a controller is in use
	local function labels()
		local pad = peek(Store.Values.bGamepad)
		local deck = LocalPlayer.PlayerGui:FindFirstChild("HUD")
		deck = deck and deck:FindFirstChild("Deck", true)
		if not deck then return end
		local map = { HangarBtn = { "HANGAR", "[Y] HANGAR" }, ShopBtn = { "SHOP", "[X] SHOP" }, SquadBtn = { "SQUAD", "[UP] SQUAD" } }
		for name, t in pairs(map) do
			local b = deck:FindFirstChild(name, true) :: TextButton?
			if b then b.Text = if pad then t[2] else t[1] end
		end
	end
	scope:Observer(Store.Values.bGamepad):onChange(labels)
	task.delay(3, labels)
end

return Responsive
