--!strict
--[[
    BossClient: Flying Fortress HUD. Countdown in the last 2 minutes before it arrives,
    then a top-centre health bar with time left, an always-on-top marker on the Fortress,
    and banners when it arrives / goes down / escapes. Reads BossServer's workspace attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local Store = require(ReplicatedStorage.BCDKClient.LMGui.Store)

local LocalPlayer = Players.LocalPlayer
local BossC = ModuleUtil.New({})

local COUNTDOWN_FROM = 120
local oMarker: BillboardGui? = nil

local function mmss(t: number): string
	t = math.max(0, math.floor(t))
	return string.format("%d:%02d", t // 60, t % 60)
end

local function banner(text: string, secs: number)
	Store.Values.sLaunchResult:set(text)
	task.delay(secs, function()
		local Fusion = require(ReplicatedStorage.Packages.fusion)
		if Fusion.peek(Store.Values.sLaunchResult) == text then Store.Values.sLaunchResult:set("") end
	end)
end

local function marker(m: Model?)
	if oMarker then oMarker:Destroy(); oMarker = nil end
	if not m or not m.PrimaryPart then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "AS_BossMarker"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(200, 40)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 40, 0)
	bb.MaxDistance = 1e6
	bb.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.Name = "Label"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 80, 60)
	l.TextStrokeTransparency = 0.3
	l.Text = "FLYING FORTRESS"
	l.Parent = bb
	bb.Adornee = m.PrimaryPart
	bb.Parent = LocalPlayer:WaitForChild("PlayerGui")
	oMarker = bb
end

function BossC.StartAsync(self)
	local lastModel = ""
	Workspace:GetAttributeChangedSignal("BossResultAt"):Connect(function()
		local r = Workspace:GetAttribute("BossResult")
		if r == "Down" then banner("FLYING FORTRESS DOWN!", 3) elseif r == "Escaped" then banner("THE FORTRESS ESCAPED", 2.5) end
	end)
	RunService.Heartbeat:Connect(function()
		local t = Workspace:GetServerTimeNow()
		local name = Workspace:GetAttribute("BossModel") :: string? or ""
		local m = if name ~= "" and Workspace:FindFirstChild("NPC") then Workspace.NPC:FindFirstChild(name) :: Model? else nil
		if name ~= lastModel then
			lastModel = name
			if name ~= "" then banner("FLYING FORTRESS INBOUND! EVERYONE ATTACK!", 3) end
		end
		if m and m.PrimaryPart then
			if not oMarker or oMarker.Adornee ~= m.PrimaryPart then marker(m) end
			local hp = (m:GetAttribute("Health") :: number? or 0) / math.max(m:GetAttribute("MaxHealth") :: number? or 1, 1)
			local left = (Workspace:GetAttribute("BossEndsAt") :: number? or t) - t
			Store.Values.nBossHp:set(hp)
			Store.Values.sBossBar:set(string.format("FLYING FORTRESS  %d%%  ·  ESCAPES IN %s", math.ceil(hp * 100), mmss(left)))
			local jet = Workspace.Jets:FindFirstChild(tostring(LocalPlayer.UserId))
			if oMarker and jet and jet:IsA("Model") then
				local d = (jet:GetPivot().Position - m:GetPivot().Position).Magnitude
				local l = oMarker:FindFirstChild("Label") :: TextLabel?
				if l then l.Text = string.format("FLYING FORTRESS  %.1f KM", d / 1000) end
			end
		else
			if oMarker then oMarker:Destroy(); oMarker = nil end
			local at = Workspace:GetAttribute("BossAt") :: number?
			local untilT = if at then at - t else math.huge
			Store.Values.nBossHp:set(-1)
			Store.Values.sBossBar:set(if untilT > 0 and untilT <= COUNTDOWN_FROM then "FLYING FORTRESS ARRIVES IN " .. mmss(untilT) else "")
		end
	end)
end

return BossC
