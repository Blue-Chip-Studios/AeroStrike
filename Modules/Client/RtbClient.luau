--!strict
--[[
    RtbClient: "return to base". Missiles, flares, fuel and repairs only come from the ground
    crew (land at the airfield or trap on the carrier and stop) or fuel from the tanker.
    This module tells the pilot when and where:
      - out of missiles  -> WINCHESTER: LAND TO REARM, marker to the nearest landing site
      - hull critical    -> LAND TO REPAIR (or eject)
      - flameout         -> GLIDE TO <site> - GEAR DOWN - OR EJECT
      - gear down near a site -> approach coach: speed and sink rate vs the touchdown limits
    Landing-site markers (AIRFIELD / CARRIER) show while guiding or with the gear down.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local FlightConfig = require(ReplicatedStorage.Config.FlightConfig)
local JetConfig = require(ReplicatedStorage.Config.JetConfig)
local FlightModel = require(ReplicatedStorage.Shared.FlightModel)

local LocalPlayer = Players.LocalPlayer
local Rtb = ModuleUtil.New({ Guiding = false })

type Site = { Name: string, Pos: Vector3, Att: Attachment?, Gui: BillboardGui? }
local tSites: { Site } = {}

local function eject(): string
	local Input = require(script.Parent.InputController) :: any
	return if Input.LastDevice == "Touch" then "TAP EJECT" elseif Input.LastDevice == "Gamepad" then "HOLD [Y] TO EJECT" else "HOLD [X] TO EJECT"
end

local function makeMarker(site: Site)
	local att = Instance.new("Attachment")
	att.Name = "AS_Site_" .. site.Name
	att.WorldPosition = site.Pos + Vector3.new(0, 30, 0)
	att.Parent = Workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Name = "AS_SiteMarker"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(150, 40)
	bb.MaxDistance = 1e6
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Adornee = att
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(92, 255, 143)
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = site.Name
	lbl.Parent = bb
	bb.Parent = LocalPlayer:WaitForChild("PlayerGui")
	site.Att, site.Gui = att, bb
end

function Rtb.StartAsync(self)
	local Flight = require(script.Parent.FlightController) :: any
	local MissionClient = require(script.Parent.MissionClient) :: any
	local Tanker = require(script.Parent.TankerClient) :: any
	local c = MapConfig.Carrier
	local a = IslandShape.Airfield
	tSites = {
		{ Name = "CARRIER", Pos = (c.CFrame * CFrame.new(0, c.DeckY, 0)).Position },
		{ Name = "AIRFIELD", Pos = Vector3.new(a.Centre.X, a.Elev, a.Centre.Y) },
	}
	for _, s in ipairs(tSites) do makeMarker(s) end
	local bOverride = false
	RunService.Heartbeat:Connect(function()
		local st, stats, jet = Flight.State, Flight.Stats, Flight.Jet
		local flying = Flight.Phase == "Flying" and st and stats and jet and jet.PrimaryPart
		local hint, guideTo = "", nil :: Site?
		local showMarkers = false
		if flying then
			local pos = jet.PrimaryPart.Position
			local nearest: Site, nd = tSites[1], math.huge
			for _, s in ipairs(tSites) do
				local d = (Vector3.new(s.Pos.X, 0, s.Pos.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
				if d < nd then nearest, nd = s, d end
			end
			local km = string.format("%.1f KM", nd / 1000) -- 1 stud = 1 m (KmhPerStud 3.6)
			local missiles = jet:GetAttribute("Missiles") :: number? or 1
			local hp = (jet:GetAttribute("Health") :: number? or 1) / math.max(jet:GetAttribute("MaxHealth") :: number? or 1, 1)
			if st.Fuel <= 0 then
				hint = string.format("FLAMEOUT! GLIDE TO THE %s (%s) - GEAR DOWN - OR %s", nearest.Name, km, eject())
				guideTo = nearest
			elseif hp <= 0.35 then
				hint = string.format("HULL CRITICAL - LAND AT THE %s TO REPAIR (%s) OR %s", nearest.Name, km, eject())
				guideTo = nearest
			elseif missiles <= 0 then
				hint = string.format("WINCHESTER: OUT OF MISSILES - LAND AT THE %s TO REARM (%s)", nearest.Name, km)
				guideTo = nearest
			end
			-- approach coach with the gear down near a landing site
			if Flight.GearDown and nd < 2600 then
				showMarkers = true
				local agl = pos.Y - nearest.Pos.Y
				-- only while actually coming down (not on the climb-out after a launch)
				if agl < 700 and jet.PrimaryPart.AssemblyLinearVelocity.Y < -1 then
					local maxSp, maxSink = FlightModel.TouchdownLimits(stats)
					local maxKmh = math.floor(maxSp * JetConfig.KmhPerStud)
					local kmh = math.floor(st.Speed * JetConfig.KmhPerStud)
					local sink = math.max(0, -jet.PrimaryPart.AssemblyLinearVelocity.Y)
					local okS, okV = kmh <= maxKmh, sink <= maxSink
					hint = string.format("APPROACH %s   SPEED %d %s (MAX %d)   SINK %d %s (MAX %d)", nearest.Name, kmh, if okS then "OK" else "TOO FAST",
						maxKmh, math.floor(sink), if okV then "OK" else "TOO STEEP", math.floor(maxSink))
				end
			elseif guideTo and not Flight.GearDown and nd < 1200 then
				hint = "LANDING: PRESS GEAR, SLOW DOWN, DESCEND GENTLY ONTO THE " .. nearest.Name
			end
		end
		-- combat-zone limit: past BoundsRadius you have ~900 studs to turn back before you're lost
		if flying then
			local pos = jet.PrimaryPart.Position
			local flat = Vector3.new(pos.X - MapConfig.MapCentre.X, 0, pos.Z - MapConfig.MapCentre.Z).Magnitude
			if flat > FlightConfig.BoundsRadius then
				local left = math.max(0, FlightConfig.BoundsRadius + 900 - flat)
				hint = string.format("LEAVING THE COMBAT ZONE - TURN BACK NOW (%d M)", math.floor(left))
			end
		end
		showMarkers = showMarkers or guideTo ~= nil
		for _, s in ipairs(tSites) do
			if s.Gui then
				s.Gui.Enabled = showMarkers
				local lbl = s.Gui:FindFirstChild("Label") :: TextLabel?
				if lbl then lbl.TextColor3 = if guideTo == s then Color3.fromRGB(255, 194, 61) else Color3.fromRGB(92, 255, 143) end
			end
		end
		-- objective arrow (the tanker's low-fuel guidance takes priority while it's active)
		if guideTo and not Tanker.Guiding then
			MissionClient.Override = guideTo.Pos
			bOverride = true
		elseif bOverride then
			bOverride = false
			if not Tanker.Guiding then MissionClient.Override = nil end
		end
		self.Guiding = guideTo ~= nil
		Store.Values.sRtbHint:set(hint)
	end)
end

return Rtb
