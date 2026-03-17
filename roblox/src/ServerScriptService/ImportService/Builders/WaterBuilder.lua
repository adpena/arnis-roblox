local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _Logger = require(ReplicatedStorage.Shared.Logger)

local WaterBuilder = {}

-- Water fills 2 studs deep from the surface so it looks like a body of water.
local WATER_DEPTH = 2

local function offsetPoint(point, origin)
	return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

-- Paint a ribbon water feature (river/stream) into terrain.
local function paintRibbonSegment(terrain, p1, p2, width)
	local delta  = p2 - p1
	local length = delta.Magnitude
	if length < 0.01 then return end

	local midY = p1.Y - WATER_DEPTH * 0.5
	local midPos = Vector3.new((p1.X + p2.X) * 0.5, midY, (p1.Z + p2.Z) * 0.5)
	local cf = CFrame.lookAt(midPos, Vector3.new(p2.X, midY, p2.Z))
	terrain:FillBlock(cf, Vector3.new(width, WATER_DEPTH, length), Enum.Material.Water)
end

-- Paint an axis-aligned water polygon (lake/pond) into terrain.
local function paintPolygon(terrain, footprint, originStuds)
	local minX, minZ, maxX, maxZ
	for _, p in ipairs(footprint) do
		local x = p.x + originStuds.x
		local z = p.z + originStuds.z
		if not minX then
			minX, minZ, maxX, maxZ = x, z, x, z
		else
			minX = math.min(minX, x)
			minZ = math.min(minZ, z)
			maxX = math.max(maxX, x)
			maxZ = math.max(maxZ, z)
		end
	end
	if not minX then return end

	local sizeX = math.max(1, maxX - minX)
	local sizeZ = math.max(1, maxZ - minZ)
	local cx = (minX + maxX) * 0.5
	local cz = (minZ + maxZ) * 0.5
	local cy = originStuds.y - WATER_DEPTH * 0.5
	terrain:FillBlock(CFrame.new(cx, cy, cz), Vector3.new(sizeX, WATER_DEPTH, sizeZ), Enum.Material.Water)
end

function WaterBuilder.BuildAll(parent, waters, originStuds)
	if not waters or #waters == 0 then return end
	for _, water in ipairs(waters) do
		WaterBuilder.FallbackBuild(parent, water, originStuds)
	end
end

function WaterBuilder.Build(parent, water, originStuds)
	WaterBuilder.FallbackBuild(parent, water, originStuds)
end

function WaterBuilder.FallbackBuild(_parent, water, originStuds)
	local terrain = Workspace.Terrain
	if water.points then
		local width = water.widthStuds or 8
		for i = 1, #water.points - 1 do
			local p1 = offsetPoint(water.points[i],     originStuds)
			local p2 = offsetPoint(water.points[i + 1], originStuds)
			paintRibbonSegment(terrain, p1, p2, width)
		end
	elseif water.footprint then
		paintPolygon(terrain, water.footprint, originStuds)
	end
end

return WaterBuilder
