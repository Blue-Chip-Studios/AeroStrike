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
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)

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
	GearDown = true,
	Landed = Instance.new("BindableEvent"), -- (where: "Carrier"|"Airfield", trapped: boolean)
})

local Input -- InputController (resolved in StartAsync)
local oRequest, oEvent
local nBarStart = 0
local nCatapultT = 0
local nLaunchSpeed = 0
local nFreeBoost = 0
local bTrapped = false -- carrier arrestor wire caught
local nTrapDecel = 0
local nStoppedT = 0
local bResupplyAsked = false
local nGearPromptUntil = 0
local tGroundRay = RaycastParams.new()
tGroundRay.FilterType = Enum.RaycastFilterType.Exclude
local bClimbOut = false
local nLaunchedAt = -math.huge
local LAUNCH_SAFE_TIME, LAUNCH_SAFE_ALT = 4, 100
local CEILING_BAND = 400 -- studs below FlightConfig.CeilingY where the nose starts being pushed level
local nPullUpTick = 0
local pullUpRay = RaycastParams.new()
pullUpRay.FilterType = Enum.RaycastFilterType.Include
local tRayParams = RaycastParams.new()
tRayParams.FilterType = Enum.RaycastFilterType.Exclude
tRayParams.IgnoreWater = false

local function setPhase(p: string)
	Flight.Phase = p
	Store.Values.sPhase:set(p)
	if p ~= "Flying" then Store.Values.bPullUp:set(false) end
	if Input then Input:SetFlightMouseLock(p == "Flying" or p == "Catapult" or p == "Ground") end
	Changed:Fire(p)
end

local function rideHeight(): number
	local jet = Flight.Jet
	return (jet and jet:GetAttribute("RideHeight") :: number?) or 3.2
end

local function setGear(bDown: boolean)
	if Flight.GearDown == bDown then return end
	Flight.GearDown = bDown
	Store.Values.bGearDown:set(bDown)
	oRequest:FireServer({ a = "Gear", down = bDown })
end

-- a surface you may land on: the carrier deck or the airfield's runway/apron
local function landingSurface(inst: Instance): string?
	if inst:GetAttribute("Runway") then return "Airfield" end
	local carrier = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Carrier")
	if carrier and inst:IsDescendantOf(carrier) then return "Carrier" end
	return nil
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
	tGroundRay.FilterDescendantsInstances = { Workspace:FindFirstChild("Jets") :: Instance }
	Flight.State = FlightModel.NewState(t.start, 0, t.stats.Fuel)
	Flight.GearDown = true
	Store.Values.bGearDown:set(true)
	Store.Values.sLaunchResult:set("")
	Store.Values.sGroundHint:set("")
	bTrapped, bResupplyAsked = false, false
	nBarStart = os.clock()
	setPhase("Deck")
end

-- back on the catapult after a carrier trap + resupply (same jet, full tanks)
local function onRecovered(t: any)
	Flight.Spawn = { start = t.start, finish = t.finish }
	if Flight.Stats then Flight.State = FlightModel.NewState(t.start, 0, Flight.Stats.Fuel) end
	Flight.GearDown = true
	Store.Values.bGearDown:set(true)
	Store.Values.sGroundHint:set("")
	bTrapped, bResupplyAsked = false, false
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
	local F = require(ReplicatedStorage.Packages.fusion)
	if F.peek(Store.Values.bHangarOpen) or F.peek(Store.Values.bSeasonOpen) then return end
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
		-- auto-launch after a few cycles so AFK/new players still go (paused in the hangar)
		local Fusion = require(ReplicatedStorage.Packages.fusion)
		if Fusion.peek(Store.Values.bHangarOpen) or Fusion.peek(Store.Values.bSeasonOpen) then
			nBarStart = os.clock()
		elseif os.clock() - nBarStart > FlightConfig.LaunchCountdown * 3 then
			requestLaunch()
		end
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
			nLaunchedAt = os.clock()
			Input:ResetThrottle(FlightConfig.DefaultThrottle)
			nGearPromptUntil = os.clock() + 10
			setPhase("Flying")
		end
		return
	end

	if Flight.Phase == "Ground" then
		local aimDelta = Input:Update(dt)
		updateAimDir(aimDelta, st.CFrame.LookVector)
		if RunService:IsStudio() then -- QA autopilot (taxi / take-off tests)
			local tp = LocalPlayer:GetAttribute("TestAimPoint")
			if typeof(tp) == "Vector3" and (tp - root.Position).Magnitude > 1 then Flight.AimDir = (tp - root.Position).Unit end
		end
		local pos = root.Position
		-- stay glued to the surface under the wheels
		local down = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -6 - rideHeight() - 6, 0), tGroundRay)
		local fwd = st.CFrame.LookVector
		local flat = Vector3.new(fwd.X, 0, fwd.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
		if not down or down.Normal.Y < 0.85 then
			-- rolled off the end of the deck / runway: you're flying (or falling) now
			setPhase("Flying")
			return
		end
		-- steering: yaw toward where you're looking (taxi turns are slow)
		local aimFlat = Vector3.new(Flight.AimDir.X, 0, Flight.AimDir.Z)
		if aimFlat.Magnitude > 1e-3 and not bTrapped then
			local want = aimFlat.Unit
			local ang = math.acos(math.clamp(flat:Dot(want), -1, 1))
			local rate = FlightConfig.GroundTurnRate * math.clamp(st.Speed / 30, 0.25, 1)
			if ang > 1e-3 then
				local sign = if flat:Cross(want).Y > 0 then 1 else -1
				flat = CFrame.fromAxisAngle(Vector3.yAxis, sign * math.min(ang, rate * dt)) * flat
			end
		end
		-- thrust / brakes / arrestor
		local thr = Input.State.Throttle
		local flameout = st.Fuel <= 0
		local boost = Input.State.Boost and not flameout
		local thrust = if flameout or bTrapped then 0 elseif boost then stats.Accel * 1.4 else stats.Accel * thr
		local drag = if bTrapped then nTrapDecel elseif thr < 0.08 and not boost then FlightConfig.GroundBrake else FlightConfig.GroundFriction
		st.Speed = math.max(0, st.Speed + (thrust - drag) * dt)
		if boost then st.Speed = math.min(st.Speed, stats.MaxSpeed) else st.Speed = math.min(st.Speed, stats.CruiseSpeed * FlightConfig.MilPowerMult) end
		st.Fuel = math.max(0, st.Fuel - (if flameout then 0 else stats.FuelBurn * (0.2 + 0.8 * thr) + (if boost then stats.BoostBurn else 0)) * dt)
		st.G, st.Bank, st.Omega = 1, 0, 0
		local p = Vector3.new(pos.X, down.Position.Y + rideHeight(), pos.Z)
		st.CFrame = CFrame.lookAt(p, p + flat)
		-- take-off: past rotate speed, pull the nose up
		local rotateSpeed = stats.MinSpeed * FlightConfig.RotateSpeedMult
		if not bTrapped and st.Speed >= rotateSpeed and Flight.AimDir.Y > 0.05 then
			st.CFrame = CFrame.lookAt(p + Vector3.new(0, 1.5, 0), p + Vector3.new(0, 1.5, 0) + (flat + Vector3.new(0, 0.12, 0)).Unit)
			Flight.AimDir = (flat + Vector3.new(0, 0.2, 0)).Unit
			nGearPromptUntil = os.clock() + 8
			Store.Values.sGroundHint:set("")
			setPhase("Flying")
			return
		end
		writeMovers(st.CFrame, flat * st.Speed)
		-- stopped: ask the ground crew for fuel, missiles and repairs
		if st.Speed <= FlightConfig.ResupplyMaxSpeed then nStoppedT += dt else nStoppedT = 0; bResupplyAsked = false end
		if nStoppedT > 0.4 and not bResupplyAsked then
			bResupplyAsked = true
			oRequest:FireServer({ a = "Resupply" })
		end
		if bTrapped and st.Speed <= 0.5 then bTrapped = false end
		local kmh = math.floor(rotateSpeed * JetConfig.KmhPerStud)
		local hint
		if bResupplyAsked then hint = "GROUND CREW: REARMING · REFUELLING · REPAIRING"
		elseif bTrapped then hint = "TRAPPED! ARRESTOR WIRE CAUGHT"
		elseif st.Speed > FlightConfig.ResupplyMaxSpeed and thr < 0.08 then hint = "BRAKING - STOP TO RESUPPLY"
		elseif st.Speed > FlightConfig.ResupplyMaxSpeed then hint = string.format("THROTTLE UP - PULL UP PAST %d KM/H TO TAKE OFF  |  IDLE TO BRAKE", kmh)
		else hint = "STOP TO RESUPPLY" end
		Store.Values.sGroundHint:set(hint)
		Store.Values.nSpeedKmh:set(math.floor(st.Speed * JetConfig.KmhPerStud))
		Store.Values.nAltitude:set(math.floor(math.max(0, p.Y - FlightConfig.WaterLevel)))
		Store.Values.nFuel:set(st.Fuel / stats.Fuel)
		Store.Values.nG:set(1)
		Store.Values.bStall:set(false)
		Store.Values.bBoost:set(boost)
		return
	end

	if Flight.Phase ~= "Flying" then return end

	-- keep the sim anchored to where physics actually put us (no drift)
	st.CFrame = CFrame.new(root.Position) * st.CFrame.Rotation
	local aimDelta = Input:Update(dt)
	if not Input.State.FreeLook then updateAimDir(aimDelta, st.CFrame.LookVector) end
	-- Studio-only QA autopilot: steer straight at a point (canyon/arch fly-through tests)
	if RunService:IsStudio() then
		local tp = LocalPlayer:GetAttribute("TestAimPoint")
		if typeof(tp) == "Vector3" then
			local d = tp - st.CFrame.Position
			if d.Magnitude > 1 then Flight.AimDir = d.Unit end
			bClimbOut = false
		end
	end
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
	-- launch safety: just off the bow the jet is ~30 studs above the sea, so for the
	-- first seconds (and while low) the aim can't point below a gentle climb
	if os.clock() - nLaunchedAt < LAUNCH_SAFE_TIME and st.CFrame.Position.Y < LAUNCH_SAFE_ALT then
		local a = Flight.AimDir
		local minY = math.sin(math.rad(6))
		if a.Y < minY then
			local flat = Vector3.new(a.X, 0, a.Z)
			if flat.Magnitude < 1e-3 then flat = st.CFrame.LookVector * Vector3.new(1, 0, 1) end
			if flat.Magnitude > 1e-3 then
				Flight.AimDir = (flat.Unit * math.cos(math.rad(6)) + Vector3.yAxis * minY).Unit
			end
		end
	end
	-- combat-zone edge: a little past the warning line an autopilot starts turning you back,
	-- harder the further out you are (an unsteered / AFK jet comes home instead of dying)
	do
		local pos = st.CFrame.Position
		local out = Vector3.new(pos.X - MapConfig.MapCentre.X, 0, pos.Z - MapConfig.MapCentre.Z)
		local past = out.Magnitude - (FlightConfig.BoundsRadius + 250)
		if past > 0 and st.CFrame.LookVector:Dot(out.Unit) > -0.5 then
			local home = (-out.Unit + Vector3.yAxis * 0.05).Unit
			if Flight.AimDir:Dot(home) < 0.2 then
				-- heading away: turn through the side you're already leaning to (no lerp through zero)
				local side = Vector3.yAxis:Cross(out.Unit)
				if Flight.AimDir:Dot(side) < 0 then side = -side end
				home = (side + Vector3.yAxis * 0.05).Unit
			end
			local k = math.clamp(0.25 + past / 400, 0, 1) * math.clamp(dt * 2.5, 0, 1)
			Flight.AimDir = Flight.AimDir:Lerp(home, k).Unit
		end
	end
	-- soft ceiling: over the last CEILING_BAND studs the nose is pushed level, above it, down
	do
		-- look ahead ~1.5 s of climb so a steep zoom eases over instead of slamming into the lid
		local climb = math.max(st.CFrame.LookVector.Y * st.Speed, 0)
		local over = st.CFrame.Position.Y + climb * 1.5 - (FlightConfig.CeilingY - CEILING_BAND)
		if over > 0 then
			local a = Flight.AimDir
			local maxY = math.sin(math.rad(math.clamp(60 - over / CEILING_BAND * 70, -15, 60)))
			if a.Y > maxY then
				local flat = Vector3.new(a.X, 0, a.Z)
				if flat.Magnitude < 1e-3 then flat = st.CFrame.LookVector * Vector3.new(1, 0, 1) end
				if flat.Magnitude < 1e-3 then flat = Vector3.zAxis end
				Flight.AimDir = (flat.Unit * math.sqrt(1 - maxY * maxY) + Vector3.yAxis * maxY).Unit
			end
		end
	end
	local input: FlightModel.Input = {
		AimDir = Flight.AimDir,
		Boost = Input.State.Boost,
		Brake = Input.State.Brake,
		Throttle = Input.State.Throttle,
		Roll = Input.State.Roll,
		Gear = Flight.GearDown,
	}
	local prev = st.CFrame
	if stats.NoGLoc then st.GLocTimer = 0; st.Strain = 0 end
	FlightModel.Step(st, input, stats :: any, dt)

	-- impact / touch-and-go test along the path we're about to fly
	local travel = st.CFrame.Position - prev.Position
	local probe = travel + travel.Unit * 6
	-- with the gear down the wheels touch first: probe from wheel height
	local origin = prev.Position - Vector3.new(0, if Flight.GearDown then rideHeight() - 0.6 else 0, 0)
	local hit = Workspace:Raycast(origin, probe, tRayParams)
	local shielded = jet:GetAttribute("Shield") == true
	if hit then
		local where = landingSurface(hit.Instance)
		local sink = -travel.Y / math.max(dt, 1e-3)
		local maxSp, maxSink = FlightModel.TouchdownLimits(stats)
		local tooFast = st.Speed > maxSp
		local tooSteep = sink > maxSink or st.CFrame.LookVector.Y < FlightConfig.TouchdownMinPitch
		local goodLanding = where ~= nil and hit.Normal.Y > 0.85 and Flight.GearDown and not tooFast and not tooSteep
		if shielded and not goodLanding then
			-- spawn / training shield: bounce instead of dying
			st.CFrame = CFrame.new(hit.Position + hit.Normal * 8 + Vector3.new(0, if Flight.GearDown then rideHeight() else 0, 0)) * st.CFrame.Rotation
		elseif where and hit.Normal.Y > 0.85 then
			if not Flight.GearDown then
				crash("BellyLanding")
				return
			elseif tooFast or tooSteep then
				crash("HardLanding")
				return
			end
			-- touchdown! wheels on the surface
			local p = Vector3.new(st.CFrame.Position.X, hit.Position.Y + rideHeight(), st.CFrame.Position.Z)
			local flat = Vector3.new(st.CFrame.LookVector.X, 0, st.CFrame.LookVector.Z)
			flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
			st.CFrame = CFrame.lookAt(p, p + flat)
			bTrapped = where == "Carrier"
			-- arrestor wire: a constant deceleration that stops you within TrapStopDistance
			nTrapDecel = (st.Speed * st.Speed) / (2 * FlightConfig.TrapStopDistance)
			nStoppedT, bResupplyAsked = 0, false
			Store.Values.sLaunchResult:set(if bTrapped then "TRAP!" else (if sink < 6 then "BUTTER! GREAT LANDING" else "TOUCHDOWN"))
			task.delay(1.6, function()
				local Fusion = require(ReplicatedStorage.Packages.fusion)
				local cur = Fusion.peek(Store.Values.sLaunchResult)
				if cur == "TRAP!" or cur == "TOUCHDOWN" or cur == "BUTTER! GREAT LANDING" then Store.Values.sLaunchResult:set("") end
			end)
			pcall(function() (require(script.Parent.CameraController) :: any):Kick(if bTrapped then 0.6 else 0.25 + sink / 40) end)
			Flight.Landed:Fire(where, bTrapped)
			Store.Values.bPullUp:set(false)
			setPhase("Ground")
			writeMovers(st.CFrame, flat * st.Speed)
			return
		else
			crash(hit.Instance.Name .. "/" .. hit.Material.Name)
			return
		end
	end

	-- soft ceiling and bounds: steer back rather than kill
	-- (the physics body follows the movers' velocity, so the hard stop has to be on velocity too)
	local p = st.CFrame.Position
	local vel = st.CFrame.LookVector * st.Speed
	if p.Y > FlightConfig.CeilingY then
		st.CFrame = CFrame.new(p.X, FlightConfig.CeilingY, p.Z) * st.CFrame.Rotation
		if vel.Y > 0 then
			-- keep the speed, redirected level (pointing straight up, the belly gives the heading)
			local flat = Vector3.new(st.CFrame.LookVector.X, 0, st.CFrame.LookVector.Z)
			if flat.Magnitude < 0.2 then flat = -Vector3.new(st.CFrame.UpVector.X, 0, st.CFrame.UpVector.Z) end
			flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
			vel = flat * st.Speed + Vector3.new(0, -20, 0)
		end
	end
	writeMovers(st.CFrame, vel)

	-- telemetry
	Store.Values.nSpeedKmh:set(math.floor(st.Speed * JetConfig.KmhPerStud))
	Store.Values.nAltitude:set(math.floor(math.max(0, p.Y - FlightConfig.WaterLevel)))
	Store.Values.nFuel:set(st.Fuel / stats.Fuel)
	Store.Values.nG:set(st.G)
	Store.Values.nGLoc:set(if st.GLocTimer > 0 then 1 else (st.Strain or 0))
	Store.Values.nStrain:set(st.Strain or 0)
	Store.Values.bGLoc:set(st.GLocTimer > 0)
	Store.Values.bCorner:set(math.abs(st.Speed - stats.CornerSpeed) <= stats.CornerSpeed * FlightConfig.CornerBand)
	Store.Values.bFlameout:set(st.Flameout == true)
	-- rookie assist: the gear raises itself after take-off and lowers itself on approach
	if stats.Rookie then
		local ground = math.max(IslandShape.Height(p.X, p.Z), 0)
		local agl = p.Y - ground
		if Flight.GearDown and agl > 120 and vel.Y > -2 then
			setGear(false)
			Store.Values.sLaunchResult:set("AUTO GEAR UP")
			task.delay(1.2, function() local F = require(ReplicatedStorage.Packages.fusion) if F.peek(Store.Values.sLaunchResult) == "AUTO GEAR UP" then Store.Values.sLaunchResult:set("") end end)
		elseif not Flight.GearDown and agl < 220 and vel.Y < -1 then
			local c = MapConfig.Carrier.CFrame.Position
			local a = IslandShape.Airfield
			local dC = (Vector3.new(p.X, 0, p.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude
			local dA = (Vector3.new(p.X, 0, p.Z) - Vector3.new(a.Centre.X, 0, a.Centre.Y)).Magnitude
			if math.min(dC, dA) < 1600 then
				setGear(true)
				Store.Values.sLaunchResult:set("AUTO GEAR DOWN")
				task.delay(1.2, function() local F = require(ReplicatedStorage.Packages.fusion) if F.peek(Store.Values.sLaunchResult) == "AUTO GEAR DOWN" then Store.Values.sLaunchResult:set("") end end)
			end
		end
	end
	Store.Values.bRookie:set(stats.Rookie == true)
	-- gear left down = speed capped: keep reminding (stronger right after take-off)
	local wantGearUp = Flight.GearDown and not stats.Rookie and p.Y > 110 and (os.clock() < nGearPromptUntil or st.Speed >= stats.CruiseSpeed * FlightConfig.GearSpeedMult * 0.97)
	Store.Values.sGroundHint:set(if wantGearUp then (if Input.LastDevice == "Touch" then "GEAR DOWN (SPEED LIMITED) - TAP GEAR" elseif Input.LastDevice == "Gamepad" then "GEAR DOWN (SPEED LIMITED) - D-PAD DOWN" else "GEAR DOWN (SPEED LIMITED) - PRESS [G]") else "")
	local lv = st.CFrame.LookVector
	Store.Values.nHeading:set((math.deg(math.atan2(lv.X, -lv.Z)) + 360) % 360)
	Store.Values.bShield:set(jet:GetAttribute("Shield") == true)
	Store.Values.bBoost:set(Input.State.Boost)
	Store.Values.bStall:set(st.Stalled == true)
	-- ground proximity: warn when the current flight path meets sea or terrain within ~3 s
	nPullUpTick += dt
	if nPullUpTick > 0.1 then
		nPullUpTick = 0
		local danger = false
		if vel.Y < -5 then
			local ahead = vel * FlightConfig.PullUpSeconds
			local tSea = (p.Y - FlightConfig.WaterLevel) / -vel.Y -- seconds until the sea at this sink rate
			danger = tSea < FlightConfig.PullUpSeconds
			if not danger then
				pullUpRay.FilterDescendantsInstances = { workspace.Terrain }
				danger = Workspace:Raycast(p, ahead, pullUpRay) ~= nil
			end
		end
		Store.Values.bPullUp:set(danger)
		Store.Values.nPullUpBlink:set((os.clock() * 4) % 1 < 0.6)
	end
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
	Input.Pressed:Connect(function(sName: string)
		if sName == "Eject" and (Flight.Phase == "Flying" or Flight.Phase == "Ground") then oRequest:FireServer({ a = "Eject" }) end
		if sName == "Gear" and Flight.Phase == "Flying" then setGear(not Flight.GearDown) end
	end)
	-- Studio-only QA: QA_Fuel = 0..1 sets the tank level (tanker / low-fuel tests)
	if RunService:IsStudio() then
		LocalPlayer:GetAttributeChangedSignal("QA_Fuel"):Connect(function()
			local v = LocalPlayer:GetAttribute("QA_Fuel")
			if typeof(v) == "number" and Flight.State and Flight.Stats then Flight.State.Fuel = Flight.Stats.Fuel * math.clamp(v, 0, 1) end
		end)
	end
	oEvent = Remote:GetEvent("FlightEvent")
	oEvent:OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Spawned" then
			task.spawn(onSpawned, t)
		elseif t.a == "Launched" then
			onLaunched(t)
		elseif t.a == "Reset" then
			setPhase("Dead")
		elseif t.a == "Resupplied" then
			self:Refuel()
			nStoppedT = 0
			Store.Values.sLaunchResult:set("REARMED · REFUELLED · REPAIRED")
			task.delay(2, function()
				local Fusion = require(ReplicatedStorage.Packages.fusion)
				if Fusion.peek(Store.Values.sLaunchResult) == "REARMED · REFUELLED · REPAIRED" then Store.Values.sLaunchResult:set("") end
			end)
		elseif t.a == "ResupplyFailed" then
			bResupplyAsked = false
		elseif t.a == "Recovered" then
			onRecovered(t)
		elseif t.a == "AirStart" then
			-- REVIVE HERE: the new jet starts in the air where you went down
			task.spawn(function()
				for _ = 1, 60 do
					if Flight.Phase == "Deck" and Flight.Jet and Flight.Jet.Parent and Flight.State then break end
					task.wait(0.1)
				end
				local st = Flight.State
				if not st or not Flight.Stats then return end
				st.CFrame = t.cf
				st.Speed = t.speed
				st.Fuel = Flight.Stats.Fuel
				Flight.AimDir = t.cf.LookVector
				Flight.GearDown = false
				Store.Values.bGearDown:set(false)
				bClimbOut = false
				nLaunchedAt = -math.huge
				Input:ResetThrottle(FlightConfig.DefaultThrottle)
				setPhase("Flying")
				Store.Values.sLaunchResult:set("REVIVED! BACK IN THE FIGHT")
				task.delay(1.8, function()
					local Fusion = require(ReplicatedStorage.Packages.fusion)
					if Fusion.peek(Store.Values.sLaunchResult) == "REVIVED! BACK IN THE FIGHT" then Store.Values.sLaunchResult:set("") end
				end)
			end)
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
