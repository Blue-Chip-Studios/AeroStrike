--!strict
--[[
    InputController
    ---------------
    Turns every input device into one action state. Gameplay never reads
    keys directly.

        Input.State.Aim      Vector2 screen offset from centre (-1..1 each axis)
        Input.State.Boost / Brake / Guns   held booleans
        Input.State.Roll     -1..1 manual roll
        Input.Pressed        signal(actionName) for edge actions:
                             "Missile", "Flare", "Launch", "FreeLook"
        Input:SetTouch(name, down)  used by HUD touch buttons

    Steering is "aim to fly": mouse cursor position, a touch drag anywhere on
    the left 60% of the screen, or the controller sticks move the aim point.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)

local Pressed = Instance.new("BindableEvent")

local Input = ModuleUtil.New({
	State = {
		Aim = Vector2.zero,
		Boost = false,
		Brake = false,
		Guns = false,
		Roll = 0,
		FreeLook = false,
		Throttle = 0.75, -- 0..1 set-and-hold; afterburner (Boost) is the detent past 100%
		Sensitivity = 1,
		InvertY = false,
		TouchMode = "Swipe", -- "Swipe": drag aims + holding away from the touch point keeps turning; "Stick": pure virtual joystick
	},
	Pressed = Pressed.Event,
	LastDevice = "KeyboardMouse",
})

local tTouchHeld: { [string]: boolean } = {}
local oDragInput: InputObject? = nil
local vDragStart = Vector2.zero
local vLastDrag = Vector2.zero
local vStick1 = Vector2.zero
local vStick2 = Vector2.zero
local nRollKeys = 0
-- throttle: W / RT ramp up (holding past 100% lights the afterburner), S / LT ramp down,
-- Shift = instant afterburner, mouse wheel steps; touch uses the HUD slider + BOOST
local bThrottleUp, bThrottleDown, bShiftAB, bTouchAB = false, false, false, false
local nEjectHeldSince: number? = nil -- hold X / Y to eject (no accidents)
local EJECT_HOLD = 0.6
local nAtMaxHeld = 0
local THROTTLE_RATE = 0.6 -- per second
local DETENT_HOLD = 0.3 -- seconds held at 100% before the afterburner lights

local DRAG_RANGE = 140 -- px of drag for full deflection

local function fire(sName: string)
	Pressed:Fire(sName)
end

function Input.SetTouch(self, sName: string, bDown: boolean)
	local was = tTouchHeld[sName]
	tTouchHeld[sName] = bDown
	if sName == "Boost" then bTouchAB = bDown
	elseif sName == "Guns" then self.State.Guns = bDown
	elseif sName == "Brake" then self.State.Brake = bDown end
	if bDown and not was and (sName == "Missile" or sName == "Flare" or sName == "Launch" or sName == "Eject" or sName == "Gear") then
		fire(sName)
	end
	if bDown and sName == "Boost" then fire("Launch") end -- BOOST also launches from the deck
end

function Input.SetThrottle(self, v: number)
	self.State.Throttle = math.clamp(v, 0, 1)
	Store.Values.nThrottle:set(self.State.Throttle)
end

function Input.ResetThrottle(self, v: number)
	bThrottleUp, bThrottleDown, nAtMaxHeld = false, false, 0
	self:SetThrottle(v)
end

local function bindHold(sAction: string, field: string, ...: any)
	ContextActionService:BindAction(sAction, function(_, state)
		if state == Enum.UserInputState.Begin then
			(Input.State :: any)[field] = true
			if field == "Boost" then fire("Launch") end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			(Input.State :: any)[field] = false
		end
		return Enum.ContextActionResult.Pass
	end, false, ...)
end

local function bindPress(sAction: string, sEvent: string, ...: any)
	ContextActionService:BindAction(sAction, function(_, state)
		if state == Enum.UserInputState.Begin then fire(sEvent) end
		return Enum.ContextActionResult.Pass
	end, false, ...)
end

local function screenCentre(): Vector2
	local cam = Workspace.CurrentCamera
	return cam.ViewportSize / 2
end

function Input.StartAsync(self)
	ContextActionService:BindAction("AS_ThrottleUp", function(_, st)
		bThrottleUp = st == Enum.UserInputState.Begin or (st == Enum.UserInputState.Change and bThrottleUp)
		if st == Enum.UserInputState.Begin then fire("Launch") end -- also launches from the deck
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.W, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("AS_ThrottleDown", function(_, st)
		bThrottleDown = st == Enum.UserInputState.Begin or (st == Enum.UserInputState.Change and bThrottleDown)
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.S, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("AS_Eject", function(_, st)
		if st == Enum.UserInputState.Begin then nEjectHeldSince = os.clock()
		elseif st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then nEjectHeldSince = nil end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.X, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("AS_Afterburner", function(_, st)
		bShiftAB = st == Enum.UserInputState.Begin
		if st == Enum.UserInputState.Begin then fire("Launch") end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift)
	UserInputService.InputChanged:Connect(function(inp, processed)
		if not processed and inp.UserInputType == Enum.UserInputType.MouseWheel then
			self:SetThrottle(self.State.Throttle + (if inp.Position.Z > 0 then 0.1 else -0.1))
		end
	end)
	bindHold("AS_Guns", "Guns", Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR1)
	bindPress("AS_Missile", "Missile", Enum.UserInputType.MouseButton2, Enum.KeyCode.Space, Enum.KeyCode.ButtonL1)
	bindPress("AS_Flare", "Flare", Enum.KeyCode.F, Enum.KeyCode.ButtonB)
	bindPress("AS_Gear", "Gear", Enum.KeyCode.G, Enum.KeyCode.DPadDown)
	bindPress("AS_Launch", "Launch", Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	ContextActionService:BindAction("AS_RollL", function(_, st)
		nRollKeys += if st == Enum.UserInputState.Begin then -1 elseif st == Enum.UserInputState.End then 1 else 0
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.A)
	ContextActionService:BindAction("AS_RollR", function(_, st)
		nRollKeys += if st == Enum.UserInputState.Begin then 1 elseif st == Enum.UserInputState.End then -1 else 0
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.D)
	ContextActionService:BindAction("AS_FreeLook", function(_, st)
		self.State.FreeLook = st == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C, Enum.KeyCode.ButtonR3)

	-- Touch steering: a drag that starts on the left 60% of the screen.
	-- touch throttle slider (HUD.ThrottleSlider): a touch that starts on it drags the throttle
	local oSliderInput: InputObject? = nil
	local function slider(): GuiObject?
		local hud = Players.LocalPlayer:FindFirstChild("PlayerGui") and Players.LocalPlayer.PlayerGui:FindFirstChild("HUD")
		return hud and hud:FindFirstChild("ThrottleSlider", true) :: GuiObject?
	end
	local function sliderSet(inp: InputObject)
		local sl = slider()
		if not sl then return end
		local inset = game:GetService("GuiService"):GetGuiInset()
		local y = inp.Position.Y + inset.Y
		self:SetThrottle(1 - (y - sl.AbsolutePosition.Y) / math.max(sl.AbsoluteSize.Y, 1))
	end
	UserInputService.TouchStarted:Connect(function(inp)
		local sl = slider()
		if sl and sl.Visible and sl.AbsoluteSize.X > 0 then
			local inset = game:GetService("GuiService"):GetGuiInset()
			local pt = Vector2.new(inp.Position.X, inp.Position.Y) + inset
			local a, b = sl.AbsolutePosition, sl.AbsolutePosition + sl.AbsoluteSize
			if pt.X >= a.X - 12 and pt.X <= b.X + 12 and pt.Y >= a.Y - 12 and pt.Y <= b.Y + 12 then
				oSliderInput = inp
				sliderSet(inp)
			end
		end
	end)
	UserInputService.TouchMoved:Connect(function(inp)
		if inp == oSliderInput then sliderSet(inp) end
	end)
	UserInputService.TouchEnded:Connect(function(inp)
		if inp == oSliderInput then oSliderInput = nil end
	end)
	UserInputService.TouchStarted:Connect(function(inp, processed)
		if processed or oDragInput or inp == oSliderInput then return end
		local vp = Workspace.CurrentCamera.ViewportSize
		if inp.Position.X < vp.X * 0.6 then
			oDragInput = inp
			vDragStart = Vector2.new(inp.Position.X, inp.Position.Y)
			vLastDrag = vDragStart
		end
	end)
	UserInputService.TouchEnded:Connect(function(inp)
		if inp == oDragInput then oDragInput = nil end
	end)

	UserInputService.InputChanged:Connect(function(inp)
		if inp.KeyCode == Enum.KeyCode.Thumbstick1 then
			vStick1 = Vector2.new(inp.Position.X, inp.Position.Y)
		elseif inp.KeyCode == Enum.KeyCode.Thumbstick2 then
			vStick2 = Vector2.new(inp.Position.X, inp.Position.Y)
		end
	end)

	UserInputService.LastInputTypeChanged:Connect(function(t)
		if t == Enum.UserInputType.Touch then
			self.LastDevice = "Touch"
		elseif string.find(t.Name, "Gamepad") then
			self.LastDevice = "Gamepad"
		elseif t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Keyboard then
			self.LastDevice = "KeyboardMouse"
		end
		Store.Values.bTouch:set(self.LastDevice == "Touch")
		Store.Values.bGamepad:set(self.LastDevice == "Gamepad")
	end)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self.LastDevice = "Touch"
		Store.Values.bTouch:set(true)
	end
	-- Studio-only QA: player attribute QA_Device = "Touch" | "Gamepad" | "KeyboardMouse" forces a device mode
	if RunService:IsStudio() then
		-- QA_Guns = true holds the trigger; QA_Press = "Missile"/"Flare"/"Launch" taps a button; QA_Throttle = 0..1
		Players.LocalPlayer:GetAttributeChangedSignal("QA_Throttle"):Connect(function()
			local v = Players.LocalPlayer:GetAttribute("QA_Throttle")
			if typeof(v) == "number" then self:SetThrottle(v) end
		end)
		Players.LocalPlayer:GetAttributeChangedSignal("QA_Guns"):Connect(function()
			self.State.Guns = Players.LocalPlayer:GetAttribute("QA_Guns") == true
		end)
		Players.LocalPlayer:GetAttributeChangedSignal("QA_Press"):Connect(function()
			local a = Players.LocalPlayer:GetAttribute("QA_Press")
			if typeof(a) == "string" and a ~= "" then
				fire(a)
				Players.LocalPlayer:SetAttribute("QA_Press", nil)
			end
		end)
		Players.LocalPlayer:GetAttributeChangedSignal("QA_Device"):Connect(function()
			local d = Players.LocalPlayer:GetAttribute("QA_Device")
			if d == "Touch" or d == "Gamepad" or d == "KeyboardMouse" then
				self.LastDevice = d
				Store.Values.bTouch:set(d == "Touch")
				Store.Values.bGamepad:set(d == "Gamepad")
			end
		end)
	end
end

--[[
    Called every frame by FlightController while flying. Returns how far to
    rotate the world-space aim direction this frame: Vector2(yaw, pitch) in
    radians (+yaw = right, +pitch = up). Camera-led aim: the aim moves, the
    jet chases it, and letting go leaves the jet flying where you pointed.
]]
-- Stick-mode visual (HUD ring + knob); only pushed to the Store when it changes
local HIDDEN = Vector2.new(-1000, -1000)
local vStickBase, vStickKnob = HIDDEN, HIDDEN
local function setStick(base: Vector2?, knob: Vector2?)
	local b, k = base or HIDDEN, knob or HIDDEN
	if (b - vStickBase).Magnitude < 0.5 and (k - vStickKnob).Magnitude < 0.5 then return end
	vStickBase, vStickKnob = b, k
	if Store.Values.tStickBase then
		Store.Values.tStickBase:set(b)
		Store.Values.tStickKnob:set(k)
	end
end

local MOUSE_RAD_PER_PX = math.rad(0.16)
local TOUCH_RAD_PER_PX = math.rad(0.32)
local HOLD_RANGE = 150 -- px (x UI scale) from the touch point to full hold-turn rate
local HOLD_DEAD = 0.18 -- small offsets stay pure swipe so precise aiming doesn't drift
-- full deflection must swing the aim faster than any jet can turn (TurnRate 1.35-1.8 rad/s), or the
-- jet never pulls max G on touch / gamepad and the G mechanic (strain, vignette, shake) never kicks in
local PULL_RAD_PER_S = math.rad(165)
local HOLD_RATE = 1.0 -- x PULL_RAD_PER_S at full hold

function Input.SetFlightMouseLock(self, bLock: boolean)
	if self.LastDevice == "KeyboardMouse" then
		UserInputService.MouseBehavior = if bLock then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = not bLock
	end
end

function Input.Update(self, dt: number): Vector2
	-- throttle ramps while held; holding up at 100% pushes through the detent into afterburner
	if bThrottleUp and not bThrottleDown then
		if self.State.Throttle >= 1 then nAtMaxHeld += dt else self:SetThrottle(self.State.Throttle + THROTTLE_RATE * dt) end
	else
		nAtMaxHeld = 0
	end
	if bThrottleDown and not bThrottleUp then self:SetThrottle(self.State.Throttle - THROTTLE_RATE * dt) end
	self.State.Boost = bShiftAB or bTouchAB or (bThrottleUp and nAtMaxHeld >= DETENT_HOLD)
	if nEjectHeldSince and os.clock() - nEjectHeldSince >= EJECT_HOLD then
		nEjectHeldSince = nil
		fire("Eject")
	end
	self.State.Brake = false
	local d = Vector2.zero
	local inv = if self.State.InvertY then -1 else 1
	local sens = self.State.Sensitivity
	if self.LastDevice == "Touch" then
		if oDragInput then
			local p = Vector2.new(oDragInput.Position.X, oDragInput.Position.Y)
			if self.State.TouchMode == "Stick" then
				-- virtual stick: where you hold relative to where you touched sets the turn rate
				local off = p - vDragStart
				local okR, Resp = pcall(require, script.Parent.ResponsiveUIController)
				local uiScale = if okR and Resp and Resp.Scale then Resp.Scale else 1
				local range = DRAG_RANGE * uiScale -- the ring is drawn with the HUD's UI scale
				local v = Vector2.new(off.X, -off.Y) / range
				if v.Magnitude > 1 then v = v.Unit end
				local knob = Vector2.new(v.X, -v.Y) * range
				if v.Magnitude < 0.08 then v = Vector2.zero end
				v = v * v.Magnitude -- fine control near the centre, full rate at the rim
				d = Vector2.new(v.X, v.Y * inv) * PULL_RAD_PER_S * dt
				local inset = game:GetService("GuiService"):GetGuiInset()
				setStick(vDragStart + inset, vDragStart + inset + knob)
			else
				-- swipe + hold: moving the thumb aims directly (precise), and holding it away from
				-- where it first touched keeps turning (faster further out), so a turn never stalls
				-- when the thumb stops or reaches the screen edge
				if vLastDrag == Vector2.zero then vLastDrag = vDragStart end
				local delta = p - vLastDrag
				vLastDrag = p
				d = Vector2.new(delta.X, -delta.Y * inv) * TOUCH_RAD_PER_PX
				local okR, Resp = pcall(require, script.Parent.ResponsiveUIController)
				local uiScale = if okR and Resp and Resp.Scale then Resp.Scale else 1
				local range = HOLD_RANGE * uiScale
				local off = p - vDragStart
				local v = Vector2.new(off.X, -off.Y) / range
				if v.Magnitude > 1 then v = v.Unit end
				local m = v.Magnitude
				if m > HOLD_DEAD then
					local k = (m - HOLD_DEAD) / (1 - HOLD_DEAD)
					local hv = v.Unit * (k ^ 1.6)
					d += Vector2.new(hv.X, hv.Y * inv) * PULL_RAD_PER_S * HOLD_RATE * dt
					local inset = game:GetService("GuiService"):GetGuiInset()
					setStick(vDragStart + inset, vDragStart + inset + Vector2.new(v.X, -v.Y) * range)
				else
					setStick(nil, nil)
				end
			end
		else
			vLastDrag = Vector2.zero
			setStick(nil, nil)
		end
	elseif self.LastDevice == "Gamepad" then
		local s = if vStick1.Magnitude > vStick2.Magnitude then vStick1 else vStick2
		if s.Magnitude < 0.12 then s = Vector2.zero end
		-- steep response: precise near the centre (tracking a target), full G-pulling rate only at the rim
		local mag = s.Magnitude
		s = if mag > 0 then s.Unit * (mag ^ 2.4) else s
		d = Vector2.new(s.X, s.Y * inv) * PULL_RAD_PER_S * dt
	else
		local md = UserInputService:GetMouseDelta()
		-- a one-frame jump this big is a window-focus / alt-tab artefact, not a flick
		if md.Magnitude > 250 then md = Vector2.zero end
		d = Vector2.new(md.X, -md.Y * inv) * MOUSE_RAD_PER_PX
	end
	-- Studio-only QA override: TestAim = angular rate (rad/s) for automated playtests
	if RunService:IsStudio() then
		local t = Players.LocalPlayer:GetAttribute("TestAim")
		if typeof(t) == "Vector2" then d = t * dt end
	end
	d *= sens
	self.State.Aim = d
	self.State.Roll = math.clamp(nRollKeys, -1, 1)
	return d
end

return Input
