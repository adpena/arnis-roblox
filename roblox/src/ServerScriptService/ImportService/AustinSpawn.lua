--!optimize 2
--!native

local AustinSpawn = {}

local PREVIEW_ROAD_PRIORITY = table.freeze({
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
})

local RUNTIME_SPAWN_ROAD_PRIORITY = table.freeze({
    service = 10,
    living_street = 12,
    residential = 16,
    unclassified = 20,
    tertiary = 36,
    secondary = 52,
    primary = 80,
    footway = 120,
    pedestrian = 130,
    cycleway = 140,
    path = 150,
    trunk = 220,
    motorway_link = 260,
    motorway = 300,
    track = 320,
})

local function getRoadPriority(kind, selectionMode)
    local priorities = if selectionMode == "runtime_spawn" then RUNTIME_SPAWN_ROAD_PRIORITY else PREVIEW_ROAD_PRIORITY
    return priorities[kind] or 65
end

local EXCLUDED_SPAWN_KINDS = table.freeze({
    motorway = true,
    motorway_link = true,
    trunk = true,
})

local AUSTIN_CANONICAL_WORLD_NAMES = table.freeze({
    ExportedWorld = true,
    AustinPreviewDowntown = true,
})

local AUSTIN_SOUTH_OF_CAPITOL_OFFSET_STUDS = -256
local RUNTIME_BUILDING_CLEARANCE_STUDS = 72
local RUNTIME_BUILDING_CLEARANCE_SCORE_SCALE = 1000
local RUNTIME_BUILDING_NEIGHBORHOOD_STUDS = 140
local RUNTIME_BUILDING_NEIGHBORHOOD_SCORE_SCALE = 10
local RUNTIME_ROOF_ONLY_NEIGHBORHOOD_WEIGHT = 20
local RUNTIME_BUILDING_INSIDE_FOOTPRINT_PENALTY = 1000000000
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

local function getLoadCenterVector(loadCenter, fallbackY)
    if typeof(loadCenter) == "Vector3" then
        return loadCenter
    end

    if type(loadCenter) == "table" then
        return Vector3.new(loadCenter.x or 0, loadCenter.y or fallbackY or 0, loadCenter.z or 0)
    end

    return nil
end

local function getAnchorCacheKey(loadRadius, loadCenter, selectionMode)
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
        tostring(selectionMode or "preview"),
    }, "|")
end

local function shouldCacheResolvedAnchor(manifest)
    if not manifest then
        return false
    end

    if type(manifest.LoadChunksWithinRadius) == "function" then
        return false
    end

    if type(manifest.GetChunk) == "function" and type(manifest.GetChunkIdsWithinRadius) == "function" then
        return false
    end

    return true
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

    if type(manifest.GetChunk) == "function" and type(manifest.GetChunkIdsWithinRadius) == "function" then
        local focusCenter = loadCenter or AustinSpawn.findFocusPoint(manifest, loadRadius, loadCenter)
        local ok, chunkIdsOrErr = pcall(function()
            return manifest:GetChunkIdsWithinRadius(focusCenter, loadRadius)
        end)
        if ok and type(chunkIdsOrErr) == "table" then
            local chunks = table.create(#chunkIdsOrErr)
            for _, chunkId in ipairs(chunkIdsOrErr) do
                local chunkOk, chunkOrErr = pcall(function()
                    return manifest:GetChunk(chunkId)
                end)
                if chunkOk and type(chunkOrErr) == "table" then
                    chunks[#chunks + 1] = chunkOrErr
                end
            end
            if #chunks > 0 then
                return chunks
            end
        end
    end

    if loadRadius == nil and type(manifest.chunkRefs) == "table" and type(manifest.GetChunk) == "function" then
        local chunks = table.create(#manifest.chunkRefs)
        for _, chunkRef in ipairs(manifest.chunkRefs) do
            local chunkId = chunkRef and chunkRef.id
            if type(chunkId) == "string" then
                local chunkOk, chunkOrErr = pcall(function()
                    return manifest:GetChunk(chunkId)
                end)
                if chunkOk and type(chunkOrErr) == "table" then
                    chunks[#chunks + 1] = chunkOrErr
                end
            end
        end
        if #chunks > 0 then
            return chunks
        end
    end

    return {}
end

local function materializeAllChunksForSelection(manifest)
    if not manifest then
        return {}
    end

    if type(manifest.chunks) == "table" and #manifest.chunks > 0 then
        return manifest.chunks
    end

    if type(manifest.chunkRefs) == "table" and type(manifest.GetChunk) == "function" then
        local chunks = table.create(#manifest.chunkRefs)
        for _, chunkRef in ipairs(manifest.chunkRefs) do
            local chunkId = chunkRef and chunkRef.id
            if type(chunkId) == "string" and chunkId ~= "" then
                local chunkOk, chunkOrErr = pcall(function()
                    return manifest:GetChunk(chunkId)
                end)
                if chunkOk and type(chunkOrErr) == "table" then
                    chunks[#chunks + 1] = chunkOrErr
                end
            end
        end
        if #chunks > 0 then
            return chunks
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

local function getExplicitCanonicalAnchorPosition(manifest)
    local canonicalAnchor = getCanonicalAnchor(manifest)
    if type(canonicalAnchor) ~= "table" then
        return nil
    end

    local positionStuds = canonicalAnchor.positionStuds
    if type(positionStuds) == "table" then
        return Vector3.new(positionStuds.x or 0, positionStuds.y or 0, positionStuds.z or 0)
    end

    return nil
end

local function applyRelativeCanonicalSpawnOffset(manifest, fallbackPoint)
    local canonicalAnchor = getCanonicalAnchor(manifest)
    if type(canonicalAnchor) == "table" then
        local offsetStuds = canonicalAnchor.positionOffsetFromHeuristicStuds
        if fallbackPoint and type(offsetStuds) == "table" then
            return Vector3.new(
                fallbackPoint.X + (offsetStuds.x or 0),
                fallbackPoint.Y + (offsetStuds.y or 0),
                fallbackPoint.Z + (offsetStuds.z or 0)
            )
        end
    end

    return fallbackPoint
end

local function hasRelativeCanonicalSpawnOffset(manifest)
    local canonicalAnchor = getCanonicalAnchor(manifest)
    if type(canonicalAnchor) ~= "table" then
        return false
    end

    return type(canonicalAnchor.positionOffsetFromHeuristicStuds) == "table"
end

local function getDesiredSpawnPoint(manifest, point)
    local explicitCanonicalPoint = getExplicitCanonicalAnchorPosition(manifest)
    if explicitCanonicalPoint then
        return explicitCanonicalPoint
    end

    local relativeCanonicalPoint = applyRelativeCanonicalSpawnOffset(manifest, point)
    if relativeCanonicalPoint ~= point then
        return relativeCanonicalPoint
    end

    if not point or not isAustinCanonicalWorld(manifest) then
        return point
    end

    -- In this Austin projection, moving to the south side of the Capitol requires
    -- biasing the target road search in the negative Z direction.
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

local function resolveAnchorInternal(manifest, loadRadius, loadCenter, selectionMode)
    if not manifest then
        local origin = Vector3.new(0, 0, 0)
        return {
            focusPoint = origin,
            spawnPoint = origin,
            lookTarget = Vector3.new(0, 0, 1),
        }
    end

    local cacheKey = getAnchorCacheKey(loadRadius, loadCenter, selectionMode)
    local canCacheResolvedAnchor = shouldCacheResolvedAnchor(manifest)
    local manifestCache = if canCacheResolvedAnchor then anchorCache[manifest] else nil
    if manifestCache and manifestCache[cacheKey] then
        return manifestCache[cacheKey]
    end

    local heuristicFocusPoint = AustinSpawn.findFocusPoint(manifest, loadRadius, loadCenter)
    local desiredSpawnPoint = getDesiredSpawnPoint(manifest, heuristicFocusPoint)
    local bestPoint
    local bestScore

    local function pointInPolygon2D(x, z, polygon)
        local inside = false
        local count = #polygon
        if count < 3 then
            return false
        end

        for i = 1, count do
            local current = polygon[i]
            local nextPoint = polygon[(i % count) + 1]
            local currentZAbove = current.Z > z
            local nextZAbove = nextPoint.Z > z
            if currentZAbove ~= nextZAbove then
                local edgeCrossX = current.X + (nextPoint.X - current.X) * ((z - current.Z) / (nextPoint.Z - current.Z))
                if x < edgeCrossX then
                    inside = not inside
                end
            end
        end

        return inside
    end

    local function distanceToSegment2D(px, pz, ax, az, bx, bz)
        local abX = bx - ax
        local abZ = bz - az
        local apX = px - ax
        local apZ = pz - az
        local denom = abX * abX + abZ * abZ
        local t = 0
        if denom > 0 then
            t = math.clamp((apX * abX + apZ * abZ) / denom, 0, 1)
        end
        local closestX = ax + abX * t
        local closestZ = az + abZ * t
        local dx = px - closestX
        local dz = pz - closestZ
        return math.sqrt(dx * dx + dz * dz)
    end

    local function collectBuildingFootprints(chunksToScan, radiusLimit, centerPoint)
        if selectionMode ~= "runtime_spawn" then
            return nil
        end

        local footprints = {}
        for _, chunk in ipairs(chunksToScan) do
            if isChunkWithinRadius(chunk, manifest, radiusLimit, centerPoint) then
                local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }
                for _, building in ipairs(chunk.buildings or {}) do
                    local footprint = building.footprint
                    if type(footprint) == "table" and #footprint >= 3 then
                        local worldFootprint = table.create(#footprint)
                        for pointIndex, point in ipairs(footprint) do
                            worldFootprint[pointIndex] = Vector3.new(origin.x + point.x, 0, origin.z + point.z)
                        end
                        local buildingUsage = string.lower(tostring(building.usage or building.kind or "unknown"))
                        footprints[#footprints + 1] = {
                            points = worldFootprint,
                            neighborhoodWeight = if buildingUsage == "roof"
                                then RUNTIME_ROOF_ONLY_NEIGHBORHOOD_WEIGHT
                                else 1,
                        }
                    end
                end
            end
        end

        return footprints
    end

    local function getRuntimeBuildingPenalty(px, pz, buildingFootprints)
        if not buildingFootprints or #buildingFootprints == 0 then
            return 0
        end

        local nearestDistance = math.huge
        local neighborhoodPenalty = 0
        for _, footprintEntry in ipairs(buildingFootprints) do
            local footprint = footprintEntry.points
            local neighborhoodWeight = footprintEntry.neighborhoodWeight or 1
            if pointInPolygon2D(px, pz, footprint) then
                return RUNTIME_BUILDING_INSIDE_FOOTPRINT_PENALTY
            end

            local footprintNearestDistance = math.huge
            for i = 1, #footprint do
                local pointA = footprint[i]
                local pointB = footprint[(i % #footprint) + 1]
                local edgeDistance = distanceToSegment2D(px, pz, pointA.X, pointA.Z, pointB.X, pointB.Z)
                footprintNearestDistance = math.min(footprintNearestDistance, edgeDistance)
            end

            nearestDistance = math.min(nearestDistance, footprintNearestDistance)
            if footprintNearestDistance < RUNTIME_BUILDING_NEIGHBORHOOD_STUDS then
                local neighborhoodDeficiency = RUNTIME_BUILDING_NEIGHBORHOOD_STUDS - footprintNearestDistance
                neighborhoodPenalty += neighborhoodDeficiency * neighborhoodDeficiency * RUNTIME_BUILDING_NEIGHBORHOOD_SCORE_SCALE * neighborhoodWeight
            end
        end

        if nearestDistance >= RUNTIME_BUILDING_CLEARANCE_STUDS then
            return neighborhoodPenalty
        end

        local deficiency = RUNTIME_BUILDING_CLEARANCE_STUDS - nearestDistance
        return deficiency * deficiency * RUNTIME_BUILDING_CLEARANCE_SCORE_SCALE + neighborhoodPenalty
    end

    local function considerChunks(chunksToScan, radiusLimit, centerPoint, scoringTarget)
        local buildingFootprints = collectBuildingFootprints(chunksToScan, radiusLimit, centerPoint)
        for _, chunk in ipairs(chunksToScan) do
            if isChunkWithinRadius(chunk, manifest, radiusLimit, centerPoint) then
                local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }
                for _, road in ipairs(chunk.roads or {}) do
                    if EXCLUDED_SPAWN_KINDS[road.kind] then
                        continue
                    end
                    local priority = getRoadPriority(road.kind, selectionMode)
                    local points = road.points or {}

                    for i = 1, #points - 1 do
                        local p1 = points[i]
                        local p2 = points[i + 1]
                        local midX = origin.x + (p1.x + p2.x) * 0.5
                        local midY = origin.y + (p1.y + p2.y) * 0.5
                        local midZ = origin.z + (p1.z + p2.z) * 0.5
                        local targetPoint = scoringTarget or heuristicFocusPoint
                        local dx = midX - targetPoint.X
                        local dz = midZ - targetPoint.Z
                        local distSq = dx * dx + dz * dz
                        if math.abs(midY - targetPoint.Y) > 18 then
                            continue
                        end
                        local score = priority * 100000000
                            + distSq
                            + getRuntimeBuildingPenalty(midX, midZ, buildingFootprints)

                        if not bestScore or score < bestScore then
                            bestScore = score
                            bestPoint = Vector3.new(midX, midY, midZ)
                        end
                    end
                end
            end
        end
    end

    local selectionCenter = loadCenter or heuristicFocusPoint
    local chunks = materializeChunksForSelection(manifest, loadRadius, heuristicFocusPoint)
    considerChunks(chunks, loadRadius, selectionCenter, desiredSpawnPoint)

    if bestPoint == nil and loadCenter == nil then
        considerChunks(materializeAllChunksForSelection(manifest), nil, nil, desiredSpawnPoint)
    end

    local explicitCanonicalPoint = getExplicitCanonicalAnchorPosition(manifest)
    local spawnPoint = if explicitCanonicalPoint then explicitCanonicalPoint else (bestPoint or desiredSpawnPoint)
    local focusPoint = heuristicFocusPoint
    if explicitCanonicalPoint then
        focusPoint = explicitCanonicalPoint
    elseif selectionMode == "preview" and loadCenter ~= nil then
        focusPoint = getLoadCenterVector(loadCenter, heuristicFocusPoint.Y) or heuristicFocusPoint
    elseif selectionMode == "preview" and loadCenter == nil and not hasRelativeCanonicalSpawnOffset(manifest) then
        focusPoint = spawnPoint
    end
    local anchor = {
        heuristicFocusPoint = heuristicFocusPoint,
        focusPoint = focusPoint,
        spawnPoint = spawnPoint,
        lookTarget = AustinSpawn.getPreferredLookTarget(manifest, spawnPoint, focusPoint),
        selectedChunks = chunks,
    }

    if canCacheResolvedAnchor then
        if not manifestCache then
            manifestCache = {}
            anchorCache[manifest] = manifestCache
        end
        manifestCache[cacheKey] = anchor
    end

    return anchor
end

function AustinSpawn.resolveAnchor(manifest, loadRadius, loadCenter)
    return resolveAnchorInternal(manifest, loadRadius, loadCenter, "preview")
end

function AustinSpawn.resolveRuntimeAnchor(manifest, loadRadius, loadCenter)
    return resolveAnchorInternal(manifest, loadRadius, loadCenter, "runtime_spawn")
end

function AustinSpawn.resolveCanonicalAnchorValues(manifest, loadRadius, loadCenter)
    return AustinSpawn.resolveAnchor(manifest, loadRadius, loadCenter)
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

    local effectiveLoadRadius = if loadCenter ~= nil then loadRadius else nil
    local bounds = {}
    local chunkRefs = iterChunkRefs(manifest)
    local weightedX = 0
    local weightedZ = 0
    local weightedCount = 0
    local sawConcreteGeometry = false

    local function accumulateFocusPoint(x, z)
        weightedX += x
        weightedZ += z
        weightedCount += 1
    end

    for _, chunk in ipairs(chunkRefs) do
        if isChunkWithinRadius(chunk, manifest, effectiveLoadRadius, loadCenter) then
            local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }

            if not chunk.roads and not chunk.buildings and not chunk.props then
                local chunkSize = manifest.meta and manifest.meta.chunkSizeStuds or 256
                accumulatePoint(bounds, origin.x, origin.y, origin.z)
                accumulatePoint(bounds, origin.x + chunkSize, origin.y, origin.z + chunkSize)
                accumulateGroundY(bounds, origin.y)
            end

            local terrain = chunk.terrain
            if terrain and terrain.heights then
                sawConcreteGeometry = true
                for _, height in ipairs(terrain.heights) do
                    accumulateGroundY(bounds, origin.y + (height or 0))
                end
            end

            for _, road in ipairs(chunk.roads or {}) do
                sawConcreteGeometry = true
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
                sawConcreteGeometry = true
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
                sawConcreteGeometry = true
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

    if not sawConcreteGeometry and manifest.chunks == nil then
        local provisionalFocus = Vector3.new(focusX, focusY, focusZ)
        local materializedChunks = materializeChunksForSelection(manifest, loadRadius, loadCenter or provisionalFocus)
        if type(materializedChunks) == "table" and #materializedChunks > 0 then
            return AustinSpawn.findFocusPoint({
                meta = manifest.meta,
                chunks = materializedChunks,
            }, loadRadius, loadCenter)
        end
    end

    return Vector3.new(focusX, focusY, focusZ)
end

function AustinSpawn.findPreviewFocusPoint(manifest, loadRadius, loadCenter)
    return AustinSpawn.resolveAnchor(manifest, loadRadius, loadCenter).focusPoint
end

function AustinSpawn.findSpawnPoint(manifest, loadRadius, loadCenter)
    return AustinSpawn.resolveRuntimeAnchor(manifest, loadRadius, loadCenter).spawnPoint
end

return AustinSpawn
