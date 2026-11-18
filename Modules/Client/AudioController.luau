--!strict
--[[
    AudioController
    ---------------
    AeroStrike's audio is a headline feature: every moment of tension and
    excitement has a layered, readable sound (GDD §27).

    THREAT INTENSITY (prey):
      Locked   -> slow warning beeps + low tension drone + "Warning, enemy lock!"
      Inbound  -> siren tempo and volume rise as the missile closes, heartbeat
                  and G-breathing swell, the rest of the mix is ducked and
                  low-passed ("tunnel vision"), "Missile! Break right!"
      Evaded   -> relief whoosh, mix opens up, "Missile defeated!"
    THRUST:   afterburner ignition whump + roar + sub-bass rumble, wind rush
              scaling with speed, sonic boom past ~Mach 1, close flybys.
    WEAPONS:  cannon loop with spin-down tail, missile = rail thump + launch
              roar + "Fox two!", kills = explosion + stinger + "Splash one!"
    G-FORCE:  strained breathing and airframe groan when over tolerance.
    MIX:      a compressor on the SFX bus for punch; threat bus never ducked.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local AudioConfig = require(ReplicatedStorage.Config.AudioConfig)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Fusion = require(ReplicatedStorage.Packages.fusion)
local peek = Fusion.peek

local LocalPlayer = Players.LocalPlayer
local Audio = ModuleUtil.New({
	Intensity = 0, -- 0..1 threat intensity (other systems may read it, e.g. camera)
})

local Flight, Weapons, Input, Vfx
local oSfx: SoundGroup -- world, engines, weapons (duckable)
local oThreat: SoundGroup -- warnings, heartbeat, VO (never ducked)
local oEq: EqualizerSoundEffect
local tLoops: { [string]: Sound } = {}
local tRemoteEngines: { [Model]: Sound } = {}
local tFlybyCooldown: { [Model]: number } = {}
local tVOLast: { [string]: number } = {}
local nLastBoom = 0
local bWasFast = false
local bWasBoost = false
local bWasFiring = false
local sLastThreat = "None"
local nLastGroan = 0
local nIntensity = 0

local function apply(s: Sound, def: AudioConfig.SoundDef)
	s.SoundId = "rbxassetid://" .. tostring(def.Id)
	s.Volume = def.Volume or 0.6
	s.Looped = def.Looped == true
	s.PlaybackSpeed = def.Speed or 1
	if def.Region then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(def.Region[1], def.Region[2])
		if s.Looped then s.LoopRegion = NumberRange.new(def.Region[1], def.Region[2]) end
	end
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = def.MinDist or 40
	s.RollOffMaxDistance = def.MaxDist or 1500
end

local function make(sKey: string, parent: Instance, group: SoundGroup?): Sound
	local s = Instance.new("Sound")
	s.Name = sKey
	apply(s, AudioConfig.Sounds[sKey])
	s.SoundGroup = group or oSfx
	s.Parent = parent
	return s
end

local function oneShot(sKey: string, opts: { At: Vector3?, Pitch: number?, Volume: number?, Threat: boolean? }?)
	local def = AudioConfig.Sounds[sKey]
	if not def or def.Id == 0 then return end
	local o = opts or {}
	local parent: Instance = SoundService
	local holder: BasePart? = nil
	if o.At then
		holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one
		holder.Position = o.At
		holder.Parent = Workspace
		parent = holder
	end
	local s = make(sKey, parent, if o.Threat then oThreat else oSfx)
	if o.Pitch then s.PlaybackSpeed *= o.Pitch end
	if o.Volume then s.Volume *= o.Volume end
	s:Play()
	local life = (if def.Region then def.Region[2] - def.Region[1] else def.Length or 6) / s.PlaybackSpeed + 0.5
	task.delay(life, function()
		s:Destroy()
		if holder then holder:Destroy() end
	end)
end

local function vo(sKey: string)
	local cd = AudioConfig.VOCooldown[sKey] or 4
	if os.clock() - (tVOLast[sKey] or -100) < cd then return end
	tVOLast[sKey] = os.clock()
	oneShot(sKey, { Threat = true })
end

local function loopSound(sKey: string, group: SoundGroup?): Sound
	local s = tLoops[sKey]
	if not s then
		s = make(sKey, SoundService, group)
		tLoops[sKey] = s
	end
	return s
end

-- Fade a loop toward a target volume/speed; plays/stops automatically.
local function drive(sKey: string, targetVol: number, dt: number, speed: number?, group: SoundGroup?, rate: number?)
	local s = loopSound(sKey, group)
	local r = math.clamp(dt * (rate or 6), 0, 1)
	s.Volume += (targetVol - s.Volume) * r
	if speed then s.PlaybackSpeed += (speed - s.PlaybackSpeed) * r end
	if targetVol > 0.005 or s.Volume > 0.01 then
		if not s.IsPlaying then s:Play() end
	elseif s.IsPlaying then
		s:Stop()
	end
end

local function nearestIncoming(jet: Model): number?
	local folder = Workspace:FindFirstChild("Missiles")
	if not folder or not jet.PrimaryPart then return nil end
	local best: number? = nil
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("BasePart") and m:GetAttribute("Target") == jet.Name then
			local d = (m.Position - jet.PrimaryPart.Position).Magnitude
			if not best or d < best then best = d end
		end
	end
	return best
end

local function step(dt: number)
	local phase = Flight.Phase
	local st = Flight.State
	local stats = Flight.Stats
	local jet = Flight.Jet
	local flying = (phase == "Flying" or phase == "Catapult") and st ~= nil and stats ~= nil

	-- ===== THRUST =====
	if flying and st and stats then
		local f = math.clamp(st.Speed / stats.MaxSpeed, 0, 1.2)
		local boost = Input.State.Boost or st.FreeBoost > 0
		drive("EngineCruise", 0.22 + 0.22 * f, dt, 0.85 + 0.35 * f)
		drive("Afterburner", if boost then 0.8 else 0, dt, 0.95 + 0.15 * f, nil, if boost then 10 else 4)
		drive("SubRumble", (if boost then 0.75 else 0.2) * (0.5 + 0.5 * f), dt, 1, nil, 5)
		drive("WindRush", 0.05 + 0.45 * f * f, dt, 0.9 + 0.25 * f)
		if boost and not bWasBoost then
			oneShot("AfterburnerIgnite")
		end
		bWasBoost = boost
		local fast = st.Speed * 3.6 >= AudioConfig.SonicBoomKmh
		if fast and not bWasFast and os.clock() - nLastBoom > 8 then
			nLastBoom = os.clock()
			oneShot("SonicBoom")
			Store.Values.sLaunchResult:set("SONIC BOOM")
			task.delay(1, function() if peek(Store.Values.sLaunchResult) == "SONIC BOOM" then Store.Values.sLaunchResult:set("") end end)
		end
		bWasFast = fast
	else
		for _, k in ipairs({ "EngineCruise", "Afterburner", "SubRumble", "WindRush" }) do drive(k, 0, dt, nil, nil, 8) end
		bWasBoost, bWasFast = false, false
	end

	-- ===== HUNTER =====
	local lock = peek(Store.Values.sLockState)
	drive("LockSeek", if flying and lock == "Seeking" then 0.4 else 0, dt, nil, oThreat, 20)
	drive("LockTone", if flying and lock == "Locked" then 0.5 else 0, dt, nil, oThreat, 20)

	-- ===== CANNON =====
	local firing = flying and Input.State.Guns and peek(Store.Values.nGunHeat) < 0.999
	drive("Cannon", if firing then 0.85 else 0, dt, nil, nil, 30)
	if bWasFiring and not firing then oneShot("CannonSpindown") end
	bWasFiring = firing

	-- ===== PREY / TENSION =====
	local threat = if flying then peek(Store.Values.sThreat) else "None"
	local target = 0
	local closeness = 0
	if threat == "Inbound" and jet then
		local d = nearestIncoming(jet)
		closeness = if d then 1 - math.clamp(d / AudioConfig.MissileDangerRange, 0, 1) else 0.5
		target = 0.55 + 0.45 * closeness
		if sLastThreat ~= "Inbound" then vo("VO_MissileBreak") end
	elseif threat == "Locked" then
		target = 0.3
		if sLastThreat == "None" then vo("VO_EnemyLock") end
	end
	sLastThreat = threat
	nIntensity += (target - nIntensity) * math.clamp(dt * (if target > nIntensity then 8 else 2.5), 0, 1)
	Audio.Intensity = nIntensity

	drive("MissileWarning", if threat == "Inbound" then 0.65 + 0.35 * closeness else 0, dt, 0.9 + 0.8 * closeness, oThreat, 25)
	drive("LockedWarning", if threat == "Locked" then 0.45 else 0, dt, 0.55, oThreat, 20)
	drive("TensionDrone", nIntensity * 0.55, dt, 0.95 + 0.15 * nIntensity, oThreat, 3)
	drive("Heartbeat", math.max(0, nIntensity - 0.25) * 1.1, dt, 0.9 + 0.5 * closeness, oThreat, 4)

	-- G strain (also part of tension)
	local g = if st then st.G else 1
	local tol = if stats then stats.GTolerance else 6
	local over = if flying then math.clamp((g - tol) / 3, 0, 1) else 0
	drive("GBreath", math.max(over * 0.7, nIntensity * 0.35), dt, 1, oThreat, 5)
	if over > 0.6 and os.clock() - nLastGroan > 7 then
		nLastGroan = os.clock()
		oneShot("AirframeGroan", { Volume = 0.6 + 0.4 * over })
	end

	-- tunnel-vision mix: duck + low-pass the world while a missile is inbound
	oSfx.Volume = 1 - 0.45 * nIntensity
	oEq.HighGain = -20 * nIntensity
	oEq.MidGain = -6 * nIntensity

	-- ===== WORLD: other jets' engines + flybys =====
	local myPos = if jet and jet.PrimaryPart then jet.PrimaryPart.Position else nil
	for _, m in ipairs(Workspace.Jets:GetChildren()) do
		if m:IsA("Model") and m.Name ~= tostring(LocalPlayer.UserId) and m.PrimaryPart then
			if not tRemoteEngines[m] then
				local s = make("EngineCruise", m.PrimaryPart)
				s.Volume = 0.6
				s.RollOffMaxDistance = 900
				s:Play()
				tRemoteEngines[m] = s
			end
			if myPos and flying then
				local d = (m.PrimaryPart.Position - myPos).Magnitude
				if d < 140 and os.clock() - (tFlybyCooldown[m] or 0) > 4 then
					tFlybyCooldown[m] = os.clock()
					oneShot("Flyby", { At = m.PrimaryPart.Position })
				end
			end
		end
	end
	for m in pairs(tRemoteEngines) do
		if not m.Parent then
			tRemoteEngines[m] = nil
			tFlybyCooldown[m] = nil
		end
	end
end

function Audio.StartAsync(self)
	Flight = require(script.Parent.FlightController)
	Weapons = require(script.Parent.WeaponsController)
	Input = require(script.Parent.InputController)
	Vfx = require(script.Parent.VfxController)

	oSfx = Instance.new("SoundGroup")
	oSfx.Name = "AS_SFX"
	oSfx.Parent = SoundService
	local comp = Instance.new("CompressorSoundEffect")
	comp.Threshold = -18
	comp.Ratio = 4
	comp.Attack = 0.01
	comp.Release = 0.2
	comp.GainMakeup = 4
	comp.Parent = oSfx
	oEq = Instance.new("EqualizerSoundEffect")
	oEq.HighGain = 0
	oEq.MidGain = 0
	oEq.LowGain = 0
	oEq.Priority = 1
	oEq.Parent = oSfx

	oThreat = Instance.new("SoundGroup")
	oThreat.Name = "AS_Threat"
	oThreat.Parent = SoundService

	Flight.Changed:Connect(function(phase: string)
		if phase == "Catapult" then
			oneShot("Catapult")
		elseif phase == "Deck" then
			vo("VO_CatapultArmed")
		end
	end)
	Weapons.Fired.Event:Connect(function(kind: string)
		if kind == "Missile" then
			oneShot("MissileThump")
			oneShot("MissileLaunch")
			vo("VO_FoxTwo")
		elseif kind == "Flare" then
			oneShot("Flares")
		elseif kind == "NoLock" then
			oneShot("HitTicks", { Pitch = 0.55, Volume = 0.6 })
		end
	end)
	Vfx.Boom.Event:Connect(function(pos: Vector3, big: boolean)
		oneShot("Explosion", { At = pos, Pitch = if big then 1 else 1.25 })
	end)
	Remote:GetEvent("CombatEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Hit" then
			oneShot("HitTicks", { Pitch = 1 + math.random() * 0.15 })
		elseif t.a == "Flares" and t.owner ~= LocalPlayer.UserId then
			oneShot("Flares", { At = t.pos })
		elseif t.a == "Evade" then
			oneShot("EvadeWhoosh", { Threat = true })
			vo("VO_MissileDefeated")
		elseif t.a == "Kill" and t.killerId == LocalPlayer.UserId then
			oneShot("KillStinger", { Threat = true })
			vo("VO_SplashOne")
		elseif t.a == "Boom" and t.hit and Flight.Jet and Flight.Jet.PrimaryPart
			and (t.pos - Flight.Jet.PrimaryPart.Position).Magnitude < 40 then
			oneShot("AirframeGroan", { Pitch = 1.2 }) -- we got hit
		end
	end)
	Remote:GetEvent("EconomyEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if (t.a == "Toast" and (t.cash or 0) > 0) or t.a == "Banked" or t.a == "RankUp" then
			oneShot("Reward", { Pitch = if t.a == "RankUp" then 0.85 else 1 })
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return Audio
