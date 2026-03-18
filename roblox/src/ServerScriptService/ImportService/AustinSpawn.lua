local AustinSpawn = {}

local ROAD_PRIORITY = {
    motorway = 90,
    trunk = 80,
    primary = 10,
    secondary = 20,
    tertiary = 30,
    residential = 40,
    living_street = 45,
    service = 50,
    unclassified = 55,
    pedestrian = 60,
    footway = 70,
    cycleway = 75,
    path = 80,
    track = 85,
}

local function getRoadPriority(kind)
    return ROAD_PRIORITY[kind] or 65
end

local function isChunkWithinRadius(chunk, manifest, loadRadius)
    if not loadRadius then
        return true
    end

    local chunkSize = manifest.meta and manifest.meta.chunkSizeStuds or 256
    local origin = chunk.originStuds or { x = 0, z = 0 }
    local centerX = origin.x + chunkSize * 0.5
    local centerZ = origin.z + chunkSize * 0.5

    return math.sqrt(centerX * centerX + centerZ * centerZ) <= loadRadius
end

function AustinSpawn.findSpawnPoint(manifest, loadRadius)
    if not manifest or not manifest.chunks then
        return Vector3.new(0, 0, 0)
    end

    local bestPoint
    local bestScore

    for _, chunk in ipairs(manifest.chunks) do
        if isChunkWithinRadius(chunk, manifest, loadRadius) then
            local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }
            for _, road in ipairs(chunk.roads or {}) do
                local priority = getRoadPriority(road.kind)
                local points = road.points or {}

                for i = 1, #points - 1 do
                    local p1 = points[i]
                    local p2 = points[i + 1]
                    local midX = origin.x + (p1.x + p2.x) * 0.5
                    local midY = origin.y + (p1.y + p2.y) * 0.5
                    local midZ = origin.z + (p1.z + p2.z) * 0.5
                    local distSq = midX * midX + midZ * midZ
                    local score = priority * 100000000 + distSq

                    if not bestScore or score < bestScore then
                        bestScore = score
                        bestPoint = Vector3.new(midX, midY, midZ)
                    end
                end
            end
        end
    end

    return bestPoint or Vector3.new(0, 0, 0)
end

return AustinSpawn
