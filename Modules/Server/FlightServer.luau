--!strict
--[[
    FlightServer
    ------------
    Owns the life of every jet: spawn on a free catapult, launch (hand
    network ownership to the pilot), validate flight, detect crashes and
    out-of-bounds, Bank-It touch-and-go, death and relaunch.

    Players never get a character: the jet IS the avatar (zero lobbies).

    Remotes
        C->S  FlightRequest { a = "Launch", perfect = bool } | { a = "Relaunch" } | { a = "Crash" }
        S->C  FlightEvent   { a = "Spawned", jet = jetId, stats = {...}, start = CF, finish = CF }
                            { a = "Launched", speed, freeBoost } | { a = "Reset", reason } | { a = "Banked", ... }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local JetStats = require(ReplicatedStorage.Shared.JetStats)
local FlightConfig = require(ReplicatedStorage.Config.FlightConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)

local mProfile = require(ServerStorage.BCDKServer.SMProfile)

export type Sortie = {
	Player: Player,
	Jet: Model,
	JetId: string,
	Stats: { [string]: any },
	Catapult: number,
	Phase: "Deck" | "Flying" | "Dead",
	LaunchedAt: number,
	LastPos: Vector3,
	LastCheck: number,
	Strikes: number,
	LastBank: number,
	Passes: { [string]: boolean },
	Resupplying: boolean?,
	DeathCF: CFrame?,
	DeadAt: number?,
	LastBoom: number?,
	Boomed: boolean?, -- first sonic boom this sortie already rewarded
}

local Flight = ModuleUtil.New({
	Sorties = {} :: { [Player]: Sortie },
	OnLaunched = Instance.new("BindableEvent"),
	OnJetDestroyed = Instance.new("BindableEvent"), -- (player, cause)
	OnTouchAndGo = Instance.new("BindableEvent"), -- (player) low pass over the deck: Bank It
	OnResupply = Instance.new("BindableEvent"), -- (player, where: "Carrier"|"Airfield") landed + stopped: rearm, refuel, repair
	OnSonicBoom = Instance.new("BindableEvent"), -- (player, firstThisSortie)
})

local oEvent = Remote:GetEvent("FlightEvent")
local oRequest = Remote:GetEvent("FlightRequest")
local oLimiter = ModuleUtil.RateLimiter(10, 2)
local tCatapultBusy: { [number]: number } = {}

local World: any -- resolved lazily (module load order is not guaranteed)
local function getWorld()
	World = World or require(ServerStorage.ServerModules.WorldServer)
	while not World.Ready do task.wait() end
	return World
end

local function getPasses(oPlayer: Player): { [string]: boolean }
	local ok, Mon = pcall(require, ServerStorage.ServerModules:FindFirstChild("MonetizationServer") :: any)
	if ok and Mon and Mon.GetPasses then return Mon:GetPasses(oPlayer) end
	return {}
end

local function pickCatapult(): number
	local now = os.clock()
	local best, bestT = 1, math.huge
	for i = 1, #MapConfig.Carrier.Catapults do
		local t = tCatapultBusy[i] or 0
		if now - t > 2.5 then return i end
		if t < bestT then best, bestT = i, t end
	end
	return best
end

function Flight.GetSortie(self, oPlayer: Player): Sortie?
	return self.Sorties[oPlayer]
end

function Flight.GetJetOf(self, oPlayer: Player): Model?
	local s = self.Sorties[oPlayer]
	return s and s.Jet or nil
end

function Flight.DestroyJet(self, oPlayer: Player, sCause: string)
	local s = self.Sorties[oPlayer]
	if not s or s.Phase == "Dead" then return end
	s.Phase = "Dead"
	local jet = s.Jet
	s.DeathCF = jet:GetPivot()
	s.DeadAt = os.clock()
	if game:GetService("RunService"):IsStudio() then
		local p = jet:GetPivot().Position
		print(`[Flight] {oPlayer.Name} jet destroyed: {sCause} at ({math.floor(p.X)}, {math.floor(p.Y)}, {math.floor(p.Z)})`)
	end
	self.OnJetDestroyed:Fire(oPlayer, sCause, jet:GetPivot().Position)
	jet:SetAttribute("Dead", true)
	task.delay(0.05, function()
		if jet.Parent then jet:Destroy() end
	end)
end

function Flight.Spawn(self, oPlayer: Player)
	local W = getWorld()
	local old = self.Sorties[oPlayer]
	if old and old.Jet and old.Jet.Parent then old.Jet:Destroy() end

	local sJetId = mProfile:GetAsync(oPlayer, "EquippedJet") or "SparrowT2"
	local tmpl = W:GetJetTemplate(sJetId) or W:GetJetTemplate("SparrowT2")
	if not tmpl then
		warn("[Flight] no jet template")
		return
	end
	local tUp = (mProfile:GetAsync(oPlayer, "Upgrades") or {})[sJetId]
	local tPasses = getPasses(oPlayer)
	local stats = JetStats.Compute(sJetId, tUp, tPasses)
	-- rookie assists for the first ranks (no G-LOC, auto gear, forgiving landings)
	local XPConfig = require(ReplicatedStorage.Config.XPConfig)
	stats.Rookie = XPConfig.fXPToLevel(mProfile:GetAsync(oPlayer, "XP") or 0) <= FlightConfig.RookieMaxRank

	local jet = tmpl:Clone()
	jet.Name = tostring(oPlayer.UserId)
	jet:SetAttribute("OwnerUserId", oPlayer.UserId)
	jet:SetAttribute("JetId", sJetId)
	jet:SetAttribute("Health", stats.Health)
	jet:SetAttribute("MaxHealth", stats.Health)
	jet:SetAttribute("Shield", true)
	jet:SetAttribute("Pilot", oPlayer.DisplayName)
	if stats.Rookie then jet:SetAttribute("Rookie", true) end -- AI goes easier on new pilots (NpcServer)
	pcall(function() require(ServerStorage.ServerModules.AnalyticsServer):LogOnce(oPlayer, "session_spawned") end)
	local trail = mProfile:GetAsync(oPlayer, "EquippedTrail") or ""
	if trail ~= "" then jet:SetAttribute("Trail", trail) end
	if stats.Special == "LowObservable" then jet:SetAttribute("LowObservable", true) end

	-- paint
	local JetConfig = require(ReplicatedStorage.Config.JetConfig)
	local tPaints = mProfile:GetAsync(oPlayer, "EquippedPaint") or {}
	local tJetCfg = JetConfig.Jets[sJetId]
	local paint = tJetCfg.Paints[tPaints[sJetId] or tJetCfg.DefaultPaint] or tJetCfg.Paints[tJetCfg.DefaultPaint]
	W:ApplyPaint(jet, paint)

	local iCat = pickCatapult()
	tCatapultBusy[iCat] = os.clock()
	local cfStart, cfEnd = W:CatapultWorld(iCat)
	-- catapult CFrames are for a belly-height root; raise by this jet's gear ride height
	local lift = Vector3.new(0, ((tmpl:GetAttribute("RideHeight") :: number?) or 3.2) - 3.2, 0)
	cfStart, cfEnd = cfStart + lift, cfEnd + lift
	jet:SetAttribute("GearDown", true)
	jet:PivotTo(cfStart)
	local root = jet.PrimaryPart :: BasePart
	root.Anchored = true
	jet.Parent = workspace.Jets
	oPlayer.ReplicationFocus = root

	local s: Sortie = {
		Player = oPlayer, Jet = jet, JetId = sJetId, Stats = stats, Catapult = iCat,
		Phase = "Deck", LaunchedAt = 0, LastPos = cfStart.Position, LastCheck = os.clock(),
		Strikes = 0, LastBank = 0, Passes = tPasses,
	}
	self.Sorties[oPlayer] = s
	oEvent:FireClient(oPlayer, { a = "Spawned", jet = sJetId, stats = stats, start = cfStart, finish = cfEnd, owner = oPlayer.UserId })
end

local function launch(self, oPlayer: Player, bPerfectClaim: boolean)
	local s = self.Sorties[oPlayer]
	if not s or s.Phase ~= "Deck" then return end
	local root = s.Jet.PrimaryPart :: BasePart
	if not root then return end
	-- the timing bar is client-side feel; accept "perfect" at most once per
	-- launch and only if the launch came after the minimum countdown window
	local elapsed = os.clock() - tCatapultBusy[s.Catapult]
	local bPerfect = bPerfectClaim and elapsed >= FlightConfig.LaunchCountdown * FlightConfig.PerfectWindow[1] * 0.8
	s.Phase = "Flying"
	s.LaunchedAt = os.clock()
	s.LastPos = root.Position
	s.LastCheck = os.clock()
	root.Anchored = false
	root:SetNetworkOwner(oPlayer)
	local speed = s.Stats.CruiseSpeed * FlightConfig.LaunchSpeedFrac * (if bPerfect then FlightConfig.PerfectLaunchBonus else 1)
	oEvent:FireClient(oPlayer, { a = "Launched", speed = speed, freeBoost = if bPerfect then FlightConfig.PerfectLaunchFreeBoost else 0, perfect = bPerfect })
	self.OnLaunched:Fire(oPlayer, bPerfect)
	task.delay(FlightConfig.SpawnShield, function()
		if s.Jet.Parent and not s.Jet:GetAttribute("Training") then s.Jet:SetAttribute("Shield", false) end
	end)
end

-- where a stopped jet may be resupplied (server truth, not the client's word)
local function landingSite(pos: Vector3): string?
	local c = MapConfig.Carrier
	local lp = c.CFrame:PointToObjectSpace(pos)
	if math.abs(lp.X) < 34 and math.abs(lp.Z) < 165 and lp.Y > c.DeckY - 1 and lp.Y < c.DeckY + 14 then return "Carrier" end
	local a = IslandShape.Airfield
	if IslandShape.AirfieldDist(pos.X, pos.Z) <= 0 and pos.Y > a.Elev - 2 and pos.Y < a.Elev + 16 then return "Airfield" end
	return nil
end

-- REVIVE HERE (Robux): a fresh jet where you went down (lifted to a safe height), full ammo,
-- 4 s of shield, and the Sortie Cash you lost restored. Only within the revive window.
function Flight.Revive(self, oPlayer: Player): boolean
	local MonetizationConfig = require(ReplicatedStorage.Config.MonetizationConfig)
	local old = self.Sorties[oPlayer]
	if not old or old.Phase ~= "Dead" or not old.DeathCF or os.clock() - (old.DeadAt or 0) > MonetizationConfig.ReviveWindow + 8 then return false end
	local cf0 = old.DeathCF
	local ground = math.max(IslandShape.Height(cf0.X, cf0.Z), 0)
	local pos = Vector3.new(cf0.X, math.max(cf0.Y, ground + 250), cf0.Z)
	local look = Vector3.new(cf0.LookVector.X, 0, cf0.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	local cf = CFrame.lookAt(pos, pos + look)
	self:Spawn(oPlayer)
	local s = self.Sorties[oPlayer]
	if not s or not s.Jet.PrimaryPart then return false end
	local root = s.Jet.PrimaryPart :: BasePart
	s.Jet:PivotTo(cf)
	s.Jet:SetAttribute("GearDown", false)
	s.Phase = "Flying"
	s.LaunchedAt = os.clock()
	s.LastPos = cf.Position
	s.LastCheck = os.clock()
	root.Anchored = false
	root:SetNetworkOwner(oPlayer)
	local speed = s.Stats.CruiseSpeed
	oEvent:FireClient(oPlayer, { a = "AirStart", cf = cf, speed = speed })
	self.OnLaunched:Fire(oPlayer, false) -- rearm etc.
	task.delay(4, function() if s.Jet.Parent and not s.Jet:GetAttribute("Training") then s.Jet:SetAttribute("Shield", false) end end)
	local ok, Economy = pcall(require, ServerStorage.ServerModules.EconomyServer)
	if ok and Economy.RestoreLoss then Economy:RestoreLoss(oPlayer) end
	return true
end

-- after a carrier trap: taxi'd onto a free catapult, same jet, ready to launch again
function Flight.Recover(self, oPlayer: Player)
	local s = self.Sorties[oPlayer]
	if not s or s.Phase ~= "Flying" or not s.Jet.PrimaryPart then return end
	local W = getWorld()
	local iCat = pickCatapult()
	tCatapultBusy[iCat] = os.clock()
	s.Catapult = iCat
	local cfStart, cfEnd = W:CatapultWorld(iCat)
	local lift = Vector3.new(0, ((s.Jet:GetAttribute("RideHeight") :: number?) or 3.2) - 3.2, 0)
	cfStart, cfEnd = cfStart + lift, cfEnd + lift
	local root = s.Jet.PrimaryPart :: BasePart
	root.Anchored = true
	s.Jet:PivotTo(cfStart)
	s.Phase = "Deck"
	s.Jet:SetAttribute("GearDown", true)
	oEvent:FireClient(oPlayer, { a = "Recovered", start = cfStart, finish = cfEnd })
end

local function resupply(self, oPlayer: Player)
	local s = self.Sorties[oPlayer]
	if not s or s.Phase ~= "Flying" or s.Resupplying or not s.Jet.PrimaryPart then return end
	local root = s.Jet.PrimaryPart :: BasePart
	local where = landingSite(root.Position)
	if not where or root.AssemblyLinearVelocity.Magnitude > FlightConfig.ResupplyMaxSpeed * 2.5 then
		oEvent:FireClient(oPlayer, { a = "ResupplyFailed" })
		return
	end
	s.Resupplying = true
	task.delay(2.5, function()
		s.Resupplying = false
		if s.Phase ~= "Flying" or not s.Jet.Parent or not s.Jet.PrimaryPart then return end
		local r = s.Jet.PrimaryPart :: BasePart
		if landingSite(r.Position) ~= where or r.AssemblyLinearVelocity.Magnitude > FlightConfig.ResupplyMaxSpeed * 2.5 then
			oEvent:FireClient(oPlayer, { a = "ResupplyFailed" })
			return
		end
		s.Jet:SetAttribute("Health", s.Jet:GetAttribute("MaxHealth"))
		self.OnResupply:Fire(oPlayer, where)
		oEvent:FireClient(oPlayer, { a = "Resupplied", where = where })
		if where == "Carrier" then
			task.delay(1.2, function() self:Recover(oPlayer) end)
		end
	end)
end

-- Validation tick: speed sanity, teleport detection, water/bounds, Bank It.
local function validate(self)
	local now = os.clock()
	local carrierCF = MapConfig.Carrier.CFrame
	for oPlayer, s in pairs(self.Sorties) do
		if s.Phase ~= "Flying" or not s.Jet.Parent then continue end
		local root = s.Jet.PrimaryPart :: BasePart
		if not root then continue end
		local pos = root.Position
		local dt = math.max(now - s.LastCheck, 1e-3)
		local maxV = s.Stats.MaxSpeed * FlightConfig.SpeedTolerance
		local vel = root.AssemblyLinearVelocity.Magnitude
		local moved = (pos - s.LastPos).Magnitude / dt
		local grace = now - s.LaunchedAt < 2
		if not grace and (vel > maxV or moved > maxV * 1.3) then
			s.Strikes += 1
			if s.Strikes >= FlightConfig.MaxStrikes then
				warn(`[Flight] {oPlayer.Name} failed validation (v={math.floor(vel)} moved={math.floor(moved)} max={math.floor(maxV)})`)
				oEvent:FireClient(oPlayer, { a = "Reset", reason = "validation" })
				self:DestroyJet(oPlayer, "reset")
				continue
			end
		else
			s.Strikes = math.max(0, s.Strikes - 0.25)
		end
		s.LastPos = pos
		s.LastCheck = now

		-- below the sea: a shielded (spawn / tutorial) jet is bounced back up by its client instead
		if pos.Y < FlightConfig.WaterLevel - 1.5 and not s.Jet:GetAttribute("Shield") then
			self:DestroyJet(oPlayer, "crash:Sea")
			continue
		end
		local flat = Vector3.new(pos.X, 0, pos.Z) - Vector3.new(MapConfig.MapCentre.X, 0, MapConfig.MapCentre.Z)
		if flat.Magnitude > FlightConfig.BoundsRadius + 900 then
			self:DestroyJet(oPlayer, "bounds")
			continue
		end

		-- Bank It: low pass over the deck
		local lp = carrierCF:PointToObjectSpace(pos)
		if math.abs(lp.X) < 40 and math.abs(lp.Z) < 160 and lp.Y > MapConfig.Carrier.DeckY - 2
			and lp.Y < MapConfig.Carrier.DeckY + EconomyConfig.BankMaxAltitude * 0.6 and now - s.LastBank > 8 then
			s.LastBank = now
			self.OnTouchAndGo:Fire(oPlayer)
			oEvent:FireClient(oPlayer, { a = "TouchAndGo" })
		end
	end
end

function Flight.StartAsync(self)
	Players.CharacterAutoLoads = false
	oRequest:OnServerEvent(function(oPlayer: Player, t: any)
		if typeof(t) ~= "table" or typeof(t.a) ~= "string" then return end
		if not oLimiter:Check(oPlayer) then return end
		if t.a == "Launch" then
			launch(self, oPlayer, t.perfect == true)
		elseif t.a == "Relaunch" then
			local s = self.Sorties[oPlayer]
			if not s or s.Phase == "Dead" then
				self:Spawn(oPlayer)
			end
		elseif t.a == "Gear" then
			local s = self.Sorties[oPlayer]
			if s and s.Phase == "Flying" then s.Jet:SetAttribute("GearDown", t.down == true) end
		elseif t.a == "Resupply" then
			resupply(self, oPlayer)
		elseif t.a == "Boom" then
			-- sonic boom: everyone nearby hears/feels it (rate-limited; speed sanity-checked)
			local s = self.Sorties[oPlayer]
			if s and s.Phase == "Flying" and s.Jet.PrimaryPart and os.clock() - (s.LastBoom or 0) > 4 then
				local root = s.Jet.PrimaryPart :: BasePart
				if root.AssemblyLinearVelocity.Magnitude * 3.6 >= 780 then
					s.LastBoom = os.clock()
					Remote:GetEvent("CombatEvent"):FireAllClients({ a = "SonicBoom", owner = oPlayer.UserId, pos = root.Position, jet = s.Jet.Name })
					self.OnSonicBoom:Fire(oPlayer, not s.Boomed)
					s.Boomed = true
				end
			end
		elseif t.a == "Eject" then
			-- pilot punches out: everyone sees the seat + parachute; the jet goes down
			local s = self.Sorties[oPlayer]
			if s and s.Phase == "Flying" and s.Jet.PrimaryPart then
				local root = s.Jet.PrimaryPart
				Remote:GetEvent("CombatEvent"):FireAllClients({ a = "Eject", owner = oPlayer.UserId,
					cf = root.CFrame, vel = root.AssemblyLinearVelocity })
				self:DestroyJet(oPlayer, "eject")
			end
		elseif t.a == "Crash" then
			-- client-reported terrain/ship impact; server trusts only if the
			-- jet is actually low or near the carrier (can't be used to dodge kills)
			local s = self.Sorties[oPlayer]
			if s and s.Phase == "Flying" and s.Jet.PrimaryPart then
				local y = s.Jet.PrimaryPart.Position.Y
				if y < 900 then self:DestroyJet(oPlayer, "crash:" .. tostring(t.hit or "?"):sub(1, 24)) end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(FlightConfig.ValidateInterval)
			validate(self)
		end
	end)
end

-- Spawn as soon as the profile is live (BCDK lifecycle).
function Flight.InitProfileAsync(self, oPlayer: Player, _tProfile)
	task.spawn(function()
		self:Spawn(oPlayer)
	end)
end

function Flight.PlayerRemoving(self, oPlayer: Player)
	local s = self.Sorties[oPlayer]
	if s and s.Jet and s.Jet.Parent then s.Jet:Destroy() end
	self.Sorties[oPlayer] = nil
end

Players.PlayerRemoving:Connect(function(oPlayer)
	local s = Flight.Sorties[oPlayer]
	if s and s.Jet and s.Jet.Parent then s.Jet:Destroy() end
	Flight.Sorties[oPlayer] = nil
end)

return Flight
