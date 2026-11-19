--!strict
--[[
    WeaponsController
    -----------------
    Client half of the combat triangle. Everything here is feel and intent;
    the server decides damage.

      Guns: hold to fire at FireRate, local raycasts against Hitboxes, hit
            claims batched to the server every 0.1 s; heat bar; tracers.
      Lock: keep a target inside the lock cone for LockTime -> "Locked".
            Seeking/Locked changes are announced so the victim hears it.
      Missile: fire at the locked target (or up to N with multi-lock).
      Flare: request; server rolls decoys.
      Threat: own jet's LockedBy / Incoming attributes -> HUD + audio.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local WeaponConfig = require(ReplicatedStorage.Config.WeaponConfig)
local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)
local Lighting = game:GetService("Lighting")
local tLosRay = RaycastParams.new()
tLosRay.FilterType = Enum.RaycastFilterType.Include
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)

local LocalPlayer = Players.LocalPlayer
local Weapons = ModuleUtil.New({
	Fired = Instance.new("BindableEvent"), -- (kind: "Gun"|"Missile"|"Flare"|"NoLock")
	LockTarget = nil :: Model?,
})

local Flight, Input
local oRequest
local nHeat = 0
local nOverheatUntil = 0
local nShotAcc = 0
local nShotsPending = 0
local tHitsPending: { [string]: number } = {}
local nLastFlush = 0
local nShotCount = 0
local nLockProgress = 0
local sLockState = "None"
local oLockCandidate: Model? = nil
local nFlaredUntil = 0 -- our lock target just popped flares
local nLastDumbFire = 0
local nNoLockHintUntil = 0
local sAnnounced = ""
local tMulti: { [Model]: number } = {} -- multi-lock progress per target (one entry per target in the cone)
local nLastFlare = -100
local tRay = RaycastParams.new()
tRay.FilterType = Enum.RaycastFilterType.Include

-- tracer pool
local tTracers: { BasePart } = {}
local iTracer = 0
local oTracerFolder: Folder

local FX = require(ReplicatedStorage.Config.VfxConfig)

-- Tracers inherit the jet's velocity so they visibly stream ahead of the nose from the chase camera.
local function tracerFrom(origin: Vector3, dir: Vector3, inherit: Vector3)
	iTracer = iTracer % #tTracers + 1
	local t = tTracers[iTracer]
	local len = FX.Gun.TracerLength
	t.Size = Vector3.new(FX.Gun.TracerWidth, FX.Gun.TracerWidth, len)
	t.CFrame = CFrame.lookAt(origin + dir * len * 0.5, origin + dir * len)
	t.Transparency = 0
	local born = os.clock()
	local vel = dir * FX.Gun.TracerSpeed + inherit
	task.spawn(function()
		local life = FX.Gun.TracerLife
		while os.clock() - born < life and t.Parent do
			local dt = RunService.Heartbeat:Wait()
			t.CFrame += vel * dt
			t.Transparency = math.clamp((os.clock() - born - life * 0.7) / (life * 0.3), 0, 1) -- fade out at range
		end
		t.Transparency = 1
	end)
end

-- Muzzle rig on the local jet: flash sprite, flicker light, gun smoke
type Muzzle = { Jet: Model, Att: Attachment, Flash: { [number]: ParticleEmitter }, Light: PointLight, Smoke: ParticleEmitter }
local tMuzzle: Muzzle? = nil
local function muzzleFor(jet: Model): Muzzle?
	if tMuzzle and tMuzzle.Jet == jet and tMuzzle.Att.Parent then return tMuzzle end
	local root = jet.PrimaryPart
	if not root then return nil end
	local att = Instance.new("Attachment")
	att.Name = "AS_Muzzle"
	att.Position = Vector3.new(0, FX.Gun.PortOffset.Y, FX.Gun.PortOffset.Z)
	att.Parent = root
	local flashes = {}
	for _, side in ipairs({ -1, 1 }) do
		local port = Instance.new("Attachment")
		port.Name = "AS_GunPort"
		port.Position = Vector3.new(FX.Gun.PortOffset.X * side, FX.Gun.PortOffset.Y, FX.Gun.PortOffset.Z)
		port.Parent = root
		local flash = Instance.new("ParticleEmitter")
		flash.Texture = FX.FlareGlow
		flash.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), Color3.fromRGB(255, 160, 60))
		flash.LightEmission = 1
		flash.LightInfluence = 0
		flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 1.2) })
		flash.Lifetime = NumberRange.new(0.04, 0.07)
		flash.Speed = NumberRange.new(0)
		flash.Rotation = NumberRange.new(0, 360)
		flash.LockedToPart = true
		flash.Rate = 0
		flash.Parent = port
		flashes[side] = flash
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Range = 22
	light.Brightness = 0
	light.Parent = att
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = FX.Smoke
	smoke.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	smoke.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.5) })
	smoke.Transparency = NumberSequence.new(0.55, 1)
	smoke.Lifetime = NumberRange.new(0.5, 0.8)
	smoke.Speed = NumberRange.new(0, 3)
	smoke.Rate = 0
	smoke.Parent = att
	tMuzzle = { Jet = jet, Att = att, Flash = flashes, Light = light, Smoke = smoke }
	return tMuzzle
end

-- Hit sparks where your rounds connect (instant local feedback)
local oSparkPart: Part? = nil
local function hitSparks(pos: Vector3)
	if not oSparkPart then
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
		p.Size = Vector3.one
		p.Name = "AS_HitSparks"
		p.Parent = oTracerFolder
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = FX.FlareGlow
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 235, 170), Color3.fromRGB(255, 120, 40))
		pe.LightEmission = 1
		pe.LightInfluence = 0
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
		pe.Lifetime = NumberRange.new(0.15, 0.35)
		pe.Speed = NumberRange.new(30, 70)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Drag = 4
		pe.Rate = 0
		pe.Parent = p
		oSparkPart = p
	end
	local p = oSparkPart :: Part
	p.Position = pos
	local pe = p:FindFirstChildOfClass("ParticleEmitter")
	if pe then pe:Emit(5) end
end

-- Missile launch: ignition flash + thick launch smoke at the wing station
local nLaunchSide = 1
local function launchEffect(jet: Model)
	local root = jet.PrimaryPart
	if not root then return end
	nLaunchSide = -nLaunchSide
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(2 * nLaunchSide, -1.5, -2)
	att.Parent = root
	local flash = Instance.new("ParticleEmitter")
	flash.Texture = FX.FlareGlow
	flash.Color = ColorSequence.new(Color3.fromRGB(255, 245, 220), Color3.fromRGB(255, 150, 60))
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 9), NumberSequenceKeypoint.new(1, 3) })
	flash.Lifetime = NumberRange.new(0.12, 0.2)
	flash.Speed = NumberRange.new(0)
	flash.Rate = 0
	flash.Parent = att
	flash:Emit(3)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = FX.Smoke
	smoke.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	smoke.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	smoke.LightEmission = 0.25 -- bright, sunlit launch puff (not a dark cloud)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Lifetime = NumberRange.new(0.8, 1.2)
	smoke.Speed = NumberRange.new(2, 8)
	smoke.SpreadAngle = Vector2.new(35, 35)
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.LockedToPart = false
	smoke.VelocityInheritance = 0.85 -- rolls back past the wing slowly instead of vanishing behind the camera
	smoke.Rate = 0
	smoke.Parent = att
	smoke:Emit(6)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 90)
	light.Range = 30
	light.Brightness = 7
	light.Parent = att
	task.delay(0.15, function() light:Destroy() end)
	game:GetService("Debris"):AddItem(att, 2.5)
end

local function allTargets(): { Model }
	local out = {}
	local own = tostring(LocalPlayer.UserId)
	for _, m in ipairs(Workspace.Jets:GetChildren()) do
		-- shielded jets (spawn / tutorial) can't be hurt: don't lock them or spark hits on them
		if m.Name ~= own and m:IsA("Model") and m.PrimaryPart and not m:GetAttribute("Dead") and not m:GetAttribute("Shield") then
			local squad = LocalPlayer:GetAttribute("SquadId")
			if not squad or m:GetAttribute("SquadId") ~= squad then
				table.insert(out, m)
			end
		end
	end
	local npc = Workspace:FindFirstChild("NPC")
	if npc then
		for _, m in ipairs(npc:GetChildren()) do
			if m:IsA("Model") and m.PrimaryPart and not m:GetAttribute("Dead") and not m:GetAttribute("Friendly") then table.insert(out, m) end
		end
	end
	return out
end

local function hitboxes(targets: { Model }): { Instance }
	local t = {}
	for _, m in ipairs(targets) do
		local hb = m:FindFirstChild("Hitbox")
		if hb then table.insert(t, hb) end
	end
	table.insert(t, Workspace.Terrain)
	return t
end

local function announce(state: string, target: Model?)
	local key = state .. (if target then target.Name else "")
	if key == sAnnounced then return end
	sAnnounced = key
	oRequest:FireServer({ a = "Lock", s = state, t = if target then target.Name else "" })
end

local function flushHits()
	if nShotsPending <= 0 then return end
	local hits = {}
	for name, n in pairs(tHitsPending) do table.insert(hits, { t = name, n = n }) end
	oRequest:FireServer({ a = "Gun", shots = nShotsPending, hits = hits })
	table.clear(tHitsPending)
	nShotsPending = 0
end

-- what the HUD marks this frame; projected to the screen AFTER the camera moves (see project)
local tShown: { Model } = {}
local oBoxTarget: Model? = nil
local oPipTarget: Model? = nil

local function step(dt: number)
	local jet = Flight.Jet
	local phase = Flight.Phase
	local cam = Workspace.CurrentCamera
	if phase ~= "Flying" or not jet or not jet.PrimaryPart then
		if sLockState ~= "None" then announce("None", nil) end
		sLockState = "None"
		nLockProgress = 0
		Store.Values.sLockState:set("None")
		Store.Values.tTargets:set({})
		tShown, oBoxTarget, oPipTarget = {}, nil, nil
		Weapons.FocusTarget = nil
		Store.Values.sThreat:set("None")
		return
	end
	local root = jet.PrimaryPart
	local cf = root.CFrame
	local stats = Flight.Stats :: { [string]: any }
	local targets = allTargets()

	-- HUD target list + lock candidate (closest to nose within cone & range)
	local hud = {}
	local best: Model? = nil
	local bestAngle = WeaponConfig.Missile.LockCone
	local nearestGun: Model? = nil
	local nearestGunDist = WeaponConfig.Gun.Range
	for _, m in ipairs(targets) do
		local p = (m.PrimaryPart :: BasePart).Position
		local to = p - cf.Position
		local dist = to.Magnitude
		if dist < 6000 then table.insert(hud, m) end
		local angle = math.acos(math.clamp(cf.LookVector:Dot(to.Unit), -1, 1))
		if dist < WeaponConfig.Missile.LockRange and angle < bestAngle then
			best = m
			bestAngle = angle
		end
		if dist < nearestGunDist and angle < math.rad(25) then
			nearestGun = m
			nearestGunDist = dist
		end
	end
	tShown = hud

	-- secondary locks for multi-lock jets/pass: every target in the cone builds its own progress
	local maxLocks = stats.MultiLock or 1
	if maxLocks > 1 then
		local seen = {}
		for _, m in ipairs(targets) do
			local p = (m.PrimaryPart :: BasePart).Position
			local to = p - cf.Position
			if to.Magnitude < WeaponConfig.Missile.LockRange and math.acos(math.clamp(cf.LookVector:Dot(to.Unit), -1, 1)) < WeaponConfig.Missile.LockCone * 1.6 then
				seen[m] = true
				tMulti[m] = (tMulti[m] or 0) + dt
			end
		end
		for m in pairs(tMulti) do if not seen[m] then tMulti[m] = nil end end
	else
		table.clear(tMulti)
	end

	-- heat-seeker lock: progress builds faster on a target's hot tail, close in, centred,
	-- and while you're not pulling hard; tougher/stealthy targets and jinking ones are slower
	local lockTime = stats.LockTime or 1.2
	local LK = WeaponConfig.Lock
	local hint = ""
	if best and best == oLockCandidate then
		local bp = (best.PrimaryPart :: BasePart)
		local tlook = bp.CFrame.LookVector
		local toMe = (cf.Position - bp.Position).Unit
		local behind = (1 - tlook:Dot(toMe)) / 2 -- 1 = right on their six, 0 = head-on
		local aspect = LK.HeadOn + (LK.TailAspect - LK.HeadOn) * behind
		if best:GetAttribute("NpcKind") and NpcConfig.Kinds[best:GetAttribute("NpcKind")] and NpcConfig.Kinds[best:GetAttribute("NpcKind")].Static then
			aspect = 1 -- ground sites have no "tail"
		end
		local dist = (bp.Position - cf.Position).Magnitude
		local range = LK.RangeNear + (LK.RangeFar - LK.RangeNear) * math.clamp(dist / WeaponConfig.Missile.LockRange, 0, 1)
		local bore = 1 - (1 - LK.BoresightEdge) * math.clamp(bestAngle / WeaponConfig.Missile.LockCone, 0, 1)
		local g = (Flight.State and Flight.State.G) or 1
		local gf = math.clamp(1 - math.max(0, g - LK.GStart) * LK.GPenalty, LK.GMin, 1)
		local kindMult = 1
		local kind = best:GetAttribute("NpcKind")
		if kind and NpcConfig.Kinds[kind] then kindMult = NpcConfig.Kinds[kind].LockTimeMult or 1 end
		if best:GetAttribute("LowObservable") then kindMult *= 1.4 end
		local evade = if best:GetAttribute("Evading") then LK.Evading else 1
		-- environment: terrain between you blocks the seeker; low targets hide in ground
		-- clutter when you look down on them; a target in front of the sun blinds it
		local env, envHint = 1, nil
		tLosRay.FilterDescendantsInstances = { Workspace.Terrain }
		local toT = bp.Position - cf.Position
		if Workspace:Raycast(cf.Position, toT * 0.97, tLosRay) then
			env, envHint = 0, "TERRAIN MASKING"
		else
			local agl = bp.Position.Y - math.max(IslandShape.Height(bp.Position.X, bp.Position.Z), 0)
			local lookDown = -toT.Unit.Y -- >0 when the target is below you
			if agl < LK.ClutterAGL and lookDown > math.sin(math.rad(8)) then
				env, envHint = LK.Clutter, "GROUND CLUTTER - GET LOW"
			end
			if toT.Unit:Dot(Lighting:GetSunDirection()) > math.cos(math.rad(LK.SunCone)) then
				env, envHint = LK.Sun, "LOST IN THE SUN"
			end
		end
		local rate = math.max(aspect * range * bore * gf * evade / kindMult, LK.MinRate) * env
		if env <= 0 then
			nLockProgress = math.max(0, nLockProgress - dt * LK.Decay * lockTime) -- masked: lock bleeds away
		else
			nLockProgress = math.min(lockTime, nLockProgress + dt * rate)
		end
		if nLockProgress < lockTime then
			if envHint then hint = envHint
			elseif aspect < LK.PoorAspectHint then hint = "GET ON THEIR SIX"
			elseif gf < 0.8 then hint = "EASE OFF THE G"
			elseif best:GetAttribute("Evading") then hint = "THEY'RE EVADING - HOLD IT" end
		end
	elseif best then
		oLockCandidate = best
		nLockProgress = 0
	else
		-- target slipped out of the cone: the lock bleeds away rather than snapping off
		nLockProgress = math.max(0, nLockProgress - dt * LK.Decay * lockTime)
		if nLockProgress <= 0 then oLockCandidate = nil end
	end
	if os.clock() < nFlaredUntil then hint = "FLARES! RE-ACQUIRE" end
	if os.clock() < nNoLockHintUntil then hint = "NO LOCK - UNGUIDED" end
	Store.Values.sLockHint:set(hint)
	local newState = if not best then "None" elseif nLockProgress >= lockTime then "Locked" else "Seeking"
	if newState ~= sLockState then
		sLockState = newState
		announce(newState, best)
	end
	Weapons.LockTarget = if newState == "Locked" then best else nil
	Weapons.FocusTarget = best or nearestGun -- what you are shooting at / locking (DamageController health bar)
	Store.Values.sLockState:set(newState)
	if RunService:IsStudio() then LocalPlayer:SetAttribute("QA_Lock", newState .. ":" .. (if best then best.Name else "")) end
	Store.Values.nLockProgress:set(if best then nLockProgress / lockTime else 0)
	oBoxTarget = best
	-- gun pip: guns are hitscan (instant), so the place to shoot IS the target's hitbox, not a lead point
	oPipTarget = nearestGun

	-- guns
	local now = os.clock()
	local firing = Input.State.Guns and now >= nOverheatUntil
	if firing then
		nShotAcc += dt * WeaponConfig.Gun.FireRate
		local list = hitboxes(targets)
		tRay.FilterDescendantsInstances = list
		local mz = muzzleFor(jet)
		local inherit = if jet.PrimaryPart then jet.PrimaryPart.AssemblyLinearVelocity else Vector3.zero
		if mz then
			mz.Light.Brightness = 3 + math.random() * 4 -- flicker
			mz.Smoke.Rate = 18
		end
		while nShotAcc >= 1 do
			nShotAcc -= 1
			nShotCount += 1
			nShotsPending += 1
			nHeat += WeaponConfig.Gun.HeatPerShot
			local spread = WeaponConfig.Gun.Spread
			-- aim assist: rounds bend onto a target that is almost on the nose (more on touch / gamepad)
			local aimCf = cf
			if nearestGun then
				local hb = nearestGun:FindFirstChild("Hitbox") :: BasePart? or nearestGun.PrimaryPart
				if hb then
					local toT = (hb.Position - cf.Position).Unit
					local cone = if Input.LastDevice == "KeyboardMouse" then WeaponConfig.Gun.AssistMouse else WeaponConfig.Gun.AssistTouch
					if math.acos(math.clamp(cf.LookVector:Dot(toT), -1, 1)) < cone then
						aimCf = CFrame.lookAt(cf.Position, cf.Position + toT, cf.UpVector)
					end
				end
			end
			local dir = (aimCf * CFrame.Angles((math.random() - 0.5) * spread, (math.random() - 0.5) * spread, 0)).LookVector
			local origin = cf.Position + cf.LookVector * 14 + cf.UpVector * -0.6
			local hit = Workspace:Raycast(origin, dir * WeaponConfig.Gun.Range, tRay)
			if hit and hit.Instance.Name == "Hitbox" and hit.Instance.Parent then
				local name = (hit.Instance.Parent :: Instance).Name
				tHitsPending[name] = (tHitsPending[name] or 0) + 1
				if nShotCount % 2 == 0 then hitSparks(hit.Position) end
			end
			if nShotCount % FX.Gun.TracerEvery == 0 then
				-- alternate twin ports; each stream converges on the aim point so it's visible from the chase camera
				local side = if (nShotCount // FX.Gun.TracerEvery) % 2 == 0 then 1 else -1
				local po = FX.Gun.PortOffset
				local port = cf:PointToWorldSpace(Vector3.new(po.X * side, po.Y, po.Z))
				local aimAt = origin + dir * FX.Gun.Converge
				tracerFrom(port, (aimAt - port).Unit, inherit)
			end
			if mz then mz.Flash[if nShotCount % 2 == 0 then 1 else -1]:Emit(1) end
			Weapons.Fired:Fire("Gun")
		end
		if nHeat >= 1 then
			nHeat = 1
			nOverheatUntil = now + WeaponConfig.Gun.OverheatLock
		end
	else
		nShotAcc = 0
		nHeat = math.max(0, nHeat - WeaponConfig.Gun.CoolRate * dt)
		if tMuzzle and tMuzzle.Att.Parent then
			tMuzzle.Light.Brightness = 0
			tMuzzle.Smoke.Rate = 0
		end
	end
	Store.Values.nGunHeat:set(nHeat)
	if now - nLastFlush > 0.1 then
		nLastFlush = now
		flushHits()
	end

	-- ammo + threat from replicated attributes
	Store.Values.nMissiles:set(jet:GetAttribute("Missiles") or 0)
	Store.Values.nMissilesMax:set(stats.Missiles or 0)
	Store.Values.nFlares:set(jet:GetAttribute("Flares") or 0)
	Store.Values.nFlaresMax:set(stats.Flares or 0)
	Store.Values.nFlareCooldown:set(math.clamp(1 - (now - nLastFlare) / WeaponConfig.Flare.Cooldown, 0, 1))
	local threat = if (jet:GetAttribute("Incoming") or 0) > 0 then "Inbound"
		elseif (jet:GetAttribute("LockedBy") or 0) > 0 then "Locked" else "None"
	Store.Values.sThreat:set(threat)
end

local function fireMissile()
	if Flight.Phase ~= "Flying" then return end
	local jet = Flight.Jet
	if not jet or (jet:GetAttribute("Missiles") or 0) <= 0 then
		Weapons.Fired:Fire("NoLock")
		return
	end
	local t = Weapons.LockTarget
	if not t then
		-- no lock: the missile still fires, unguided (server flies it straight with a proximity fuse)
		if os.clock() - nLastDumbFire < WeaponConfig.Missile.ReloadInterval then return end
		nLastDumbFire = os.clock()
		oRequest:FireServer({ a = "Missile", t = {} })
		launchEffect(jet)
		Weapons.Fired:Fire("Missile")
		nNoLockHintUntil = os.clock() + 1.2
		return
	end
	local names = { t.Name }
	local stats = Flight.Stats or {}
	local maxLocks = stats.MultiLock or 1
	if maxLocks > 1 then
		-- extra targets that have held in the cone long enough
		local extra = {}
		for m, prog in pairs(tMulti) do
			local need = WeaponConfig.MultiLock.LockTime * (if m:GetAttribute("LowObservable") then 1.4 else 1)
			if m ~= t and m.Parent and prog >= need then table.insert(extra, { m = m, p = prog }) end
		end
		table.sort(extra, function(a, b) return a.p > b.p end)
		for i = 1, math.min(#extra, maxLocks - 1) do table.insert(names, extra[i].m.Name) end
	end
	oRequest:FireServer({ a = "Missile", t = names })
	for _ = 1, #names do launchEffect(jet) end
	Weapons.Fired:Fire("Missile")
end

local function fireFlare()
	if Flight.Phase ~= "Flying" then return end
	if os.clock() - nLastFlare < WeaponConfig.Flare.Cooldown then return end
	local jet = Flight.Jet
	if not jet or (jet:GetAttribute("Flares") or 0) <= 0 then return end
	nLastFlare = os.clock()
	oRequest:FireServer({ a = "Flare" })
	Weapons.Fired:Fire("Flare")
end

function Weapons.StartAsync(self)
	Flight = require(script.Parent.FlightController)
	Input = require(script.Parent.InputController)
	oRequest = Remote:GetEvent("CombatRequest")
	-- the target we are locking pops flares: the seeker is dazzled and loses a chunk of the lock
	Remote:GetEvent("CombatEvent"):OnClientEvent(function(t: any)
		if typeof(t) == "table" and t.a == "Flares" and oLockCandidate and tostring(t.owner) == oLockCandidate.Name then
			nLockProgress *= (1 - WeaponConfig.Lock.FlareKnock)
			nFlaredUntil = os.clock() + 1.2
		end
	end)

	oTracerFolder = Instance.new("Folder")
	oTracerFolder.Name = "AS_Tracers"
	oTracerFolder.Parent = Workspace
	for i = 1, 90 do -- ~9 tracers/s x 1.1 s life, with headroom
		local t = Instance.new("Part")
		t.Anchored = true
		t.CanCollide = false
		t.CanQuery = false
		t.CanTouch = false
		t.CastShadow = false
		t.Material = Enum.Material.Neon
		t.Color = FX.Gun.TracerColor
		t.Transparency = 1
		t.Size = Vector3.new(FX.Gun.TracerWidth, FX.Gun.TracerWidth, FX.Gun.TracerLength)
		t.Parent = oTracerFolder
		tTracers[i] = t
	end

	Input.Pressed:Connect(function(sName)
		if sName == "Missile" then fireMissile()
		elseif sName == "Flare" then fireFlare() end
	end)
	RunService.Heartbeat:Connect(step)
	-- project HUD markers after the camera has moved this frame (on Heartbeat they trailed a frame behind,
	-- so in a turn the lock box / pip sat beside the plane, worse at low frame rates)
	RunService:BindToRenderStep("AS_WeaponsHud", Enum.RenderPriority.Camera.Value + 2, function()
		if Flight.Phase ~= "Flying" then return end
		local cam = Workspace.CurrentCamera
		local jet = Flight.Jet
		local myPos = if jet and jet.PrimaryPart then jet.PrimaryPart.Position else cam.CFrame.Position
		local hud = {}
		for _, m in ipairs(tShown) do
			local pp = m.PrimaryPart
			if pp and m.Parent and not m:GetAttribute("Dead") then
				local sp, on = cam:WorldToViewportPoint(pp.Position)
				if on then
					local kind = if m:GetAttribute("NpcKind") and not m:GetAttribute("Bot") then "Mission" elseif m:GetAttribute("Bounty") then "Ace"
						elseif LocalPlayer:GetAttribute("RevengeOn") == m:GetAttribute("OwnerUserId") then "Revenge" else "Enemy"
					table.insert(hud, { Pos = Vector2.new(sp.X, sp.Y), Name = m:GetAttribute("Pilot") or m:GetAttribute("NpcKind") or "", Kind = kind,
						Dist = (pp.Position - myPos).Magnitude, Id = m.Name })
				end
			end
		end
		Store.Values.tTargets:set(hud)
		local function screenOf(m: Model?): Vector2
			local pp = m and (m:FindFirstChild("Hitbox") :: BasePart? or m.PrimaryPart)
			if not pp then return Vector2.new(-1000, -1000) end
			local sp, on = cam:WorldToViewportPoint(pp.Position)
			return if on then Vector2.new(sp.X, sp.Y) else Vector2.new(-1000, -1000)
		end
		Store.Values.tLockScreen:set(screenOf(oBoxTarget))
		Store.Values.tLeadScreen:set(screenOf(oPipTarget))
	end)
end

return Weapons
