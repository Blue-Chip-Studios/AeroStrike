--!strict
--[[
    FlightController
    ----------------
    Client side of a sortie: deck -> Perfect Launch timing bar -> catapult
    stroke -> free flight with the shared FlightModel, writing the jet's
    LinearVelocity / AlignOrientation (the client owns its jet's physics; the
    server validates). Detects terrain/ship impacts and deck touch-and-gos,
    and publishes telemetry to the HUD Store.

    Other client modules read: Flight.Phase, Flight.Jet, Flight.State,
    Flight.Stats, Flight.Changed (signal(phase)).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local FlightModel = require(ReplicatedStorage.Shared.FlightModel)
local FlightConfig = require(ReplicatedStorage.Config.FlightConfig)
local JetConfig = require(ReplicatedStorage.Config.JetConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)

local LocalPlayer = Players.LocalPlayer
local Changed = Instance.new("BindableEvent")

local Flight = ModuleUtil.New({
	Phase = "Loading",
	Jet = nil :: Model?,
	State = nil :: FlightModel.State?,
	Stats = nil :: { [string]: any }?,
	Changed = Changed.Event,
	Crashed = Instance.new("BindableEvent"),
	AimDir = Vector3.new(0, 0, -1), -- world-space aim (camera-led steering)
	Spawn = nil :: { start: CFrame, finish: CFrame }?,
})

local Input -- InputController (resolved in StartAsync)
local oRequest, oEvent
local nBarStart = 0
local nCatapultT = 0
local nLaunchSpeed = 0
local nFreeBoost = 0
local nTouchAndGoCooldown = 0
local bClimbOut = false
local tRayParams = RaycastParams.new()
tRayParams.FilterType = Enum.RaycastFilterType.Exclude
tRayParams.IgnoreWater = false

local function setPhase(p: string)
	Flight.Phase = p
	Store.Values.sPhase:set(p)
	if Input then Input:SetFlightMouseLock(p == "Flying" or p == "Catapult") end
	Changed:Fire(p)
end

local function waitForJet(nTimeout: number): Model?
	local folder = Workspace:WaitForChild("Jets", 10)
	if not folder then return nil end
	return folder:WaitForChild(tostring(LocalPlayer.UserId), nTimeout) :: Model?
end

local function onSpawned(t: any)
	Flight.Stats = t.stats
	Flight.Spawn = { start = t.start, finish = t.finish }
	local jet = waitForJet(15)
	if not jet then
		warn("[Flight] jet did not stream in")
		return
	end
	Flight.Jet = jet
	tRayParams.FilterDescendantsInstances = { Workspace:FindFirstChild("Jets") :: Instance }
	Flight.State = FlightModel.NewState(t.start, 0, t.stats.Fuel)
	Store.Values.sLaunchResult:set("")
	nBarStart = os.clock()
	setPhase("Deck")
end

local function onLaunched(t: any)
	nLaunchSpeed = t.speed
	nFreeBoost = t.freeBoost or 0
	nCatapultT = 0
	Store.Values.sLaunchResult:set(if t.perfect then "PERFECT LAUNCH!" else "LAUNCH")
	task.delay(1.6, function() Store.Values.sLaunchResult:set("") end)
	setPhase("Catapult")
end

local function requestLaunch()
	if Flight.Phase ~= "Deck" then return end
	local frac = ((os.clock() - nBarStart) % FlightConfig.LaunchCountdown) / FlightConfig.LaunchCountdown
	local w = FlightConfig.PerfectWindow
	local bPerfect = frac >= w[1] and frac <= w[2]
	setPhase("Launching")
	oRequest:FireServer({ a = "Launch", perfect = bPerfect })
end

local function writeMovers(cf: CFrame, vel: Vector3)
	local jet = Flight.Jet
	if not jet or not jet.PrimaryPart then return end
	local root = jet.PrimaryPart
	local thrust = root:FindFirstChild("Thrust") :: LinearVelocity?
	local steer = root:FindFirstChild("Steer") :: AlignOrientation?
	if thrust then thrust.VectorVelocity = vel end
	if steer then steer.CFrame = cf.Rotation end
end

local function crash(sHit: string?)
	if Flight.Phase ~= "Flying" then return end
	setPhase("Dead")
	oRequest:FireServer({ a = "Crash", hit = sHit })
	Flight.Crashed:Fire()
end

-- Camera-led aim: rotate the world-space aim direction by this frame's
-- input (yaw about world up, pitch about the aim's right axis), keep it
-- within MaxAimAngle of the nose and away from straight up/down.
local MAX_AIM_PITCH = math.rad(84)
local function updateAimDir(d: Vector2, fwd: Vector3)
	local a = Flight.AimDir
	if d.X ~= 0 then a = CFrame.fromAxisAngle(Vector3.yAxis, -d.X) * a end
	if d.Y ~= 0 then
		local right = a:Cross(Vector3.yAxis)
		if right.Magnitude > 1e-4 then a = CFrame.fromAxisAngle(right.Unit, d.Y) * a end
	end
	a = a.Unit
	-- pitch clamp
	local pitch = math.asin(math.clamp(a.Y, -1, 1))
	if math.abs(pitch) > MAX_AIM_PITCH then
		local flat = Vector3.new(a.X, 0, a.Z)
		if flat.Magnitude < 1e-3 then flat = Vector3.new(fwd.X, 0, fwd.Z) end
		flat = flat.Unit
		local p = math.sign(pitch) * MAX_AIM_PITCH
		a = (flat * math.cos(p) + Vector3.yAxis * math.sin(p)).Unit
	end
	-- leash to the nose
	local ang = math.acos(math.clamp(a:Dot(fwd), -1, 1))
	if ang > FlightConfig.MaxAimAngle then
		local axis = fwd:Cross(a)
		if axis.Magnitude > 1e-5 then a = (CFrame.fromAxisAngle(axis.Unit, FlightConfig.MaxAimAngle) * fwd).Unit end
	end
	Flight.AimDir = a
end

local function step(dt: number)
	local st = Flight.State
	local jet = Flight.Jet
	if not st or not jet or not jet.Parent or not jet.PrimaryPart then return end
	local root = jet.PrimaryPart
	local stats = Flight.Stats :: { [string]: any }

	if Flight.Phase == "Deck" then
		local frac = ((os.clock() - nBarStart) % FlightConfig.LaunchCountdown) / FlightConfig.LaunchCountdown
		Store.Values.nLaunchBar:set(frac)
		-- auto-launch after a few cycles so AFK/new players still go
		if os.clock() - nBarStart > FlightConfig.LaunchCountdown * 3 then requestLaunch() end
		return
	end

	if Flight.Phase == "Catapult" then
		local sp = Flight.Spawn :: { start: CFrame, finish: CFrame }
		nCatapultT += dt / FlightConfig.CatapultTime
		local t = math.clamp(nCatapultT, 0, 1)
		local ease = t * t
		local cf = sp.start:Lerp(sp.finish, ease)
		local speed = nLaunchSpeed * t
		writeMovers(cf, (sp.finish.Position - sp.start.Position).Unit * math.max(speed, 20))
		st.CFrame = cf
		st.Speed = math.max(speed, 1)
		Store.Values.nSpeedKmh:set(math.floor(st.Speed * JetConfig.KmhPerStud))
		if t >= 1 then
			st.Speed = nLaunchSpeed
			st.FreeBoost = nFreeBoost
			-- small climb kick off the bow
			st.CFrame = CFrame.lookAt(root.Position, root.Position + sp.finish.LookVector + Vector3.new(0, 0.12, 0))
			Flight.AimDir = (sp.finish.LookVector + Vector3.new(0, 0.18, 0)).Unit -- gentle climb-out
			bClimbOut = true
			setPhase("Flying")
		end
		return
	end

	if Flight.Phase ~= "Flying" then return end

	-- keep the sim anchored to where physics actually put us (no drift)
	st.CFrame = CFrame.new(root.Position) * st.CFrame.Rotation
	local aimDelta = Input:Update(dt)
	if not Input.State.FreeLook then updateAimDir(aimDelta, st.CFrame.LookVector) end
	-- climb-out assist: after launch, level off at ~280 studs unless the pilot steers
	if bClimbOut then
		if aimDelta.Magnitude > 0.002 then
			bClimbOut = false
		elseif st.CFrame.Position.Y > 280 then
			local a = Flight.AimDir
			local flat = Vector3.new(a.X, 0, a.Z)
			if flat.Magnitude > 1e-3 then
				Flight.AimDir = a:Lerp(flat.Unit, math.clamp(dt * 1.5, 0, 1)).Unit
				if math.abs(Flight.AimDir.Y) < 0.01 then bClimbOut = false end
			end
		end
	end
	local input: FlightModel.Input = {
		AimDir = Flight.AimDir,
		Boost = Input.State.Boost,
		Brake = Input.State.Brake,
		Roll = Input.State.Roll,
	}
	local prev = st.CFrame
	if stats.NoGLoc then st.GLocTimer = 0; st.OverGTime = 0 end
	FlightModel.Step(st, input, stats :: any, dt)

	-- impact / touch-and-go test along the path we're about to fly
	local travel = st.CFrame.Position - prev.Position
	local probe = travel + travel.Unit * 6
	local hit = Workspace:Raycast(prev.Position, probe, tRayParams)
	if hit and not jet:GetAttribute("Shield") then
		local carrier = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Carrier")
		local onDeck = carrier and hit.Instance:IsDescendantOf(carrier) and hit.Normal.Y > 0.9
		if onDeck and st.CFrame.LookVector.Y > -0.35 then
			-- gentle contact with the deck: roll along it (touch-and-go)
			local p = st.CFrame.Position
			st.CFrame = CFrame.new(p.X, hit.Position.Y + 3.2, p.Z) * st.CFrame.Rotation
			if os.clock() > nTouchAndGoCooldown then nTouchAndGoCooldown = os.clock() + 3 end
		else
			crash(hit.Instance.Name .. "/" .. hit.Material.Name)
			return
		end
	elseif hit and jet:GetAttribute("Shield") then
		-- spawn shield: bounce instead of dying
		st.CFrame = CFrame.new(hit.Position + hit.Normal * 8) * st.CFrame.Rotation
	end

	-- soft ceiling and bounds: steer back rather than kill
	local p = st.CFrame.Position
	if p.Y > FlightConfig.CeilingY then
		st.CFrame = CFrame.new(p.X, FlightConfig.CeilingY, p.Z) * st.CFrame.Rotation
	end

	local vel = st.CFrame.LookVector * st.Speed
	writeMovers(st.CFrame, vel)

	-- telemetry
	Store.Values.nSpeedKmh:set(math.floor(st.Speed * JetConfig.KmhPerStud))
	Store.Values.nAltitude:set(math.floor(math.max(0, p.Y - FlightConfig.WaterLevel)))
	Store.Values.nFuel:set(st.Fuel / stats.Fuel)
	Store.Values.nG:set(st.G)
	Store.Values.nGLoc:set(if st.GLocTimer > 0 then 1 else math.clamp(st.OverGTime / FlightConfig.GLocTime, 0, 1) * 0.5)
	local lv = st.CFrame.LookVector
	Store.Values.nHeading:set((math.deg(math.atan2(lv.X, -lv.Z)) + 360) % 360)
	Store.Values.bShield:set(jet:GetAttribute("Shield") == true)
	Store.Values.bBoost:set(Input.State.Boost)
	local cam = Workspace.CurrentCamera
	local aimPt, aimOn = cam:WorldToViewportPoint(p + Flight.AimDir * FlightConfig.AimDistance)
	Store.Values.tAimScreen:set(if aimOn then Vector2.new(aimPt.X, aimPt.Y) else Vector2.new(-1000, -1000))
	local nose, onScreen = cam:WorldToViewportPoint(p + lv * FlightConfig.AimDistance)
	Store.Values.tNoseScreen:set(if onScreen then Vector2.new(nose.X, nose.Y) else Vector2.new(-1000, -1000))
end

function Flight.Refuel(self)
	if self.State and self.Stats then
		self.State.Fuel = self.Stats.Fuel
	end
end

function Flight.StartAsync(self)
	Input = require(script.Parent.InputController)
	oRequest = Remote:GetEvent("FlightRequest")
	oEvent = Remote:GetEvent("FlightEvent")
	oEvent:OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Spawned" then
			task.spawn(onSpawned, t)
		elseif t.a == "Launched" then
			onLaunched(t)
		elseif t.a == "Reset" then
			setPhase("Dead")
		elseif t.a == "TouchAndGo" then
			self:Refuel()
		end
	end)
	Input.Pressed:Connect(function(sName)
		if sName == "Launch" then requestLaunch() end
	end)
	RunService.Heartbeat:Connect(step)

	-- jet removed by server (shot down / reset)
	Workspace:WaitForChild("Jets").ChildRemoved:Connect(function(c)
		if c == self.Jet and self.Phase ~= "Loading" then
			setPhase("Dead")
		end
	end)
end

function Flight.Relaunch(self)
	if self.Phase == "Dead" then
		oRequest:FireServer({ a = "Relaunch" })
	end
end

return Flight
