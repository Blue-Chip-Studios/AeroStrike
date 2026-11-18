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
}


local Npc = ModuleUtil.New({
	Active = {} :: { [Model]: Npc },
	OnRemoved = Instance.new("BindableEvent"), -- (model, tag, killed: boolean)
})

local nNextId = 0
local oCombatEvent = Remote:GetEvent("CombatEvent")
local World: any, Combat: any

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
	thrust.VectorVelocity = newDir * n.Cfg.Speed
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
local function sam(n: Npc, now: number)
	local s = n.Cfg.Sam
	if not s or now - n.LastShot < s.Cooldown then return end
	local root = n.Model.PrimaryPart :: BasePart
	local from = root.Position + Vector3.new(0, 10, 0)
	tSamRay.FilterDescendantsInstances = { workspace.Terrain }
	for _, jet in ipairs(workspace.Jets:GetChildren()) do
		if jet:IsA("Model") and jet.PrimaryPart and not jet:GetAttribute("Dead") and not jet:GetAttribute("Shield") then
			local to = jet.PrimaryPart.Position - from
			if to.Magnitude < s.Range and not workspace:Raycast(from, to, tSamRay) then
				n.LastShot = now
				Combat:FireMissileAt(nil, CFrame.lookAt(from, jet.PrimaryPart.Position), jet, s.Damage, n.Model)
				return
			end
		end
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

-- Fighters hunt: chase the nearest player (with lead) when not defending
local function pursue(n: Npc, pos: Vector3, routeTarget: Vector3): Vector3
	local d = n.Cfg.Dogfight
	if not d or n.Tactic then return routeTarget end
	local best, bd = nil, d.Range
	for _, jet in ipairs(workspace.Jets:GetChildren()) do
		if jet:IsA("Model") and jet.PrimaryPart and not jet:GetAttribute("Dead") and not jet:GetAttribute("Shield") then
			local dist = (jet.PrimaryPart.Position - pos).Magnitude
			if dist < bd then best, bd = jet, dist end
		end
	end
	if not best then return routeTarget end
	local tp = (best.PrimaryPart :: BasePart)
	return tp.Position + tp.AssemblyLinearVelocity * math.clamp(bd / 600, 0, 1.2)
end

-- Fighter nose guns: short bursts when a player sits in front
local function noseGun(n: Npc, now: number)
	local g = n.Cfg.NoseGun
	if not g or now - n.LastShot < 1 / g.Rate then return end
	local root = n.Model.PrimaryPart :: BasePart
	local fwd = root.CFrame.LookVector
	for _, jet in ipairs(workspace.Jets:GetChildren()) do
		if jet:IsA("Model") and jet.PrimaryPart and not jet:GetAttribute("Dead") and not jet:GetAttribute("Shield") then
			local to = jet.PrimaryPart.Position - root.Position
			local dist = to.Magnitude
			if dist < g.Range and math.acos(math.clamp(fwd:Dot(to.Unit), -1, 1)) < g.Cone then
				n.LastShot = now
				local hit = math.random() < g.HitChance * (1 - dist / g.Range * 0.5)
				local miss = if hit then Vector3.zero else Vector3.new(math.random(-14, 14), math.random(-8, 8), math.random(-14, 14))
				oCombatEvent:FireAllClients({ a = "NpcFire", from = root.Position + fwd * 14, to = jet.PrimaryPart.Position + miss })
				if hit then Combat:Damage(jet, g.Damage, nil, "Red Talon") end
				return
			end
		end
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
	local tmpl = W:GetNpcTemplate(sKind)
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
	m:SetAttribute("Pilot", if sKind == "Bomber" then "TALON BOMBER" elseif sKind == "Interceptor" then "RED TALON" else "DRONE")
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
	}
	return m
end

function Npc.Remove(self, m: Model, bKilled: boolean)
	local n = self.Active[m]
	if not n then return end
	self.Active[m] = nil
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

function Npc.StartAsync(self)
	World = require(ServerStorage.ServerModules.WorldServer)
	Combat = require(ServerStorage.ServerModules.CombatServer)
	Combat.OnKill.Event:Connect(function(_killer, victim: Model)
		if self.Active[victim] then self:Remove(victim, true) end
	end)
	task.spawn(function()
		local dt = 1 / NpcConfig.TickRate
		while true do
			task.wait(dt)
			local now = os.clock()
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
				flak(n, now)
				flares(n, now)
			end
		end
	end)
end

return Npc
