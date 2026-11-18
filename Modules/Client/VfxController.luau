--!strict
--[[
    VfxController
    -------------
    Cosmetic, client-only effects (never replicated): missile smoke trails
    and smoothing, flare bursts, explosions, kill-feed and evade toasts,
    afterburner light scaling. Pooled where frequent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)

local LocalPlayer = Players.LocalPlayer
local Vfx = ModuleUtil.New({
	Boom = Instance.new("BindableEvent"), -- (pos, big) for audio
})

local Flight, Input
local oFx: Folder

local FX = require(ReplicatedStorage.Config.VfxConfig)

local function smokeEmitter(parent: Instance, color: Color3, rate: number, life: number, size: number)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = FX.Smoke
	pe.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-20, 20)
	pe.Color = ColorSequence.new(color)
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(life * 0.7, life)
	pe.Speed = NumberRange.new(0, 2)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size * 2.2) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	pe.LightEmission = 0.1
	pe.LockedToPart = false
	pe.Parent = parent
	return pe
end

local function explosion(pos: Vector3, big: boolean)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.Position = pos
	a.Parent = oFx
	local s = if big then 1 else 0.5
	-- rolling fireballs (flipbook plays white-hot -> orange -> smoke over each particle's life)
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = FX.Fireball
	fire.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	fire.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	fire.LightEmission = 0.6
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10 * s), NumberSequenceKeypoint.new(1, 26 * s) })
	fire.Lifetime = NumberRange.new(0.9, 1.4)
	fire.Speed = NumberRange.new(8 * s, 26 * s)
	fire.Drag = 3
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Rotation = NumberRange.new(0, 360)
	fire.RotSpeed = NumberRange.new(-40, 40)
	fire.Rate = 0
	fire.Parent = a
	fire:Emit(if big then 9 else 4)
	-- shockwave ring
	local ring = Instance.new("ParticleEmitter")
	ring.Texture = FX.Shockwave
	ring.LightEmission = 1
	ring.LightInfluence = 0
	ring.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4 * s), NumberSequenceKeypoint.new(1, 70 * s) })
	ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	ring.Lifetime = NumberRange.new(0.45)
	ring.Speed = NumberRange.new(0)
	ring.Rate = 0
	ring.Parent = a
	ring:Emit(1)
	-- hot sparks / debris streaks
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = FX.FlareGlow
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 120, 40))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4 * s + 0.4), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.5, 1.1)
	sparks.Speed = NumberRange.new(60 * s, 140 * s)
	sparks.Drag = 2.5
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Parent = a
	sparks:Emit(if big then 40 else 14)
	-- lingering smoke
	local smoke = smokeEmitter(a, Color3.fromRGB(46, 44, 46), 0, 3.5, 9 * s + 2)
	smoke.Speed = NumberRange.new(4, 14 * s + 4)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke:Emit(if big then 14 else 6)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = if big then 70 else 34
	light.Brightness = 8
	light.Parent = a
	task.spawn(function() -- quick flash that decays
		local t0 = os.clock()
		while os.clock() - t0 < 0.4 and light.Parent do
			light.Brightness = 8 * (1 - (os.clock() - t0) / 0.4)
			RunService.Heartbeat:Wait()
		end
		light:Destroy()
	end)
	Debris:AddItem(a, 5)
	Vfx.Boom:Fire(pos, big)
end

local function flares(pos: Vector3, back: Vector3)
	for i = 1, 4 do
		local f = Instance.new("Part")
		f.Size = Vector3.one * 0.5
		f.Transparency = 1
		f.CanCollide = false
		f.CanQuery = false
		f.Anchored = true
		f.Position = pos
		f.Parent = oFx
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 200, 120)
		pl.Range = 28
		pl.Brightness = 5
		pl.Parent = f
		-- shimmering magnesium glow: many short-lived glow sprites
		local glow = Instance.new("ParticleEmitter")
		glow.Texture = FX.FlareGlow
		glow.Color = ColorSequence.new(Color3.fromRGB(255, 245, 220), Color3.fromRGB(255, 190, 110))
		glow.LightEmission = 1
		glow.LightInfluence = 0
		glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 2.5) })
		glow.Transparency = NumberSequence.new(0.05, 0.6)
		glow.Lifetime = NumberRange.new(0.06, 0.12)
		glow.Rate = 50
		glow.Speed = NumberRange.new(0)
		glow.Rotation = NumberRange.new(0, 360)
		glow.LockedToPart = true
		glow.Parent = f
		smokeEmitter(f, Color3.fromRGB(238, 238, 242), 40, 2.4, 2.2)
		local side = (i - 2.5) * 0.6
		local vel = back * 60 + Vector3.new(side * 40, -10 - i * 6, side * 30)
		local born = os.clock()
		task.spawn(function()
			while os.clock() - born < 3 do
				local dt = RunService.Heartbeat:Wait()
				vel += Vector3.new(0, -30 * dt, 0)
				f.Position += vel * dt
			end
			-- burnt out: stop glowing, let the smoke trail finish
			glow.Rate = 0
			pl:Destroy()
			Debris:AddItem(f, 2.5)
		end)
	end
end

-- Missile parts are server-anchored and replicate in steps; render a smooth
-- local proxy with a smoke trail that eases toward the real position.
type Proxy = { Root: PVInstance, Tail: Attachment, Emitters: { ParticleEmitter }, Visual: { BasePart }, Own: boolean, Born: number, Trail: Trail? }
local tProxies: { [BasePart]: Proxy } = {}
local nRailSide = 1
local function onMissile(p: Instance)
	if not p:IsA("BasePart") then return end
	p.LocalTransparencyModifier = 1
	-- the Blender missile if it loaded, else a simple stand-in
	local ct = ReplicatedStorage:FindFirstChild("ClientTemplates")
	local tmpl = ct and ct:FindFirstChild("Missile") :: Model?
	local root: PVInstance
	local anchorPart: BasePart
	local visual: { BasePart } = {}
	-- your own missile drops off the rail below/behind the wing, then the motor catches and it
	-- surges past the cockpit (the proxy eases toward the real missile in stepProxies)
	local startCf = p.CFrame
	if p:GetAttribute("Owner") == LocalPlayer.UserId then
		nRailSide = -nRailSide
		startCf = p.CFrame * CFrame.new(7 * nRailSide, -6, 6)
	end
	if tmpl and tmpl.PrimaryPart then
		local m = tmpl:Clone()
		m:PivotTo(startCf)
		m.Parent = oFx
		root, anchorPart = m, m.PrimaryPart :: BasePart
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then table.insert(visual, d) end end
	else
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.5, 0.5, 3.6)
		part.Color = Color3.fromRGB(230, 232, 236)
		part.Anchored, part.CanCollide, part.CanQuery = true, false, false
		part.CFrame = startCf
		part.Parent = oFx
		root, anchorPart = part, part
		visual = { part }
	end
	local tail = Instance.new("Attachment")
	tail.Name = "Tail"
	tail.WorldCFrame = startCf * CFrame.new(0, 0, 1.95)
	tail.Parent = anchorPart
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 90)
	glow.Range = 14
	glow.Brightness = 3
	glow.Parent = tail
	-- motor flame (short, hot, fast) + long smoke trail
	local flame = Instance.new("ParticleEmitter")
	flame.Texture = FX.FlareGlow
	flame.Color = ColorSequence.new(Color3.fromRGB(255, 230, 170), Color3.fromRGB(255, 110, 40))
	flame.LightEmission = 1
	flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4.2), NumberSequenceKeypoint.new(1, 0.6) })
	flame.Transparency = NumberSequence.new(0, 1)
	flame.Lifetime = NumberRange.new(0.06, 0.1)
	flame.Rate = 90
	flame.Speed = NumberRange.new(0)
	flame.LockedToPart = true
	flame.Parent = tail
	local smoke = smokeEmitter(tail, Color3.fromRGB(232, 232, 236), 80, 3.6, 3)
	local a1 = Instance.new("Attachment")
	a1.WorldCFrame = tail.WorldCFrame * CFrame.new(0, 0.9, 0)
	a1.Parent = anchorPart
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = tail, a1
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 218, 224))
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new(1.2, 3.5)
	tr.Lifetime = 1.6
	tr.LightEmission = 0.3
	tr.FaceCamera = true
	tr.Parent = anchorPart
	tProxies[p] = { Root = root, Tail = tail, Emitters = { flame, smoke }, Visual = visual,
		Own = p:GetAttribute("Owner") == LocalPlayer.UserId, Born = os.clock(), Trail = tr }
end

local function stepProxies(dt: number)
	for real, px in pairs(tProxies) do
		if not real.Parent then
			tProxies[real] = nil
			for _, part in ipairs(px.Visual) do part.Transparency = 1 end
			for _, em in ipairs(px.Emitters) do em.Rate = 0 end
			if px.Trail then px.Trail.Enabled = false end
			local pl = px.Tail:FindFirstChildOfClass("PointLight"); if pl then pl:Destroy() end
			Debris:AddItem(px.Root, 3)
		else
			local cur = px.Root:GetPivot()
			local ease = if px.Own and os.clock() - px.Born < 0.9 then 2.6 else 12
			px.Root:PivotTo(cur:Lerp(real.CFrame + real.CFrame.LookVector * 330 * dt, math.clamp(dt * ease, 0, 1)))
		end
	end
	-- afterburner light follows boost
	local jet = Flight.Jet
	if jet then
		local glow = jet:FindFirstChild("Glow")
		local pl = glow and glow:FindFirstChild("Afterburner") :: PointLight?
		if pl then pl.Brightness = if Input.State.Boost then 6 else 1.5 end
	end
end

-- ===================== KILL PAYOFF =====================
-- A charred copy of the downed aircraft tumbles out of the sky trailing fire and smoke,
-- throws off burning debris, and splashes / bursts on impact.
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)
local function burningEmitters(parent: Instance, scale: number)
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = FX.Fireball
	fire.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	fire.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	fire.LightEmission = 0.5
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4 * scale), NumberSequenceKeypoint.new(1, 9 * scale) })
	fire.Lifetime = NumberRange.new(0.6, 0.9)
	fire.Rate = 30
	fire.Speed = NumberRange.new(0, 4)
	fire.Rotation = NumberRange.new(0, 360)
	fire.Parent = parent
	local smoke = smokeEmitter(parent, Color3.fromRGB(34, 32, 34), 34, 4, 5 * scale)
	smoke.Speed = NumberRange.new(0, 3)
	return fire, smoke
end

local function wreck(src: Model, vel: Vector3)
	local ok, w = pcall(function() return src:Clone() end)
	if not ok or not w then return end
	local cf0 = src:GetPivot()
	for _, d in ipairs(w:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			if d.Transparency < 1 then d.Color = d.Color:Lerp(Color3.fromRGB(20, 18, 18), 0.55) end -- charred
			if d.Name == "Glow" then d.Transparency = 1 end
		elseif d:IsA("Constraint") or d:IsA("Attachment") or d:IsA("BillboardGui") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Trail") then
			d:Destroy()
		end
	end
	w.Name = "Wreck"
	w.Parent = oFx
	local _, size = w:GetBoundingBox()
	local scale = math.clamp(size.Magnitude / 30, 0.6, 2.5)
	local core = Instance.new("Part")
	core.Anchored, core.CanCollide, core.CanQuery, core.Transparency, core.Size = true, false, false, 1, Vector3.one
	core.CFrame = cf0
	core.Parent = w
	local fire, smoke = burningEmitters(core, scale)
	-- debris chunks flung out
	local chunks = {}
	for _ = 1, 5 do
		local c = Instance.new("Part")
		c.Anchored, c.CanCollide, c.CanQuery = true, false, false
		c.Size = Vector3.new(math.random(10, 26) / 10, math.random(4, 10) / 10, math.random(10, 30) / 10) * scale
		c.Color = Color3.fromRGB(38, 36, 38)
		c.Material = Enum.Material.Metal
		c.CFrame = cf0
		c.Parent = oFx
		local sp = Instance.new("ParticleEmitter")
		sp.Texture = FX.FlareGlow
		sp.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 90, 30))
		sp.LightEmission = 1
		sp.Size = NumberSequence.new(1.2, 0)
		sp.Lifetime = NumberRange.new(0.2, 0.4)
		sp.Rate = 24
		sp.Speed = NumberRange.new(0)
		sp.Parent = c
		table.insert(chunks, { P = c, V = vel * 0.6 + Vector3.new(math.random(-60, 60), math.random(10, 70), math.random(-60, 60)),
			R = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8)) })
	end
	local v = vel * 0.85 + Vector3.new(0, 10, 0)
	local spin = Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 2, (math.random() - 0.5) * 5)
	local cf = cf0
	local born = os.clock()
	task.spawn(function()
		while w.Parent and os.clock() - born < 9 do
			local dt = RunService.Heartbeat:Wait()
			v += Vector3.new(0, -55 * dt, 0)
			v *= (1 - 0.15 * dt) -- drag
			cf = (cf + v * dt) * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
			w:PivotTo(cf)
			core.CFrame = cf
			for _, ch in ipairs(chunks) do
				if ch.P.Parent then
					ch.V += Vector3.new(0, -60 * dt, 0)
					ch.P.CFrame = (ch.P.CFrame + ch.V * dt) * CFrame.Angles(ch.R.X * dt, ch.R.Y * dt, ch.R.Z * dt)
				end
			end
			local p = cf.Position
			local groundY = math.max(IslandShape.Height(p.X, p.Z), 0)
			if p.Y <= groundY + 2 then
				explosion(Vector3.new(p.X, groundY + 2, p.Z), false) -- impact burst / splash
				break
			end
		end
		fire.Rate, smoke.Rate = 0, 0
		for _, d in ipairs(w:GetDescendants()) do if d:IsA("BasePart") and d ~= core then d.Transparency = 1 end end
		for _, ch in ipairs(chunks) do
			local e = ch.P:FindFirstChildOfClass("ParticleEmitter"); if e then e.Rate = 0 end
			ch.P.Transparency = 1
			Debris:AddItem(ch.P, 1)
		end
		Debris:AddItem(w, 4)
	end)
end

-- your own kills: a punchy centre banner that escalates for quick multi-kills
local tMyKills: { number } = {}
local function killBanner()
	local now = os.clock()
	table.insert(tMyKills, now)
	while #tMyKills > 0 and now - tMyKills[1] > 6 do table.remove(tMyKills, 1) end
	local n = #tMyKills
	local text = if n >= 4 then "ACE SPLASH!" elseif n == 3 then "TRIPLE SPLASH!" elseif n == 2 then "DOUBLE SPLASH!" else "SPLASH!"
	Store.Values.sLaunchResult:set(text)
	task.delay(1.6, function()
		local Fusion = require(ReplicatedStorage.Packages.fusion)
		if Fusion.peek(Store.Values.sLaunchResult) == text then Store.Values.sLaunchResult:set("") end
	end)
	pcall(function() (require(script.Parent.CameraController) :: any):Kick(0.55 + 0.15 * math.min(n, 3)) end)
end

local function toast(text: string, color: Color3?)
	local Fusion = require(ReplicatedStorage.Packages.fusion)
	local t = table.clone(Fusion.peek(Store.Values.tToasts) :: any)
	table.insert(t, 1, { Text = text, Color = color, T = os.clock() })
	while #t > 4 do table.remove(t) end
	Store.Values.tToasts:set(t)
end
Vfx.Toast = function(_self, text: string, color: Color3?) toast(text, color) end

function Vfx.StartAsync(self)
	Flight = require(script.Parent.FlightController)
	Input = require(script.Parent.InputController)
	oFx = Instance.new("Folder")
	oFx.Name = "AS_Fx"
	oFx.Parent = Workspace

	local missiles = Workspace:WaitForChild("Missiles", 30)
	if missiles then
		missiles.ChildAdded:Connect(onMissile)
		for _, c in ipairs(missiles:GetChildren()) do onMissile(c) end
	end
	RunService.RenderStepped:Connect(stepProxies)

	Remote:GetEvent("CombatEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Boom" then
			explosion(t.pos, t.hit)
		elseif t.a == "Kill" then
			explosion(t.pos, true)
			-- the downed aircraft falls out of the sky (clone it before the server removes it)
			if typeof(t.model) == "string" then
				local src = Workspace.Jets:FindFirstChild(t.model) or (Workspace:FindFirstChild("NPC") and Workspace.NPC:FindFirstChild(t.model))
				local ship = src and src:GetAttribute("NpcKind") == "Destroyer"
				if src and src:IsA("Model") and not ship then wreck(src, if typeof(t.vel) == "Vector3" then t.vel else Vector3.zero) end
			end
			local mine = t.killerId == LocalPlayer.UserId
			if mine then killBanner() end
			local me = t.victimId == LocalPlayer.UserId
			local line = if t.killer ~= "" then `{t.killer}  ▸  {t.victim}  [{t.weapon}]` else `{t.victim}  [{t.weapon}]`
			toast(line, if mine then Color3.fromRGB(255, 194, 61) elseif me then Color3.fromRGB(255, 75, 62) else nil)
			if me then
				Store.Values.tKillCard:set({ Killer = t.killer, Weapon = t.weapon, KillerId = t.killerId })
			end
		elseif t.a == "Flares" then
			local jet = Workspace.Jets:FindFirstChild(tostring(t.owner))
			local back = if jet and jet.PrimaryPart then -jet.PrimaryPart.CFrame.LookVector else Vector3.zAxis
			flares(t.pos, back)
		elseif t.a == "Evade" then
			Store.Values.sLaunchResult:set(if t.ace then "ACE EVADE!" else "MISSILE DEFEATED")
			task.delay(1.4, function() Store.Values.sLaunchResult:set("") end)
		elseif t.a == "Flak" then
			-- dark flak burst
			local a = Instance.new("Part")
			a.Anchored, a.CanCollide, a.CanQuery, a.Transparency, a.Size, a.Position = true, false, false, 1, Vector3.one, t.pos
			a.Parent = oFx
			local pe = smokeEmitter(a, Color3.fromRGB(28, 26, 26), 0, 1.8, 7)
			pe.Speed = NumberRange.new(4, 14)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe:Emit(14)
			local fire = Instance.new("PointLight")
			fire.Color, fire.Range, fire.Brightness = Color3.fromRGB(255, 140, 60), 30, 5
			fire.Parent = a
			task.delay(0.12, function() fire:Destroy() end)
			Debris:AddItem(a, 3)
			Vfx.Boom:Fire(t.pos, false)
		elseif t.a == "NpcFire" then
			-- tail-gunner tracer
			local dir = (t.to - t.from)
			local tr = Instance.new("Part")
			tr.Anchored = true
			tr.CanCollide = false
			tr.CanQuery = false
			tr.CastShadow = false
			tr.Material = Enum.Material.Neon
			tr.Color = Color3.fromRGB(255, 90, 60)
			tr.Size = Vector3.new(0.3, 0.3, 14)
			tr.CFrame = CFrame.lookAt(t.from, t.to)
			tr.Parent = oFx
			local born = os.clock()
			local len = dir.Magnitude
			task.spawn(function()
				while os.clock() - born < len / 900 do
					local dt = RunService.Heartbeat:Wait()
					tr.CFrame += dir.Unit * 900 * dt
				end
				tr:Destroy()
			end)
		end
	end)

	Flight.Crashed.Event:Connect(function()
		local jet = Flight.Jet
		if jet and jet.PrimaryPart then explosion(jet.PrimaryPart.Position, true) end
	end)
end

return Vfx
