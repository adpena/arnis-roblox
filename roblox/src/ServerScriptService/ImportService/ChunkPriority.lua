local ChunkPriority = {}

local CANONICAL_LAYER_ORDER = {
    terrain = 1,
    landuse = 2,
    roads = 3,
    buildings = 4,
    water = 5,
    props = 6,
}

local function normalizeNumber(value, fallback)
    if type(value) ~= "number" then
        return fallback
    end
    return value
end

local function parseChunkId(chunkId)
    if type(chunkId) ~= "string" then
        return math.huge, math.huge
    end

    local xString, zString = string.match(chunkId, "^(-?%d+)_(-?%d+)$")
    local x = tonumber(xString)
    local z = tonumber(zString)
    if x == nil or z == nil then
        return math.huge, math.huge
    end
    return x, z
end

function ChunkPriority.GetCanonicalLayerRank(layerOrWorkItem)
    local layer = layerOrWorkItem
    if type(layerOrWorkItem) == "table" then
        local subplan = layerOrWorkItem.subplan
        layer = subplan and subplan.layer or nil
    end

    return CANONICAL_LAYER_ORDER[layer] or math.huge
end

function ChunkPriority.BuildPriorityKey(workItem)
    local chunkId = workItem.chunkId or ""
    local chunkX, chunkZ = parseChunkId(chunkId)
    local subplan = workItem.subplan or {}

    return {
        ring = normalizeNumber(workItem.ring, math.huge),
        forwardBias = normalizeNumber(workItem.forwardBias, 0),
        layerRank = ChunkPriority.GetCanonicalLayerRank(workItem),
        chunkX = chunkX,
        chunkZ = chunkZ,
        chunkId = chunkId,
        subplanId = subplan.id or "",
    }
end

function ChunkPriority.CompareWorkItems(left, right)
    local leftKey = ChunkPriority.BuildPriorityKey(left)
    local rightKey = ChunkPriority.BuildPriorityKey(right)

    if leftKey.ring ~= rightKey.ring then
        return leftKey.ring < rightKey.ring
    end

    if leftKey.forwardBias ~= rightKey.forwardBias then
        return leftKey.forwardBias > rightKey.forwardBias
    end

    if leftKey.layerRank ~= rightKey.layerRank then
        return leftKey.layerRank < rightKey.layerRank
    end

    if leftKey.chunkX ~= rightKey.chunkX then
        return leftKey.chunkX < rightKey.chunkX
    end

    if leftKey.chunkZ ~= rightKey.chunkZ then
        return leftKey.chunkZ < rightKey.chunkZ
    end

    if leftKey.chunkId ~= rightKey.chunkId then
        return leftKey.chunkId < rightKey.chunkId
    end

    return leftKey.subplanId < rightKey.subplanId
end

function ChunkPriority.SortWorkItems(workItems)
    local sorted = {}
    for _, workItem in ipairs(workItems or {}) do
        table.insert(sorted, workItem)
    end

    table.sort(sorted, ChunkPriority.CompareWorkItems)
    return sorted
end

return ChunkPriority
