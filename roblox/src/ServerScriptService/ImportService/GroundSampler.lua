--!optimize 2
--!native

local GroundSampler = {}

local DEFAULT_CELL_SIZE = 16

function GroundSampler.sampleWorldHeight(chunk, worldX, worldZ)
    if not chunk or not chunk.terrain or not chunk.terrain.heights then
        return (chunk and chunk.originStuds and chunk.originStuds.y) or 0
    end

    local terrainGrid = chunk.terrain
    local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }
    local cellSize = terrainGrid.cellSizeStuds or DEFAULT_CELL_SIZE
    local width = terrainGrid.width or 0
    local depth = terrainGrid.depth or 0

    if width <= 0 or depth <= 0 then
        return origin.y
    end

    local relX = math.max(0, math.min(worldX - origin.x, width * cellSize - 0.001))
    local relZ = math.max(0, math.min(worldZ - origin.z, depth * cellSize - 0.001))
    local cellX = math.clamp(math.floor(relX / cellSize), 0, width - 1)
    local cellZ = math.clamp(math.floor(relZ / cellSize), 0, depth - 1)
    local idx = cellZ * width + cellX + 1
    local height = terrainGrid.heights[idx] or 0

    return origin.y + height
end

return GroundSampler
