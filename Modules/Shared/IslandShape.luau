--!strict
--[[
    IslandShape: the Kestrel Archipelago height field (GDD §11), shared by
    the terrain builder (Tools/BuildIsland.server.luau, run once in Studio)
    and by gameplay (AI altitude, prop placement, canyon missions).

    Pure functions of (x, z) in studs; sea level is y = 0.
]]

local IslandShape = {}

IslandShape.Centre = Vector2.new(0, 0)
IslandShape.Radii = Vector2.new(2300, 1850)
IslandShape.Volcano = Vector2.new(750, -420)
IslandShape.CanyonHalfWidth = 95
IslandShape.CanyonFloor = 50
-- West-coast airfield: a flat pad levelled into the hills (runway runs east-west along X,
-- apron/tower on the +Z side). Rect is [Centre.X +- HalfX] x [Centre.Y + MinZ .. Centre.Y + MaxZ].
IslandShape.Airfield = {
	Centre = Vector2.new(-1700, -550), -- runway centre (x, z)
	Elev = 60, -- pad height (runway surface sits ~0.3 above)
	HalfX = 780, -- runway 1200 long + approach lights
	MinZ = -70,
	MaxZ = 380, -- taxiway, apron, hangars
	Blend = 260,
	RunwayLength = 1200,
	RunwayWidth = 64,
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Canyon centre line z for a given x (winds east-west across the island)
function IslandShape.CanyonZ(x: number): number
	return 260 * math.sin(x / 720) + 70 * math.sin(x / 240 + 1.3) + 380
end

-- Distance from the canyon centre line (approximate, along z)
function IslandShape.CanyonDist(x: number, z: number): number
	return math.abs(z - IslandShape.CanyonZ(x))
end

function IslandShape.Mask(x: number, z: number): number
	local dx = (x - IslandShape.Centre.X) / IslandShape.Radii.X
	local dz = (z - IslandShape.Centre.Y) / IslandShape.Radii.Y
	local d = math.sqrt(dx * dx + dz * dz)
	-- wobbly coastline
	d += math.noise(x / 900, z / 900, 7.3) * 0.12
	return smooth((1.02 - d) / 0.32)
end

-- 0 inside the airfield pad, rising to 1 at the edge of its blend band (and beyond)
function IslandShape.AirfieldDist(x: number, z: number): number
	local a = IslandShape.Airfield
	local dx = math.max(math.abs(x - a.Centre.X) - a.HalfX, 0)
	local lz = z - a.Centre.Y
	local dz = if lz < a.MinZ then a.MinZ - lz elseif lz > a.MaxZ then lz - a.MaxZ else 0
	return math.sqrt(dx * dx + dz * dz) / a.Blend
end

function IslandShape.InAirfield(x: number, z: number, margin: number?): boolean
	return IslandShape.AirfieldDist(x, z) * IslandShape.Airfield.Blend <= (margin or 0)
end

local naturalHeight: (number, number) -> number

-- Height of the surface at (x, z). Values <= 0 are open sea.
function IslandShape.Height(x: number, z: number): number
	local h = naturalHeight(x, z)
	local d = IslandShape.AirfieldDist(x, z)
	if d < 1 then
		local t = smooth(d)
		h = IslandShape.Airfield.Elev * (1 - t) + h * t
	end
	return h
end

function naturalHeight(x: number, z: number): number
	local mask = IslandShape.Mask(x, z)
	if mask <= 0 then return -12 end
	local n = math.noise(x / 720, z / 720, 1.1) * 0.55 + math.noise(x / 270, z / 270, 2.7) * 0.28 + math.noise(x / 105, z / 105, 4.1) * 0.12
	local h = 30 + mask * (210 + n * 240)

	-- volcano with a crater
	local v = Vector2.new(x, z) - IslandShape.Volcano
	local vd = v.Magnitude
	local cone = math.max(0, 760 - vd * 1.05) * mask
	if vd < 150 then cone -= (150 - vd) * 2.2 end
	h = math.max(h, 40 + cone)

	-- carve the canyon (steep walls, flat lava-seamed floor)
	local cd = IslandShape.CanyonDist(x, z)
	local hw = IslandShape.CanyonHalfWidth
	if cd < hw * 1.6 then
		local floor = math.min(IslandShape.CanyonFloor, h)
		local t = math.clamp((cd - hw * 0.45) / (hw * 1.15), 0, 1)
		h = floor + (h - floor) * (t ^ 2.6)
	end

	-- fade to the sea floor at the coast
	return h * mask + (-12) * (1 - mask)
end

function IslandShape.Material(x: number, z: number, h: number): Enum.Material
	local ad = IslandShape.AirfieldDist(x, z)
	if ad <= 0 then return Enum.Material.LeafyGrass end
	if ad < 0.35 then return Enum.Material.Grass end
	if h < 6 then return Enum.Material.Sand end
	local cd = IslandShape.CanyonDist(x, z)
	if cd < 14 and h < IslandShape.CanyonFloor + 8 then return Enum.Material.CrackedLava end
	if cd < IslandShape.CanyonHalfWidth * 0.55 and h < IslandShape.CanyonFloor + 20 then return Enum.Material.Basalt end
	local vd = (Vector2.new(x, z) - IslandShape.Volcano).Magnitude
	if vd < 150 then return Enum.Material.CrackedLava end
	if vd < 420 then return Enum.Material.Basalt end
	if h > 360 then return Enum.Material.Basalt end
	if h > 170 or cd < IslandShape.CanyonHalfWidth * 1.3 then return Enum.Material.Sandstone end
	if h > 110 then return Enum.Material.Grass end
	return Enum.Material.LeafyGrass
end

return IslandShape
