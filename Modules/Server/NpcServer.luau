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
	m:SetAttribute("Pilot", if sKind == "Bomber" then "TALON BOMBER" else "DRONE")
	if o.Tag then m:SetAttribute("MissionTag", o.Tag) end
	m:PivotTo(cf)
	m.Parent = workspace.NPC
	local root = m.PrimaryPart :: BasePart
	root.Anchored = false
	root:SetNetworkOwner(nil)
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
				steer(n, target, dt)
				tailGun(n, now)
				flares(n, now)
			end
		end
	end)
end

return Npc
