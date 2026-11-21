--!strict
--[[
    NpcServer
    ---------
    Red Talon AI aircraft. Same rig as player jets (Root + movers + Hitbox),
    server-owned physics so motion replicates with interpolation.

    Npc:Spawn(kind, cframe, { Route = {Vector3}, Loop = bool, Orbit = {Centre, Radius}, Tag = string })
    Behaviours: follow a route / orbit a point; bombers have a tail gunner
    that shoots at players behind them and may pop flares at incoming missiles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)

type Npc = {
	Model: Model,
	Kind: string,
	Cfg: any,
	Route: { Vector3 },
	Wp: number,
	Loop: boolean,
	Orbit: { Centre: Vector3, Radius: number }?,
	Angle: number,
	Tag: string,
	LastShot: number,
	LastFlare: number,
	TrackedSince: number?, -- when an attacker's seeker started tracking this NPC
	EvadeUntil: number?,
	NextEvade: number?,
	Tactic: string?,
	TacticT0: number?,
	Chasing: boolean?,
	LockOn: Model?, -- player jet this AI's seeker is tracking (their RWR hears it)
	LockT0: number?,
	LastMissile: number?,
	MissilesLeft: number?,
	Engage: Model?, -- the one jet (player or opposing bot) this fighter is assigned to attack
	EngageT0: number?,
	Side: string?, -- bots only: "Blue" | "Red" (unassigned bots dogfight the other side)
	SelfDef: boolean?,
}


local Npc = ModuleUtil.New({
	Active = {} :: { [Model]: Npc },
	OnRemoved = Instance.new("BindableEvent"), -- (model, tag, killed: boolean)
})

local nNextId = 0
local oCombatEvent = Remote:GetEvent("CombatEvent")
local World: any, Combat: any, Flight: any
local Engage = NpcConfig.Engagement
local nSide = 0
local nNextAssign = 0

local function steer(n: Npc, target: Vector3, dt: number)
	local root = n.Model.PrimaryPart :: BasePart
	local cf = root.CFrame
	local to = target - cf.Position
	if to.Magnitude < 1 then return end
	local cur = cf.LookVector
	local want = to.Unit
	local angle = math.acos(math.clamp(cur:Dot(want), -1, 1))
	local maxTurn = n.Cfg.TurnRate * dt
	local newDir = want
	if angle > maxTurn then
		local axis = cur:Cross(want)
		if axis.Magnitude > 1e-5 then newDir = CFrame.fromAxisAngle(axis.Unit, maxTurn) * cur end
	end
	-- gentle bank into turns
	local lateral = cf.RightVector:Dot(want - cur)
	local bank = math.clamp(-lateral * 2, -0.6, 0.6)
	local rot = CFrame.lookAt(Vector3.zero, newDir) * CFrame.Angles(0, 0, bank)
	local thrust = root:FindFirstChild("Thrust") :: LinearVelocity
	local align = root:FindFirstChild("Steer") :: AlignOrientation
	thrust.VectorVelocity = newDir * (if n.Chasing and n.Cfg.ChaseSpeed then n.Cfg.ChaseSpeed else n.Cfg.Speed)
	align.CFrame = rot
end

local function tailGun(n: Npc, now: number)
	local g = n.Cfg.TailGun
	if not g or now - n.LastShot < 1 / g.Rate then return end
	local root = n.Model.PrimaryPart :: BasePart
	local back = -root.CFrame.LookVector
	local best: Model? = nil
	local bestD = g.Range
	for _, jet in ipairs(workspace.Jets:GetChildren()) do
		if jet:IsA("Model") and jet.PrimaryPart and not jet:GetAttribute("Dead") and not jet:GetAttribute("Shield") then
			local to = jet.PrimaryPart.Position - root.Position
			local d = to.Magnitude
			if d < bestD and math.acos(math.clamp(back:Dot(to.Unit), -1, 1)) < g.Cone then
				best, bestD = jet, d
			end
		end
	end
	if not best then return end
	n.LastShot = now
	local hit = math.random() < g.HitChance * (1 - bestD / g.Range * 0.6)
	local tp = (best.PrimaryPart :: BasePart).Position
	oCombatEvent:FireAllClients({ a = "NpcFire", from = root.Position + back * 22, to = tp + (if hit then Vector3.zero else Vector3.new(math.random(-12, 12), math.random(-8, 8), math.random(-12, 12))) })
	if hit then Combat:Damage(best, g.Damage, nil, "Tail Gunner") end
end

-- Destroyer flak: bursts around the nearest jet in range (puffs on clients; chance to hit)
local function flak(n: Npc, now: number)
	local f = n.Cfg.Flak
	if not f or now - n.LastShot < 1 / f.Rate then return end
	local root = n.Model.PrimaryPart :: BasePart
	local best: Model? = nil
	local bestD = f.Range
	for _, jet in ipairs(workspace.Jets:GetChildren()) do
		if jet:IsA("Model") and jet.PrimaryPart and not jet:GetAttribute("Dead") and not jet:GetAttribute("Shield") then
			local d = (jet.PrimaryPart.Position - root.Position).Magnitude
			if d < bestD then best, bestD = jet, d end
		end
	end
	if not best then return end
	n.LastShot = now
	local tp = (best.PrimaryPart :: BasePart).Position
	local hit = math.random() < f.HitChance * (1 - bestD / f.Range * 0.5)
	local miss = if hit then Vector3.zero else Vector3.new(math.random(-40, 40), math.random(-25, 25), math.random(-40, 40))
	oCombatEvent:FireAllClients({ a = "Flak", pos = tp + miss })
	if hit then Combat:Damage(best, f.Damage, nil, "Flak") end
end

-- SAM site: real (dodgeable) missile at a jet in range with line of sight
local tSamRay = RaycastParams.new()
tSamRay.FilterType = Enum.RaycastFilterType.Include
local releaseLock: (n: Npc) -> ()
-- SAM site: tracks a jet first (the pilot hears the lock tone and can dive behind terrain), then fires.
-- Rookies get a longer warning: SAMs were 15% of all shoot-downs of new players.
local function sam(n: Npc, now: number)
	local s = n.Cfg.Sam
	if not s then return end
	local root = n.Model.PrimaryPart :: BasePart
	local from = root.Position + Vector3.new(0, 10, 0)
	tSamRay.FilterDescendantsInstances = { workspace.Terrain }
	local function ok(jet: Model?): boolean
		if not jet or not jet.Parent or not jet.PrimaryPart or jet:GetAttribute("Dead") or jet:GetAttribute("Shield") then return false end
		local to = jet.PrimaryPart.Position - from
		return to.Magnitude < s.Range and not workspace:Raycast(from, to, tSamRay)
	end
	if n.LockOn and not ok(n.LockOn) then releaseLock(n) end
	if now - n.LastShot < s.Cooldown then return end
	if not n.LockOn then
		for _, jet in ipairs(workspace.Jets:GetChildren()) do
			if jet:IsA("Model") and ok(jet) then
				n.LockOn, n.LockT0 = jet, now
				jet:SetAttribute("LockedBy", (jet:GetAttribute("LockedBy") :: number? or 0) + 1)
				break
			end
		end
		return
	end
	local jet = n.LockOn :: Model
	local track = if jet:GetAttribute("Rookie") then Engage.SamTrackRookie else Engage.SamTrack
	if now - (n.LockT0 :: number) >= track then
		releaseLock(n)
		n.LastShot = now
		Combat:FireMissileAt(nil, CFrame.lookAt(from, (jet.PrimaryPart :: BasePart).Position), jet, s.Damage, n.Model)
	end
end

-- ===================== AI TACTICS =====================
-- Once a player's seeker tracks an aircraft (its "RWR" hears the lock), the pilot picks a
-- tactic after a reaction delay. Each tactic works *with* the lock mechanic (WeaponsController):
--   Jink     weave hard left/right            -> boresight + "evading" lock penalty
--   Mask     dive for low ground / the canyon  -> terrain blocks the seeker, ground clutter halves it
--   Vertical pull straight up, dump flares    -> flare knock-back, sun glare if it climbs sunward
--   Break    turn hard into the attacker       -> forces a weak head-on aspect
local function ground(x: number, z: number): number
	return math.max(IslandShape.Height(x, z), 0)
end

local function nearestTracker(pos: Vector3): Model?
	local best, bd = nil, 4000
	for _, jet in ipairs(workspace.Jets:GetChildren()) do
		if jet:IsA("Model") and jet.PrimaryPart and not jet:GetAttribute("Dead") then
			local d = (jet.PrimaryPart.Position - pos).Magnitude
			if d < bd then best, bd = jet, d end
		end
	end
	return best
end

local function popFlares(n: Npc, now: number, pos: Vector3)
	if now - n.LastFlare < 0.9 then return end
	n.LastFlare = now
	Combat:DecoyMissilesAt(n.Model)
	oCombatEvent:FireAllClients({ a = "Flares", owner = n.Model.Name, pos = pos })
end

-- lowest ground ahead (prefers the canyon if it is close): where a pilot would go to hide
local function maskPoint(pos: Vector3, fwd: Vector3, agl: number): Vector3
	local flat = Vector3.new(fwd.X, 0, fwd.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local bestP, bestH = pos + flat * 600, math.huge
	for i = -3, 3 do
		local dir = CFrame.Angles(0, math.rad(i * 22), 0) * flat
		for _, d in ipairs({ 500, 800 }) do
			local p = pos + dir * d
			local h = ground(p.X, p.Z)
			if h < bestH then bestH, bestP = h, p end
		end
	end
	-- the canyon floor is the best cover of all if it is within reach
	local cx = pos.X + flat.X * 600
	local cp = Vector3.new(cx, 0, IslandShape.CanyonZ(cx))
	if (Vector3.new(pos.X, 0, pos.Z) - cp).Magnitude < 1400 and IslandShape.Mask(cp.X, cp.Z) > 0.5 then
		bestP, bestH = cp, IslandShape.CanyonFloor
	end
	return Vector3.new(bestP.X, bestH + agl, bestP.Z)
end

local function evade(n: Npc, now: number, pos: Vector3, routeTarget: Vector3): Vector3
	local ev = n.Cfg.Evasion
	if not ev then return routeTarget end
	local tracked = (n.Model:GetAttribute("LockedBy") or 0) > 0
	n.TrackedSince = if tracked then (n.TrackedSince or now) else nil
	local fwd = n.Model:GetPivot().LookVector
	if not (n.EvadeUntil and now < n.EvadeUntil) then
		if tracked and now - (n.TrackedSince :: number) >= ev.React and now >= (n.NextEvade or 0) then
			-- pick a tactic that suits the situation
			local options = ev.Tactics or { "Jink" }
			local overLand = ground(pos.X, pos.Z) > 0 or IslandShape.Mask(pos.X + fwd.X * 800, pos.Z + fwd.Z * 800) > 0
			local pick = options[math.random(1, #options)]
			if table.find(options, "Mask") and overLand and math.random() < 0.5 then pick = "Mask" end
			n.Tactic = pick
			n.TacticT0 = now
			n.EvadeUntil = now + ev.Duration
			n.NextEvade = now + ev.Duration + ev.Cooldown
			n.Model:SetAttribute("Evading", pick)
			if pick == "Vertical" or (ev.FlareOnLock and math.random() < ev.FlareOnLock) then popFlares(n, now, pos) end
		else
			if n.Model:GetAttribute("Evading") then n.Model:SetAttribute("Evading", nil) end
			n.Tactic = nil
			return routeTarget
		end
	end
	local t = now - (n.TacticT0 or now)
	if n.Tactic == "Mask" then
		return maskPoint(pos, fwd, ev.MaskAGL or 70)
	elseif n.Tactic == "Vertical" then
		if t > 1.3 and t < 1.5 then popFlares(n, now, pos) end -- second salvo near the top
		if t < 2.4 then return pos + Vector3.new(0, 900, 0) + fwd * 120 end
		return pos + fwd * 600 + Vector3.new(0, -120, 0) -- roll out and dive away
	elseif n.Tactic == "Break" then
		local att = nearestTracker(pos)
		if att and att.PrimaryPart then return att.PrimaryPart.Position end
	end
	-- Jink (default): alternate hard left/right around the heading
	local base = (routeTarget - pos)
	base = if base.Magnitude > 1 then base.Unit else fwd
	local right = base:Cross(Vector3.yAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	local side = if math.floor(now / ev.Period) % 2 == 0 then 1 else -1
	return pos + base * 400 + right * side * ev.Jink + Vector3.new(0, side * ev.Jink * 0.25, 0)
end

-- the carrier's CIWS umbrella: AI won't chase or shoot into it (fresh launches get a fair start)
local function underUmbrella(p: Vector3): boolean
	local c = MapConfig.Carrier
	return (Vector3.new(p.X, 0, p.Z) - Vector3.new(c.CFrame.X, 0, c.CFrame.Z)).Magnitude < c.SafeRadius
end

-- how hard a player jet is manoeuvring (approx. G from its turn rate); hard jinking spoils aim
local function targetG(jet: Model): number
	local root = jet.PrimaryPart :: BasePart
	return 1 + root.AssemblyAngularVelocity.Magnitude * root.AssemblyLinearVelocity.Magnitude * 0.032
end

-- bot-on-bot fights stay over the combat zone (chasing each other they used to drift off the map for good)
local function inArena(p: Vector3): boolean
	local P = NpcConfig.Population
	return (Vector3.new(p.X, 0, p.Z) - Vector3.new(P.Centre.X, 0, P.Centre.Z)).Magnitude < Engage.BotArena
end

-- Fighters hunt: chase the nearest player (with lead) when not defending
local function pursue(n: Npc, pos: Vector3, routeTarget: Vector3): Vector3
	local d = n.Cfg.Dogfight
	n.Chasing = false
	if not d or n.Tactic then return routeTarget end
	-- chase only the target the engagement manager assigned (see assignTargets)
	local e = n.Engage
	if not e or not e.Parent or not e.PrimaryPart or e:GetAttribute("Dead") then return routeTarget end
	local tp = e.PrimaryPart :: BasePart
	local bd = (tp.Position - pos).Magnitude
	if bd > d.Range * 1.3 then return routeTarget end
	if e.Parent ~= workspace.Jets and not (inArena(pos) and inArena(tp.Position)) then return routeTarget end
	n.Chasing = true
	return tp.Position + tp.AssemblyLinearVelocity * math.clamp(bd / 600, 0, 1.2)
end

-- Fighter nose guns: short bursts when a player sits in front
local function noseGun(n: Npc, now: number)
	local g = n.Cfg.NoseGun
	if not g or now - n.LastShot < 1 / g.Rate then return end
	local root = n.Model.PrimaryPart :: BasePart
	local fwd = root.CFrame.LookVector
	local jet = n.Engage
	if not jet or not jet.Parent or not jet.PrimaryPart or jet:GetAttribute("Dead") then return end
	if jet.Parent ~= workspace.Jets then
		-- bot-on-bot: lighter damage so their fights run long and fill the sky
		local to = jet.PrimaryPart.Position - root.Position
		if to.Magnitude < g.Range and math.acos(math.clamp(fwd:Dot(to.Unit), -1, 1)) < g.Cone then
			n.LastShot = now
			local hit = math.random() < g.HitChance * (1 - to.Magnitude / g.Range * 0.5)
			local miss = if hit then Vector3.zero else Vector3.new(math.random(-14, 14), math.random(-8, 8), math.random(-14, 14))
			oCombatEvent:FireAllClients({ a = "NpcFire", from = root.Position + fwd * 14, to = jet.PrimaryPart.Position + miss })
			if hit then Combat:Damage(jet, g.Damage * Engage.BotVsBotDamage, nil, "Cannon") end
		end
		return
	end
	if jet:GetAttribute("Shield") or now - (n.EngageT0 or now) < Engage.HoldFire then return end
	do
		do
			local to = jet.PrimaryPart.Position - root.Position
			local dist = to.Magnitude
			if dist < g.Range and math.acos(math.clamp(fwd:Dot(to.Unit), -1, 1)) < g.Cone and not underUmbrella(jet.PrimaryPart.Position) then
				n.LastShot = now
				-- steady targets get hit; a hard break (high G) throws the gunner's aim off
				local jink = math.clamp(1.25 - targetG(jet) / 8, 0.3, 1)
				local rookie = if jet:GetAttribute("Rookie") then 0.5 else 1 -- new pilots (rank <= FlightConfig.RookieMaxRank) get a chance to learn
				local hit = math.random() < g.HitChance * (1 - dist / g.Range * 0.5) * jink * rookie
				local miss = if hit then Vector3.zero else Vector3.new(math.random(-14, 14), math.random(-8, 8), math.random(-14, 14))
				oCombatEvent:FireAllClients({ a = "NpcFire", from = root.Position + fwd * 14, to = jet.PrimaryPart.Position + miss })
				if hit then Combat:Damage(jet, g.Damage, nil, if n.Cfg.Bot then (n.Model:GetAttribute("Pilot") :: string) else "Red Talon") end
				return
			end
		end
	end
end

-- AI heat-seeker: hold a player in the seeker cone (they hear the lock tone) long enough and
-- a real missile comes off the rail: flares, a hard break or terrain masking defeat it
local tLosRay = RaycastParams.new()
tLosRay.FilterType = Enum.RaycastFilterType.Include
function releaseLock(n: Npc)
	local j = n.LockOn
	if j and j.Parent then j:SetAttribute("LockedBy", math.max(0, (j:GetAttribute("LockedBy") :: number? or 0) - 1)) end
	n.LockOn, n.LockT0 = nil, nil
end
local function aiMissile(n: Npc, now: number)
	local mc = n.Cfg.Missile
	if not mc then return end
	if n.MissilesLeft == nil then n.MissilesLeft = mc.Count end
	local root = n.Model.PrimaryPart :: BasePart
	local fwd = root.CFrame.LookVector
	local function valid(jet: Model?): boolean
		if not jet or not jet.Parent or not jet.PrimaryPart or jet:GetAttribute("Dead") or jet:GetAttribute("Shield") then return false end
		local to = jet.PrimaryPart.Position - root.Position
		if to.Magnitude > mc.Range or math.acos(math.clamp(fwd:Dot(to.Unit), -1, 1)) > mc.Cone then return false end
		if underUmbrella(jet.PrimaryPart.Position) then return false end
		-- never more than two seekers on one pilot at a time (unless this AI already holds the lock)
		if n.LockOn ~= jet and (jet:GetAttribute("LockedBy") :: number? or 0) >= 2 then return false end
		tLosRay.FilterDescendantsInstances = { workspace.Terrain }
		return workspace:Raycast(root.Position, to, tLosRay) == nil
	end
	if (n.MissilesLeft :: number) <= 0 or now - (n.LastMissile or -math.huge) < mc.Cooldown then
		if n.LockOn then releaseLock(n) end
		return
	end
	if n.LockOn and not valid(n.LockOn) then releaseLock(n) end
	if n.LockOn and n.LockOn ~= n.Engage then releaseLock(n) end
	if not n.LockOn then
		local jet = n.Engage
		if jet and jet.Parent == workspace.Jets and now - (n.EngageT0 or now) >= Engage.HoldFire and valid(jet) then
			n.LockOn, n.LockT0 = jet, now
			jet:SetAttribute("LockedBy", (jet:GetAttribute("LockedBy") :: number? or 0) + 1)
		end
		return
	end
	local lockTime = mc.LockTime * (if (n.LockOn :: Model):GetAttribute("Rookie") then 1.6 else 1)
	if now - (n.LockT0 :: number) >= lockTime then
		local jet = n.LockOn :: Model
		releaseLock(n)
		n.LastMissile = now
		n.MissilesLeft = (n.MissilesLeft :: number) - 1
		Combat:FireMissileAt(nil, root.CFrame * CFrame.new(0, -2, -12), jet, mc.Damage, n.Model)
	end
end

-- Never fly into the island: look ahead along the nose and pull up over rising ground
local function avoidTerrain(n: Npc, pos: Vector3, target: Vector3): Vector3
	if n.Cfg.Ship or n.Cfg.Static then return target end
	local agl = n.Cfg.MinAGL or 60
	local tg = ground(target.X, target.Z) + agl
	if target.Y < tg then target = Vector3.new(target.X, tg, target.Z) end
	local look = n.Model:GetPivot().LookVector
	for _, d in ipairs({ 120, 300, 550 }) do
		local p = pos + look * d
		local need = ground(p.X, p.Z) + agl
		if p.Y < need then
			return Vector3.new(target.X, math.max(target.Y, need + 250), target.Z) + Vector3.new(0, 200, 0)
		end
	end
	return target
end

local function flares(n: Npc, now: number)
	if not n.Cfg.FlareChance or now - n.LastFlare < 4 then return end
	if (n.Model:GetAttribute("Incoming") or 0) <= 0 then return end
	n.LastFlare = now
	if math.random() < n.Cfg.FlareChance then
		Combat:DecoyMissilesAt(n.Model)
		oCombatEvent:FireAllClients({ a = "Flares", owner = n.Model.Name, pos = n.Model:GetPivot().Position })
	end
end

function Npc.Spawn(self, sKind: string, cf: CFrame, opts: { [string]: any }?): Model?
	local W = World
	while not W.Ready do task.wait() end
	local cfgK = NpcConfig.Kinds[sKind]
	local botJet: string? = nil
	local tmpl
	if cfgK and cfgK.Jets then
		botJet = cfgK.Jets[math.random(1, #cfgK.Jets)]
		tmpl = W:GetJetTemplate(botJet)
	else
		tmpl = W:GetNpcTemplate(sKind)
	end
	if not tmpl then return nil end
	local count = 0
	for _ in pairs(self.Active) do count += 1 end
	if count >= NpcConfig.MaxNpcs then return nil end
	local o = opts or {}
	nNextId += 1
	local m = tmpl:Clone()
	m.Name = "N" .. nNextId
	local cfg = NpcConfig.Kinds[sKind]
	m:SetAttribute("NpcKind", sKind)
	m:SetAttribute("Health", cfg.Health)
	m:SetAttribute("MaxHealth", cfg.Health)
	m:SetAttribute("Pilot", if sKind == "Bomber" then "TALON BOMBER" elseif sKind == "Interceptor" then "RED TALON" elseif sKind == "Tanker" then "TANKER" else "DRONE")
	if cfg.PilotName then m:SetAttribute("Pilot", cfg.PilotName) end
	if botJet then
		-- looks and reads like another pilot: player airframe, random livery, player-style callsign
		local JetConfig = require(ReplicatedStorage.Config.JetConfig)
		local jc = JetConfig.Jets[botJet]
		local names = {}
		for k in pairs(jc.Paints) do if not JetConfig.IsMasteryPaint(k) then table.insert(names, k) end end
		W:ApplyPaint(m, jc.Paints[names[math.random(1, #names)]])
		local cs = NpcConfig.Callsigns
		local call = cs.Prefix[math.random(1, #cs.Prefix)] .. cs.Suffix[math.random(1, #cs.Suffix)]
		if math.random() < 0.6 then call ..= tostring(math.random(1, 99)) end
		m:SetAttribute("Pilot", call)
		m:SetAttribute("Bot", true)
		m:SetAttribute("JetId", botJet)
		nSide += 1
		m:SetAttribute("Side", if nSide % 2 == 0 then "Blue" else "Red")
		-- half the bot pilots fly a season trail (shows players what's earnable)
		if math.random() < 0.5 then
			local ids = { "Crimson", "Sky", "Emerald", "Solar", "Violet", "Arctic", "Inferno" }
			m:SetAttribute("Trail", ids[math.random(1, #ids)])
		end
	end
	if cfg.Persistent then m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end -- boss: every client tracks it
	if cfg.Friendly then
		m:SetAttribute("Friendly", true)
		-- always streamed to every client: its marker / low-fuel guidance must work from anywhere
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
	if o.Tag then m:SetAttribute("MissionTag", o.Tag) end
	m:PivotTo(cf)
	m.Parent = workspace.NPC
	local root = m.PrimaryPart :: BasePart
	if cfg.Static then
		root.Anchored = true
	else
		root.Anchored = false
		root:SetNetworkOwner(nil)
	end
	self.Active[m] = {
		Model = m, Kind = sKind, Cfg = cfg, Route = o.Route or {}, Wp = 1, Loop = o.Loop == true,
		Orbit = o.Orbit, Angle = math.random() * math.pi * 2, Tag = o.Tag or "", LastShot = 0, LastFlare = 0,
		Side = m:GetAttribute("Side") :: string?,
	}
	return m
end

function Npc.Remove(self, m: Model, bKilled: boolean)
	local n = self.Active[m]
	if not n then return end
	self.Active[m] = nil
	releaseLock(n)
	self.OnRemoved:Fire(m, n.Tag, bKilled)
	if bKilled and n.Cfg.Ship and m.PrimaryPart then
		-- a sunk destroyer lists to one side and slides under over ~6s (a payoff
		-- moment everyone in the strike can see) instead of vanishing
		local root = m.PrimaryPart
		root.Anchored = true
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = false; d.CanQuery = false end
		end
		local start = m:GetPivot()
		local roll = if math.random() < 0.5 then -1 else 1
		task.spawn(function()
			local t0 = os.clock()
			while m.Parent and os.clock() - t0 < 6 do
				local a = math.clamp((os.clock() - t0) / 6, 0, 1)
				local e = a * a
				m:PivotTo(start * CFrame.new(0, -60 * e, 0) * CFrame.Angles(math.rad(-12 * a), 0, math.rad(28 * roll * a)))
				task.wait()
			end
			if m.Parent then m:Destroy() end
		end)
		return
	end
	task.delay(0.05, function() if m.Parent then m:Destroy() end end)
end

function Npc.RemoveTag(self, sTag: string)
	for m, n in pairs(self.Active) do
		if n.Tag == sTag then self:Remove(m, false) end
	end
end

-- ENGAGEMENT MANAGER: give every AI fighter at most one target, capping how many hunt any one player
local function aliveModel(m: Model?): boolean
	return m ~= nil and m.Parent ~= nil and m.PrimaryPart ~= nil and not m:GetAttribute("Dead")
end

local function assignTargets(self, now: number)
	local FlightConfig = require(ReplicatedStorage.Config.FlightConfig)
	local tPlayerJets: { [Model]: { cap: number, count: number } } = {}
	local tJetOf: { [Player]: Model } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local so = Flight and Flight:GetSortie(p)
		local jet = so and so.Jet
		if jet and aliveModel(jet) and so.Phase == "Flying" and not jet:GetAttribute("Shield")
			and not underUmbrella((jet.PrimaryPart :: BasePart).Position) then
			local ls = p:FindFirstChild("leaderstats")
			local rv = ls and ls:FindFirstChild("Rank")
			local rank = if rv then tonumber((rv :: any).Value) or 1 else 1
			local tier = if rank <= FlightConfig.RookieMaxRank then "Rookie" elseif rank <= Engage.MidRank then "Mid" else "Vet"
			local calm = if so.AirStart then math.min(Engage.Calm[tier], Engage.CalmAirStart) else Engage.Calm[tier]
			if os.clock() - (so.LaunchedAt or 0) >= calm then
				tPlayerJets[jet] = { cap = Engage.Cap[tier], count = 0 }
				tJetOf[p] = jet
			end
		end
	end
	local fighters: { Npc } = {}
	for m, n in pairs(self.Active) do
		if n.Cfg.Dogfight and aliveModel(m) then table.insert(fighters, n) end
	end
	local function dist(a: Model, b: Model): number
		return ((a.PrimaryPart :: BasePart).Position - (b.PrimaryPart :: BasePart).Position).Magnitude
	end
	-- 1) self-defence: a fighter a player has just hit goes after that player (outside the cap)
	local serverNow = workspace:GetServerTimeNow()
	for _, n in ipairs(fighters) do
		n.SelfDef = false
		local uid, at = n.Model:GetAttribute("LastAttacker"), n.Model:GetAttribute("LastAttackedAt")
		if typeof(uid) == "number" and typeof(at) == "number" and serverNow - at < Engage.SelfDefence then
			local ap = Players:GetPlayerByUserId(uid)
			local jet = ap and tJetOf[ap]
			if jet then
				if n.Engage ~= jet then n.Engage, n.EngageT0 = jet, now end
				n.SelfDef = true
				tPlayerJets[jet].count += 1
			end
		end
	end
	-- 2) keep existing player engagements that are still valid and within the cap
	for _, n in ipairs(fighters) do
		if n.SelfDef then continue end
		local e = n.Engage
		if e and tPlayerJets[e] then
			local info = tPlayerJets[e]
			if info.count < info.cap and dist(n.Model, e) < n.Cfg.Dogfight.Range * 1.3 then
				info.count += 1
			else
				n.Engage = nil
			end
		elseif e and e.Parent == workspace.Jets then
			n.Engage = nil -- player in a calm window / shielded / landed / gone
		end
	end
	-- 3) fill each player's spare slots with the nearest fighters not already on a player
	for jet, info in pairs(tPlayerJets) do
		while info.count < info.cap do
			local best, bd = nil, math.huge
			for _, n in ipairs(fighters) do
				if not (n.Engage and tPlayerJets[n.Engage]) then
					local d = dist(n.Model, jet)
					if d < n.Cfg.Dogfight.Range and d < bd then best, bd = n, d end
				end
			end
			if not best then break end
			best.Engage, best.EngageT0 = jet, now
			info.count += 1
		end
	end
	-- 4) everyone else: bots dogfight the other side (never mission aircraft), others patrol
	for _, n in ipairs(fighters) do
		if n.Engage and tPlayerJets[n.Engage] then continue end
		local function ok(m: Model?): boolean
			local o = m and self.Active[m]
			return o ~= nil and aliveModel(m) and o.Side ~= nil and o.Side ~= n.Side and dist(n.Model, m :: Model) < n.Cfg.Dogfight.Range
				and inArena((n.Model.PrimaryPart :: BasePart).Position) and inArena(((m :: Model).PrimaryPart :: BasePart).Position)
		end
		if not (n.Engage and ok(n.Engage)) then
			n.Engage = nil
			if Engage.BotDogfights and n.Side then
				local best, bd = nil, math.huge
				for _, o in ipairs(fighters) do
					if o ~= n and ok(o.Model) then
						local d = dist(n.Model, o.Model)
						if d < bd then best, bd = o, d end
					end
				end
				if best then n.Engage, n.EngageT0 = best.Model, now end
			end
		end
	end
	-- visible for QA / debugging: which model each fighter is attacking
	for _, n in ipairs(fighters) do
		local want = if n.Engage then n.Engage.Name else nil
		if n.Model:GetAttribute("Engaging") ~= want then n.Model:SetAttribute("Engaging", want) end
	end
end

function Npc.StartAsync(self)
	World = require(ServerStorage.ServerModules.WorldServer)
	Combat = require(ServerStorage.ServerModules.CombatServer)
	Flight = require(ServerStorage.ServerModules.FlightServer)
	Combat.OnKill.Event:Connect(function(_killer, victim: Model)
		if self.Active[victim] then self:Remove(victim, true) end
	end)
	task.spawn(function()
		local dt = 1 / NpcConfig.TickRate
		while true do
			task.wait(dt)
			local now = os.clock()
			if now >= nNextAssign then
				nNextAssign = now + Engage.Interval
				local okA, errA = pcall(assignTargets, self, now)
				if not okA then warn("[Npc] assignTargets", errA) end
			end
			for m, n in pairs(self.Active) do
				if not m.Parent or not m.PrimaryPart then
					self.Active[m] = nil
					continue
				end
				local pos = m.PrimaryPart.Position
				if n.Cfg.Static then
					sam(n, now)
					continue
				end
				local target: Vector3
				if n.Orbit then
					n.Angle += dt * n.Cfg.Speed / n.Orbit.Radius
					target = n.Orbit.Centre + Vector3.new(math.cos(n.Angle) * n.Orbit.Radius, math.sin(n.Angle * 0.5) * 20, math.sin(n.Angle) * n.Orbit.Radius)
				else
					local wp = n.Route[n.Wp]
					if not wp then
						self:Remove(m, false)
						continue
					end
					if (wp - pos).Magnitude < 120 then
						n.Wp += 1
						if n.Wp > #n.Route then
							if n.Loop then n.Wp = 1 else self:Remove(m, false) continue end
						end
					end
					target = n.Route[n.Wp] or wp
				end
				if n.Cfg.Ship then target = Vector3.new(target.X, 0, target.Z) end -- ships stay on the sea
				target = pursue(n, pos, target)
				target = evade(n, now, pos, target)
				target = avoidTerrain(n, pos, target)
				steer(n, target, dt)
				tailGun(n, now)
				noseGun(n, now)
				aiMissile(n, now)
				flak(n, now)
				flares(n, now)
			end
		end
	end)
end

return Npc
