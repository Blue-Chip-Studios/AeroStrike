--!strict
--[[
    EnvironmentServer: dresses the Kestrel Archipelago with the Blender
    environment kit (arches over the canyon, rock spires on plateaus, pines
    on the green lowlands, boulders) using the shared IslandShape height
    field and a fixed seed. Built once at server start into workspace.Map.Env.
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)
local EnvironmentConfig = require(ReplicatedStorage.Config.EnvironmentConfig)

local Environment = ModuleUtil.New({})

local function load(nId: number): Model?
	for attempt = 1, 3 do
		local ok, res = pcall(InsertService.LoadAsset, InsertService, nId)
		if ok and res then
			local m = res:FindFirstChildWhichIsA("Model") or res
			m.Parent = nil
			return m :: Model
		end
		task.wait(attempt)
	end
	warn("[Environment] failed to load", nId)
	return nil
end

local function prep(m: Model, bCollide: boolean)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = bCollide
			d.CanQuery = bCollide -- crash raycasts only see solid rock
			d.CanTouch = false
			d.Name = ModuleUtil.StripSuffix(d.Name)
			local spec = EnvironmentConfig.Paint[d.Name]
			if spec then
				d.Color = spec.Color
				d.Material = spec.Material
			end
		end
	end
end

function Environment.StartAsync(self)
	local map = workspace:WaitForChild("Map")
	local old = map:FindFirstChild("Env")
	if old then old:Destroy() end
	local env = Instance.new("Folder")
	env.Name = "Env"

	local tmpl: { [string]: Model } = {}
	for k, def in pairs(EnvironmentConfig.Kit) do
		local m = load(def.AssetId)
		if m then
			prep(m, def.Collide)
			tmpl[k] = m
		end
	end
	local rng = Random.new(EnvironmentConfig.Seed)
	local function place(kind: string, cf: CFrame, scale: number?, parent: Instance)
		local t = tmpl[kind]
		if not t then return end
		local m = t:Clone()
		if scale and scale ~= 1 then m:ScaleTo(scale) end
		m:PivotTo(cf)
		m.Parent = parent
	end

	-- arches across the canyon, aligned with its direction
	local arches = Instance.new("Folder")
	arches.Name = "Arches"
	arches.Parent = env
	for _, x in ipairs(EnvironmentConfig.ArchX) do
		local z = IslandShape.CanyonZ(x)
		local z2 = IslandShape.CanyonZ(x + 10)
		local tangent = Vector3.new(10, 0, z2 - z).Unit
		local pos = Vector3.new(x, IslandShape.CanyonFloor - 4, z)
		place("Arch", CFrame.lookAt(pos, pos + tangent), EnvironmentConfig.ArchScale, arches)
	end

	-- spires on high sandstone
	local spires = Instance.new("Folder")
	spires.Name = "Spires"
	spires.Parent = env
	local placed, tries = 0, 0
	while placed < EnvironmentConfig.Spires and tries < 2000 do
		tries += 1
		local x = rng:NextNumber(-IslandShape.Radii.X, IslandShape.Radii.X)
		local z = rng:NextNumber(-IslandShape.Radii.Y, IslandShape.Radii.Y)
		local h = if IslandShape.InAirfield(x, z, 120) then -100 else IslandShape.Height(x, z) -- keep the airfield clear
		if h > 170 and h < 360 and IslandShape.CanyonDist(x, z) > 220 then
			place("Spire", CFrame.new(x, h - 6, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(0.7, 1.3), spires)
			placed += 1
		end
	end

	-- pines on the green lowlands (in small clusters)
	local pines = Instance.new("Folder")
	pines.Name = "Pines"
	pines.Parent = env
	placed, tries = 0, 0
	while placed < EnvironmentConfig.Pines and tries < 8000 do
		tries += 1
		local x = rng:NextNumber(-IslandShape.Radii.X, IslandShape.Radii.X)
		local z = rng:NextNumber(-IslandShape.Radii.Y, IslandShape.Radii.Y)
		local h = if IslandShape.InAirfield(x, z, 120) then -100 else IslandShape.Height(x, z) -- keep the airfield clear
		if h > 10 and h < 165 and IslandShape.Material(x, z, h) ~= Enum.Material.Sand then
			for _ = 1, rng:NextInteger(1, 4) do
				local px, pz = x + rng:NextNumber(-40, 40), z + rng:NextNumber(-40, 40)
				local ph = IslandShape.Height(px, pz)
				if ph > 10 and ph < 170 then
					place("Pine", CFrame.new(px, ph - 2, pz) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.8, 1.5), pines)
					placed += 1
				end
			end
		end
		if placed % 40 == 0 then task.wait() end
	end

	-- boulders anywhere above the beach
	local boulders = Instance.new("Folder")
	boulders.Name = "Boulders"
	boulders.Parent = env
	placed, tries = 0, 0
	while placed < EnvironmentConfig.Boulders and tries < 3000 do
		tries += 1
		local x = rng:NextNumber(-IslandShape.Radii.X, IslandShape.Radii.X)
		local z = rng:NextNumber(-IslandShape.Radii.Y, IslandShape.Radii.Y)
		local h = if IslandShape.InAirfield(x, z, 120) then -100 else IslandShape.Height(x, z) -- keep the airfield clear
		if h > 12 then
			place("Boulder", CFrame.new(x, h - 3, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.6, 1.8), boulders)
			placed += 1
		end
	end

	env.Parent = map
end

return Environment
