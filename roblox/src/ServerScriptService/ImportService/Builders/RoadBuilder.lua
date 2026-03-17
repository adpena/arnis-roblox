local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Shared.Logger)

local RoadBuilder = {}

-- Maps road kind → Roblox terrain material and a darkening color overlay (optional).
local ROAD_MATERIAL = {
	motorway     = Enum.Material.ConcretePlank,
	trunk        = Enum.Material.ConcretePlank,
	primary      = Enum.Material.ConcretePlank,
	secondary    = Enum.Material.Asphalt,
	tertiary     = Enum.Material.Asphalt,
	residential  = Enum.Material.Asphalt,
	service      = Enum.Material.Asphalt,
	living_street= Enum.Material.Asphalt,
	footway      = Enum.Material.Pavement,
	path         = Enum.Material.Pavement,
	pedestrian   = Enum.Material.Pavement,
	cycleway     = Enum.Material.Pavement,
	steps        = Enum.Material.Pavement,
	track        = Enum.Material.Ground,
	unclassified = Enum.Material.Asphalt,
	default      = Enum.Material.Asphalt,
}

local ROAD_THICKNESS = 1  -- studs; road fills 0.5 studs into terrain + 0.5 above

local function getMaterial(materialName, kind)
	if materialName then
		local ok, m = pcall(function() return Enum.Material[materialName] end)
		if ok and m then return m end
	end
	return ROAD_MATERIAL[kind] or ROAD_MATERIAL.default
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
	local material = getMaterial(road.material, road.kind)
	local width    = road.widthStuds or 10

	for i = 1, #road.points - 1 do
		local p1 = offsetPoint(road.points[i],     originStuds)
		local p2 = offsetPoint(road.points[i + 1], originStuds)
		paintSegment(terrain, p1, p2, width, material)
	end
end

return RoadBuilder
