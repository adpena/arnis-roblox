--!optimize 2
--!native

local SpatialQuery = {}
local RoadProfile = require(script.Parent.RoadProfile)

local ROAD_INDEX_CELL_SIZE = 64
local INDEX_BUILD_YIELD_INTERVAL = 1024

local roadIndexCache = setmetatable({}, { __mode = "k" })

local function distancePointToSegmentSq(px, pz, ax, az, bx, bz)
    local dx = bx - ax
    local dz = bz - az
    local lenSq = dx * dx + dz * dz
    if lenSq <= 1e-6 then
        local ddx = px - ax
        local ddz = pz - az
        return ddx * ddx + ddz * ddz, 0, ax, az
    end

    local t = ((px - ax) * dx + (pz - az) * dz) / lenSq
    t = math.max(0, math.min(1, t))
    local projX = ax + dx * t
    local projZ = az + dz * t
    local ddx = px - projX
    local ddz = pz - projZ

    return ddx * ddx + ddz * ddz, t, projX, projZ
end

local function getCellCoord(value, cellSize)
    return math.floor(value / cellSize)
end

local function getOrCreateRoadIndex(roads, originStuds)
    if not roads or #roads == 0 then
        return nil
    end

    local cached = roadIndexCache[roads]
    if cached and cached.originX == originStuds.x and cached.originZ == originStuds.z then
        return cached
    end

    local index = {
        originX = originStuds.x,
        originZ = originStuds.z,
        cellSize = ROAD_INDEX_CELL_SIZE,
        buckets = {},
        segments = {},
    }

    local builtSegments = 0
    for _, road in ipairs(roads) do
        local width = RoadProfile.getRoadWidth(road)
        local clearance = RoadProfile.getRoadClearance(road, width)
        local clearanceSq = clearance * clearance
        local points = road.points or {}

        for i = 1, #points - 1 do
            local p1 = points[i]
            local p2 = points[i + 1]
            local ax = p1.x + originStuds.x
            local az = p1.z + originStuds.z
            local bx = p2.x + originStuds.x
            local bz = p2.z + originStuds.z
            local dx = bx - ax
            local dz = bz - az
            local lenSq = dx * dx + dz * dz

            if lenSq > 1e-6 then
                local length = math.sqrt(lenSq)
                local segment = {
                    road = road,
                    ax = ax,
                    ay = p1.y + originStuds.y,
                    az = az,
                    bx = bx,
                    by = p2.y + originStuds.y,
                    bz = bz,
                    dirX = dx / length,
                    dirZ = dz / length,
                    width = width,
                    clearance = clearance,
                    clearanceSq = clearanceSq,
                }

                table.insert(index.segments, segment)

                local minX = math.min(ax, bx) - clearance
                local minZ = math.min(az, bz) - clearance
                local maxX = math.max(ax, bx) + clearance
                local maxZ = math.max(az, bz) + clearance

                local minCellX = getCellCoord(minX, index.cellSize)
                local minCellZ = getCellCoord(minZ, index.cellSize)
                local maxCellX = getCellCoord(maxX, index.cellSize)
                local maxCellZ = getCellCoord(maxZ, index.cellSize)

                for cellX = minCellX, maxCellX do
                    local row = index.buckets[cellX]
                    if not row then
                        row = {}
                        index.buckets[cellX] = row
                    end

                    for cellZ = minCellZ, maxCellZ do
                        local bucket = row[cellZ]
                        if not bucket then
                            bucket = {}
                            row[cellZ] = bucket
                        end
                        bucket[#bucket + 1] = segment
                    end
                end

                builtSegments += 1
                if builtSegments % INDEX_BUILD_YIELD_INTERVAL == 0 then
                    task.wait()
                end
            end
        end
    end

    roadIndexCache[roads] = index
    return index
end

local function getCandidateSegments(index, worldX, worldZ)
    if not index then
        return nil
    end

    local row = index.buckets[getCellCoord(worldX, index.cellSize)]
    if not row then
        return nil
    end

    return row[getCellCoord(worldZ, index.cellSize)]
end

local function buildQueryResult(segment, distanceSq, t, projX, projZ)
    return {
        road = segment.road,
        distance = math.sqrt(distanceSq),
        projX = projX,
        projY = segment.ay + (segment.by - segment.ay) * t,
        projZ = projZ,
        dirX = segment.dirX,
        dirZ = segment.dirZ,
        width = segment.width,
    }
end

local function scanSegments(segments, worldX, worldZ, onlyWithinClearance)
    if not segments or #segments == 0 then
        return nil
    end

    local bestSegment
    local bestDistanceSq
    local bestT
    local bestProjX
    local bestProjZ

    for _, segment in ipairs(segments) do
        local distanceSq, t, projX, projZ =
            distancePointToSegmentSq(worldX, worldZ, segment.ax, segment.az, segment.bx, segment.bz)

        if
            (not onlyWithinClearance or distanceSq <= segment.clearanceSq)
            and (not bestDistanceSq or distanceSq < bestDistanceSq)
        then
            bestSegment = segment
            bestDistanceSq = distanceSq
            bestT = t
            bestProjX = projX
            bestProjZ = projZ
        end
    end

    if not bestSegment then
        return nil
    end

    return buildQueryResult(bestSegment, bestDistanceSq, bestT, bestProjX, bestProjZ)
end

function SpatialQuery.findNearestRoadSegment(roads, originStuds, worldX, worldZ)
    local index = getOrCreateRoadIndex(roads, originStuds)
    if not index then
        return nil
    end

    local best = scanSegments(getCandidateSegments(index, worldX, worldZ), worldX, worldZ, false)
    if best then
        return best
    end

    return scanSegments(index.segments, worldX, worldZ, false)
end

function SpatialQuery.GetRoadIndex(roads, originStuds)
    return getOrCreateRoadIndex(roads, originStuds)
end

function SpatialQuery.isPointNearRoadIndex(index, worldX, worldZ)
    if not index then
        return false, nil
    end

    local best = scanSegments(getCandidateSegments(index, worldX, worldZ), worldX, worldZ, true)
    if not best then
        return false, nil
    end

    return true, best
end

function SpatialQuery.isPointNearAnyRoad(roads, originStuds, worldX, worldZ)
    return SpatialQuery.isPointNearRoadIndex(getOrCreateRoadIndex(roads, originStuds), worldX, worldZ)
end

return SpatialQuery
