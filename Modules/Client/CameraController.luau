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

local Cam = ModuleUtil.New({})

local Flight, Input
local cfSmooth: CFrame? = nil
local vDeathPoint = Vector3.zero
local nDeathAngle = 0
local nShakeT = 0
local nKick = 0 -- one-off impulse shake (kills, big hits), decays quickly
local oGrade: ColorCorrectionEffect

local CHASE_OFFSET = Vector3.new(0, 7.5, 34)
local nLookYaw, nLookPitch = 0, 0

local function update(dt: number)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local jet = Flight.Jet
	local phase = Flight.Phase
	local st = Flight.State

	if phase == "Dead" or not jet or not jet.Parent or not jet.PrimaryPart then
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
	local dist = CHASE_OFFSET.Z + speedFrac * 6
	local desiredPos = (basis * CFrame.new(0, CHASE_OFFSET.Y, dist)).Position
	local lookAt = jcf.Position + fwd * FlightConfig.AimDistance

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

	-- G-LOC grey-out
	local gloc = if st and st.GLocTimer > 0 then 1 else math.clamp((g - tol) / 4, 0, 0.6)
	oGrade.Brightness = -0.35 * gloc
	oGrade.Contrast = -0.2 * gloc
	oGrade.Saturation = -0.9 * gloc
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

-- one-off camera punch (e.g. your kill, a big hit nearby); stacks to the strongest
function Cam.Kick(self, amount: number)
	nKick = math.max(nKick, amount)
end

return Cam
