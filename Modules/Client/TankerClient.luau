--!strict
--[[
    TankerClient: aerial refuelling (the only mid-air refuel; the carrier touch-and-go is the other).
    Fly into the zone behind the tanker's drogue basket and hold your speed close to the
    tanker's: fuel flows in. The tanker is always marked; when fuel runs low it becomes the
    objective marker and a LOW FUEL prompt shows the way.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)
local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)

local LocalPlayer = Players.LocalPlayer
local Tanker = ModuleUtil.New({ Refuelling = false, Guiding = false })

local CFG = NpcConfig.Kinds.Tanker
local oMarker: BillboardGui? = nil
local bWasRefuelling = false
local bGuiding = false

local function findTanker(): Model?
	local npc = Workspace:FindFirstChild("NPC")
	if not npc then return nil end
	for _, m in ipairs(npc:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("NpcKind") == "Tanker" and m.PrimaryPart then return m end
	end
	return nil
end

local function ensureMarker(t: Model)
	if oMarker and oMarker.Adornee and oMarker.Adornee:IsDescendantOf(t) then return end
	if oMarker then oMarker:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "AS_TankerMarker"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(120, 34)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 16, 0)
	bb.MaxDistance = 1e6
	bb.LightInfluence = 0
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(92, 255, 143)
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = "TANKER"
	lbl.Parent = bb
	bb.Adornee = t.PrimaryPart
	bb.Parent = LocalPlayer:WaitForChild("PlayerGui")
	oMarker = bb
end

function Tanker.StartAsync(self)
	if not CFG then return end
	local Flight = require(script.Parent.FlightController) :: any
	local MissionClient = require(script.Parent.MissionClient) :: any
	local R = CFG.Refuel
	RunService.Heartbeat:Connect(function(dt: number)
		local t = findTanker()
		if not t then
			if oMarker then oMarker:Destroy(); oMarker = nil end
			return
		end
		ensureMarker(t)
		local st, stats, jet = Flight.State, Flight.Stats, Flight.Jet
		local flying = Flight.Phase == "Flying" and st and stats and jet and jet.PrimaryPart
		local refuelling = false
		local hint = ""
		local fuelFrac = if flying then st.Fuel / stats.Fuel else 1
		if flying then
			local drogue = t:FindFirstChild("Drogue", true) :: BasePart?
			local dpos = if drogue then drogue.Position else t:GetPivot().Position
			local dist = (jet.PrimaryPart.Position - dpos).Magnitude
			local tankerSpeed = t.PrimaryPart.AssemblyLinearVelocity.Magnitude
			if dist < R.Radius * 3 then
				local dv = st.Speed - tankerSpeed
				-- connect inside the zone at matched speed; once hooked up, small drifts don't break it
				local inZone = dist < R.Radius and math.abs(dv) < R.SpeedMatch
				local stayHooked = bWasRefuelling and dist < R.Radius * 2 and math.abs(dv) < R.SpeedMatch * 1.4
				if inZone or stayHooked then
					refuelling = st.Fuel < stats.Fuel
					-- hooked up: hold the tanker's speed for you (you only steer to stay on the basket)
					st.Speed += (tankerSpeed - st.Speed) * math.clamp(dt * 2.5, 0, 1)
					if refuelling then
						st.Fuel = math.min(stats.Fuel, st.Fuel + R.Rate * dt)
						hint = string.format("REFUELLING %d%%", math.floor(st.Fuel / stats.Fuel * 100))
					else
						hint = "TANKS FULL - BREAK AWAY"
					end
				elseif dist < R.Radius * 3 then
					hint = if dv > R.SpeedMatch then "TOO FAST - THROTTLE BACK"
						elseif dv < -R.SpeedMatch then "TOO SLOW - ADD THROTTLE"
						else "CLOSE IN ON THE BASKET"
				end
			end
		end
		-- low fuel: guide the pilot to the tanker
		-- (after a flameout the tanker can't be caught: RtbClient guides you to a runway instead)
		local low = flying and fuelFrac < R.LowFuel and st.Fuel > 0
		if low and not refuelling then
			MissionClient.Override = t:GetPivot().Position
			bGuiding = true
			if hint == "" then hint = "LOW FUEL - FOLLOW THE MARKER TO THE TANKER" end
		elseif bGuiding then
			MissionClient.Override = nil
			bGuiding = false
		end
		self.Guiding = bGuiding
		if oMarker then
			local lbl = oMarker:FindFirstChild("Label") :: TextLabel?
			if lbl then lbl.TextColor3 = if low then Color3.fromRGB(255, 194, 61) else Color3.fromRGB(92, 255, 143) end
		end
		Store.Values.sRefuelHint:set(hint)
		self.Refuelling = refuelling
		if refuelling and not bWasRefuelling then
			pcall(function() (require(script.Parent.AudioController) :: any):Cue("Reward") end)
		end
		bWasRefuelling = refuelling
	end)
end

return Tanker
