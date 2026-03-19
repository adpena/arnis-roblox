local AustinSpawn = {}

local ROAD_PRIORITY = {
    footway = 10,
    pedestrian = 12,
    path = 14,
    cycleway = 16,
    living_street = 18,
    service = 20,
    residential = 24,
    unclassified = 28,
    tertiary = 36,
    secondary = 52,
    primary = 80,
    trunk = 140,
    motorway_link = 220,
    motorway = 260,
    track = 280,
}

local function getRoadPriority(kind)
    return ROAD_PRIORITY[kind] or 65
end

local EXCLUDED_SPAWN_KINDS = {
    motorway = true,
    motorway_link = true,
    trunk = true,
}

local AUSTIN_CANONICAL_WORLD_NAMES = {
    ExportedWorld = true,
    AustinPreviewDowntown = true,
}

local AUSTIN_SOUTH_OF_CAPITOL_OFFSET_STUDS = -192
local anchorCache = setmetatable({}, { __mode = "k" })

local function getLoadCenter(loadCenter)
    if typeof(loadCenter) == "Vector3" then
        return loadCenter.X, loadCenter.Z
    end

    if type(loadCenter) == "table" then
        return loadCenter.x or 0, loadCenter.z or 0
    end

    return 0, 0
end

local function getAnchorCacheKey(loadRadius, loadCenter)
    local centerX, centerZ = getLoadCenter(loadCenter)
    local centerY = 0
    if typeof(loadCenter) == "Vector3" then
        centerY = loadCenter.Y
    elseif type(loadCenter) == "table" then
        centerY = loadCenter.y or 0
    end
    return table.concat({
        tostring(loadRadius or "nil"),
        tostring(centerX),
        tostring(centerY),
        tostring(centerZ),
    }, "|")
end

local function isChunkWithinRadius(chunk, manifest, loadRadius, loadCenter)
    if not loadRadius then
        return true
    end

    local chunkSize = manifest.meta and manifest.meta.chunkSizeStuds or 256
    local origin = chunk.originStuds or { x = 0, z = 0 }
    local centerX = origin.x + chunkSize * 0.5
    local centerZ = origin.z + chunkSize * 0.5
    local loadCenterX, loadCenterZ = getLoadCenter(loadCenter)
    local dx = centerX - loadCenterX
    local dz = centerZ - loadCenterZ

    local loadRadiusSq = loadRadius * loadRadius
    return dx * dx + dz * dz <= loadRadiusSq
end

local function iterChunkRefs(manifest)
    if not manifest then
        return {}
    end

    if manifest.chunks then
        return manifest.chunks
    end

    if manifest.chunkRefs then
        return manifest.chunkRefs
    end

    return {}
end

local function materializeChunksForSelection(manifest, loadRadius, loadCenter)
    if not manifest then
        return {}
    end

    if type(manifest.chunks) == "table" and #manifest.chunks > 0 then
        return manifest.chunks
    end

    if type(manifest.LoadChunksWithinRadius) == "function" then
        local focusCenter = loadCenter or AustinSpawn.findFocusPoint(manifest, loadRadius, loadCenter)
        local ok, chunksOrErr = pcall(function()
            return manifest:LoadChunksWithinRadius(focusCenter, loadRadius)
        end)
        if ok and type(chunksOrErr) == "table" then
            return chunksOrErr
        end
    end

    return {}
end

local function isAustinCanonicalWorld(manifest)
    local meta = manifest and manifest.meta
    local worldName = meta and meta.worldName
    return type(worldName) == "string" and AUSTIN_CANONICAL_WORLD_NAMES[worldName] == true
end

local function getCanonicalAnchor(manifest)
    local meta = manifest and manifest.meta
    local canonicalAnchor = meta and meta.canonicalAnchor
    if type(canonicalAnchor) ~= "table" then
        return nil
    end
    return canonicalAnchor
end

local function applyCanonicalAnchor(manifest, fallbackPoint)
    local canonicalAnchor = getCanonicalAnchor(manifest)
    if type(canonicalAnchor) == "table" then
        local positionStuds = canonicalAnchor.positionStuds
        if type(positionStuds) == "table" then
            return Vector3.new(positionStuds.x or 0, positionStuds.y or 0, positionStuds.z or 0)
        end

        local offsetStuds = canonicalAnchor.positionOffsetFromHeuristicStuds
        if fallbackPoint and type(offsetStuds) == "table" then
            return Vector3.new(
                fallbackPoint.X + (offsetStuds.x or 0),
                fallbackPoint.Y + (offsetStuds.y or 0),
                fallbackPoint.Z + (offsetStuds.z or 0)
            )
        end
    end

    return nil
end

local function applyAustinCanonicalAnchorOverride(manifest, point)
    local canonicalPoint = applyCanonicalAnchor(manifest, point)
    if canonicalPoint then
        return canonicalPoint
    end

    if not point or not isAustinCanonicalWorld(manifest) then
        return point
    end

    -- In this Austin projection, moving to the south side of the Capitol requires
    -- shifting the heuristic anchor in the negative Z direction.
    return Vector3.new(point.X, point.Y, point.Z + AUSTIN_SOUTH_OF_CAPITOL_OFFSET_STUDS)
end

function AustinSpawn.getPreferredLookTarget(manifest, spawnPoint, fallbackFocusPoint)
    local canonicalAnchor = getCanonicalAnchor(manifest)
    local lookDirectionStuds = canonicalAnchor and canonicalAnchor.lookDirectionStuds
    if spawnPoint and type(lookDirectionStuds) == "table" then
        return Vector3.new(
            spawnPoint.X + (lookDirectionStuds.x or 0),
            spawnPoint.Y + (lookDirectionStuds.y or 0),
            spawnPoint.Z + (lookDirectionStuds.z or 0)
        )
    end

    if isAustinCanonicalWorld(manifest) and spawnPoint then
        return Vector3.new(spawnPoint.X, spawnPoint.Y, spawnPoint.Z + 1)
    end

    return fallbackFocusPoint or spawnPoint or Vector3.new(0, 0, 1)
end

function AustinSpawn.resolveAnchor(manifest, loadRadius, loadCenter)
    if not manifest then
        local origin = Vector3.new(0, 0, 0)
        return {
            focusPoint = origin,
            spawnPoint = origin,
            lookTarget = Vector3.new(0, 0, 1),
        }
    end

    local cacheKey = getAnchorCacheKey(loadRadius, loadCenter)
    local manifestCache = anchorCache[manifest]
    if manifestCache and manifestCache[cacheKey] then
        return manifestCache[cacheKey]
    end

    local heuristicFocusPoint = AustinSpawn.findFocusPoint(manifest, loadRadius, loadCenter)
    local bestPoint
    local bestScore
    local selectionCenter = loadCenter or heuristicFocusPoint
    local chunks = materializeChunksForSelection(manifest, loadRadius, heuristicFocusPoint)

    for _, chunk in ipairs(chunks) do
        if isChunkWithinRadius(chunk, manifest, loadRadius, selectionCenter) then
            local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }
            for _, road in ipairs(chunk.roads or {}) do
                if EXCLUDED_SPAWN_KINDS[road.kind] then
                    continue
                end
                local priority = getRoadPriority(road.kind)
                local points = road.points or {}

                for i = 1, #points - 1 do
                    local p1 = points[i]
                    local p2 = points[i + 1]
                    local midX = origin.x + (p1.x + p2.x) * 0.5
                    local midY = origin.y + (p1.y + p2.y) * 0.5
                    local midZ = origin.z + (p1.z + p2.z) * 0.5
                    local dx = midX - heuristicFocusPoint.X
                    local dz = midZ - heuristicFocusPoint.Z
                    local distSq = dx * dx + dz * dz
                    if math.abs(midY - heuristicFocusPoint.Y) > 18 then
                        continue
                    end
                    local score = priority * 100000000 + distSq

                    if not bestScore or score < bestScore then
                        bestScore = score
                        bestPoint = Vector3.new(midX, midY, midZ)
                    end
                end
            end
        end
    end

    local spawnPoint = applyAustinCanonicalAnchorOverride(manifest, bestPoint or heuristicFocusPoint)
    local anchor = {
        heuristicFocusPoint = heuristicFocusPoint,
        focusPoint = spawnPoint,
        spawnPoint = spawnPoint,
        lookTarget = AustinSpawn.getPreferredLookTarget(manifest, spawnPoint, heuristicFocusPoint),
        selectedChunks = chunks,
    }

    if not manifestCache then
        manifestCache = {}
        anchorCache[manifest] = manifestCache
    end
    manifestCache[cacheKey] = anchor

    return anchor
end

local function accumulatePoint(bounds, x, y, z)
    if not bounds.minX or x < bounds.minX then
        bounds.minX = x
    end
    if not bounds.maxX or x > bounds.maxX then
        bounds.maxX = x
    end
    if not bounds.minY or y < bounds.minY then
        bounds.minY = y
    end
    if not bounds.maxY or y > bounds.maxY then
        bounds.maxY = y
    end
    if not bounds.minZ or z < bounds.minZ then
        bounds.minZ = z
    end
    if not bounds.maxZ or z > bounds.maxZ then
        bounds.maxZ = z
    end
end

local function accumulateGroundY(bounds, y)
    if not bounds.minGroundY or y < bounds.minGroundY then
        bounds.minGroundY = y
    end
    if not bounds.maxGroundY or y > bounds.maxGroundY then
        bounds.maxGroundY = y
    end
end

function AustinSpawn.findFocusPoint(manifest, loadRadius, loadCenter)
    if not manifest then
        return Vector3.new(0, 0, 0)
    end

    local bounds = {}
    local chunkRefs = iterChunkRefs(manifest)
    local weightedX = 0
    local weightedZ = 0
    local weightedCount = 0

    local function accumulateFocusPoint(x, z)
        weightedX += x
        weightedZ += z
        weightedCount += 1
    end

    for _, chunk in ipairs(chunkRefs) do
        if isChunkWithinRadius(chunk, manifest, loadRadius, loadCenter) then
            local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }

            if not chunk.roads and not chunk.buildings and not chunk.props then
                local chunkSize = manifest.meta and manifest.meta.chunkSizeStuds or 256
                accumulatePoint(bounds, origin.x, origin.y, origin.z)
                accumulatePoint(bounds, origin.x + chunkSize, origin.y, origin.z + chunkSize)
                accumulateGroundY(bounds, origin.y)
            end

            local terrain = chunk.terrain
            if terrain and terrain.heights then
                for _, height in ipairs(terrain.heights) do
                    accumulateGroundY(bounds, origin.y + (height or 0))
                end
            end

            for _, road in ipairs(chunk.roads or {}) do
                for _, point in ipairs(road.points or {}) do
                    local worldX = origin.x + point.x
                    local worldY = origin.y + point.y
                    local worldZ = origin.z + point.z
                    accumulatePoint(bounds, worldX, worldY, worldZ)
                    accumulateGroundY(bounds, worldY)
                    accumulateFocusPoint(worldX, worldZ)
                end
            end

            for _, building in ipairs(chunk.buildings or {}) do
                local baseY = origin.y + (building.baseY or 0)
                for _, point in ipairs(building.footprint or {}) do
                    local worldX = origin.x + point.x
                    local worldZ = origin.z + point.z
                    accumulatePoint(bounds, worldX, baseY, worldZ)
                    accumulateFocusPoint(worldX, worldZ)
                end
                accumulateGroundY(bounds, baseY)
            end

            for _, prop in ipairs(chunk.props or {}) do
                local position = prop.position
                if position then
                    local worldX = origin.x + position.x
                    local worldY = origin.y + position.y
                    local worldZ = origin.z + position.z
                    accumulatePoint(bounds, worldX, worldY, worldZ)
                    accumulateFocusPoint(worldX, worldZ)
                end
            end
        end
    end

    if not bounds.minX then
        return Vector3.new(0, 0, 0)
    end

    local focusY
    if bounds.minGroundY ~= nil and bounds.maxGroundY ~= nil then
        focusY = (bounds.minGroundY + bounds.maxGroundY) * 0.5
    else
        focusY = (bounds.minY + bounds.maxY) * 0.5
    end

    local focusX = (bounds.minX + bounds.maxX) * 0.5
    local focusZ = (bounds.minZ + bounds.maxZ) * 0.5
    if weightedCount > 0 then
        focusX = weightedX / weightedCount
        focusZ = weightedZ / weightedCount
    end

    return Vector3.new(focusX, focusY, focusZ)
end

function AustinSpawn.findPreviewFocusPoint(manifest, loadRadius, loadCenter)
    return AustinSpawn.resolveAnchor(manifest, loadRadius, loadCenter).focusPoint
end

function AustinSpawn.findSpawnPoint(manifest, loadRadius, loadCenter)
    return AustinSpawn.resolveAnchor(manifest, loadRadius, loadCenter).spawnPoint
end

return AustinSpawn
