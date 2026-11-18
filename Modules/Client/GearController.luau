--!strict
--[[
    GearController: mounts the Blender landing gear (ClientTemplates.Gear) on every player jet
    and animates it from the jet's replicated "GearDown" attribute: nose leg folds forward,
    main legs fold inward, and the whole set hides in the bays once tucked away.

    Mount points come from the airframe's bounding box (template attributes GearSpan /
    RideHeight, set by WorldServer), so every jet gets correctly placed legs that reach
    exactly to the ground at the ride height FlightController keeps on the deck/runway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)

local Gear = ModuleUtil.New({})

local CYCLE_TIME = 1.6 -- seconds for a full raise / lower
local INSET = 1.0 -- strut tops sit this far up inside the belly

type Leg = { Welds: { Weld }, Offs: { CFrame }, Parts: { BasePart }, Mount: CFrame, Fold: CFrame }
type Rig = { Legs: { Leg }, T: number, Target: number, Hidden: boolean }

local tRigs: { [Model]: Rig } = {}

local function buildLeg(tmpl: Model, prefix: string, root: BasePart, folder: Folder, mount: CFrame, fold: CFrame): Leg?
	local strut = tmpl:FindFirstChild(prefix .. "Strut") :: BasePart?
	local wheel = tmpl:FindFirstChild(prefix .. "Wheel") :: BasePart?
	if not strut or not wheel then return nil end
	-- pivot = top of the strut, straight above the wheel (template space)
	local pivot = CFrame.new(wheel.Position.X, strut.Position.Y + strut.Size.Y / 2, wheel.Position.Z)
	local leg: Leg = { Welds = {}, Offs = {}, Parts = {}, Mount = mount, Fold = fold }
	for _, suffix in ipairs({ "Strut", "Wheel", "Door" }) do
		local src = tmpl:FindFirstChild(prefix .. suffix) :: BasePart?
		if src then
			local p = src:Clone()
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CastShadow = true
			p.Parent = folder
			local w = Instance.new("Weld")
			w.Part0 = root
			w.Part1 = p
			local off = pivot:ToObjectSpace(src.CFrame)
			w.C0 = mount * off
			w.Parent = p
			table.insert(leg.Welds, w)
			table.insert(leg.Offs, off)
			table.insert(leg.Parts, p)
		end
	end
	return leg
end

local function pose(rig: Rig)
	local a = rig.T
	local hide = a >= 0.98
	for _, leg in ipairs(rig.Legs) do
		-- fold by lerping from straight-down to the folded rotation
		local rot = CFrame.new():Lerp(leg.Fold, a)
		for i, w in ipairs(leg.Welds) do
			w.C0 = leg.Mount * rot * leg.Offs[i]
		end
		if hide ~= rig.Hidden then
			for _, p in ipairs(leg.Parts) do p.Transparency = if hide then 1 else 0 end
		end
	end
	rig.Hidden = hide
end

local function attach(jet: Model)
	if tRigs[jet] then return end
	local ct = ReplicatedStorage:FindFirstChild("ClientTemplates")
	local tmpl = ct and ct:FindFirstChild("Gear") :: Model?
	local root = jet.PrimaryPart
	local span = jet:GetAttribute("GearSpan") :: Vector3?
	if not tmpl or not root or not span then return end
	local folder = Instance.new("Folder")
	folder.Name = "GearVis"
	folder.Parent = jet
	local y = -span.Y / 2 + INSET
	local legs = {}
	local nose = buildLeg(tmpl, "Nose", root, folder, CFrame.new(0, y, -0.3 * span.Z), CFrame.Angles(math.rad(95), 0, 0))
	if nose then table.insert(legs, nose) end
	for _, side in ipairs({ -1, 1 }) do
		local main = buildLeg(tmpl, "Main", root, folder, CFrame.new(side * 2.1, y, 0.08 * span.Z) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			CFrame.Angles(0, 0, math.rad(-92)))
		if main then table.insert(legs, main) end
	end
	local down = jet:GetAttribute("GearDown") ~= false
	local rig: Rig = { Legs = legs, T = if down then 0 else 1, Target = if down then 0 else 1, Hidden = false }
	tRigs[jet] = rig
	pose(rig)
	jet:GetAttributeChangedSignal("GearDown"):Connect(function()
		rig.Target = if jet:GetAttribute("GearDown") == false then 1 else 0
	end)
end

function Gear.StartAsync(self)
	local jets = Workspace:WaitForChild("Jets")
	local function try(j: Instance)
		if not j:IsA("Model") then return end
		task.spawn(function()
			for _ = 1, 50 do
				if (j :: Model).PrimaryPart and j:GetAttribute("GearSpan") then break end
				task.wait(0.1)
			end
			if j.Parent then attach(j :: Model) end
		end)
	end
	for _, j in ipairs(jets:GetChildren()) do try(j) end
	jets.ChildAdded:Connect(try)
	jets.ChildRemoved:Connect(function(j) tRigs[j :: Model] = nil end)
	RunService.RenderStepped:Connect(function(dt: number)
		for jet, rig in pairs(tRigs) do
			if not jet.Parent then
				tRigs[jet] = nil
			elseif rig.T ~= rig.Target then
				local step = dt / CYCLE_TIME
				rig.T = if rig.Target > rig.T then math.min(rig.Target, rig.T + step) else math.max(rig.Target, rig.T - step)
				pose(rig)
			end
		end
	end)
end

return Gear
