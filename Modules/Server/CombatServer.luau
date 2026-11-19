--!strict
--[[
    CombatServer
    ------------
    Authoritative combat for every "targetable" (player jets in workspace.Jets
    and AI units in workspace.NPC). A targetable is a Model with a PrimaryPart,
    a "Hitbox" part and attributes Health / MaxHealth (+ OwnerUserId for
    players, NpcKind for AI).

    Remotes
      C->S CombatRequest  { a="Gun", hits={ {t=targetName, n=count} }, shots=n }
                          { a="Missile", t=targetName } | { a="Flare" }
                          { a="Lock", t=targetName|"" }   (announces seeking/lock for victim warnings)
      S->C CombatEvent    { a="Hit", t=..., dmg } | { a="Kill", killer, victim, weapon }
                          { a="Flares", owner=userId, pos=Vector3 } | { a="Evade", ace=bool }
                          { a="MissileFired", owner, target }

    Events for other modules: Combat.OnKill(killerPlayer?, victimModel, weapon, info)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local WeaponConfig = require(ReplicatedStorage.Config.WeaponConfig)

local Combat = ModuleUtil.New({
	OnKill = Instance.new("BindableEvent"), -- (killer: Player?, victim: Model, weapon: string, info: {})
	OnDamage = Instance.new("BindableEvent"), -- (attacker: Player?, victim: Model, dmg: number)
	OnEvade = Instance.new("BindableEvent"), -- (player, ace: boolean)
})

type Missile = {
	Part: BasePart,
	Owner: Player?,
	OwnerModel: Model?,
	Target: Model?,
	Unguided: boolean?,
	DecoyPos: Vector3?,
	Born: number,
	Damage: number,
	Turn: number,
	Vel: Vector3,
}

local oEvent = Remote:GetEvent("CombatEvent")
local oRequest = Remote:GetEvent("CombatRequest")
local tMissiles: { Missile } = {}
local tGunState: { [Player]: { Heat: number, Last: number, Locked: number } } = {}
local tLastMissile: { [Player]: number } = {}
local tLastFlare: { [Player]: number } = {}
local tAmmo: { [Model]: { Missiles: number, Flares: number } } = {}
local tLockedBy: { [Player]: Model? } = {}
local tLockState: { [Player]: number } = {} -- 0 none, 1 seeking, 2 locked (from the player's seeker)
-- damage ledger for assists: [victim] = { [attacker] = {dmg, t} }
local tLedger: { [Model]: { [Player]: { Dmg: number, T: number } } } = {}
local oLockLimiter = ModuleUtil.RateLimiter(WeaponConfig.LockAnnounceRate.Count, WeaponConfig.LockAnnounceRate.Window)
local oReqLimiter = ModuleUtil.RateLimiter(40, 1)

local oMissileFolder: Folder
local tRay = RaycastParams.new()
tRay.FilterType = Enum.RaycastFilterType.Include

local Flight: any
local function flight()
	Flight = Flight or require(ServerStorage.ServerModules.FlightServer)
	return Flight
end

local function squadmates(a: Player, b: Player): boolean
	local ok, Squad = pcall(require, ServerStorage.ServerModules:FindFirstChild("SocialServer") :: any)
	if ok and Squad and Squad.AreSquadmates then return Squad:AreSquadmates(a, b) end
	return false
end

-- Resolve a target by its model name ("<userId>" in Jets, "<id>" in NPC).
local function findTarget(sName: any): Model?
	if typeof(sName) ~= "string" or #sName > 32 then return nil end
	local m = workspace.Jets:FindFirstChild(sName) or (workspace:FindFirstChild("NPC") and workspace.NPC:FindFirstChild(sName))
	if m and m:IsA("Model") and m.PrimaryPart and not m:GetAttribute("Dead") then return m end
	return nil
end

local function ownerOf(m: Model): Player?
	local uid = m:GetAttribute("OwnerUserId")
	return if uid then Players:GetPlayerByUserId(uid) else nil
end

local function canHarm(attacker: Player, victim: Model): boolean
	if victim:GetAttribute("Shield") or victim:GetAttribute("Friendly") then return false end
	local vp = ownerOf(victim)
	if vp == attacker then return false end
	if vp and squadmates(attacker, vp) then return false end
	-- shielded pilots (spawn / training) can't hurt other players: no invulnerable attackers
	if vp then
		local aj = workspace.Jets:FindFirstChild(tostring(attacker.UserId))
		if aj and aj:GetAttribute("Shield") then
			-- a tutorial pilot who opens fire on a player chooses to go live (otherwise their
			-- shots silently do nothing for up to TrainingShieldMax seconds)
			if not aj:GetAttribute("Training") then return false end
			aj:SetAttribute("Training", nil)
			aj:SetAttribute("Shield", false)
		end
	end
	return true
end

function Combat.SetAmmo(self, jet: Model, nMissiles: number, nFlares: number)
	tAmmo[jet] = { Missiles = nMissiles, Flares = nFlares }
	jet:SetAttribute("Missiles", nMissiles)
	jet:SetAttribute("Flares", nFlares)
end

function Combat.Rearm(self, oPlayer: Player)
	local s = flight():GetSortie(oPlayer)
	if s and s.Jet.Parent then
		self:SetAmmo(s.Jet, s.Stats.Missiles, s.Stats.Flares)
	end
end

function Combat.Damage(self, victim: Model, nDmg: number, attacker: Player?, sWeapon: string)
	if victim:GetAttribute("Dead") or victim:GetAttribute("Friendly") then return end
	local hp = (victim:GetAttribute("Health") :: number? or 0) - nDmg
	victim:SetAttribute("Health", math.max(0, hp))
	if attacker then
		tLedger[victim] = tLedger[victim] or {}
		local e = tLedger[victim][attacker] or { Dmg = 0, T = 0 }
		e.Dmg += nDmg
		e.T = os.clock()
		tLedger[victim][attacker] = e
		victim:SetAttribute("LastAttacker", attacker.UserId)
		victim:SetAttribute("LastAttackedAt", workspace:GetServerTimeNow())
	end
	self.OnDamage:Fire(attacker, victim, nDmg)
	if hp <= 0 then
		local info = { Assists = {} :: { Player } }
		local maxHp = victim:GetAttribute("MaxHealth") :: number? or 100
		for p, e in pairs(tLedger[victim] or {}) do
			if p ~= attacker and os.clock() - e.T < WeaponConfig.AssistWindow and e.Dmg >= maxHp * 0.25 then
				table.insert(info.Assists, p)
			end
		end
		tLedger[victim] = nil
		victim:SetAttribute("Dead", true)
		local victimPlayer = ownerOf(victim)
		self.OnKill:Fire(attacker, victim, sWeapon, info)
		oEvent:FireAllClients({
			a = "Kill",
			killer = if attacker then attacker.DisplayName else "",
			killerId = if attacker then attacker.UserId else 0,
			victim = victim:GetAttribute("Pilot") or victim.Name,
			victimId = if victimPlayer then victimPlayer.UserId else 0,
			weapon = sWeapon,
			pos = victim:GetPivot().Position,
			model = victim.Name, -- clients spawn a falling, burning wreck from this model
			vel = if victim.PrimaryPart then victim.PrimaryPart.AssemblyLinearVelocity else Vector3.zero,
		})
		if victimPlayer then
			flight():DestroyJet(victimPlayer, "shot")
		end
	end
end

-- ===================== GUNS =====================
-- MetricsServer mechanics counters (never let metrics break combat)
local function mech(p: Player?, key: string, n: number?)
	local ok, M = pcall(require, ServerStorage.ServerModules.MetricsServer)
	if ok and M and M.Mech then pcall(M.Mech, M, p, key, n) end
end

local function onGun(oPlayer: Player, t: any)
	local s = flight():GetSortie(oPlayer)
	if not s or s.Phase ~= "Flying" or not s.Jet.PrimaryPart then return end
	local g = tGunState[oPlayer] or { Heat = 0, Last = os.clock(), Locked = 0 }
	tGunState[oPlayer] = g
	local now = os.clock()
	local dt = now - g.Last
	g.Last = now
	g.Heat = math.max(0, g.Heat - WeaponConfig.Gun.CoolRate * math.max(0, dt - 0.15))
	if now < g.Locked then return end
	local shots = math.clamp(tonumber(t.shots) or 0, 0, math.ceil(WeaponConfig.Gun.FireRate * math.min(dt, 0.5) * 1.3) + 1)
	g.Heat += shots * WeaponConfig.Gun.HeatPerShot
	if shots > 0 then mech(oPlayer, "gun_shots", shots) end
	if g.Heat >= 1 then
		g.Heat = 1
		g.Locked = now + WeaponConfig.Gun.OverheatLock
	end
	if typeof(t.hits) ~= "table" then return end
	local root = s.Jet.PrimaryPart
	local origin = root.Position
	local fwd = root.CFrame.LookVector
	local budget = shots
	for i, h in ipairs(t.hits) do
		if i > 4 or budget <= 0 then break end
		if typeof(h) ~= "table" then continue end
		local target = findTarget(h.t)
		if not target or target == s.Jet or not canHarm(oPlayer, target) then continue end
		local tp = (target:FindFirstChild("Hitbox") :: BasePart? or target.PrimaryPart :: BasePart).Position
		local to = tp - origin
		local dist = to.Magnitude
		if dist > WeaponConfig.Gun.Range * 1.15 then continue end
		local angle = math.acos(math.clamp(fwd:Dot(to.Unit), -1, 1))
		if angle > WeaponConfig.Gun.ConeTolerance then continue end
		tRay.FilterDescendantsInstances = { workspace.Terrain }
		if workspace:Raycast(origin, to, tRay) then continue end -- terrain in the way
		local n = math.clamp(math.floor(tonumber(h.n) or 0), 0, budget)
		budget -= n
		if n > 0 then
			Combat:Damage(target, n * WeaponConfig.Gun.Damage, oPlayer, "Cannon")
			mech(oPlayer, "gun_hits", n)
			oEvent:FireClient(oPlayer, { a = "Hit", t = target.Name, dmg = n * WeaponConfig.Gun.Damage })
		end
	end
end

-- ===================== MISSILES =====================
local function spawnMissile(oPlayer: Player?, from: CFrame, target: Model?, nDamage: number, nTurnMult: number, ownerModel: Model?)
	local p = Instance.new("Part")
	p.Name = "Missile"
	p.Size = Vector3.new(0.6, 0.6, 4)
	p.Color = Color3.fromRGB(220, 224, 230)
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Anchored = true
	p.CFrame = from
	p:SetAttribute("Owner", if oPlayer then oPlayer.UserId else 0)
	p:SetAttribute("Target", if target then target.Name else "")
	p.Parent = oMissileFolder
	table.insert(tMissiles, {
		Part = p, Owner = oPlayer, OwnerModel = ownerModel, Target = target, Born = os.clock(),
		Damage = nDamage, Turn = WeaponConfig.Missile.TurnRate * nTurnMult,
		Vel = from.LookVector * WeaponConfig.Missile.Speed * 0.75,
	})
	if target then
		target:SetAttribute("Incoming", (target:GetAttribute("Incoming") :: number? or 0) + 1)
		local vp = ownerOf(target)
		if vp then mech(vp, if oPlayer then "msl_incoming_pvp" else "msl_incoming_ai") end
	end
	oEvent:FireAllClients({ a = "MissileFired", owner = if oPlayer then oPlayer.UserId else 0, target = if target then target.Name else "" })
end

function Combat.FireMissileAt(self, oPlayer: Player?, from: CFrame, target: Model, nDamage: number?, ownerModel: Model?)
	spawnMissile(oPlayer, from, target, nDamage or WeaponConfig.Missile.Damage, 1, ownerModel)
end

local function onMissile(oPlayer: Player, t: any)
	local s = flight():GetSortie(oPlayer)
	if not s or s.Phase ~= "Flying" or not s.Jet.PrimaryPart then return end
	local now = os.clock()
	if now - (tLastMissile[oPlayer] or 0) < WeaponConfig.Missile.ReloadInterval then return end
	local ammo = tAmmo[s.Jet]
	if not ammo or ammo.Missiles <= 0 then return end
	local root = s.Jet.PrimaryPart
	local targets = if typeof(t.t) == "table" then t.t else { t.t }
	local maxTargets = if s.Stats.MultiLock then s.Stats.MultiLock else 1
	-- the primary target must be the one this player's seeker announced as fully Locked
	-- (the heat-seeker difficulty can't be skipped by a modified client)
	local primary = findTarget(targets[1])
	if not primary or tLockedBy[oPlayer] ~= primary or tLockState[oPlayer] ~= 2 then
		-- no confirmed lock: the missile still leaves the rail, unguided, with a proximity fuse
		spawnMissile(oPlayer, root.CFrame * CFrame.new(2, -1.5, -4), nil, WeaponConfig.Missile.Damage, 1, s.Jet)
		tMissiles[#tMissiles].Unguided = true
		mech(oPlayer, "msl_unguided")
		-- tutorial: missiles don't run out (a rookie who misses twice would be stuck on the lock step)
		if not s.Jet:GetAttribute("Training") then ammo.Missiles -= 1 end
		tLastMissile[oPlayer] = now
		s.Jet:SetAttribute("Missiles", ammo.Missiles)
		return
	end
	local fired = 0
	for i, name in ipairs(targets) do
		if i > maxTargets or ammo.Missiles <= 0 then break end
		local target = findTarget(name)
		if not target or target == s.Jet or not canHarm(oPlayer, target) then continue end
		local to = target:GetPivot().Position - root.Position
		local cone = WeaponConfig.Missile.LockCone * 1.5 -- tolerance for latency
		if to.Magnitude > WeaponConfig.Missile.LockRange * 1.1 then continue end
		if math.acos(math.clamp(root.CFrame.LookVector:Dot(to.Unit), -1, 1)) > cone then continue end
		-- a salvo at several targets uses the lighter multi-lock warhead; a single shot is full damage
		local dmg = if #targets > 1 then WeaponConfig.MultiLock.Damage else WeaponConfig.Missile.Damage
		local side = if fired % 2 == 0 then 2 else -2
		spawnMissile(oPlayer, root.CFrame * CFrame.new(side, -1.5, -4), target, dmg, s.Stats.MissileTurnMult or 1, s.Jet)
		if not s.Jet:GetAttribute("Training") then ammo.Missiles -= 1 end
		fired += 1
	end
	if fired > 0 then
		mech(oPlayer, "msl_fired", fired)
		tLastMissile[oPlayer] = now
		s.Jet:SetAttribute("Missiles", ammo.Missiles)
	end
end

local function onFlare(oPlayer: Player)
	local s = flight():GetSortie(oPlayer)
	if not s or s.Phase ~= "Flying" then return end
	local now = os.clock()
	if now - (tLastFlare[oPlayer] or 0) < WeaponConfig.Flare.Cooldown then return end
	local ammo = tAmmo[s.Jet]
	if not ammo or ammo.Flares <= 0 then return end
	ammo.Flares -= 1
	s.Jet:SetAttribute("Flares", ammo.Flares)
	mech(oPlayer, "flare_used")
	tLastFlare[oPlayer] = now
	local pos = s.Jet:GetPivot().Position
	oEvent:FireAllClients({ a = "Flares", owner = oPlayer.UserId, pos = pos })
	-- decoy every missile currently chasing this jet
	local bestAce = false
	local evaded = 0
	for _, m in ipairs(tMissiles) do
		if m.Target == s.Jet and not m.DecoyPos then
			local dist = (m.Part.Position - pos).Magnitude
			local tti = dist / math.max(m.Vel.Magnitude, 1)
			local ace = tti <= WeaponConfig.Flare.AceWindow
			local chance = if ace then WeaponConfig.Flare.AceChance else WeaponConfig.Flare.DecoyChance
			if math.random() < chance then
				m.DecoyPos = pos - s.Jet:GetPivot().LookVector * 40 + Vector3.new(0, -25, 0)
				evaded += 1
				bestAce = bestAce or ace
			end
		end
	end
	if evaded > 0 then
		mech(oPlayer, "flare_saved", evaded)
		oEvent:FireClient(oPlayer, { a = "Evade", ace = bestAce })
		Combat.OnEvade:Fire(oPlayer, bestAce)
	end
end

-- AI flares: decoy missiles chasing an NPC (same odds as players, no Ace window)
function Combat.DecoyMissilesAt(self, victim: Model)
	local pos = victim:GetPivot().Position
	for _, m in ipairs(tMissiles) do
		if m.Target == victim and not m.DecoyPos and math.random() < WeaponConfig.Flare.DecoyChance then
			m.DecoyPos = pos - victim:GetPivot().LookVector * 50 + Vector3.new(0, -30, 0)
		end
	end
end

local function onLock(oPlayer: Player, t: any)
	if not oLockLimiter:Check(oPlayer) then return end
	local prev = tLockedBy[oPlayer]
	local target = findTarget(t.t)
	local state = if t.s == "Locked" then 2 elseif t.s == "Seeking" then 1 else 0
	if prev and prev ~= target then
		prev:SetAttribute("LockedBy", math.max(0, (prev:GetAttribute("LockedBy") :: number? or 0) - 1))
	end
	if target and state > 0 and target ~= prev then
		target:SetAttribute("LockedBy", (target:GetAttribute("LockedBy") :: number? or 0) + 1)
	end
	tLockedBy[oPlayer] = if state > 0 then target else nil
	tLockState[oPlayer] = state
end

-- ===================== MISSILE SIM =====================
local function detonate(m: Missile, hitTarget: Model?)
	if m.Target and m.Target.Parent then
		m.Target:SetAttribute("Incoming", math.max(0, (m.Target:GetAttribute("Incoming") :: number? or 1) - 1))
	end
	oEvent:FireAllClients({ a = "Boom", pos = m.Part.Position, hit = hitTarget ~= nil })
	if hitTarget and not hitTarget:GetAttribute("Dead") then
		local owner = m.Owner
		if owner then
			if canHarm(owner, hitTarget) then
				Combat:Damage(hitTarget, m.Damage, owner, "IR Missile")
				mech(owner, "msl_hit")
			end
		else
			if not hitTarget:GetAttribute("Shield") then Combat:Damage(hitTarget, m.Damage, nil, "SAM") end
		end
	elseif m.DecoyPos and m.Owner == nil and m.Target then
		-- (AI missile evaded: nothing)
	end
	m.Part:Destroy()
end

local function stepMissiles(dt: number)
	local now = os.clock()
	for i = #tMissiles, 1, -1 do
		local m = tMissiles[i]
		local age = now - m.Born
		local alive = m.Part.Parent ~= nil
		local targetPos: Vector3? = nil
		if m.DecoyPos then
			targetPos = m.DecoyPos
		elseif m.Target and m.Target.Parent and not m.Target:GetAttribute("Dead") and m.Target.PrimaryPart then
			targetPos = m.Target.PrimaryPart.Position
		end
		if m.Unguided and alive and age <= WeaponConfig.Missile.UnguidedLifetime then
			local pos = m.Part.Position
			local speed = WeaponConfig.Missile.Speed * (if age < WeaponConfig.Missile.Boost then 0.75 + 0.25 * age / WeaponConfig.Missile.Boost else 1)
			m.Vel = m.Vel.Unit * speed
			local newPos = pos + m.Vel * dt
			local victim: Model? = nil
			local fuse = WeaponConfig.Missile.Fuse * WeaponConfig.Missile.UnguidedFuseMult
			for _, folder in ipairs({ workspace.Jets, workspace:FindFirstChild("NPC") }) do
				if folder then
					for _, mdl in ipairs(folder:GetChildren()) do
						if mdl:IsA("Model") and mdl ~= m.OwnerModel and mdl.PrimaryPart and not mdl:GetAttribute("Dead")
							and (mdl.PrimaryPart.Position - newPos).Magnitude < fuse
							and (not m.Owner or canHarm(m.Owner, mdl)) then
							victim = mdl
							break
						end
					end
				end
				if victim then break end
			end
			tRay.FilterDescendantsInstances = { workspace.Terrain }
			local hitT = workspace:Raycast(pos, newPos - pos, tRay)
			if victim or hitT or newPos.Y < 0 then
				table.remove(tMissiles, i)
				m.Target = victim
				detonate(m, victim)
				continue
			end
			m.Part.CFrame = CFrame.lookAt(newPos, newPos + m.Vel.Unit)
			continue
		end
		if not alive or age > WeaponConfig.Missile.Lifetime or not targetPos then
			table.remove(tMissiles, i)
			if alive then detonate(m, nil) end
			continue
		end
		local pos = m.Part.Position
		local speed = WeaponConfig.Missile.Speed * (if age < WeaponConfig.Missile.Boost then 0.75 + 0.25 * age / WeaponConfig.Missile.Boost else 1)
		local to = (targetPos :: Vector3) - pos
		local dist = to.Magnitude
		if dist < WeaponConfig.Missile.Fuse then
			table.remove(tMissiles, i)
			detonate(m, if m.DecoyPos then nil else m.Target)
			continue
		end
		-- turn-rate-limited pursuit (pure pursuit + lead)
		local desired = to.Unit
		if m.Target and m.Target.PrimaryPart and not m.DecoyPos then
			local tv = m.Target.PrimaryPart.AssemblyLinearVelocity
			local lead = (targetPos :: Vector3) + tv * math.clamp(dist / speed, 0, 2) * 0.6
			desired = (lead - pos).Unit
		end
		local cur = m.Vel.Unit
		local angle = math.acos(math.clamp(cur:Dot(desired), -1, 1))
		local maxTurn = m.Turn * dt
		local newDir = desired
		if angle > maxTurn and angle > 1e-4 then
			local axis = cur:Cross(desired)
			if axis.Magnitude > 1e-5 then newDir = CFrame.fromAxisAngle(axis.Unit, maxTurn) * cur end
		end
		m.Vel = newDir * speed
		local newPos = pos + m.Vel * dt
		-- closest approach this step (relative motion): a fast crossing shot can pass the fuse radius between
		-- two server ticks, which used to read as "the lock was fine but it flew straight past"
		if not m.DecoyPos and m.Target and m.Target.PrimaryPart then
			local tv = m.Target.PrimaryPart.AssemblyLinearVelocity
			local rel0 = (targetPos :: Vector3) - pos
			local relV = tv - m.Vel
			local tStar = math.clamp(-rel0:Dot(relV) / math.max(relV:Dot(relV), 1e-6), 0, dt)
			if (rel0 + relV * tStar).Magnitude < WeaponConfig.Missile.Fuse then
				table.remove(tMissiles, i)
				m.Part.CFrame = CFrame.new(pos + m.Vel * tStar)
				detonate(m, m.Target)
				continue
			end
		end
		-- terrain impact
		tRay.FilterDescendantsInstances = { workspace.Terrain }
		local hit = workspace:Raycast(pos, newPos - pos, tRay)
		if hit or newPos.Y < 0 then
			table.remove(tMissiles, i)
			detonate(m, nil)
			continue
		end
		m.Part.CFrame = CFrame.lookAt(newPos, newPos + newDir)
	end
end

function Combat.StartAsync(self)
	oMissileFolder = workspace:FindFirstChild("Missiles") :: Folder or Instance.new("Folder")
	oMissileFolder.Name = "Missiles"
	oMissileFolder.Parent = workspace

	oRequest:OnServerEvent(function(oPlayer: Player, t: any)
		if typeof(t) ~= "table" or typeof(t.a) ~= "string" then return end
		if not oReqLimiter:Check(oPlayer) then return end
		if t.a == "Gun" then onGun(oPlayer, t)
		elseif t.a == "Missile" then onMissile(oPlayer, t)
		elseif t.a == "Flare" then onFlare(oPlayer)
		elseif t.a == "Lock" then onLock(oPlayer, t) end
		-- session funnel steps (once per session)
		local A = require(ServerStorage.ServerModules.AnalyticsServer)
		if t.a == "Gun" then A:LogOnce(oPlayer, "session_first_shot")
		elseif t.a == "Lock" and t.s == "Locked" then A:LogOnce(oPlayer, "session_first_lock") end
	end)

	-- rearm on spawn and on touch-and-go
	local F = flight()
	F.OnLaunched.Event:Connect(function(oPlayer: Player)
		self:Rearm(oPlayer)
	end)
	-- missiles/flares are reloaded by the ground crew after you land and stop (FlightServer.OnResupply)
	F.OnResupply.Event:Connect(function(oPlayer: Player)
		self:Rearm(oPlayer)
	end)
	F.OnJetDestroyed.Event:Connect(function(oPlayer: Player, sCause: string, vPos: Vector3)
		local s = F:GetSortie(oPlayer)
		local jet = s and s.Jet
		if jet then
			tAmmo[jet] = nil
			tLedger[jet] = nil
			-- crashes while being chased credit the last attacker
			-- client-reported impacts arrive as "crash:<what was hit>", server ones as "crash"
			local ejected = sCause == "eject"
			if (string.sub(sCause, 1, 5) == "crash" or ejected or sCause == "bounds") and not jet:GetAttribute("Dead") then
				local uid = jet:GetAttribute("LastAttacker")
				local at = jet:GetAttribute("LastAttackedAt") :: number? or -math.huge
				local recent = workspace:GetServerTimeNow() - at <= WeaponConfig.CrashCreditWindow
				local killer = if uid and recent then Players:GetPlayerByUserId(uid) else nil
				if killer == oPlayer then killer = nil end
				jet:SetAttribute("Dead", true)
				local how = if ejected then (if killer then "Forced Eject" else "Ejected") elseif killer then "Crash (chased)" else "Crash"
				self.OnKill:Fire(killer, jet, how, { Assists = {} })
				oEvent:FireAllClients({ a = "Kill", killer = if killer then killer.DisplayName else "", killerId = if killer then killer.UserId else 0,
					victim = oPlayer.DisplayName, victimId = oPlayer.UserId, weapon = if ejected then "Eject" elseif sCause == "bounds" then "Bounds" else "Crash", pos = vPos,
					reason = string.sub(sCause, 7, 30), -- "crash:<what>" -> what (BellyLanding / HardLanding / Terrain...)
					model = jet.Name, vel = if jet.PrimaryPart then jet.PrimaryPart.AssemblyLinearVelocity else Vector3.zero })
			end
		end
		tLockedBy[oPlayer] = nil
	end)

	RunService.Heartbeat:Connect(stepMissiles)
end

function Combat.PlayerRemoving(self, oPlayer: Player)
	tGunState[oPlayer] = nil
	tLastMissile[oPlayer] = nil
	tLastFlare[oPlayer] = nil
	tLockedBy[oPlayer] = nil
	tLockState[oPlayer] = nil
end

return Combat
