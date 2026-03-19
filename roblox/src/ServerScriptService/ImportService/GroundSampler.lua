--!optimize 2
--!native

local GroundSampler = {}
local samplerCache = setmetatable({}, { __mode = "k" })

local DEFAULT_CELL_SIZE = 2 -- matches ExportConfig.terrain_cell_size default
local function lerp(a, b, t)
    return a + (b - a) * t
end

local function buildSampler(chunk)
    if not chunk or not chunk.terrain or not chunk.terrain.heights then
        local fallbackY = (chunk and chunk.originStuds and chunk.originStuds.y) or 0
        return function()
            return fallbackY
        end
    end

    local terrainGrid = chunk.terrain
    local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }
    local originX = origin.x
    local originY = origin.y
    local originZ = origin.z
    local cellSize = terrainGrid.cellSizeStuds or DEFAULT_CELL_SIZE
    local width = terrainGrid.width or 0
    local depth = terrainGrid.depth or 0
    local heights = terrainGrid.heights

    if width <= 0 or depth <= 0 then
        return function()
            return originY
        end
    end

    local maxRelX = math.max((width - 1) * cellSize, 0)
    local maxRelZ = math.max((depth - 1) * cellSize, 0)

    return function(worldX, worldZ)
        local relX = math.max(0, math.min(worldX - originX, maxRelX))
        local relZ = math.max(0, math.min(worldZ - originZ, maxRelZ))
        local gridX = relX / cellSize
        local gridZ = relZ / cellSize
        local cellX0 = math.clamp(math.floor(gridX), 0, width - 1)
        local cellZ0 = math.clamp(math.floor(gridZ), 0, depth - 1)
        local cellX1 = math.min(cellX0 + 1, width - 1)
        local cellZ1 = math.min(cellZ0 + 1, depth - 1)
        local fracX = math.clamp(gridX - cellX0, 0, 1)
        local fracZ = math.clamp(gridZ - cellZ0, 0, 1)

        local function sampleHeight(cellX, cellZ)
            local idx = cellZ * width + cellX + 1
            return heights[idx] or 0
        end

        local h00 = sampleHeight(cellX0, cellZ0)
        local h10 = sampleHeight(cellX1, cellZ0)
        local h01 = sampleHeight(cellX0, cellZ1)
        local h11 = sampleHeight(cellX1, cellZ1)
        local hx0 = lerp(h00, h10, fracX)
        local hx1 = lerp(h01, h11, fracX)
        local height = lerp(hx0, hx1, fracZ)

        return originY + height
    end
end

function GroundSampler.createSampler(chunk)
    local cached = samplerCache[chunk]
    if cached then
        return cached
    end

    local sampler = buildSampler(chunk)
    samplerCache[chunk] = sampler
    return sampler
end

function GroundSampler.sampleWorldHeight(chunk, worldX, worldZ)
    return GroundSampler.createSampler(chunk)(worldX, worldZ)
end

return GroundSampler
