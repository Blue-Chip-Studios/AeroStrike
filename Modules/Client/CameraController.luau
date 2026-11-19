--!strict
--[[
    CameraController
    ----------------
    Scriptable chase camera with the game-feel layer:
      - Deck: slow cinematic orbit-in behind the jet on the catapult
      - Catapult: low, close, FOV punch
      - Flying: lagged chase that looks AT the aim distance ahead (so the
        screen centre is where the nose goes), FOV widens with speed,
        G shake above tolerance, grey-out on G-LOC, free look
      - Dead: slow orbit around the wreck point
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local FlightConfig = require(ReplicatedStorage.Config.FlightConfig)

-- Mode: "Chase" (default), "Close" (tighter chase) or "Nose" (HUD-only view from the nose,
-- your own jet hidden). KillCamOn toggles the missile kill cam. Both come from Settings.
local Cam = ModuleUtil.New({ Mode = "Chase", KillCamOn = true })
local oHiddenJet: Model? = nil
local function hideOwnJet(jet: Model?, hide: boolean)
	local want = if hide then jet else nil
	if want == oHiddenJet then return end
	if oHiddenJet and oHiddenJet.Parent then
		for _, d in ipairs(oHiddenJet:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 end
		end
	end
	oHiddenJet = want
	if want then
		for _, d in ipairs(want:GetDescendants()) do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
		end
	end
end

local Flight, Input
local cfSmooth: CFrame? = nil
local vDeathPoint = Vector3.zero
local nDeathAngle = 0
local nShakeT = 0
local nKick = 0 -- one-off impulse shake (kills, big hits), decays quickly
local nFovPunch = 0 -- one-off FOV widen (sonic boom), decays
local oGrade: ColorCorrectionEffect

local CHASE_OFFSET = Vector3.new(0, 7.5, 34)
-- KILL CAM: a short cut to your missile kill (only when nothing is locked on you)
local KILLCAM_TIME, KILLCAM_COOLDOWN = 0.9, 20
local nKillCamUntil, nKillCamLast = 0, -math.huge
local vKillPos, vKillFrom = Vector3.zero, Vector3.zero
local nLookYaw, nLookPitch = 0, 0

local function update(dt: number)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local jet = Flight.Jet
	local phase = Flight.Phase
	local st = Flight.State

	-- nose view hides your own airframe only while flying in that mode (and never in the kill cam)
	hideOwnJet(jet, Cam.Mode == "Nose" and phase == "Flying" and os.clock() >= nKillCamUntil and jet ~= nil and jet.Parent ~= nil)

	if phase == "Dead" or not jet or not jet.Parent or not jet.PrimaryPart then
		-- you ejected: watch your own parachute drift down (with the wreck falling away behind)
		local chute = (require(script.Parent.VfxController) :: any).OwnChuteCF :: CFrame?
		if chute then
			nDeathAngle += dt * 0.18
			local p = chute.Position + Vector3.new(math.cos(nDeathAngle) * 38, 10, math.sin(nDeathAngle) * 38)
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(p, chute.Position + Vector3.new(0, 6, 0)), math.clamp(dt * 3, 0, 1))
			cam.FieldOfView = 65
			oGrade.Saturation = 0
			return
		end
		nDeathAngle += dt * 0.25
		local p = vDeathPoint + Vector3.new(math.cos(nDeathAngle) * 90, 45, math.sin(nDeathAngle) * 90)
		cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(p, vDeathPoint), math.clamp(dt * 2, 0, 1))
		cam.FieldOfView = 70
		oGrade.Saturation = -0.4
		return
	end
	oGrade.Saturation = 0

	local root = jet.PrimaryPart
	local jcf = root.CFrame
	vDeathPoint = jcf.Position

	if phase == "Flying" and os.clock() < nKillCamUntil then
		-- framed from your side of the fireball, slight push-in, then the chase blends back
		local t = 1 - (nKillCamUntil - os.clock()) / KILLCAM_TIME
		local away = (vKillFrom - vKillPos)
		away = if away.Magnitude > 1 then away.Unit else Vector3.zAxis
		local side = away:Cross(Vector3.yAxis)
		side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
		local p = vKillPos + away * (60 - t * 18) + side * 22 + Vector3.new(0, 14, 0)
		local cf = CFrame.lookAt(p, vKillPos)
		cam.CFrame = cf
		cam.FieldOfView = 52 - t * 6
		cfSmooth = cf -- the chase lerps home from here
		return
	end

	if phase == "Deck" or phase == "Launching" then
		-- cinematic: side-low view sweeping to behind
		local t = (os.clock() % 30) / 30
		local side = jcf * CFrame.new(18 - t * 4, 5, 26)
		cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(side.Position, jcf.Position + jcf.LookVector * 30), math.clamp(dt * 3, 0, 1))
		cam.FieldOfView = 62
		return
	end

	local speed = if st then st.Speed else 0
	local maxS = if Flight.Stats then Flight.Stats.MaxSpeed else 250
	local speedFrac = math.clamp(speed / maxS, 0, 1)

	-- camera-led chase: sit behind the jet along the AIM direction (where the
	-- player is pointing), keep up near world-up (bank shows on the jet)
	local fwd = if phase == "Flying" then Flight.AimDir else jcf.LookVector
	local flatUp = Vector3.yAxis
	if math.abs(fwd:Dot(flatUp)) > 0.97 then flatUp = jcf.UpVector end
	local basis = CFrame.lookAt(jcf.Position, jcf.Position + fwd, flatUp)
	local close = Cam.Mode == "Close"
	local dist = (if close then 23 else CHASE_OFFSET.Z) + speedFrac * (if close then 4 else 6)
	local desiredPos = (basis * CFrame.new(0, if close then 5 else CHASE_OFFSET.Y, dist)).Position
	local lookAt = jcf.Position + fwd * FlightConfig.AimDistance

	if Cam.Mode == "Nose" and phase == "Flying" and not Input.State.FreeLook then
		-- HUD-only view from just ahead of the canopy, rolling with the jet
		local span = jet:GetAttribute("GearSpan")
		local len = if typeof(span) == "Vector3" then span.Z else 27
		local eye = jcf.Position + jcf.LookVector * (len * 0.5 + 1) + jcf.UpVector * 1.2
		local cf = CFrame.lookAt(eye, eye + jcf.LookVector * 100, jcf.UpVector)
		local g0 = if st then st.G else 1
		local tol0 = if Flight.Stats then Flight.Stats.GTolerance else 6
		local sh = math.clamp((g0 - tol0) / 3, 0, 1) * 0.35 + nKick
		nKick = math.max(0, nKick - dt * 2.2)
		if sh > 0 then
			nShakeT += dt * 40
			cf *= CFrame.Angles(math.noise(nShakeT, 1) * sh * 0.03, math.noise(nShakeT, 2) * sh * 0.03, 0)
		end
		cam.CFrame = cf
		cfSmooth = cf
		local fov = 74 + speedFrac * 12 + (if Input.State.Boost then 4 else 0)
		cam.FieldOfView += (fov - cam.FieldOfView) * math.clamp(dt * 4, 0, 1)
		local strain0 = if st then (st.Strain or 0) else 0
		local gl = if st and st.GLocTimer > 0 then 1 else math.clamp((strain0 - FlightConfig.GreyoutAt) / (1 - FlightConfig.GreyoutAt), 0, 1) * 0.8
		oGrade.Brightness, oGrade.Contrast, oGrade.Saturation = -0.35 * gl, -0.2 * gl, -0.9 * gl
		return
	end

	if Input.State.FreeLook then
		local a = Input.State.Aim
		nLookYaw += a.X
		nLookPitch = math.clamp(nLookPitch + a.Y, -1.2, 1.2)
		local orbit = basis * CFrame.Angles(0, -nLookYaw, 0) * CFrame.Angles(nLookPitch, 0, 0)
		desiredPos = (orbit * CFrame.new(0, 6, 40)).Position
		lookAt = jcf.Position
	else
		nLookYaw, nLookPitch = 0, 0
	end

	local desired = CFrame.lookAt(desiredPos, lookAt, flatUp)
	cfSmooth = if cfSmooth then cfSmooth:Lerp(desired, math.clamp(dt * 14, 0, 1)) else desired
	local out = cfSmooth :: CFrame

	-- G shake + catapult punch
	local g = if st then st.G else 1
	local tol = if Flight.Stats then Flight.Stats.GTolerance else 6
	local shake = math.clamp((g - tol) / 3, 0, 1) * 0.35
	if phase == "Catapult" then shake = 0.25 end
	shake += (require(script.Parent.AudioController) :: any).Intensity * 0.12 -- threat tremble
	if Input.State.Boost then shake += 0.05 end
	shake += nKick
	nKick = math.max(0, nKick - dt * 2.2)
	if shake > 0 then
		nShakeT += dt * 40
		out *= CFrame.Angles(math.noise(nShakeT, 1) * shake * 0.05, math.noise(nShakeT, 2) * shake * 0.05, 0)
	end
	cam.CFrame = out

	-- FOV: wider with speed and afterburner
	local targetFov = 68 + speedFrac * 14 + (if Input.State.Boost then 4 else 0) + (if phase == "Catapult" then 8 else 0)
	cam.FieldOfView += (targetFov - cam.FieldOfView) * math.clamp(dt * 4, 0, 1)
	if nFovPunch > 0 then
		cam.FieldOfView += nFovPunch
		nFovPunch = math.max(0, nFovPunch - dt * 18)
	end

	-- G-LOC grey-out
	-- G strain tunnels the view; a G-LOC blacks it out (HUD draws the black)
	local strain = if st then (st.Strain or 0) else 0
	local gloc = if st and st.GLocTimer > 0 then 1 else math.clamp((strain - FlightConfig.GreyoutAt) / (1 - FlightConfig.GreyoutAt), 0, 1) * 0.8
	oGrade.Brightness = -0.35 * gloc
	oGrade.Contrast = -0.2 * gloc
	oGrade.Saturation = -0.9 * gloc
end

function Cam.KillCam(self, pos: Vector3)
	local function qa(why: string) if RunService:IsStudio() then Players.LocalPlayer:SetAttribute("QA_KillCam", why) end end
	if not Cam.KillCamOn or os.clock() - nKillCamLast < KILLCAM_COOLDOWN or not Flight or Flight.Phase ~= "Flying" then
		qa(`skip: on={Cam.KillCamOn} phase={Flight and Flight.Phase}`)
		return
	end
	local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
	local Fusion = require(ReplicatedStorage.Packages.fusion)
	local threat = Fusion.peek(Store.Values.sThreat)
	if threat ~= "None" then qa("skip: threat " .. tostring(threat)); return end -- never look away while a missile is on you
	qa("shown")
	local jet = Flight.Jet
	if not jet or not jet.PrimaryPart then return end
	if (jet.PrimaryPart.Position - pos).Magnitude > 2500 then return end
	nKillCamLast = os.clock()
	nKillCamUntil = os.clock() + KILLCAM_TIME
	vKillPos, vKillFrom = pos, jet.PrimaryPart.Position
end

function Cam.StartAsync(self)
	Flight = require(script.Parent.FlightController)
	Input = require(script.Parent.InputController)
	oGrade = Instance.new("ColorCorrectionEffect")
	oGrade.Name = "AS_GForce"
	oGrade.Parent = Workspace.CurrentCamera
	Flight.Crashed.Event:Connect(function()
		local jet = Flight.Jet
		if jet and jet.PrimaryPart then vDeathPoint = jet.PrimaryPart.Position end
	end)
	RunService:BindToRenderStep("AS_Camera", Enum.RenderPriority.Camera.Value + 1, update)
	Players.LocalPlayer.CameraMode = Enum.CameraMode.Classic
end

-- one-off FOV widen (sonic boom): the world "jumps" away from you, then settles
function Cam.FovPunch(self, amount: number)
	nFovPunch = math.max(nFovPunch, amount)
end

-- one-off camera punch (e.g. your kill, a big hit nearby); stacks to the strongest
function Cam.Kick(self, amount: number)
	nKick = math.max(nKick, amount)
end

return Cam
