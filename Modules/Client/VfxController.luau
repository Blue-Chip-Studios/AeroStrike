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

local function smokeEmitter(parent: Instance, color: Color3, rate: number, life: number, size: number)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
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
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 80, 20))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if big then 14 else 6), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.4, 0.9)
	fire.Speed = NumberRange.new(20, if big then 70 else 35)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Rate = 0
	fire.Parent = a
	fire:Emit(if big then 60 else 25)
	local smoke = smokeEmitter(a, Color3.fromRGB(40, 40, 44), 0, 3, if big then 12 else 6)
	smoke.Speed = NumberRange.new(5, 20)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke:Emit(if big then 30 else 12)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = if big then 60 else 30
	light.Brightness = 6
	light.Parent = a
	task.delay(0.25, function() light:Destroy() end)
	Debris:AddItem(a, 4)
	Vfx.Boom:Fire(pos, big)
end

local function flares(pos: Vector3, back: Vector3)
	for i = 1, 4 do
		local f = Instance.new("Part")
		f.Shape = Enum.PartType.Ball
		f.Size = Vector3.one * 1.6
		f.Material = Enum.Material.Neon
		f.Color = Color3.fromRGB(255, 230, 170)
		f.CanCollide = false
		f.CanQuery = false
		f.Anchored = true
		f.Position = pos
		f.Parent = oFx
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 200, 120)
		pl.Range = 25
		pl.Brightness = 4
		pl.Parent = f
		smokeEmitter(f, Color3.fromRGB(235, 235, 240), 40, 2.2, 2)
		local side = (i - 2.5) * 0.6
		local vel = back * 60 + Vector3.new(side * 40, -10 - i * 6, side * 30)
		local born = os.clock()
		task.spawn(function()
			while os.clock() - born < 3 do
				local dt = RunService.Heartbeat:Wait()
				vel += Vector3.new(0, -30 * dt, 0)
				f.Position += vel * dt
			end
			f.Transparency = 1
			Debris:AddItem(f, 2.5)
		end)
	end
end

-- Missile parts are server-anchored and replicate in steps; render a smooth
-- local proxy with a smoke trail that eases toward the real position.
local tProxies: { [BasePart]: BasePart } = {}
local function onMissile(p: Instance)
	if not p:IsA("BasePart") then return end
	p.LocalTransparencyModifier = 1
	local proxy = Instance.new("Part")
	proxy.Size = Vector3.new(0.5, 0.5, 3.6)
	proxy.Color = Color3.fromRGB(230, 232, 236)
	proxy.Material = Enum.Material.SmoothPlastic
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CFrame = p.CFrame
	proxy.Parent = oFx
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, 1.8)
	a0.Parent = proxy
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 90)
	glow.Range = 12
	glow.Parent = proxy
	smokeEmitter(a0, Color3.fromRGB(220, 220, 225), 60, 2.6, 2.4)
	tProxies[p] = proxy
end

local function stepProxies(dt: number)
	for real, proxy in pairs(tProxies) do
		if not real.Parent then
			tProxies[real] = nil
			proxy.Transparency = 1
			local pe = proxy:FindFirstChildWhichIsA("Attachment")
			if pe then
				local em = pe:FindFirstChildWhichIsA("ParticleEmitter")
				if em then em.Rate = 0 end
			end
			Debris:AddItem(proxy, 3)
		else
			proxy.CFrame = proxy.CFrame:Lerp(real.CFrame + real.CFrame.LookVector * 330 * dt, math.clamp(dt * 12, 0, 1))
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
			local mine = t.killerId == LocalPlayer.UserId
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
		elseif t.a == "Hit" then
			Store.Values.sPrompt:set("")
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
