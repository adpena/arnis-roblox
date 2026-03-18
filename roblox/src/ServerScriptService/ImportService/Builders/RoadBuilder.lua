local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Shared.Logger)

local RoadBuilder = {}

-- Maps OSM surface tag → Roblox terrain material (checked before kind fallback)
local SURFACE_MATERIAL = {
	asphalt             = Enum.Material.Asphalt,
	concrete            = Enum.Material.Concrete,
	["concrete:plates"] = Enum.Material.Concrete,
	cobblestone         = Enum.Material.Cobblestone,
	paving_stones       = Enum.Material.Pavement,
	bricks              = Enum.Material.Cobblestone,
	sett                = Enum.Material.Cobblestone,
	gravel              = Enum.Material.Ground,
	fine_gravel         = Enum.Material.Ground,
	compacted           = Enum.Material.Ground,
	pebblestone         = Enum.Material.Ground,
	rock                = Enum.Material.Rock,
	unpaved             = Enum.Material.Mud,
	dirt                = Enum.Material.Mud,
	earth               = Enum.Material.Mud,
	grass               = Enum.Material.Grass,
	wood                = Enum.Material.SmoothPlastic,
	stepping_stones     = Enum.Material.Pavement,
	paved               = Enum.Material.Concrete,
	sand                = Enum.Material.Sand,
}

-- Maps road kind → Roblox terrain material for Terrain:FillBlock
local ROAD_MATERIAL = {
	-- Highways: smooth concrete
	motorway      = Enum.Material.Concrete,
	motorway_link = Enum.Material.Concrete,
	trunk         = Enum.Material.Concrete,
	trunk_link    = Enum.Material.Concrete,
	-- Primary/secondary: asphalt
	primary       = Enum.Material.Asphalt,
	primary_link  = Enum.Material.Asphalt,
	secondary     = Enum.Material.Asphalt,
	secondary_link= Enum.Material.Asphalt,
	-- Local streets: asphalt (slightly different feel via paint order)
	tertiary      = Enum.Material.Asphalt,
	tertiary_link = Enum.Material.Asphalt,
	residential   = Enum.Material.Asphalt,
	living_street = Enum.Material.Pavement,
	service       = Enum.Material.Limestone,
	-- Pedestrian / cycling
	footway       = Enum.Material.Pavement,
	path          = Enum.Material.Cobblestone,
	pedestrian    = Enum.Material.SmoothPlastic,
	cycleway      = Enum.Material.Sandstone,
	steps         = Enum.Material.Slate,
	bridleway     = Enum.Material.Ground,
	-- Unpaved
	track         = Enum.Material.Mud,
	unclassified  = Enum.Material.Ground,
	road          = Enum.Material.Ground,
	default       = Enum.Material.Asphalt,
}

local ROAD_THICKNESS = 1  -- studs; road fills 0.5 studs into terrain + 0.5 above

local function getMaterial(road)
	-- 1. OSM surface tag takes priority (most specific physical description)
	if road.surface then
		local m = SURFACE_MATERIAL[road.surface]
		if m then return m end
	end
	-- 2. Legacy manifest material name (Enum.Material string)
	if road.material then
		local ok, m = pcall(function() return Enum.Material[road.material] end)
		if ok and m then return m end
	end
	-- 3. Road kind fallback
	return ROAD_MATERIAL[road.kind] or ROAD_MATERIAL.default
end

local function offsetPoint(point, origin)
	return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

-- Paint one road segment into terrain using FillBlock.
-- This mirrors Arnis / Minecraft: each road segment overwrites the terrain at its
-- footprint with road material, so intersections are seamless — no z-fighting,
-- no gaps at chunk edges, no floating parts.
local function paintSegment(terrain, p1, p2, width, material)
	local delta  = p2 - p1
	local length = delta.Magnitude
	if length < 0.01 then return end

	-- Center the slab so its top surface sits at Y=p1.Y (road surface level).
	local midY   = p1.Y - ROAD_THICKNESS * 0.5
	local midPos = Vector3.new(
		(p1.X + p2.X) * 0.5,
		midY,
		(p1.Z + p2.Z) * 0.5
	)

	-- lookAt rotates the CFrame so its -Z axis points toward p2.
	-- FillBlock honours the rotation → oriented slab aligned with the road.
	local cf = CFrame.lookAt(midPos, Vector3.new(p2.X, midY, p2.Z))
	terrain:FillBlock(cf, Vector3.new(width, ROAD_THICKNESS, length), material)
end

-- Build ALL roads in a chunk by painting them into the terrain.
function RoadBuilder.BuildAll(parent, roads, originStuds)
	if not roads or #roads == 0 then return end
	local terrain = Workspace.Terrain
	for _, road in ipairs(roads) do
		RoadBuilder.FallbackBuild(parent, road, originStuds)
	end
end

function RoadBuilder.Build(parent, road, originStuds)
	RoadBuilder.FallbackBuild(parent, road, originStuds)
end

function RoadBuilder.FallbackBuild(_parent, road, originStuds)
	local terrain  = Workspace.Terrain
	local material = getMaterial(road)
	local width    = road.widthStuds or 10

	for i = 1, #road.points - 1 do
		local p1 = offsetPoint(road.points[i],     originStuds)
		local p2 = offsetPoint(road.points[i + 1], originStuds)
		paintSegment(terrain, p1, p2, width, material)
	end
end

return RoadBuilder
