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
-- Kept as AABB fallback when footprint has too few points.
local function paintPolygonAABB(terrain, worldPts, cy)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(worldPts) do
		minX = math.min(minX, p.X); minZ = math.min(minZ, p.Z)
		maxX = math.max(maxX, p.X); maxZ = math.max(maxZ, p.Z)
	end
	local sizeX = math.max(1, maxX - minX)
	local sizeZ = math.max(1, maxZ - minZ)
	terrain:FillBlock(CFrame.new((minX+maxX)*0.5, cy, (minZ+maxZ)*0.5),
		Vector3.new(sizeX, WATER_DEPTH, sizeZ), Enum.Material.Water)
end

-- Scanline polygon rasterisation: fills the actual polygon shape row by row.
-- material defaults to Water; pass Enum.Material.LeafyGrass etc. to cut islands.
local SCAN_STEP = 4  -- studs resolution per scanline row
local function paintPolygonScanline(terrain, worldPts, cy, material)
	material = material or Enum.Material.Water
	if #worldPts < 3 then return end
	local n = #worldPts
	local minZ, maxZ = math.huge, -math.huge
	for _, p in ipairs(worldPts) do
		minZ = math.min(minZ, p.Z); maxZ = math.max(maxZ, p.Z)
	end
	local z = minZ + SCAN_STEP * 0.5
	while z <= maxZ do
		-- Find X intersections with all edges at this Z
		local xs = {}
		for i = 1, n do
			local p1 = worldPts[i]
			local p2 = worldPts[(i % n) + 1]
			local z1, z2 = p1.Z, p2.Z
			if (z1 <= z and z < z2) or (z2 <= z and z < z1) then
				local t = (z - z1) / (z2 - z1)
				table.insert(xs, p1.X + t * (p2.X - p1.X))
			end
		end
		table.sort(xs)
		local i = 1
		while i + 1 <= #xs do
			local x0, x1 = xs[i], xs[i + 1]
			if x1 - x0 > 0.1 then
				terrain:FillBlock(
					CFrame.new((x0 + x1) * 0.5, cy, z),
					Vector3.new(x1 - x0, WATER_DEPTH, SCAN_STEP),
					material
				)
			end
			i = i + 2
		end
		z = z + SCAN_STEP
	end
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
	elseif water.footprint and #water.footprint >= 3 then
		-- Build world-space point array
		local cy = originStuds.y - WATER_DEPTH * 0.5
		local worldPts = {}
		for _, p in ipairs(water.footprint) do
			table.insert(worldPts, Vector3.new(p.x + originStuds.x, cy, p.z + originStuds.z))
		end
		-- Scanline fill for accurate polygon shape
		paintPolygonScanline(terrain, worldPts, cy, Enum.Material.Water)
		-- Restore islands: fill inner rings (holes) with terrain
		if water.holes then
			for _, hole in ipairs(water.holes) do
				if #hole >= 3 then
					local holePts = {}
					for _, p in ipairs(hole) do
						table.insert(holePts, Vector3.new(p.x + originStuds.x, cy, p.z + originStuds.z))
					end
					paintPolygonScanline(terrain, holePts, cy, Enum.Material.LeafyGrass)
				end
			end
		end
	end
end

return WaterBuilder
