--!strict
--[[
    FTUEClient
    ----------
    Runs the onboarding lesson: shows one prompt at a time (device-aware),
    builds the client-local training lane (green rings + gold fuel ring from
    the Blender ring model), points the objective marker at the next goal,
    detects completion of each step from real gameplay state, and reports
    steps to the server (which validates order, saves and logs analytics).

    Teaches through doing; every step is skippable after a short time, and
    the whole lesson can be skipped from step 3.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local FTUEConfig = require(ReplicatedStorage.Config.FTUEConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local Fusion = require(ReplicatedStorage.Packages.fusion)
local peek = Fusion.peek

local LocalPlayer = Players.LocalPlayer
local FTUE = ModuleUtil.New({
	Step = 0, -- last completed step (server-confirmed)
	Done = true,
	Active = false,
})

local Flight, Input, MissionClient
local oRequest
local nStepStarted = 0
local tRings: { Model } = {}
local iRing = 1
local oFuelRing: Model? = nil
local nBoostHeld = 0
local nGunHits = 0
local nGHeld = 0
local bSamRequested = false
local nPending = 0 -- step we've reported and await confirmation for

local function deviceKey(): string
	if Input.LastDevice == "Touch" then return "Touch" end
	if Input.LastDevice == "Gamepad" then return "Pad" end
	return "Mouse"
end

local function currentIndex(): number
	return FTUE.Step + 1
end

local function setPrompt()
	if not FTUE.Active then
		Store.Values.sPrompt:set("")
		return
	end
	local s = FTUEConfig.Steps[currentIndex()]
	Store.Values.sPrompt:set(if s then s.Prompt[deviceKey() :: any] else "")
end

local function complete(n: number)
	if n ~= currentIndex() or nPending == n then return end
	nPending = n
	oRequest:FireServer({ a = "Step", step = n })
end

local function carrierCF(): CFrame
	return MapConfig.Carrier.CFrame
end

local function clearLane()
	for _, r in ipairs(tRings) do r:Destroy() end
	table.clear(tRings)
	if oFuelRing then oFuelRing:Destroy() oFuelRing = nil end
end

local function placeRing(pos: Vector3, dir: Vector3, gold: boolean): Model?
	local ct = ReplicatedStorage:FindFirstChild("ClientTemplates")
	local tmpl = ct and ct:FindFirstChild("Ring") :: Model?
	if not tmpl then return nil end
	local r = tmpl:Clone()
	r:PivotTo(CFrame.lookAt(pos, pos + dir))
	if gold then
		for _, d in ipairs(r:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Glow" then d.Color = Color3.fromRGB(255, 194, 61) end
		end
	end
	r.Parent = Workspace
	return r
end

local function buildLane()
	clearLane()
	local cf = carrierCF()
	local fwd = cf.LookVector
	for _, off in ipairs(FTUEConfig.Rings) do
		local r = placeRing((cf * CFrame.new(off)).Position, fwd, false)
		if r then table.insert(tRings, r) end
	end
	iRing = 1
end

local function trainingDronePos(): Vector3?
	local npc = Workspace:FindFirstChild("NPC")
	if not npc then return nil end
	local best: Vector3? = nil
	local bestD = math.huge
	local jet = Flight.Jet
	local from = if jet and jet.PrimaryPart then jet.PrimaryPart.Position else carrierCF().Position
	for _, m in ipairs(npc:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("NpcKind") == "Drone" and m.PrimaryPart then
			local d = (m.PrimaryPart.Position - from).Magnitude
			if d < bestD then best, bestD = m.PrimaryPart.Position, d end
		end
	end
	return best
end

local function step(dt: number)
	if not FTUE.Active then
		MissionClient.Override = nil
		return
	end
	local idx = currentIndex()
	local id = FTUEConfig.Steps[idx] and FTUEConfig.Steps[idx].Id
	local phase = Flight.Phase
	local jet = Flight.Jet
	local st = Flight.State
	local pos = if jet and jet.PrimaryPart then jet.PrimaryPart.Position else nil

	if id == "spawned_on_catapult" then
		if phase == "Deck" or phase == "Launching" or phase == "Catapult" or phase == "Flying" then complete(idx) end
	elseif id == "launched" then
		MissionClient.Override = nil
		if phase == "Flying" then complete(idx) end
	elseif id == "steer_rings" then
		if #tRings == 0 and phase == "Flying" then buildLane() end
		local r = tRings[iRing]
		if r then
			local c = r:GetPivot().Position
			MissionClient.Override = c
			if pos and (pos - c).Magnitude < FTUEConfig.RingRadius then
				r:Destroy()
				iRing += 1
				Store.Values.sLaunchResult:set(`RING {iRing - 1}/{#FTUEConfig.Rings}`)
				task.delay(0.8, function() Store.Values.sLaunchResult:set("") end)
			end
		elseif #tRings > 0 then
			table.clear(tRings)
			complete(idx)
		end
	elseif id == "afterburner" then
		if Input.State.Boost then nBoostHeld += dt end
		if nBoostHeld >= FTUEConfig.BoostHoldTime and not oFuelRing then
			local cf = carrierCF()
			-- place the gold ring ahead of the pilot, not at a fixed spot they may have passed
			local ahead = if jet and jet.PrimaryPart then jet.PrimaryPart.Position + jet.PrimaryPart.CFrame.LookVector * 700 else (cf * CFrame.new(FTUEConfig.FuelRing)).Position
			local dir = if jet and jet.PrimaryPart then jet.PrimaryPart.CFrame.LookVector else cf.LookVector
			oFuelRing = placeRing(Vector3.new(ahead.X, math.max(ahead.Y, 150), ahead.Z), dir, true)
		end
		if oFuelRing then
			local c = oFuelRing:GetPivot().Position
			MissionClient.Override = c
			if pos and (pos - c).Magnitude < FTUEConfig.RingRadius * 1.3 then
				oFuelRing:Destroy()
				oFuelRing = nil
				Flight:Refuel()
				Store.Values.sLaunchResult:set("REFUELLED")
				task.delay(1, function() Store.Values.sLaunchResult:set("") end)
				complete(idx)
			end
		end
	elseif id == "guns" then
		MissionClient.Override = trainingDronePos()
		if nGunHits >= FTUEConfig.GunHitsNeeded then complete(idx) end
	elseif id == "lock_and_fire" then
		MissionClient.Override = trainingDronePos()
		-- completed by a missile kill (see CombatEvent handler)
	elseif id == "flare" then
		MissionClient.Override = nil
		if not bSamRequested and phase == "Flying" and os.clock() - nStepStarted > FTUEConfig.TrainingSamDelay then
			bSamRequested = true
			oRequest:FireServer({ a = "Sam" })
			task.delay(8, function()
				-- missed it? fire another
				if FTUE.Active and FTUEConfig.Steps[currentIndex()].Id == "flare" then bSamRequested = false end
			end)
		end
	elseif id == "pull_g" then
		if st and st.G >= FTUEConfig.GTarget then nGHeld += dt else nGHeld = math.max(0, nGHeld - dt * 0.5) end
		if nGHeld >= FTUEConfig.GHoldTime then complete(idx) end
	elseif id == "bank_it" then
		local deck = (carrierCF() * CFrame.new(0, MapConfig.Carrier.DeckY + 8, 0)).Position
		MissionClient.Override = deck
		-- completed by TouchAndGo (FlightEvent)
	elseif id == "first_upgrade" then
		MissionClient.Override = nil
		if os.clock() - nStepStarted > 2.5 then complete(idx) end
	elseif id == "go_live" then
		MissionClient.Override = nil
		if os.clock() - nStepStarted > 3 then complete(idx) end
	end
end

local function onState(t: any)
	FTUE.Step = t.step or 0
	FTUE.Done = t.done == true
	FTUE.Active = not FTUE.Done
	nPending = 0
	nStepStarted = os.clock()
	nBoostHeld, nGunHits, nGHeld, bSamRequested = 0, 0, 0, false
	if FTUE.Done then
		clearLane()
		MissionClient.Override = nil
	end
	Store.Values.bFTUESkippable:set(FTUE.Active and FTUE.Step >= 2 and FTUE.Step < 10)
	Store.Values.bFTUEActive:set(FTUE.Active and FTUE.Step < 10)
	setPrompt()
end

function FTUE.Skip(self)
	oRequest:FireServer({ a = "Skip" })
end

function FTUE.StartAsync(self)
	Flight = require(script.Parent.FlightController)
	Input = require(script.Parent.InputController)
	MissionClient = require(script.Parent.MissionClient)
	oRequest = Remote:GetEvent("FTUERequest")

	Remote:GetEvent("FTUEEvent"):OnClientEvent(function(t: any)
		if typeof(t) == "table" and t.a == "State" then onState(t) end
	end)
	Remote:GetEvent("CombatEvent"):OnClientEvent(function(t: any)
		if not FTUE.Active or typeof(t) ~= "table" then return end
		local id = FTUEConfig.Steps[currentIndex()] and FTUEConfig.Steps[currentIndex()].Id
		if t.a == "Hit" and id == "guns" then
			nGunHits += 1
		elseif t.a == "Kill" and t.killerId == LocalPlayer.UserId then
			if id == "guns" then nGunHits = FTUEConfig.GunHitsNeeded end
			if id == "lock_and_fire" and string.find(t.weapon or "", "Missile") then complete(currentIndex()) end
		elseif t.a == "Evade" and id == "flare" then
			complete(currentIndex())
		end
	end)
	Remote:GetEvent("FlightEvent"):OnClientEvent(function(t: any)
		if FTUE.Active and typeof(t) == "table" and t.a == "TouchAndGo" then
			local id = FTUEConfig.Steps[currentIndex()] and FTUEConfig.Steps[currentIndex()].Id
			if id == "bank_it" then complete(currentIndex()) end
		end
	end)
	-- keep prompt text matched to the device in use
	Flight.Changed:Connect(function() setPrompt() end)
	RunService.Heartbeat:Connect(step)
end

return FTUE
