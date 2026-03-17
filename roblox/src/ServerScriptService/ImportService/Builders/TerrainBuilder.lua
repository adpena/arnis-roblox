local Workspace = game:GetService("Workspace")

local TerrainBuilder = {}

TerrainBuilder.DEFAULT_CLEAR_HEIGHT = 512
local TERRAIN_THICKNESS = 4 -- studs to fill below the height surface

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

local function getHeight(grid, x, z)
	local index = z * grid.width + x + 1
	return grid.heights[index] or 0
end

local function getMaterial(grid, x, z)
	if not grid.materials then
		return Enum.Material[grid.material] or Enum.Material.Grass
	end
	local index = z * grid.width + x + 1
	local matName = grid.materials[index]
	return Enum.Material[matName] or Enum.Material[grid.material] or Enum.Material.Grass
end

function TerrainBuilder.Build(_parent, chunk)
	local terrainGrid = chunk.terrain
	if not terrainGrid then
		return
	end

	-- 1. Clear the chunk's terrain footprint first for idempotency.
	TerrainBuilder.Clear(chunk)

	local terrain = Workspace.Terrain
	local cellSize = terrainGrid.cellSizeStuds
	local origin = chunk.originStuds

	-- 2. Fill with actual material
	for z = 0, terrainGrid.depth - 1 do
		for x = 0, terrainGrid.width - 1 do
			local surfaceHeight = getHeight(terrainGrid, x, z)
			local material = getMaterial(terrainGrid, x, z)
			local cellCenterRelX = x * cellSize + cellSize * 0.5
			local cellCenterRelZ = z * cellSize + cellSize * 0.5

			-- We fill from (surfaceHeight - TERRAIN_THICKNESS) to surfaceHeight.
			local fillHeight = surfaceHeight + TERRAIN_THICKNESS
			if fillHeight > 0 then
				local fillSize = Vector3.new(cellSize, fillHeight, cellSize)
				local fillCFrame = CFrame.new(
					origin.x + cellCenterRelX,
					origin.y + surfaceHeight - (fillHeight * 0.5),
					origin.z + cellCenterRelZ
				)
				terrain:FillBlock(fillCFrame, fillSize, material)
			end
		end
	end
end

return TerrainBuilder
