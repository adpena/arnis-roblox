local ChunkPriority = {}

local CANONICAL_LAYER_ORDER = {
    terrain = 1,
    landuse = 2,
    roads = 3,
    buildings = 4,
    water = 5,
    props = 6,
}

local FEATURE_KEYS = {
    "roads",
    "rails",
    "buildings",
    "water",
    "props",
    "landuse",
    "barriers",
}

local STREAMING_COST_WEIGHTS = {
    roads = 4,
    rails = 3,
    buildings = 12,
    water = 2,
    props = 1,
    landuse = 6,
    barriers = 2,
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

local function getChunkCenter(chunkLike, chunkSizeStuds)
    local origin = chunkLike and chunkLike.originStuds or nil
    local halfSize = normalizeNumber(chunkSizeStuds, 256) * 0.5
    local x = type(origin) == "table" and normalizeNumber(origin.x, 0) or 0
    local y = type(origin) == "table" and normalizeNumber(origin.y, 0) or 0
    local z = type(origin) == "table" and normalizeNumber(origin.z, 0) or 0
    return x + halfSize, y, z + halfSize
end

local function getFocusXZ(focusPoint)
    if typeof(focusPoint) == "Vector3" then
        return focusPoint.X, focusPoint.Z
    end
    if type(focusPoint) == "table" then
        local x = normalizeNumber(focusPoint.X or focusPoint.x, 0)
        local z = normalizeNumber(focusPoint.Z or focusPoint.z, 0)
        return x, z
    end
    return 0, 0
end

local function getForwardXZ(forwardVector)
    if typeof(forwardVector) == "Vector3" then
        return forwardVector.X, forwardVector.Z
    end
    if type(forwardVector) == "table" then
        local x = normalizeNumber(forwardVector.X or forwardVector.x, 0)
        local z = normalizeNumber(forwardVector.Z or forwardVector.z, 0)
        return x, z
    end
    return 0, 0
end

local function computeForwardScore(chunkCenterX, chunkCenterZ, focusPoint, forwardVector)
    local focusX, focusZ = getFocusXZ(focusPoint)
    local dx = chunkCenterX - focusX
    local dz = chunkCenterZ - focusZ
    local dirX, dirZ = getForwardXZ(forwardVector)
    local dirMag = math.sqrt(dirX * dirX + dirZ * dirZ)
    local deltaMag = math.sqrt(dx * dx + dz * dz)
    if dirMag == 0 or deltaMag == 0 then
        return 0
    end
    return (dx * dirX + dz * dirZ) / (dirMag * deltaMag)
end

local function deriveFeatureCount(chunkLike)
    local total = 0
    for _, key in ipairs(FEATURE_KEYS) do
        local value = chunkLike and chunkLike[key] or nil
        if type(value) == "table" then
            total += #value
        end
    end
    if chunkLike and chunkLike.terrain ~= nil then
        total += 1
    end
    return total
end

local function deriveStreamingCost(chunkLike)
    local total = 0
    for key, weight in pairs(STREAMING_COST_WEIGHTS) do
        local value = chunkLike and chunkLike[key] or nil
        if type(value) == "table" then
            total += #value * weight
        end
    end
    if chunkLike and chunkLike.terrain ~= nil then
        total += 8
    end
    return total
end

function ChunkPriority.GetFeatureCount(chunkLike)
    if chunkLike and chunkLike.featureCount ~= nil then
        return normalizeNumber(chunkLike.featureCount, 0)
    end
    return deriveFeatureCount(chunkLike)
end

function ChunkPriority.GetStreamingCost(chunkLike)
    if chunkLike and chunkLike.streamingCost ~= nil then
        return normalizeNumber(chunkLike.streamingCost, 0)
    end
    return deriveStreamingCost(chunkLike)
end

function ChunkPriority.BuildChunkPriorityKey(chunkEntry, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    local chunkId = resolveChunkId(chunkEntry)
    local chunkCenterX, _, chunkCenterZ = getChunkCenter(chunkEntry, chunkSizeStuds)
    local focusX, focusZ = getFocusXZ(focusPoint)
    local dx = chunkCenterX - focusX
    local dz = chunkCenterZ - focusZ
    local chunkX, chunkZ = parseChunkId(chunkId)

    return {
        chunkId = chunkId,
        chunkX = chunkX,
        chunkZ = chunkZ,
        distSq = dx * dx + dz * dz,
        forwardScore = computeForwardScore(chunkCenterX, chunkCenterZ, focusPoint, forwardVector),
        streamingCost = ChunkPriority.GetStreamingCost(chunkEntry),
        observedCost = normalizeNumber(type(observedCostById) == "table" and observedCostById[chunkId], math.huge),
        featureCount = ChunkPriority.GetFeatureCount(chunkEntry),
    }
end

local function compareChunkKeys(leftKey, rightKey)
    if leftKey.distSq ~= rightKey.distSq then
        return leftKey.distSq < rightKey.distSq
    end

    if leftKey.forwardScore ~= rightKey.forwardScore then
        return leftKey.forwardScore > rightKey.forwardScore
    end

    if leftKey.streamingCost ~= rightKey.streamingCost then
        return leftKey.streamingCost < rightKey.streamingCost
    end

    if leftKey.observedCost ~= rightKey.observedCost then
        return leftKey.observedCost < rightKey.observedCost
    end

    if leftKey.featureCount ~= rightKey.featureCount then
        return leftKey.featureCount < rightKey.featureCount
    end

    if leftKey.chunkX ~= rightKey.chunkX then
        return leftKey.chunkX < rightKey.chunkX
    end

    if leftKey.chunkZ ~= rightKey.chunkZ then
        return leftKey.chunkZ < rightKey.chunkZ
    end

    return leftKey.chunkId < rightKey.chunkId
end

function ChunkPriority.CompareChunkEntries(left, right, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    return compareChunkKeys(
        ChunkPriority.BuildChunkPriorityKey(left, focusPoint, chunkSizeStuds, forwardVector, observedCostById),
        ChunkPriority.BuildChunkPriorityKey(right, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    )
end

function ChunkPriority.SortChunkEntriesByPriority(
    chunkEntries,
    focusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    table.sort(chunkEntries, function(left, right)
        return ChunkPriority.CompareChunkEntries(
            left,
            right,
            focusPoint,
            chunkSizeStuds,
            forwardVector,
            observedCostById
        )
    end)
    return chunkEntries
end

function ChunkPriority.SortChunkIdsByPriority(
    chunkIds,
    chunkRefById,
    focusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById
)
    table.sort(chunkIds, function(leftId, rightId)
        local left = type(chunkRefById) == "table" and chunkRefById[leftId] or { id = leftId, chunkId = leftId }
        local right = type(chunkRefById) == "table" and chunkRefById[rightId] or { id = rightId, chunkId = rightId }
        return ChunkPriority.CompareChunkEntries(
            left,
            right,
            focusPoint,
            chunkSizeStuds,
            forwardVector,
            observedCostById
        )
    end)
    return chunkIds
end

function ChunkPriority.GetCanonicalLayerRank(layerOrWorkItem)
    local layer = layerOrWorkItem
    if type(layerOrWorkItem) == "table" then
        local subplan = layerOrWorkItem.subplan
        layer = subplan and subplan.layer or nil
    end

    return CANONICAL_LAYER_ORDER[layer] or math.huge
end

function ChunkPriority.BuildPriorityKey(
    workItem,
    focusPoint,
    chunkSizeStuds,
    forwardVector,
    observedCostById,
    sourceOrder
)
    local chunkKey =
        ChunkPriority.BuildChunkPriorityKey(workItem, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    local subplan = workItem and workItem.subplan or {}

    return {
        chunkId = chunkKey.chunkId,
        chunkX = chunkKey.chunkX,
        chunkZ = chunkKey.chunkZ,
        distSq = chunkKey.distSq,
        forwardScore = chunkKey.forwardScore,
        streamingCost = chunkKey.streamingCost,
        observedCost = chunkKey.observedCost,
        featureCount = chunkKey.featureCount,
        layerRank = ChunkPriority.GetCanonicalLayerRank(workItem),
        sourceOrder = normalizeNumber(sourceOrder or workItem and workItem.sourceOrder, math.huge),
        subplanId = subplan.id or "",
    }
end

function ChunkPriority.CompareWorkItems(left, right, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    local leftKey = ChunkPriority.BuildPriorityKey(left, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    local rightKey = ChunkPriority.BuildPriorityKey(right, focusPoint, chunkSizeStuds, forwardVector, observedCostById)

    if leftKey.distSq ~= rightKey.distSq then
        return leftKey.distSq < rightKey.distSq
    end

    if leftKey.forwardScore ~= rightKey.forwardScore then
        return leftKey.forwardScore > rightKey.forwardScore
    end

    if leftKey.layerRank ~= rightKey.layerRank then
        return leftKey.layerRank < rightKey.layerRank
    end

    if leftKey.sourceOrder ~= rightKey.sourceOrder then
        return leftKey.sourceOrder < rightKey.sourceOrder
    end

    if leftKey.streamingCost ~= rightKey.streamingCost then
        return leftKey.streamingCost < rightKey.streamingCost
    end

    if leftKey.observedCost ~= rightKey.observedCost then
        return leftKey.observedCost < rightKey.observedCost
    end

    if leftKey.featureCount ~= rightKey.featureCount then
        return leftKey.featureCount < rightKey.featureCount
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

function ChunkPriority.SortWorkItems(workItems, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    local decorated = {}
    for index, workItem in ipairs(workItems or {}) do
        decorated[index] = {
            item = workItem,
            sourceOrder = index,
        }
    end

    table.sort(decorated, function(left, right)
        local leftKey = ChunkPriority.BuildPriorityKey(
            left.item,
            focusPoint,
            chunkSizeStuds,
            forwardVector,
            observedCostById,
            left.sourceOrder
        )
        local rightKey = ChunkPriority.BuildPriorityKey(
            right.item,
            focusPoint,
            chunkSizeStuds,
            forwardVector,
            observedCostById,
            right.sourceOrder
        )

        if leftKey.distSq ~= rightKey.distSq then
            return leftKey.distSq < rightKey.distSq
        end

        if leftKey.forwardScore ~= rightKey.forwardScore then
            return leftKey.forwardScore > rightKey.forwardScore
        end

        if leftKey.layerRank ~= rightKey.layerRank then
            return leftKey.layerRank < rightKey.layerRank
        end

        if leftKey.sourceOrder ~= rightKey.sourceOrder then
            return leftKey.sourceOrder < rightKey.sourceOrder
        end

        if leftKey.streamingCost ~= rightKey.streamingCost then
            return leftKey.streamingCost < rightKey.streamingCost
        end

        if leftKey.observedCost ~= rightKey.observedCost then
            return leftKey.observedCost < rightKey.observedCost
        end

        if leftKey.featureCount ~= rightKey.featureCount then
            return leftKey.featureCount < rightKey.featureCount
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
    end)

    for index, entry in ipairs(decorated) do
        workItems[index] = entry.item
    end

    return workItems
end

return ChunkPriority
