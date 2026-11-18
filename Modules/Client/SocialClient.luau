--!strict
--[[
    SocialClient: squads (invites, roster, Formation fuel bonus), Ace Bounty
    presentation (announcements + gold contrails), and the daily reward track.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Remote = require(ReplicatedStorage.BCDKShared.Remote)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local Fusion = require(ReplicatedStorage.Packages.fusion)
local peek = Fusion.peek

local LocalPlayer = Players.LocalPlayer
local Social = ModuleUtil.New({})
local oReq
local Flight, Vfx, Input
local bDailyShownThisSession = false
local bDailyQueued = false

-- Show the daily panel only while idle on the carrier deck: never in the tutorial,
-- never in flight, and not on the death screen (where Relaunch would carry it into a fight).
local function queueDaily()
	if bDailyQueued then return end
	bDailyQueued = true
	task.spawn(function()
		local FlightC = require(script.Parent.FlightController) :: any
		while peek(Store.Values.bFTUEActive) or FlightC.Phase ~= "Deck" do task.wait(0.5) end
		bDailyQueued = false
		local d = peek(Store.Values.tDaily)
		if d and d.claimable then Store.Values.bDailyOpen:set(true) end
	end)
end
local tTrails: { [Model]: { Trail } } = {}

function Social.Invite(self, userId: number) oReq:FireServer({ a = "Invite", userId = userId }) end
function Social.Accept(self)
	local inv = peek(Store.Values.tInvite)
	if inv then oReq:FireServer({ a = "Accept", from = inv.from }) end
	Store.Values.tInvite:set(false)
end
function Social.Decline(self)
	local inv = peek(Store.Values.tInvite)
	if inv then oReq:FireServer({ a = "Decline", from = inv.from }) end
	Store.Values.tInvite:set(false)
end
function Social.Leave(self) oReq:FireServer({ a = "Leave" }) end
function Social.ClaimDaily(self)
	oReq:FireServer({ a = "ClaimDaily" })
	Store.Values.bDailyOpen:set(false)
end
function Social.CloseDaily(self) Store.Values.bDailyOpen:set(false) end

function Social.OpenSquad(self)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local isFriend = false
			pcall(function() isFriend = LocalPlayer:IsFriendsWith(p.UserId) end)
			table.insert(list, { id = p.UserId, name = p.DisplayName, friend = isFriend })
		end
	end
	table.sort(list, function(a, b) if a.friend ~= b.friend then return a.friend end return a.name < b.name end)
	Store.Values.tPlayerList:set(list)
	Store.Values.bSquadOpen:set(true)
	Input:SetFlightMouseLock(false)
end
function Social.CloseSquad(self) Store.Values.bSquadOpen:set(false) end

-- gold contrails for Aces (bounty) and VIP pilots
local function ensureTrail(m: Model, on: boolean)
	if on and not tTrails[m] and m.PrimaryPart then
		local _, size = m:GetBoundingBox()
		local trails = {}
		for _, side in ipairs({ -1, 1 }) do
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(side * size.X * 0.48, 0, size.Z * 0.2)
			a0.Parent = m.PrimaryPart
			local a1 = Instance.new("Attachment")
			a1.Position = a0.Position + Vector3.new(0, 0.6, 0)
			a1.Parent = m.PrimaryPart
			local t = Instance.new("Trail")
			t.Attachment0, t.Attachment1 = a0, a1
			t.Color = ColorSequence.new(Color3.fromRGB(255, 216, 107))
			t.LightEmission = 0.8
			t.Lifetime = 1.6
			t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			t.WidthScale = NumberSequence.new(1, 0.2)
			t.Parent = m.PrimaryPart
			table.insert(trails, t)
		end
		tTrails[m] = trails
	elseif not on and tTrails[m] then
		for _, t in ipairs(tTrails[m]) do t:Destroy() end
		tTrails[m] = nil
	end
end

-- Ace Bounty marker: a gold "★ ACE ◉value · distance" tag over every other Ace,
-- visible through terrain at any range so underdogs can find and hunt them
local tMarkers: { [Model]: BillboardGui } = {}
local function ensureMarker(m: Model, bounty: number?)
	local mine = m.Name == tostring(LocalPlayer.UserId)
	local squad = LocalPlayer:GetAttribute("SquadId")
	local friendly = squad ~= nil and m:GetAttribute("SquadId") == squad
	local want = bounty ~= nil and not mine and not friendly and m.PrimaryPart ~= nil
	local bb = tMarkers[m]
	if want and not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "AS_AceMarker"
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Size = UDim2.fromOffset(150, 46)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
		bb.MaxDistance = 1e6
		local star = Instance.new("TextLabel")
		star.Name = "Tag"
		star.BackgroundTransparency = 1
		star.Size = UDim2.new(1, 0, 0.6, 0)
		star.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
		star.TextScaled = true
		star.TextColor3 = Color3.fromRGB(255, 216, 107)
		star.TextStrokeTransparency = 0.3
		star.Parent = bb
		local dist = Instance.new("TextLabel")
		dist.Name = "Dist"
		dist.BackgroundTransparency = 1
		dist.Position = UDim2.fromScale(0, 0.6)
		dist.Size = UDim2.new(1, 0, 0.4, 0)
		dist.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		dist.TextScaled = true
		dist.TextColor3 = Color3.fromRGB(255, 236, 180)
		dist.TextStrokeTransparency = 0.4
		dist.Parent = bb
		bb.Adornee = m.PrimaryPart
		bb.Parent = LocalPlayer:WaitForChild("PlayerGui")
		tMarkers[m] = bb
	elseif not want and bb then
		bb:Destroy()
		tMarkers[m] = nil
		return
	end
	if bb and bounty then
		(bb:FindFirstChild("Tag") :: TextLabel).Text = `★ ACE  ◉{bounty}`
		local me = Flight.Jet and Flight.Jet.PrimaryPart
		local d = if me and m.PrimaryPart then (m.PrimaryPart.Position - me.Position).Magnitude else nil
		(bb:FindFirstChild("Dist") :: TextLabel).Text = if d then string.format("%.1f km", d * 0.28 / 1000) else ""
	end
end

local nFormationTick = 0
local function step(dt: number)
	-- contrails + Ace markers
	for _, m in ipairs(Workspace.Jets:GetChildren()) do
		if m:IsA("Model") then
			local bounty = m:GetAttribute("Bounty") :: number?
			ensureTrail(m, bounty ~= nil or m:GetAttribute("VIP") == true)
			ensureMarker(m, bounty)
		end
	end
	for m in pairs(tTrails) do if not m.Parent then tTrails[m] = nil end end
	for m, bb in pairs(tMarkers) do if not m.Parent then bb:Destroy(); tMarkers[m] = nil end end

	-- Formation bonus: a squadmate within range slowly refuels you
	nFormationTick += dt
	local jet = Flight.Jet
	local sid = LocalPlayer:GetAttribute("SquadId")
	local inForm = false
	if sid and jet and jet.PrimaryPart and Flight.Phase == "Flying" and Flight.State and Flight.Stats then
		for _, m in ipairs(Workspace.Jets:GetChildren()) do
			if m ~= jet and m:IsA("Model") and m.PrimaryPart and m:GetAttribute("SquadId") == sid then
				if (m.PrimaryPart.Position - jet.PrimaryPart.Position).Magnitude < EconomyConfig.FormationRange then
					inForm = true
					break
				end
			end
		end
		if inForm then
			local st = Flight.State
			st.Fuel = math.min(Flight.Stats.Fuel, st.Fuel + EconomyConfig.FormationFuelPerSec * dt)
		end
	end
	Store.Values.bFormation:set(inForm)
end

function Social.StartAsync(self)
	oReq = Remote:GetEvent("SocialRequest")
	Flight = require(script.Parent.FlightController)
	Vfx = require(script.Parent.VfxController)
	Input = require(script.Parent.InputController)
	Remote:GetEvent("SocialEvent"):OnClientEvent(function(t: any)
		if typeof(t) ~= "table" then return end
		if t.a == "Invite" then
			Store.Values.tInvite:set({ from = t.from, name = t.name })
			task.delay(30, function()
				local cur = peek(Store.Values.tInvite)
				if cur and cur.from == t.from then Store.Values.tInvite:set(false) end
			end)
		elseif t.a == "Squad" then
			Store.Values.tSquad:set(t.members or {})
		elseif t.a == "Bounty" then
			if t.userId == LocalPlayer.UserId then
				Store.Values.sLaunchResult:set(`YOU'RE THE ACE! BOUNTY {t.value}`)
				task.delay(2.4, function() Store.Values.sLaunchResult:set("") end)
			else
				Vfx:Toast(`★ ACE BOUNTY: {t.name}  ◉{t.value}. Hunt them!`, Color3.fromRGB(255, 216, 107))
			end
		elseif t.a == "BountyClaimed" then
			Vfx:Toast(`★ {t.killer} claimed {t.victim}'s bounty  ◉{t.value}`, Color3.fromRGB(255, 216, 107))
		elseif t.a == "Daily" then
			Store.Values.tDaily:set({ day = t.day, streak = t.streak, claimable = t.claimable })
			if t.claimable and not bDailyShownThisSession then
				bDailyShownThisSession = true
				queueDaily()
			end
		end
	end)
	-- launching with the panel still open closes it; it comes back next time on the deck
	Flight.Changed:Connect(function(phase: string)
		if (phase == "Catapult" or phase == "Flying") and peek(Store.Values.bDailyOpen) then
			Store.Values.bDailyOpen:set(false)
			local d = peek(Store.Values.tDaily)
			if d and d.claimable then queueDaily() end
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return Social
