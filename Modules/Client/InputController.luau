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
		Sensitivity = 1,
		InvertY = false,
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

local DRAG_RANGE = 140 -- px of drag for full deflection

local function fire(sName: string)
	Pressed:Fire(sName)
end

function Input.SetTouch(self, sName: string, bDown: boolean)
	local was = tTouchHeld[sName]
	tTouchHeld[sName] = bDown
	if sName == "Boost" then self.State.Boost = bDown
	elseif sName == "Guns" then self.State.Guns = bDown
	elseif sName == "Brake" then self.State.Brake = bDown end
	if bDown and not was and (sName == "Missile" or sName == "Flare" or sName == "Launch") then
		fire(sName)
	end
	if bDown and sName == "Boost" then fire("Launch") end -- BOOST also launches from the deck
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
	bindHold("AS_Boost", "Boost", Enum.KeyCode.W, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)
	bindHold("AS_Brake", "Brake", Enum.KeyCode.S, Enum.KeyCode.ButtonL2)
	bindHold("AS_Guns", "Guns", Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR1)
	bindPress("AS_Missile", "Missile", Enum.UserInputType.MouseButton2, Enum.KeyCode.Space, Enum.KeyCode.ButtonL1)
	bindPress("AS_Flare", "Flare", Enum.KeyCode.F, Enum.KeyCode.ButtonB)
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
	UserInputService.TouchStarted:Connect(function(inp, processed)
		if processed or oDragInput then return end
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
local MOUSE_RAD_PER_PX = math.rad(0.16)
local TOUCH_RAD_PER_PX = math.rad(0.32)
local STICK_RAD_PER_S = math.rad(95)

function Input.SetFlightMouseLock(self, bLock: boolean)
	if self.LastDevice == "KeyboardMouse" then
		UserInputService.MouseBehavior = if bLock then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = not bLock
	end
end

function Input.Update(self, dt: number): Vector2
	local d = Vector2.zero
	local inv = if self.State.InvertY then -1 else 1
	local sens = self.State.Sensitivity
	if self.LastDevice == "Touch" then
		if oDragInput then
			local p = Vector2.new(oDragInput.Position.X, oDragInput.Position.Y)
			if vLastDrag == Vector2.zero then vLastDrag = vDragStart end
			local delta = p - vLastDrag
			vLastDrag = p
			d = Vector2.new(delta.X, -delta.Y * inv) * TOUCH_RAD_PER_PX
		else
			vLastDrag = Vector2.zero
		end
	elseif self.LastDevice == "Gamepad" then
		local s = if vStick1.Magnitude > vStick2.Magnitude then vStick1 else vStick2
		if s.Magnitude < 0.12 then s = Vector2.zero end
		-- squared response: fine control near centre, fast at full deflection
		s = s * s.Magnitude
		d = Vector2.new(s.X, s.Y * inv) * STICK_RAD_PER_S * dt
	else
		local md = UserInputService:GetMouseDelta()
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
