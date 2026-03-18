--!optimize 2
--!native

local RoadProfile = {}

local KIND_WIDTH = {
    motorway = 24,
    trunk = 20,
    primary = 16,
    secondary = 12,
    tertiary = 10,
    residential = 8,
    service = 6,
    footway = 3,
    cycleway = 3,
    path = 2,
    track = 4,
    living_street = 7,
    unclassified = 8,
}

function RoadProfile.getRoadWidth(road)
    if road.lanes and road.lanes > 0 then
        return road.lanes * 4 + 4
    end

    if road.widthStuds and road.widthStuds > 0 then
        return road.widthStuds
    end

    return KIND_WIDTH[road.kind] or 8
end

function RoadProfile.getSidewalkWidth(road, roadWidth)
    if not road.hasSidewalk then
        return 0
    end

    roadWidth = roadWidth or RoadProfile.getRoadWidth(road)
    return math.clamp(roadWidth * 0.25, 2.5, 4)
end

function RoadProfile.getEdgeBufferWidth(road, roadWidth)
    roadWidth = roadWidth or RoadProfile.getRoadWidth(road)

    if RoadProfile.getSidewalkWidth(road, roadWidth) > 0 then
        return 0.75
    end

    if roadWidth >= 12 then
        return 0.75
    end

    if roadWidth >= 8 then
        return 0.5
    end

    return 0.25
end

function RoadProfile.getPavementHalfWidth(road, roadWidth)
    roadWidth = roadWidth or RoadProfile.getRoadWidth(road)
    return roadWidth * 0.5
        + RoadProfile.getSidewalkWidth(road, roadWidth)
        + RoadProfile.getEdgeBufferWidth(road, roadWidth)
end

function RoadProfile.getRoadClearance(road, roadWidth)
    return RoadProfile.getPavementHalfWidth(road, roadWidth) + 0.5
end

return RoadProfile
