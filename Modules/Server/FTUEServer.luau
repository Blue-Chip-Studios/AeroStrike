--!strict
--[[
    FTUEServer
    ----------
    Server half of onboarding: persists progress (profile FTUE.Step / Done /
    Skipped), logs every step to the onboarding funnel, protects pilots in
    training (spawn shield stays on until "go_live"), fires the harmless
    training SAM for the flare lesson, and grants the one-time free upgrade.

    C->S FTUERequest { a="Step", step=n } | { a="Skip" } | { a="Sam" }
    S->C FTUEEvent   { a="State", step, done }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local FTUEConfig = require(ReplicatedStorage.Config.FTUEConfig)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)

local FTUE = ModuleUtil.New({})
local oEvent = Remote:GetEvent("FTUEEvent")
local oRequest = Remote:GetEvent("FTUERequest")
local oLimiter = ModuleUtil.RateLimiter(10, 3)
local tLastSam: { [Player]: number } = {}

local Economy: any, Analytics: any, Flight: any, Combat: any

local GO_LIVE = 11
local FINAL = #FTUEConfig.Steps

function FTUE.IsTraining(self, oPlayer: Player): boolean
	local f = mProfile:GetAsync(oPlayer, "FTUE")
	return f ~= nil and not f.Done and not f.Skipped and (f.Step or 0) < GO_LIVE
end

local function setStep(oPlayer: Player, n: number, bSkipped: boolean?)
	Economy:SetProfileKey(oPlayer, "FTUE", function(f)
		f = f or { Step = 0, Done = false, Skipped = false }
		if bSkipped then
			f.Skipped = true
			f.Done = true
		elseif n > (f.Step or 0) then
			f.Step = n
			if n >= FINAL then f.Done = true end
		end
		return f
	end)
end

local function onStep(oPlayer: Player, n: number)
	local f = mProfile:GetAsync(oPlayer, "FTUE")
	if not f or f.Done then return end
	-- steps must advance one at a time (no jumping to rewards)
	if n ~= (f.Step or 0) + 1 then return end
	setStep(oPlayer, n)
	local id = FTUEConfig.Steps[n].Id
	Analytics:Log(oPlayer, "ftue_" .. id)
	if id == "first_upgrade" then
		-- one-time free Flare Pod level on the equipped jet
		local jet = mProfile:GetAsync(oPlayer, "EquippedJet") or "SparrowT2"
		Economy:SetProfileKey(oPlayer, "Upgrades", function(u)
			u = u or {}
			u[jet] = u[jet] or {}
			u[jet].Flares = math.max(u[jet].Flares or 0, 1)
			return u
		end)
		Economy:Reward(oPlayer, "DroneTraining", { Bank = true, Label = "FREE UPGRADE: +1 FLARE POD" })
	elseif id == "go_live" then
		local s = Flight:GetSortie(oPlayer)
		if s and s.Jet.Parent then
			task.delay(3, function()
				if s.Jet.Parent then
					s.Jet:SetAttribute("Training", nil)
					s.Jet:SetAttribute("Shield", false)
				end
			end)
		end
	end
	oEvent:FireClient(oPlayer, { a = "State", step = n, done = n >= FINAL })
end

function FTUE.StartAsync(self)
	Economy = require(ServerStorage.ServerModules.EconomyServer)
	Analytics = require(ServerStorage.ServerModules.AnalyticsServer)
	Flight = require(ServerStorage.ServerModules.FlightServer)
	Combat = require(ServerStorage.ServerModules.CombatServer)

	oRequest:OnServerEvent(function(oPlayer: Player, t: any)
		if typeof(t) ~= "table" or not oLimiter:Check(oPlayer) then return end
		if t.a == "Step" and typeof(t.step) == "number" then
			onStep(oPlayer, math.floor(t.step))
		elseif t.a == "Skip" then
			local f = mProfile:GetAsync(oPlayer, "FTUE")
			if f and not f.Done and (f.Step or 0) >= 2 then
				setStep(oPlayer, f.Step, true)
				Analytics:Log(oPlayer, "ftue_skip", { at = f.Step })
				local s = Flight:GetSortie(oPlayer)
				if s and s.Jet.Parent then
					s.Jet:SetAttribute("Training", nil)
					s.Jet:SetAttribute("Shield", false)
				end
				oEvent:FireClient(oPlayer, { a = "State", step = f.Step, done = true })
			end
		elseif t.a == "Sam" then
			-- harmless training SAM for the flare lesson (0 damage)
			local f = mProfile:GetAsync(oPlayer, "FTUE")
			if not f or f.Done or (f.Step or 0) ~= 6 then return end
			if os.clock() - (tLastSam[oPlayer] or 0) < 6 then return end
			tLastSam[oPlayer] = os.clock()
			local s = Flight:GetSortie(oPlayer)
			if s and s.Phase == "Flying" and s.Jet.PrimaryPart then
				local cf = s.Jet.PrimaryPart.CFrame
				local p = cf.Position - cf.LookVector * FTUEConfig.TrainingSamDistance
				p = Vector3.new(p.X, math.max(cf.Position.Y - 120, 60), p.Z) -- never spawn under the sea
				local from = CFrame.lookAt(p, cf.Position)
				Combat:FireMissileAt(nil, from, s.Jet, 0)
			end
		end
	end)

	-- keep training pilots shielded through the lesson (no griefing), but not forever: after
	-- TrainingShieldMax seconds of flight, or the moment they attack a real enemy, they're live
	local function dropShield(jet: Model)
		if jet.Parent and jet:GetAttribute("Training") then
			jet:SetAttribute("Training", nil)
			jet:SetAttribute("Shield", false)
		end
	end
	Flight.OnLaunched.Event:Connect(function(oPlayer: Player)
		if self:IsTraining(oPlayer) then
			local s = Flight:GetSortie(oPlayer)
			if s and s.Jet.Parent then
				local jet = s.Jet
				jet:SetAttribute("Training", true)
				jet:SetAttribute("Shield", true)
				task.delay(FTUEConfig.TrainingShieldMax, function() dropShield(jet) end)
			end
		end
	end)
	Combat.OnDamage.Event:Connect(function(attacker: Player?, victim: Model)
		if not attacker or victim:GetAttribute("MissionTag") == "Training" or not victim:GetAttribute("NpcKind") then return end
		local s = Flight:GetSortie(attacker)
		if s and s.Jet then dropShield(s.Jet) end
	end)

	-- first kill / mission completes the FTUE
	Combat.OnKill.Event:Connect(function(killer: Player?)
		if not killer then return end
		local f = mProfile:GetAsync(killer, "FTUE")
		if f and not f.Done and (f.Step or 0) == GO_LIVE then onStep(killer, FINAL) end
	end)
end

function FTUE.InitProfileAsync(self, oPlayer: Player, tProfile)
	local f = tProfile.Data.FTUE
	task.delay(2, function()
		oEvent:FireClient(oPlayer, { a = "State", step = f.Step or 0, done = f.Done == true })
	end)
end

function FTUE.PlayerRemoving(self, oPlayer: Player)
	local f = mProfile:GetAsync(oPlayer, "FTUE")
	if f and not f.Done then
		Analytics:Log(oPlayer, "ftue_abandon", { at = f.Step or 0 })
	end
	tLastSam[oPlayer] = nil
end

return FTUE
