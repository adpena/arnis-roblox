--!optimize 2
--!native

local GroundSampler = require(script.Parent.GroundSampler)
local RoadProfile = require(script.Parent.RoadProfile)
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)

local RoadChunkPlan = {}

local GROUND_ROAD_CLEARANCE = WorldConfig.GroundRoadClearance or 0.75

local function offsetPoint(point, origin)
    return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

local function defaultClassifySegment(road, p1, p2)
    if road.elevated then
        return "bridge", p1, p2
    elseif road.tunnel then
        return "tunnel", p1, p2
    else
        return "ground", p1, p2
    end
end

local function getSidewalkMode(road)
    if road.sidewalk then
        return road.sidewalk
    end
    return road.hasSidewalk and "both" or "no"
end

local function getEffectiveWidth(_road, profileWidth)
    return profileWidth
end

local function alignGroundPoint(point, sampleGroundY)
    if not sampleGroundY then
        return point
    end

    local groundY = sampleGroundY(point.X, point.Z)
    local targetY = if type(groundY) == "number" then groundY + GROUND_ROAD_CLEARANCE else nil
    if type(targetY) ~= "number" or targetY <= point.Y then
        return point
    end

    return Vector3.new(point.X, targetY, point.Z)
end

function RoadChunkPlan.build(roads, originStuds, chunk, options)
    local classifySegment = (options and options.classifySegment) or defaultClassifySegment
    local getMaterial = options and options.getMaterial
    local getRoadColor = options and options.getRoadColor
    local sampleGroundY = if chunk then GroundSampler.createRenderedSurfaceSampler(chunk) else nil
    local plannedRoads = {}

    for _, road in ipairs(roads or {}) do
        local width = getEffectiveWidth(road, RoadProfile.getRoadWidth(road))
        local layerElevation = if road.layer and road.layer > 0 then road.layer * 8 else 0
        local roadPlan = {
            road = road,
            chunk = chunk,
            width = width,
            sidewalkMode = getSidewalkMode(road),
            material = getMaterial and getMaterial(road) or nil,
            color = getRoadColor and getRoadColor(road) or nil,
            sampleGroundY = sampleGroundY,
            segments = {},
            firstEndpoint = nil,
            firstDirection = nil,
            lastEndpoint = nil,
            lastDirection = nil,
        }

        for index = 1, math.max(#(road.points or {}) - 1, 0) do
            local p1 = offsetPoint(road.points[index], originStuds)
            local p2 = offsetPoint(road.points[index + 1], originStuds)

            if layerElevation > 0 then
                local surfaceY = (p1.Y + p2.Y) * 0.5 + layerElevation
                p1 = Vector3.new(p1.X, surfaceY, p1.Z)
                p2 = Vector3.new(p2.X, surfaceY, p2.Z)
            end

            local mode, resolvedP1, resolvedP2 = classifySegment(road, p1, p2, chunk)
            if mode == "ground" then
                resolvedP1 = alignGroundPoint(resolvedP1, sampleGroundY)
                resolvedP2 = alignGroundPoint(resolvedP2, sampleGroundY)
            end
            local direction = resolvedP2 - resolvedP1
            if direction.Magnitude > 0.01 then
                local unitDirection = direction.Unit
                if roadPlan.firstDirection == nil then
                    roadPlan.firstEndpoint = resolvedP1
                    roadPlan.firstDirection = unitDirection
                end
                roadPlan.lastEndpoint = resolvedP2
                roadPlan.lastDirection = unitDirection
            end

            roadPlan.segments[#roadPlan.segments + 1] = {
                mode = mode,
                p1 = resolvedP1,
                p2 = resolvedP2,
            }
        end

        plannedRoads[#plannedRoads + 1] = roadPlan
    end

    return {
        sampleGroundY = sampleGroundY,
        roads = plannedRoads,
    }
end

return RoadChunkPlan
