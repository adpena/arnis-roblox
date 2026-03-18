local Workspace = game:GetService("Workspace")

local TerrainBuilder = {}

TerrainBuilder.DEFAULT_CLEAR_HEIGHT = 512

function TerrainBuilder.Clear(chunk)
	local terrainGrid = chunk.terrain
	if not terrainGrid then
		return
	end

	local terrain = Workspace.Terrain
	local cellSize = terrainGrid.cellSizeStuds
	local origin = chunk.originStuds

	local footprintWidth = terrainGrid.width * cellSize
	local footprintDepth = terrainGrid.depth * cellSize

	local clearSize = Vector3.new(footprintWidth, TerrainBuilder.DEFAULT_CLEAR_HEIGHT, footprintDepth)
	local clearCFrame = CFrame.new(
		origin.x + footprintWidth * 0.5,
		origin.y,
		origin.z + footprintDepth * 0.5
	)
	terrain:FillBlock(clearCFrame, clearSize, Enum.Material.Air)
end

local VOXEL_SIZE = 4
local TERRAIN_THICKNESS = 8 -- studs below the surface to fill

function TerrainBuilder.Build(_parent, chunk)
	local terrainGrid = chunk.terrain
	if not terrainGrid then return end

	TerrainBuilder.Clear(chunk)

	local terrain = Workspace.Terrain
	local cellSize = terrainGrid.cellSizeStuds
	local origin = chunk.originStuds
	local totalWidth = terrainGrid.width * cellSize
	local totalDepth = terrainGrid.depth * cellSize

	-- Find height bounds for region sizing
	local minH = 0
	local maxH = 0
	for _, h in ipairs(terrainGrid.heights) do
		if h < minH then minH = h end
		if h > maxH then maxH = h end
	end

	-- Snap a value down or up to the nearest VOXEL_SIZE multiple
	local function snap(v, down)
		if down then
			return math.floor(v / VOXEL_SIZE) * VOXEL_SIZE
		else
			return math.ceil(v / VOXEL_SIZE) * VOXEL_SIZE
		end
	end

	local rMinX = snap(origin.x, true)
	local rMinY = snap(origin.y + minH - TERRAIN_THICKNESS, true)
	local rMinZ = snap(origin.z, true)
	local rMaxX = snap(origin.x + totalWidth, false)
	local rMaxY = snap(origin.y + maxH + VOXEL_SIZE, false)
	local rMaxZ = snap(origin.z + totalDepth, false)

	-- Ensure positive region dimensions
	if rMaxX <= rMinX then rMaxX = rMinX + VOXEL_SIZE end
	if rMaxY <= rMinY then rMaxY = rMinY + VOXEL_SIZE end
	if rMaxZ <= rMinZ then rMaxZ = rMinZ + VOXEL_SIZE end

	local vX = (rMaxX - rMinX) / VOXEL_SIZE
	local vY = (rMaxY - rMinY) / VOXEL_SIZE
	local vZ = (rMaxZ - rMinZ) / VOXEL_SIZE

	-- Pre-build 3D arrays (all Air, all 0 occupancy)
	local materials = table.create(vX)
	local occupancies = table.create(vX)
	for ix = 1, vX do
		materials[ix] = table.create(vY)
		occupancies[ix] = table.create(vY)
		for iy = 1, vY do
			materials[ix][iy] = table.create(vZ, Enum.Material.Air)
			occupancies[ix][iy] = table.create(vZ, 0)
		end
	end

	-- Resolve material for a given grid cell
	local function getMat(x, z)
		if terrainGrid.materials then
			local idx = z * terrainGrid.width + x + 1
			local name = terrainGrid.materials[idx]
			if name then
				local ok, m = pcall(function() return Enum.Material[name] end)
				if ok and m then return m end
			end
		end
		local name = terrainGrid.material
		local ok, m = pcall(function() return Enum.Material[name] end)
		if ok and m then return m end
		return Enum.Material.Grass
	end

	-- Fill voxels from terrain grid cells
	for cellZ = 0, terrainGrid.depth - 1 do
		for cellX = 0, terrainGrid.width - 1 do
			local idx = cellZ * terrainGrid.width + cellX + 1
			local surfH = terrainGrid.heights[idx] or 0
			local mat = getMat(cellX, cellZ)

			local worldSurfY = origin.y + surfH
			local worldBotY  = worldSurfY - TERRAIN_THICKNESS

			local wx0 = origin.x + cellX * cellSize
			local wz0 = origin.z + cellZ * cellSize
			local wx1 = wx0 + cellSize
			local wz1 = wz0 + cellSize

			-- Convert to 1-indexed voxel indices within the region
			local vx0 = math.max(1, math.floor((wx0 - rMinX) / VOXEL_SIZE) + 1)
			local vx1 = math.min(vX, math.ceil((wx1 - rMinX) / VOXEL_SIZE))
			local vz0 = math.max(1, math.floor((wz0 - rMinZ) / VOXEL_SIZE) + 1)
			local vz1 = math.min(vZ, math.ceil((wz1 - rMinZ) / VOXEL_SIZE))
			local vy0 = math.max(1, math.floor((worldBotY - rMinY) / VOXEL_SIZE) + 1)
			local vy1 = math.min(vY, math.ceil((worldSurfY - rMinY) / VOXEL_SIZE))

			for ix = vx0, vx1 do
				for iz = vz0, vz1 do
					for iy = vy0, vy1 do
						materials[ix][iy][iz] = mat
						occupancies[ix][iy][iz] = 1
					end
				end
			end
		end
	end

	local region = Region3.new(
		Vector3.new(rMinX, rMinY, rMinZ),
		Vector3.new(rMaxX, rMaxY, rMaxZ)
	)
	terrain:WriteVoxels(region, VOXEL_SIZE, materials, occupancies)
end

return TerrainBuilder
