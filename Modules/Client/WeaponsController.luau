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
local sAnnounced = ""
local tMulti: { [Model]: number } = {} -- multi-lock progress per target
local nLastFlare = -100
local tRay = RaycastParams.new()
tRay.FilterType = Enum.RaycastFilterType.Include

-- tracer pool
local tTracers: { BasePart } = {}
local iTracer = 0
local oTracerFolder: Folder

local function tracerFrom(origin: Vector3, dir: Vector3)
	iTracer = iTracer % #tTracers + 1
	local t = tTracers[iTracer]
	local len = 18
	t.Size = Vector3.new(0.25, 0.25, len)
	t.CFrame = CFrame.lookAt(origin + dir * len * 0.5, origin + dir * len)
	t.Transparency = 0
	local born = os.clock()
	local speed = WeaponConfig.Gun.MuzzleSpeed
	task.spawn(function()
		while os.clock() - born < 0.45 and t.Transparency < 1 do
			local dt = RunService.Heartbeat:Wait()
			t.CFrame += dir * speed * dt
		end
		t.Transparency = 1
	end)
end

local function allTargets(): { Model }
	local out = {}
	local own = tostring(LocalPlayer.UserId)
	for _, m in ipairs(Workspace.Jets:GetChildren()) do
		if m.Name ~= own and m:IsA("Model") and m.PrimaryPart and not m:GetAttribute("Dead") then
			local squad = LocalPlayer:GetAttribute("SquadId")
			if not squad or m:GetAttribute("SquadId") ~= squad then
				table.insert(out, m)
			end
		end
	end
	local npc = Workspace:FindFirstChild("NPC")
	if npc then
		for _, m in ipairs(npc:GetChildren()) do
			if m:IsA("Model") and m.PrimaryPart and not m:GetAttribute("Dead") then table.insert(out, m) end
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
	local leadScreen = Vector2.new(-1000, -1000)
	local nearestGun: Model? = nil
	local nearestGunDist = WeaponConfig.Gun.Range
	for _, m in ipairs(targets) do
		local p = (m.PrimaryPart :: BasePart).Position
		local to = p - cf.Position
		local dist = to.Magnitude
		local sp, on = cam:WorldToViewportPoint(p)
		local kind = if m:GetAttribute("NpcKind") then "Mission" elseif m:GetAttribute("Bounty") then "Ace"
			elseif LocalPlayer:GetAttribute("RevengeOn") == m:GetAttribute("OwnerUserId") then "Revenge" else "Enemy"
		if on and dist < 6000 then
			table.insert(hud, { Pos = Vector2.new(sp.X, sp.Y), Name = m:GetAttribute("Pilot") or m:GetAttribute("NpcKind") or "", Kind = kind, Dist = dist, Id = m.Name })
		end
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
	Store.Values.tTargets:set(hud)

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

	-- lock state machine (stealth jets take longer to lock)
	local lockTime = stats.LockTime or 1.2
	if best and best:GetAttribute("LowObservable") then lockTime *= 1.4 end
	if best and best == oLockCandidate then
		nLockProgress = math.min(lockTime, nLockProgress + dt)
	else
		oLockCandidate = best
		nLockProgress = 0
	end
	local newState = if not best then "None" elseif nLockProgress >= lockTime then "Locked" else "Seeking"
	if newState ~= sLockState then
		sLockState = newState
		announce(newState, best)
	end
	Weapons.LockTarget = if newState == "Locked" then best else nil
	Store.Values.sLockState:set(newState)
	if RunService:IsStudio() then LocalPlayer:SetAttribute("QA_Lock", newState .. ":" .. (if best then best.Name else "")) end
	Store.Values.nLockProgress:set(if best then nLockProgress / lockTime else 0)
	if best then
		local sp, on = cam:WorldToViewportPoint((best.PrimaryPart :: BasePart).Position)
		Store.Values.tLockScreen:set(if on then Vector2.new(sp.X, sp.Y) else Vector2.new(-1000, -1000))
	else
		Store.Values.tLockScreen:set(Vector2.new(-1000, -1000))
	end

	-- lead pip for guns
	if nearestGun then
		local tp = (nearestGun.PrimaryPart :: BasePart)
		local lead = tp.Position + tp.AssemblyLinearVelocity * (nearestGunDist / WeaponConfig.Gun.MuzzleSpeed)
		local sp, on = cam:WorldToViewportPoint(lead)
		if on then leadScreen = Vector2.new(sp.X, sp.Y) end
	end
	Store.Values.tLeadScreen:set(leadScreen)

	-- guns
	local now = os.clock()
	local firing = Input.State.Guns and now >= nOverheatUntil
	if firing then
		nShotAcc += dt * WeaponConfig.Gun.FireRate
		local list = hitboxes(targets)
		tRay.FilterDescendantsInstances = list
		while nShotAcc >= 1 do
			nShotAcc -= 1
			nShotCount += 1
			nShotsPending += 1
			nHeat += WeaponConfig.Gun.HeatPerShot
			local spread = WeaponConfig.Gun.Spread
			local dir = (cf * CFrame.Angles((math.random() - 0.5) * spread, (math.random() - 0.5) * spread, 0)).LookVector
			local origin = cf.Position + cf.LookVector * 14 + cf.UpVector * -0.6
			local hit = Workspace:Raycast(origin, dir * WeaponConfig.Gun.Range, tRay)
			if hit and hit.Instance.Name == "Hitbox" and hit.Instance.Parent then
				local name = (hit.Instance.Parent :: Instance).Name
				tHitsPending[name] = (tHitsPending[name] or 0) + 1
			end
			if nShotCount % WeaponConfig.Gun.TracerEvery == 0 then tracerFrom(origin, dir) end
			Weapons.Fired:Fire("Gun")
		end
		if nHeat >= 1 then
			nHeat = 1
			nOverheatUntil = now + WeaponConfig.Gun.OverheatLock
		end
	else
		nShotAcc = 0
		nHeat = math.max(0, nHeat - WeaponConfig.Gun.CoolRate * dt)
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
		Weapons.Fired:Fire("NoLock")
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

	oTracerFolder = Instance.new("Folder")
	oTracerFolder.Name = "AS_Tracers"
	oTracerFolder.Parent = Workspace
	for i = 1, 40 do
		local t = Instance.new("Part")
		t.Anchored = true
		t.CanCollide = false
		t.CanQuery = false
		t.CanTouch = false
		t.CastShadow = false
		t.Material = Enum.Material.Neon
		t.Color = Color3.fromRGB(255, 210, 120)
		t.Transparency = 1
		t.Size = Vector3.new(0.25, 0.25, 18)
		t.Parent = oTracerFolder
		tTracers[i] = t
	end

	Input.Pressed:Connect(function(sName)
		if sName == "Missile" then fireMissile()
		elseif sName == "Flare" then fireFlare() end
	end)
	RunService.Heartbeat:Connect(step)
end

return Weapons
