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

-- Configurable via WorldConfig; defaults favor maximum fidelity
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local VOXEL_SIZE = WorldConfig.VoxelSize or 1
local TERRAIN_THICKNESS = WorldConfig.TerrainThickness or 8

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

	local gridW = terrainGrid.width
	local gridD = terrainGrid.depth
	local heights = terrainGrid.heights

	-- Bilinear interpolation of height at a fractional position within the grid.
	-- cellX/cellZ are 0-indexed cell coordinates; fracX/fracZ are [0,1] within that cell.
	local function sampleInterpolatedHeight(cellX, cellZ, fracX, fracZ)
		local function getH(cx, cz)
			cx = math.max(0, math.min(gridW - 1, cx))
			cz = math.max(0, math.min(gridD - 1, cz))
			return heights[cz * gridW + cx + 1] or 0
		end
		local h00 = getH(cellX,     cellZ)
		local h10 = getH(cellX + 1, cellZ)
		local h01 = getH(cellX,     cellZ + 1)
		local h11 = getH(cellX + 1, cellZ + 1)
		local h0  = h00 + (h10 - h00) * fracX
		local h1  = h01 + (h11 - h01) * fracX
		return h0 + (h1 - h0) * fracZ
	end

	-- Slope at a cell as a rise/run ratio (gradient magnitude via central differences).
	local function computeSlope(cx, cz)
		local function getH(x, z)
			x = math.max(0, math.min(gridW - 1, x))
			z = math.max(0, math.min(gridD - 1, z))
			return heights[z * gridW + x + 1] or 0
		end
		local dhdx = (getH(cx + 1, cz) - getH(cx - 1, cz)) / (2 * cellSize)
		local dhdz = (getH(cx, cz + 1) - getH(cx, cz - 1)) / (2 * cellSize)
		return math.sqrt(dhdx * dhdx + dhdz * dhdz)
	end

	-- Resolve material for a given grid cell, with slope-based override.
	local function getMat(x, z)
		local baseMat
		if terrainGrid.materials then
			local idx = z * gridW + x + 1
			local name = terrainGrid.materials[idx]
			if name then
				local ok, m = pcall(function() return Enum.Material[name] end)
				if ok and m then baseMat = m end
			end
		end
		if not baseMat then
			local name = terrainGrid.material
			local ok, m = pcall(function() return Enum.Material[name] end)
			if ok and m then baseMat = m else baseMat = Enum.Material.Grass end
		end

		local slope = computeSlope(x, z)
		if slope > 1.0 then          -- > ~45°
			return Enum.Material.Rock
		elseif slope > 0.47 then     -- > ~25°
			return Enum.Material.Ground
		end
		return baseMat
	end

	-- Fill voxels from terrain grid cells, using per-voxel interpolated height
	-- so transitions between cells produce smooth slopes rather than flat plateaus.
	for cellZ = 0, gridD - 1 do
		for cellX = 0, gridW - 1 do
			local mat = getMat(cellX, cellZ)

			local wx0 = origin.x + cellX * cellSize
			local wz0 = origin.z + cellZ * cellSize
			local wx1 = wx0 + cellSize
			local wz1 = wz0 + cellSize

			-- Voxel column range for this cell in X and Z
			local vx0 = math.max(1, math.floor((wx0 - rMinX) / VOXEL_SIZE) + 1)
			local vx1 = math.min(vX, math.ceil((wx1 - rMinX) / VOXEL_SIZE))
			local vz0 = math.max(1, math.floor((wz0 - rMinZ) / VOXEL_SIZE) + 1)
			local vz1 = math.min(vZ, math.ceil((wz1 - rMinZ) / VOXEL_SIZE))

			for ix = vx0, vx1 do
				-- Fractional X position of this voxel centre within the cell [0,1]
				local voxelWorldX = rMinX + (ix - 0.5) * VOXEL_SIZE
				local fracX = math.clamp((voxelWorldX - wx0) / cellSize, 0, 1)

				for iz = vz0, vz1 do
					-- Fractional Z position of this voxel centre within the cell [0,1]
					local voxelWorldZ = rMinZ + (iz - 0.5) * VOXEL_SIZE
					local fracZ = math.clamp((voxelWorldZ - wz0) / cellSize, 0, 1)

					-- Interpolated surface height for this column
					local interpH = sampleInterpolatedHeight(cellX, cellZ, fracX, fracZ)
					local worldSurfY = origin.y + interpH
					local worldBotY  = worldSurfY - TERRAIN_THICKNESS

					local vy0 = math.max(1, math.floor((worldBotY - rMinY) / VOXEL_SIZE) + 1)
					local vy1 = math.min(vY, math.ceil((worldSurfY - rMinY) / VOXEL_SIZE))

					for iy = vy0, vy1 do
						materials[ix][iy][iz] = mat
						occupancies[ix][iy][iz] = 1
					end
				end
			end
		end
	end

	local dimX = vX
	local dimY = vY
	local dimZ = vZ

	local MAX_VOXELS_PER_CALL = 500000
	local totalVoxels = dimX * dimY * dimZ

	if totalVoxels <= MAX_VOXELS_PER_CALL then
		local region = Region3.new(
			Vector3.new(rMinX, rMinY, rMinZ),
			Vector3.new(rMaxX, rMaxY, rMaxZ)
		)
		terrain:WriteVoxels(region, VOXEL_SIZE, materials, occupancies)
	else
		-- Write in Z-strips to avoid exceeding Roblox WriteVoxels limits.
		-- Each strip covers the full X and Y range but only a subset of Z slices.
		local stripDepth = math.max(1, math.floor(MAX_VOXELS_PER_CALL / (dimX * dimY)))
		local iz = 1
		while iz <= dimZ do
			local iz1 = math.min(iz + stripDepth - 1, dimZ)
			local stripLen = iz1 - iz + 1

			-- Build sub-arrays for this Z strip
			local subMat = table.create(dimX)
			local subOcc = table.create(dimX)
			for ix = 1, dimX do
				subMat[ix] = table.create(dimY)
				subOcc[ix] = table.create(dimY)
				for iy = 1, dimY do
					subMat[ix][iy] = table.create(stripLen)
					subOcc[ix][iy] = table.create(stripLen)
					for s = 1, stripLen do
						subMat[ix][iy][s] = materials[ix][iy][iz + s - 1]
						subOcc[ix][iy][s] = occupancies[ix][iy][iz + s - 1]
					end
				end
			end

			local zWorldMin = rMinZ + (iz - 1) * VOXEL_SIZE
			local zWorldMax = rMinZ + iz1 * VOXEL_SIZE
			local stripRegion = Region3.new(
				Vector3.new(rMinX, rMinY, zWorldMin),
				Vector3.new(rMaxX, rMaxY, zWorldMax)
			)
			terrain:WriteVoxels(stripRegion, VOXEL_SIZE, subMat, subOcc)

			iz = iz1 + 1
		end
	end
end

return TerrainBuilder
