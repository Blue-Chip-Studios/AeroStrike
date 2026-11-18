--!strict
--[[
    WorldServer
    -----------
    Loads every Blender-made model by asset id (Config is the source of
    truth), applies data-driven paint, and builds the live world:

        workspace.Map.Carrier     painted carrier + invisible colliders
        workspace.Jets            live jets (one per player, named by UserId)
        ServerStorage.Templates   cached, painted-on-demand jet templates

    Other modules: World:GetJetTemplate(jetId), World:ApplyPaint(model, paint),
    World:CarrierCFrame(), World:CatapultWorld(i).
]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")

local ModuleUtil = require(ReplicatedStorage.Shared.ModuleUtil)
local JetConfig = require(ReplicatedStorage.Config.JetConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local FlightConfig = require(ReplicatedStorage.Config.FlightConfig)
local IslandShape = require(ReplicatedStorage.Shared.IslandShape)

local World = ModuleUtil.New({
	Ready = false,
})

local oTemplates: Folder
local tJetTemplates: { [string]: Model } = {}

local function loadModel(nAssetId: number): Model?
	for attempt = 1, 4 do
		local ok, res = pcall(InsertService.LoadAsset, InsertService, nAssetId)
		if ok and res then
			local m = res:FindFirstChildWhichIsA("Model") or res
			if m:IsA("Model") then
				m.Parent = nil
				return m
			end
		end
		warn(`[World] LoadAsset {nAssetId} failed (attempt {attempt}): {res}`)
		task.wait(attempt)
	end
	return nil
end

function World.ApplyPaint(self, oModel: Model, tPaint: { [string]: { Color: Color3, Material: Enum.Material } })
	for _, d in ipairs(oModel:GetDescendants()) do
		if d:IsA("MeshPart") then
			local spec = tPaint[ModuleUtil.StripSuffix(d.Name)]
			if spec then
				d.Color = spec.Color
				d.Material = spec.Material
				-- PBR skin (panel lines, roughness, metalness) is greyscale: the paint tints it
				local sa = d:FindFirstChildOfClass("SurfaceAppearance")
				if sa then pcall(function() (sa :: any).Color = spec.Color end) end
				if spec.Material == Enum.Material.Glass then
					d.Transparency = 0.35
				end
			end
		end
	end
end

local function prepMeshes(oModel: Model)
	for _, d in ipairs(oModel:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.CastShadow = true
			d.Name = ModuleUtil.StripSuffix(d.Name)
		end
	end
end

-- Flyer templates (player jets and AI aircraft) get a Root (physics +
-- movers) and a Hitbox (gun/missile queries).
local function buildFlyerTemplate(nAssetId: number, sName: string): Model?
	local m = loadModel(nAssetId)
	if not m then return nil end
	prepMeshes(m)
	local cf, size = m:GetBoundingBox()

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = cf
	root.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0, 0)
	root.Parent = m

	local hit = Instance.new("Part")
	hit.Name = "Hitbox"
	hit.Size = Vector3.new(size.X * 0.7, size.Y * 0.9, size.Z * 0.9)
	hit.Transparency = 1
	hit.CanCollide = false
	hit.CanTouch = false
	hit.CanQuery = true
	hit.Massless = true
	hit.CFrame = cf
	hit.Parent = m

	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end

	local att = Instance.new("Attachment")
	att.Name = "RootAtt"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "Thrust"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "Steer"
	ao.Attachment0 = att
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.RigidityEnabled = true
	ao.CFrame = cf.Rotation
	ao.Parent = root

	-- engine glow light (cosmetic, client can scale it with throttle)
	local glow = m:FindFirstChild("Glow")
	if glow and glow:IsA("BasePart") then
		local pl = Instance.new("PointLight")
		pl.Name = "Afterburner"
		pl.Color = Color3.fromRGB(255, 150, 60)
		pl.Range = 14
		pl.Brightness = 2
		pl.Parent = glow
	end

	m.PrimaryPart = root
	m.Name = sName
	-- landing gear: the root (bbox centre) rides this far above the surface with gear down;
	-- GearController mounts the struts from GearSpan (the airframe's bbox size)
	m:SetAttribute("RideHeight", size.Y / 2 + FlightConfig.RideClearance)
	m:SetAttribute("GearSpan", size)
	return m
end

local tNpcTemplates: { [string]: Model } = {}

function World.GetJetTemplate(self, sJetId: string): Model?
	return tJetTemplates[sJetId]
end

function World.GetNpcTemplate(self, sKind: string): Model?
	return tNpcTemplates[sKind]
end

function World.CarrierCFrame(self): CFrame
	return MapConfig.Carrier.CFrame
end

function World.CatapultWorld(self, i: number): (CFrame, CFrame)
	local c = MapConfig.Carrier.Catapults[i]
	local base = MapConfig.Carrier.CFrame
	return base * c.Start, base * c.End
end

local function buildCarrier()
	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local old = map:FindFirstChild("Carrier")
	if old then old:Destroy() end

	local m = loadModel(MapConfig.Carrier.AssetId)
	if not m then
		warn("[World] carrier failed to load")
		return
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Name = ModuleUtil.StripSuffix(d.Name)
		end
	end
	World:ApplyPaint(m, MapConfig.Carrier.Paint)
	m.Name = "Carrier"
	m:PivotTo(MapConfig.Carrier.CFrame)

	local cols = Instance.new("Folder")
	cols.Name = "Colliders"
	cols.Parent = m
	for _, c in ipairs(MapConfig.Carrier.Colliders) do
		local p = Instance.new("Part")
		p.Name = c.Name
		p.Anchored = true
		p.Size = c.Size
		p.CFrame = MapConfig.Carrier.CFrame * c.CFrame
		p.Transparency = 1
		p.CanCollide = true
		p.CanQuery = true
		p.CanTouch = false
		p.Parent = cols
	end
	m.Parent = map
end

-- West-coast airfield: Blender runway/apron/tower/hangars on the levelled pad (IslandShape.Airfield),
-- plus invisible "Runway" colliders you can land and taxi on
local function buildAirfield()
	local cfg = MapConfig.Airfield
	if not cfg or cfg.AssetId == 0 then return end
	local map = workspace:FindFirstChild("Map") :: Folder
	local old = map:FindFirstChild("Airfield")
	if old then old:Destroy() end
	local m = loadModel(cfg.AssetId)
	if not m then warn("[World] airfield failed to load") return end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
			d.Name = ModuleUtil.StripSuffix(d.Name)
			d.CastShadow = d.Name ~= "Runway" and d.Name ~= "Markings" and d.Name ~= "Yellow" and d.Name ~= "Concrete"
		end
	end
	World:ApplyPaint(m, cfg.Paint)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and string.find(d.Name, "^Lights") then d.Material = Enum.Material.Neon end
	end
	local a = IslandShape.Airfield
	local runway = m:FindFirstChild("Runway") :: BasePart
	-- map the runway slab (top centre, long axis) onto the pad: centred, running along world X
	local cf = runway.CFrame
	local along = if runway.Size.X >= runway.Size.Z then cf.RightVector else cf.LookVector
	along = Vector3.new(along.X, 0, along.Z).Unit
	local topC = runway.Position + Vector3.new(0, runway.Size.Y / 2, 0)
	local from = CFrame.fromMatrix(topC, along, Vector3.yAxis)
	-- smooth terrain draws its surface about half a voxel above the filled height: measure it
	local tp = RaycastParams.new()
	tp.FilterType = Enum.RaycastFilterType.Include
	tp.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(a.Centre.X, a.Elev + 60, a.Centre.Y), Vector3.new(0, -120, 0), tp)
	local surfaceY = (if hit then hit.Position.Y else a.Elev) + 0.3
	workspace:SetAttribute("AirfieldSurfaceY", surfaceY)
	local centre = Vector3.new(a.Centre.X, surfaceY, a.Centre.Y)
	local to = CFrame.fromMatrix(centre, Vector3.xAxis, Vector3.yAxis)
	m:PivotTo(to * from:Inverse() * m:GetPivot())
	-- the apron/tower must sit on the +Z (inland) side of the runway
	local tower = m:FindFirstChild("Tower") :: BasePart?
	if tower and tower.Position.Z < a.Centre.Y then
		local c = CFrame.new(centre)
		m:PivotTo(c * CFrame.Angles(0, math.pi, 0) * c:Inverse() * m:GetPivot())
	end
	m.Name = "Airfield"
	-- colliders: runway + taxiway/apron (flat, landable, marked Runway)
	local cols = Instance.new("Folder")
	cols.Name = "Colliders"
	cols.Parent = m
	local function collider(name: string, cf: CFrame, size: Vector3)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, true, true, false
		p.Transparency = 1
		p.Size = size
		p.CFrame = cf
		p:SetAttribute("Runway", true)
		p.Parent = cols
	end
	collider("RunwayCollider", CFrame.new(a.Centre.X, surfaceY - 0.5, a.Centre.Y), Vector3.new(a.RunwayLength + 40, 1, a.RunwayWidth + 20))
	for _, d in ipairs(m:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "Concrete" then
			-- taxiway + apron share one mesh; cover its footprint at surface height
			collider("ApronCollider", CFrame.new(d.Position.X, surfaceY - 0.5, d.Position.Z), Vector3.new(d.Size.X, 1, d.Size.Z))
		end
	end
	m.Parent = map
end

local function applyLighting()
	-- "Golden Sortie" preset (GDD §26). Lighting.Technology = Future is a
	-- place setting (not scriptable at runtime); set once in Studio.
	Lighting.ClockTime = 16.6
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 3
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.ShadowSoftness = 0.35
	local function ensure(cls: string, name: string): Instance
		local i = Lighting:FindFirstChild(name) or Instance.new(cls)
		i.Name = name
		i.Parent = Lighting
		return i
	end
	local atm = ensure("Atmosphere", "AS_Atmosphere") :: Atmosphere
	atm.Density = 0.22
	atm.Offset = 0.05
	atm.Color = Color3.fromRGB(196, 214, 232)
	atm.Decay = Color3.fromRGB(120, 140, 170)
	atm.Glare = 0.35
	atm.Haze = 0.45
	local bloom = ensure("BloomEffect", "AS_Bloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6
	local rays = ensure("SunRaysEffect", "AS_SunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6
	local cc = ensure("ColorCorrectionEffect", "AS_Grade") :: ColorCorrectionEffect
	cc.Contrast = 0.08
	cc.Saturation = 0.06
	local terrain = workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(245, 245, 250)
	clouds.Parent = terrain
	terrain.WaterColor = Color3.fromRGB(18, 78, 110)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.25
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = 0.6
end

function World.PreloadAsync(self)
	oTemplates = ServerStorage:FindFirstChild("Templates") :: Folder or Instance.new("Folder")
	oTemplates.Name = "Templates"
	oTemplates.Parent = ServerStorage

	local jets = workspace:FindFirstChild("Jets") or Instance.new("Folder")
	jets.Name = "Jets"
	jets.Parent = workspace

	-- never let a cosmetic failure stop the server boot
	local ok, err = pcall(applyLighting)
	if not ok then warn("[World] lighting:", err) end
	buildCarrier()
	local okA, errA = pcall(buildAirfield)
	if not okA then warn("[World] airfield:", errA) end
	for sId, tJet in pairs(JetConfig.Jets) do
		local m = buildFlyerTemplate(tJet.ModelAssetId, tJet.Id)
		if m then
			m:SetAttribute("JetId", tJet.Id)
			-- PBR skins are authored in Studio (ServerStorage.PBR.<JetId>_Body), cloned onto the Body mesh
			local lib = ServerStorage:FindFirstChild("PBR")
			local sa = lib and lib:FindFirstChild(tJet.Id .. "_Body")
			local body = m:FindFirstChild("Body", true)
			if sa and body and body:IsA("MeshPart") then
				sa:Clone().Parent = body
			elseif not sa then
				warn(`[World] no PBR skin for {tJet.Id}`)
			end
			m.Parent = oTemplates
			tJetTemplates[sId] = m
		else
			warn(`[World] jet {sId} failed to load`)
		end
	end
	local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)
	for sKind, tKind in pairs(NpcConfig.Kinds) do
		if tKind.Jets then continue end -- bot pilots fly the player jet templates
		local m = buildFlyerTemplate(tKind.AssetId, sKind)
		if m then
			local skinLib = ServerStorage:FindFirstChild("PBR")
			local skin = tKind.Skin and skinLib and skinLib:FindFirstChild(tKind.Skin .. "_Body")
			local body = m:FindFirstChild("Body", true)
			if skin and body and body:IsA("MeshPart") then skin:Clone().Parent = body end
			self:ApplyPaint(m, tKind.Paint)
			if tKind.Scale then m:ScaleTo(tKind.Scale) end
			m.Parent = oTemplates
			tNpcTemplates[sKind] = m
		else
			warn(`[World] npc {sKind} failed to load`)
		end
	end
	-- client-side templates (local-only gameplay markers, e.g. FTUE/fuel rings)
	local ct = ReplicatedStorage:FindFirstChild("ClientTemplates") or Instance.new("Folder")
	ct.Name = "ClientTemplates"
	local ring = loadModel(MapConfig.RingAssetId)
	if ring then
		for _, d in ipairs(ring:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				d.Name = ModuleUtil.StripSuffix(d.Name)
				if d.Name == "Glow" then d.Material = Enum.Material.Neon; d.Color = Color3.fromRGB(92, 255, 143) end
				if d.Name == "Frame" then d.Material = Enum.Material.Metal; d.Color = Color3.fromRGB(30, 36, 42) end
			end
		end
		ring.Name = "Ring"
		ring.Parent = ct
	end
	-- Blender IR missile: cosmetic proxy for the server-simulated missiles (VfxController)
	local missile = loadModel(MapConfig.MissileAssetId)
	if missile then
		local paint = {
			Body = { Color3.fromRGB(226, 228, 232), Enum.Material.SmoothPlastic },
			Band = { Color3.fromRGB(255, 194, 61), Enum.Material.SmoothPlastic },
			Seeker = { Color3.fromRGB(20, 32, 38), Enum.Material.Glass },
			Trim = { Color3.fromRGB(46, 49, 54), Enum.Material.Metal },
			Glow = { Color3.fromRGB(255, 160, 70), Enum.Material.Neon },
		}
		local primary: BasePart? = nil
		for _, d in ipairs(missile:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				d.Name = ModuleUtil.StripSuffix(d.Name)
				local p = paint[d.Name]
				if p then d.Color = p[1]; d.Material = p[2] end
				if d.Name == "Body" then primary = d end
			end
		end
		missile.PrimaryPart = primary
		-- point the pivot's LookVector along the actual nose (Seeker ahead of Trim), measured in the
		-- Body's own space, so it is right whatever axes the FBX importer produced
		-- (with a PrimaryPart the pivot is PrimaryPart.CFrame * PivotOffset; WorldPivot is ignored)
		local seeker, trim = missile:FindFirstChild("Seeker"), missile:FindFirstChild("Trim")
		if primary and seeker and trim and seeker:IsA("BasePart") and trim:IsA("BasePart") then
			local noseWorld = (seeker.Position - trim.Position).Unit
			local noseLocal = primary.CFrame:VectorToObjectSpace(noseWorld)
			local up = if math.abs(noseLocal.Y) > 0.9 then Vector3.zAxis else Vector3.yAxis
			primary.PivotOffset = CFrame.lookAt(Vector3.zero, noseLocal, up)
		end
		missile.Name = "Missile"
		missile.Parent = ct
	end
	-- Blender ejection seat + pilot + parachute (VfxController plays the eject sequence)
	local chute = loadModel(MapConfig.ParachuteAssetId)
	if chute then
		local paint = {
			Canopy = { Color3.fromRGB(255, 120, 30), Enum.Material.Fabric },
			CanopyAlt = { Color3.fromRGB(236, 236, 230), Enum.Material.Fabric },
			Lines = { Color3.fromRGB(220, 220, 214), Enum.Material.SmoothPlastic },
			Pilot = { Color3.fromRGB(82, 92, 62), Enum.Material.Fabric },
			Helmet = { Color3.fromRGB(232, 232, 226), Enum.Material.SmoothPlastic },
			Visor = { Color3.fromRGB(22, 16, 10), Enum.Material.Glass },
			Seat = { Color3.fromRGB(42, 44, 48), Enum.Material.Metal },
		}
		for _, d in ipairs(chute:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
				d.Name = ModuleUtil.StripSuffix(d.Name)
				local p = paint[d.Name]
				if p then d.Color = p[1]; d.Material = p[2] end
			end
		end
		chute.Name = "Parachute"
		chute.Parent = ct
	end
	-- Blender landing gear (GearController mounts it on every player jet)
	local gear = loadModel(MapConfig.GearAssetId)
	if gear then
		local paint = {
			NoseStrut = { Color3.fromRGB(196, 198, 202), Enum.Material.Metal }, MainStrut = { Color3.fromRGB(196, 198, 202), Enum.Material.Metal },
			NoseWheel = { Color3.fromRGB(24, 24, 26), Enum.Material.Rubber }, MainWheel = { Color3.fromRGB(24, 24, 26), Enum.Material.Rubber },
			NoseDoor = { Color3.fromRGB(120, 126, 132), Enum.Material.Metal }, MainDoor = { Color3.fromRGB(120, 126, 132), Enum.Material.Metal },
		}
		for _, d in ipairs(gear:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = false, false, false, false, true
				d.Name = ModuleUtil.StripSuffix(d.Name)
				local p = paint[d.Name]
				if p then d.Color = p[1]; d.Material = p[2] end
			end
		end
		gear.Name = "Gear"
		gear.Parent = ct
	end
	ct.Parent = ReplicatedStorage

	local npc = workspace:FindFirstChild("NPC") or Instance.new("Folder")
	npc.Name = "NPC"
	npc.Parent = workspace
	self.Ready = true
end

return World
