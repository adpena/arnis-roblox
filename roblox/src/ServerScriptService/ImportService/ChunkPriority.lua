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

local function resolveChunkId(chunkLike)
    if type(chunkLike) ~= "table" then
        return ""
    end
    return chunkLike.chunkId or chunkLike.id or ""
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

local function buildChunkPriorityKey(chunkEntry)
    local chunkId = resolveChunkId(chunkEntry)
    local chunkX, chunkZ = parseChunkId(chunkId)

    return {
        ring = normalizeNumber(chunkEntry and chunkEntry.ring, math.huge),
        forwardBias = normalizeNumber(chunkEntry and chunkEntry.forwardBias, 0),
        chunkX = chunkX,
        chunkZ = chunkZ,
        chunkId = chunkId,
    }
end

local function compareChunkKeys(leftKey, rightKey)
    if leftKey.ring ~= rightKey.ring then
        return leftKey.ring < rightKey.ring
    end

    if leftKey.forwardBias ~= rightKey.forwardBias then
        return leftKey.forwardBias > rightKey.forwardBias
    end

    if leftKey.chunkX ~= rightKey.chunkX then
        return leftKey.chunkX < rightKey.chunkX
    end

    if leftKey.chunkZ ~= rightKey.chunkZ then
        return leftKey.chunkZ < rightKey.chunkZ
    end

    return leftKey.chunkId < rightKey.chunkId
end

function ChunkPriority.GetFeatureCount(chunkLike)
    return normalizeNumber(chunkLike and chunkLike.featureCount, 0)
end

function ChunkPriority.GetStreamingCost(chunkLike)
    return normalizeNumber(chunkLike and chunkLike.streamingCost, 0)
end

function ChunkPriority.BuildChunkPriorityKey(chunkEntry)
    return buildChunkPriorityKey(chunkEntry or {})
end

function ChunkPriority.CompareChunkEntries(left, right)
    return compareChunkKeys(ChunkPriority.BuildChunkPriorityKey(left), ChunkPriority.BuildChunkPriorityKey(right))
end

function ChunkPriority.SortChunkEntriesByPriority(chunkEntries)
    local sorted = {}
    for _, chunkEntry in ipairs(chunkEntries or {}) do
        table.insert(sorted, chunkEntry)
    end

    table.sort(sorted, ChunkPriority.CompareChunkEntries)
    return sorted
end

function ChunkPriority.SortChunkIdsByPriority(chunkIds, chunkEntriesById)
    local decorated = {}
    for _, chunkId in ipairs(chunkIds or {}) do
        local entry = type(chunkEntriesById) == "table" and chunkEntriesById[chunkId] or nil
        if type(entry) ~= "table" then
            entry = {
                id = chunkId,
                chunkId = chunkId,
            }
        end
        table.insert(decorated, {
            chunkId = chunkId,
            entry = entry,
        })
    end

    table.sort(decorated, function(left, right)
        if ChunkPriority.CompareChunkEntries(left.entry, right.entry) then
            return true
        end
        if ChunkPriority.CompareChunkEntries(right.entry, left.entry) then
            return false
        end
        return left.chunkId < right.chunkId
    end)

    local sortedChunkIds = {}
    for _, item in ipairs(decorated) do
        table.insert(sortedChunkIds, item.chunkId)
    end
    return sortedChunkIds
end

function ChunkPriority.GetCanonicalLayerRank(layerOrWorkItem)
    local layer = layerOrWorkItem
    if type(layerOrWorkItem) == "table" then
        local subplan = layerOrWorkItem.subplan
        layer = subplan and subplan.layer or nil
    end

    return CANONICAL_LAYER_ORDER[layer] or math.huge
end

function ChunkPriority.BuildPriorityKey(workItem, sourceOrder)
    local chunkKey = buildChunkPriorityKey(workItem or {})
    local subplan = workItem and workItem.subplan or {}

    return {
        ring = chunkKey.ring,
        forwardBias = chunkKey.forwardBias,
        layerRank = ChunkPriority.GetCanonicalLayerRank(workItem),
        chunkX = chunkKey.chunkX,
        chunkZ = chunkKey.chunkZ,
        chunkId = chunkKey.chunkId,
        sourceOrder = normalizeNumber(sourceOrder or workItem and workItem.sourceOrder, math.huge),
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

    if leftKey.sourceOrder ~= rightKey.sourceOrder then
        return leftKey.sourceOrder < rightKey.sourceOrder
    end

    return leftKey.subplanId < rightKey.subplanId
end

function ChunkPriority.SortWorkItems(workItems)
    local decorated = {}
    for index, workItem in ipairs(workItems or {}) do
        table.insert(decorated, {
            item = workItem,
            sourceOrder = index,
        })
    end

    table.sort(decorated, function(left, right)
        local leftKey = ChunkPriority.BuildPriorityKey(left.item, left.sourceOrder)
        local rightKey = ChunkPriority.BuildPriorityKey(right.item, right.sourceOrder)

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

        if leftKey.sourceOrder ~= rightKey.sourceOrder then
            return leftKey.sourceOrder < rightKey.sourceOrder
        end

        return leftKey.subplanId < rightKey.subplanId
    end)

    local sorted = {}
    for _, item in ipairs(decorated) do
        table.insert(sorted, item.item)
    end
    return sorted
end

return ChunkPriority
