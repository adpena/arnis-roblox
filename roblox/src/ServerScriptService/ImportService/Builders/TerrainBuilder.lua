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

	local dimX = vX
	local dimY = vY
	local dimZ = vZ

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
		if slope > (WorldConfig.SlopeRockThreshold or 1.0) then    -- > ~45°
			return Enum.Material.Rock
		elseif slope > (WorldConfig.SlopeGroundThreshold or 0.47) then -- > ~25°
			return Enum.Material.Ground
		end
		return baseMat
	end

	-- Strip-based WriteVoxels: process 16 Z-voxels at a time so peak memory is
	-- O(dimX * dimY * STRIP_DEPTH) instead of O(dimX * dimY * dimZ).
	-- At VoxelSize=1, a 256-stud chunk reduces peak allocation ~16x.
	local STRIP_DEPTH = 16

	-- Reusable strip buffers, allocated once and refilled each iteration.
	local stripMat = nil
	local stripOcc = nil

	local izBase = 1  -- 1-indexed global Z voxel, start of current strip
	while izBase <= dimZ do
		local izEnd   = math.min(izBase + STRIP_DEPTH - 1, dimZ)  -- inclusive, 1-indexed
		local stripLen = izEnd - izBase + 1  -- number of Z slices in this strip

		-- Allocate buffers on the first strip; reuse on subsequent strips.
		-- Inner Z dimension is always STRIP_DEPTH except possibly the last strip,
		-- so we allocate fresh when stripLen changes (only the final strip differs).
		if stripMat == nil or #stripMat[1][1] ~= stripLen then
			stripMat = table.create(dimX)
			stripOcc = table.create(dimX)
			for ix = 1, dimX do
				stripMat[ix] = table.create(dimY)
				stripOcc[ix] = table.create(dimY)
				for iy = 1, dimY do
					stripMat[ix][iy] = table.create(stripLen, Enum.Material.Air)
					stripOcc[ix][iy] = table.create(stripLen, 0)
				end
			end
		else
			-- Clear buffers back to Air/0 for reuse.
			for ix = 1, dimX do
				for iy = 1, dimY do
					local mRow = stripMat[ix][iy]
					local oRow = stripOcc[ix][iy]
					for s = 1, stripLen do
						mRow[s] = Enum.Material.Air
						oRow[s] = 0
					end
				end
			end
		end

		-- Fill this strip by iterating over terrain cells that overlap the strip's Z range.
		-- Global voxel Z range covered by this strip: [izBase, izEnd] (1-indexed).
		for cellZ = 0, gridD - 1 do
			local wz0 = origin.z + cellZ * cellSize
			local wz1 = wz0 + cellSize

			-- Global voxel Z range for this cell
			local cellVz0 = math.max(1,    math.floor((wz0 - rMinZ) / VOXEL_SIZE) + 1)
			local cellVz1 = math.min(dimZ, math.ceil((wz1 - rMinZ) / VOXEL_SIZE))

			-- Clamp to current strip window
			local stripVz0 = math.max(cellVz0, izBase)
			local stripVz1 = math.min(cellVz1, izEnd)
			if stripVz0 > stripVz1 then continue end

			for cellX = 0, gridW - 1 do
				local mat = getMat(cellX, cellZ)

				local wx0 = origin.x + cellX * cellSize
				local wx1 = wx0 + cellSize

				-- Voxel X range for this cell
				local vx0 = math.max(1,    math.floor((wx0 - rMinX) / VOXEL_SIZE) + 1)
				local vx1 = math.min(dimX, math.ceil((wx1 - rMinX) / VOXEL_SIZE))

				for ix = vx0, vx1 do
					local voxelWorldX = rMinX + (ix - 0.5) * VOXEL_SIZE
					local fracX = math.clamp((voxelWorldX - wx0) / cellSize, 0, 1)

					for globalIz = stripVz0, stripVz1 do
						local localIz = globalIz - izBase + 1  -- 1-indexed within strip

						local voxelWorldZ = rMinZ + (globalIz - 0.5) * VOXEL_SIZE
						local fracZ = math.clamp((voxelWorldZ - wz0) / cellSize, 0, 1)

						-- Interpolated surface height for this (X, Z) column
						local interpH = sampleInterpolatedHeight(cellX, cellZ, fracX, fracZ)
						local worldSurfY = origin.y + interpH
						local worldBotY  = worldSurfY - TERRAIN_THICKNESS

						local vy0 = math.max(1,    math.floor((worldBotY - rMinY) / VOXEL_SIZE) + 1)
						local vy1 = math.min(dimY, math.ceil((worldSurfY - rMinY) / VOXEL_SIZE))

						for iy = vy0, vy1 do
							stripMat[ix][iy][localIz] = mat
							stripOcc[ix][iy][localIz] = 1
						end
					end
				end
			end
		end

		-- Write this strip to Roblox terrain.
		local zWorldMin = rMinZ + (izBase - 1) * VOXEL_SIZE
		local zWorldMax = rMinZ + izEnd * VOXEL_SIZE
		local stripRegion = Region3.new(
			Vector3.new(rMinX, rMinY, zWorldMin),
			Vector3.new(rMaxX, rMaxY, zWorldMax)
		)
		terrain:WriteVoxels(stripRegion, VOXEL_SIZE, stripMat, stripOcc)

		izBase = izEnd + 1
	end
end

function TerrainBuilder.ImprintRoads(roads, originStuds, chunk)
	local terrain = Workspace.Terrain
	local voxelSize = WorldConfig.VoxelSize or 1

	for _, road in ipairs(roads) do
		if road.tunnel then continue end  -- don't imprint tunnels

		local halfWidth = (road.widthStuds or 10) * 0.5

		for i = 1, #road.points - 1 do
			local p1 = road.points[i]
			local p2 = road.points[i + 1]

			local worldP1 = Vector3.new(
				p1.x + originStuds.x,
				p1.y + originStuds.y,
				p1.z + originStuds.z
			)
			local worldP2 = Vector3.new(
				p2.x + originStuds.x,
				p2.y + originStuds.y,
				p2.z + originStuds.z
			)

			-- Compute segment direction and length
			local dir = (worldP2 - worldP1)
			local segLen = dir.Magnitude
			if segLen < 0.1 then continue end
			dir = dir.Unit

			-- Average road surface Y
			local surfaceY = (worldP1.Y + worldP2.Y) * 0.5

			-- Flatten terrain in a box along the road segment
			-- Fill with Asphalt at road level, Air above
			local midpoint = (worldP1 + worldP2) * 0.5

			-- Fill the road bed with the road's own material, falling back to Asphalt.
			local roadMat = Enum.Material.Asphalt
			if road.material then
				pcall(function() roadMat = Enum.Material[road.material] end)
			end
			terrain:FillBlock(
				CFrame.new(midpoint.X, surfaceY - 1, midpoint.Z) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), 0),
				Vector3.new(halfWidth * 2, 2, segLen),
				roadMat
			)
		end
	end
end

return TerrainBuilder
