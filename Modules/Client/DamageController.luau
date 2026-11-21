--!strict
--[[
    DamageController: makes damage readable.
      * Every aircraft (players + AI) shows its condition: grey smoke trail when hurt,
        black smoke + fire when badly damaged, so you can SEE your rounds working.
      * Your own jet: HULL gauge, a red edge flash + camera jolt on every hit, and a
        HULL CRITICAL warning (with the eject prompt) when it is close to going down.
      * Gun feedback: a hit-marker flash on server-confirmed hits and a health bar under
        whatever you are shooting at / locking.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local FX = require(ReplicatedStorage.Config.VfxConfig)

local LocalPlayer = Players.LocalPlayer
local Damage = ModuleUtil.New({})

local DAMAGED, CRITICAL = 0.65, 0.35
type Rig = { Stage: number, Att: Attachment, Smoke: ParticleEmitter, Fire: ParticleEmitter, Light: PointLight }
local tRigs: { [Model]: Rig } = {}

local function rigFor(m: Model): Rig?
	local r = tRigs[m]
	if r and r.Att.Parent then return r end
	local root = m.PrimaryPart
	if not root then return nil end
	local _, size = m:GetBoundingBox()
	local scale = math.clamp(size.Magnitude / 30, 0.6, 2.5)
	local att = Instance.new("Attachment")
	att.Name = "AS_DamageFx"
	att.Position = Vector3.new(0, 0.5, size.Z * 0.15)
	att.Parent = root
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = FX.Smoke
	smoke.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	smoke.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5 * scale), NumberSequenceKeypoint.new(1, 6 * scale) })
	smoke.Transparency = NumberSequence.new(0.35, 1)
	smoke.Lifetime = NumberRange.new(1.6, 2.4)
	smoke.Speed = NumberRange.new(0, 2)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.Rate = 0
	smoke.Parent = att
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = FX.Fireball
	fire.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	fire.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	fire.LightEmission = 0.6
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4 * scale), NumberSequenceKeypoint.new(1, 2.6 * scale) })
	fire.Lifetime = NumberRange.new(0.35, 0.55)
	fire.Speed = NumberRange.new(0, 3)
	fire.Rotation = NumberRange.new(0, 360)
	fire.Rate = 0
	fire.Parent = att
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 16
	light.Brightness = 0
	light.Parent = att
	r = { Stage = -1, Att = att, Smoke = smoke, Fire = fire, Light = light }
	tRigs[m] = r
	return r
end

local function setStage(r: Rig, stage: number)
	if r.Stage == stage then return end
	r.Stage = stage
	if stage == 0 then
		r.Smoke.Rate, r.Fire.Rate, r.Light.Brightness = 0, 0, 0
	elseif stage == 1 then
		r.Smoke.Color = ColorSequence.new(Color3.fromRGB(150, 150, 155))
		r.Smoke.Rate, r.Fire.Rate, r.Light.Brightness = 22, 0, 0
	else
		r.Smoke.Color = ColorSequence.new(Color3.fromRGB(30, 28, 30))
		r.Smoke.Rate, r.Fire.Rate, r.Light.Brightness = 34, 28, 2.5
	end
end

local nLastOwnHp: number? = nil
local nHurt = 0
local nHitStamp = 0

function Damage.StartAsync(self)
	local Flight = require(script.Parent.FlightController) :: any
	local Weapons = require(script.Parent.WeaponsController) :: any

	-- server-confirmed hits: hit-marker flash
	Remote:GetEvent("CombatEvent"):OnClientEvent(function(t: any)
		if typeof(t) == "table" and t.a == "Hit" then
			Store.Values.bHitMarker:set(true)
			local stamp = os.clock()
			nHitStamp = stamp
			task.delay(0.14, function() if nHitStamp == stamp then Store.Values.bHitMarker:set(false) end end)
		end
	end)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt: number)
		-- condition effects on every aircraft (4x a second is plenty)
		acc += dt
		if acc > 0.25 then
			acc = 0
			for _, folder in ipairs({ Workspace:FindFirstChild("Jets"), Workspace:FindFirstChild("NPC") }) do
				if folder then
					for _, m in ipairs(folder:GetChildren()) do
						if m:IsA("Model") and not m:GetAttribute("Friendly") then
							local hp, max = m:GetAttribute("Health") :: number?, m:GetAttribute("MaxHealth") :: number?
							if hp and max and max > 0 then
								local f = hp / max
								local stage = if f <= CRITICAL then 2 elseif f <= DAMAGED then 1 else 0
								if stage > 0 or tRigs[m] then
									local r = rigFor(m)
									if r then setStage(r, stage) end
								end
							end
						end
					end
				end
			end
			for m in pairs(tRigs) do if not m.Parent then tRigs[m] = nil end end
		end

		-- own hull: gauge, hurt flash, critical warning
		local jet = Flight.Jet
		local hp = jet and jet:GetAttribute("Health") :: number?
		local max = jet and jet:GetAttribute("MaxHealth") :: number?
		if Flight.Phase == "Flying" and hp and max and max > 0 then
			local f = hp / max
			Store.Values.nHull:set(f)
			Store.Values.bHullCritical:set(f <= CRITICAL)
			Store.Values.bRookieJet:set(jet:GetAttribute("Rookie") == true)
			if nLastOwnHp and hp < nLastOwnHp - 0.5 then
				nHurt = math.min(1, nHurt + 0.35 + (nLastOwnHp - hp) / max)
				pcall(function() (require(script.Parent.CameraController) :: any):Kick(0.35) end)
			end
			nLastOwnHp = hp
		else
			nLastOwnHp = nil
			Store.Values.bHullCritical:set(false)
		end
		nHurt = math.max(0, nHurt - dt * 1.8)
		Store.Values.nHurt:set(nHurt)

		-- health bar under whatever you're shooting at / locking
		local tgt = Weapons.FocusTarget :: Model?
		local cam = Workspace.CurrentCamera
		if tgt and tgt.Parent and tgt.PrimaryPart then
			local th, tm = tgt:GetAttribute("Health") :: number?, tgt:GetAttribute("MaxHealth") :: number?
			local sp, on = cam:WorldToViewportPoint(tgt.PrimaryPart.Position)
			if th and tm and tm > 0 and on then
				Store.Values.tTargetHp:set({ Pos = Vector2.new(sp.X, sp.Y), Frac = math.clamp(th / tm, 0, 1) })
			else
				Store.Values.tTargetHp:set(false)
			end
		else
			Store.Values.tTargetHp:set(false)
		end
	end)
end

return Damage
