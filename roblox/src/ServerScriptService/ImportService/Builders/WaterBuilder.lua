local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local GroundSampler = require(script.Parent.Parent.GroundSampler)
local GeoUtils = require(script.Parent.Parent.GeoUtils)
local PolygonBatcher = require(script.Parent.Parent.PolygonBatcher)
local _Logger = require(ReplicatedStorage.Shared.Logger)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local WaterBuilder = {}

-- Water fills 2 studs deep from the surface so it looks like a body of water.
local WATER_DEPTH = 2
-- How many studs below the water surface to carve terrain.
local CARVE_DEPTH = WorldConfig.WaterCarveDepth or 4

local function getWaterDetailParent(parent)
    local detailFolder = parent:FindFirstChild("Detail")
    if detailFolder then
        return detailFolder
    end

    detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")
    detailFolder.Parent = parent
    return detailFolder
end

local function createWaterSurface(parent, cframe, size, name)
    local surface = Instance.new("Part")
    surface.Name = name or "WaterSurface"
    surface.Size = size
    surface.CFrame = cframe
    surface.Material = Enum.Material.Glass
    surface.Color = Color3.fromRGB(40, 80, 120)
    surface.Transparency = 0.4
    surface:SetAttribute("BaseTransparency", surface.Transparency)
    surface:SetAttribute("ArnisBaseTransparency", surface.Transparency)
    surface.Reflectance = 0.35
    surface.Anchored = true
    surface.CanCollide = false
    surface.CastShadow = false
    surface.Parent = parent
    CollectionService:AddTag(surface, "LOD_Detail")
    return surface
end

local function offsetPoint(point, origin)
    return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

local function resolveWaterSurfaceY(water, fallbackY, _chunk, _worldX, _worldZ)
    if water.surfaceY then
        return water.surfaceY
    end
    return fallbackY
end

local function estimatePolygonSurfaceY(chunk, worldPts, sampleGroundY)
    if not worldPts or #worldPts == 0 then
        return (chunk and chunk.originStuds and chunk.originStuds.y) or 0
    end

    local minGroundY = math.huge
    local sumX = 0
    local sumZ = 0
    for _, point in ipairs(worldPts) do
        local groundY = sampleGroundY(point.X, point.Z)
        if groundY < minGroundY then
            minGroundY = groundY
        end
        sumX += point.X
        sumZ += point.Z
    end

    local centroidGroundY = sampleGroundY(sumX / #worldPts, sumZ / #worldPts)
    return math.min(minGroundY, centroidGroundY)
end

-- Paint a ribbon water feature (river/stream) into terrain.
local function paintRibbonSegment(terrain, p1, p2, width, waterMaterial)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    -- Use per-vertex Y so FillBlock tilts to follow the river's slope.
    local startPos = Vector3.new(p1.X, p1.Y - WATER_DEPTH * 0.5, p1.Z)
    local endPos = Vector3.new(p2.X, p2.Y - WATER_DEPTH * 0.5, p2.Z)
    local midPos = (startPos + endPos) * 0.5
    local cf = CFrame.lookAt(midPos, endPos)
    terrain:FillBlock(cf, Vector3.new(width, WATER_DEPTH, length), waterMaterial or Enum.Material.Water)
end

-- Carve a channel of Air below a ribbon water segment.
local function carveRibbonChannel(terrain, p1, p2, width)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    -- Use per-vertex Y so the carved channel follows terrain slope.
    local startPos = Vector3.new(p1.X, p1.Y - WATER_DEPTH - CARVE_DEPTH * 0.5, p1.Z)
    local endPos = Vector3.new(p2.X, p2.Y - WATER_DEPTH - CARVE_DEPTH * 0.5, p2.Z)
    local midPos = (startPos + endPos) * 0.5
    local cf = CFrame.lookAt(midPos, endPos)
    terrain:FillBlock(cf, Vector3.new(width, CARVE_DEPTH, length), Enum.Material.Air)
end

local function mergeRibbonSegments(points, width, material)
    local merged = {}
    local active = nil

    local function canMerge(current, nextSegment)
        local currentDir = (current.p2 - current.p1).Unit
        local nextDir = (nextSegment.p2 - nextSegment.p1).Unit
        if currentDir:Dot(nextDir) < 0.999 then
            return false
        end
        if math.abs(current.width - nextSegment.width) > 1e-6 or current.material ~= nextSegment.material then
            return false
        end
        return (current.p2 - nextSegment.p1).Magnitude <= 1e-6
    end

    for i = 1, #points - 1 do
        local nextSegment = {
            p1 = points[i],
            p2 = points[i + 1],
            width = width,
            material = material,
        }
        if (nextSegment.p2 - nextSegment.p1).Magnitude < 0.01 then
            continue
        end
        if active and canMerge(active, nextSegment) then
            active.p2 = nextSegment.p2
        else
            if active then
                merged[#merged + 1] = active
            end
            active = nextSegment
        end
    end

    if active then
        merged[#merged + 1] = active
    end

    return merged
end

-- Scanline polygon rasterisation: fills the actual polygon shape row by row.
-- material defaults to Water; pass Enum.Material.LeafyGrass etc. to cut islands.
local SCAN_STEP = 4 -- studs resolution per scanline row

local function emitPolygonWaterSurfaces(detailParent, worldPts, surfaceY)
    for index, rect in ipairs(PolygonBatcher.BuildRects(worldPts, SCAN_STEP)) do
        createWaterSurface(
            detailParent,
            CFrame.new(rect.centerX, surfaceY + 0.05, rect.centerZ),
            Vector3.new(rect.width, 0.1, rect.depth),
            string.format("PolygonWaterSurface_%d", index)
        )
    end
end

local function paintPolygonScanline(terrain, worldPts, cy, material)
    material = material or Enum.Material.Water
    for _, rect in ipairs(PolygonBatcher.BuildRects(worldPts, SCAN_STEP)) do
        terrain:FillBlock(
            CFrame.new(rect.centerX, cy, rect.centerZ),
            Vector3.new(rect.width, WATER_DEPTH, rect.depth),
            material
        )
    end
end

-- Carve Air below a polygon water footprint using the same scanline approach.
-- Skips cells that fall inside any of the island hole polygons so that
-- islands remain solid terrain.
local function carvePolygonBelow(terrain, worldPts, surfaceY, holePtsList)
    if #worldPts < 3 then
        return
    end
    local n = #worldPts
    local minZ, maxZ = math.huge, -math.huge
    for _, p in ipairs(worldPts) do
        minZ = math.min(minZ, p.Z)
        maxZ = math.max(maxZ, p.Z)
    end

    -- Carve block starts just below the water surface.
    local carveSurfaceY = surfaceY - WATER_DEPTH
    local carveHeight = CARVE_DEPTH
    local carveCenterY = carveSurfaceY - carveHeight * 0.5

    local rows = {}
    local z = minZ + SCAN_STEP * 0.5
    while z <= maxZ do
        local xs = {}
        for i = 1, n do
            local p1 = worldPts[i]
            local p2 = worldPts[(i % n) + 1]
            local z1, z2 = p1.Z, p2.Z
            if (z1 <= z and z < z2) or (z2 <= z and z < z1) then
                local t = (z - z1) / (z2 - z1)
                table.insert(xs, p1.X + t * (p2.X - p1.X))
            end
        end
        table.sort(xs)
        local i = 1
        local segments = {}
        while i + 1 <= #xs do
            local x0, x1 = xs[i], xs[i + 1]
            if x1 - x0 > 0.1 then
                local cx = (x0 + x1) * 0.5

                -- Skip this cell if it falls inside any island polygon.
                local inHole = false
                if holePtsList then
                    for _, holePts in ipairs(holePtsList) do
                        if GeoUtils.pointInPolygon(cx, z, holePts) then
                            inHole = true
                            break
                        end
                    end
                end

                if not inHole then
                    segments[#segments + 1] = {
                        x0 = x0,
                        x1 = x1,
                    }
                end
            end
            i = i + 2
        end
        if #segments > 0 then
            rows[#rows + 1] = {
                z = z,
                segments = segments,
            }
        end
        z = z + SCAN_STEP
    end

    for _, rect in ipairs(PolygonBatcher.BuildRectsFromRows(rows, SCAN_STEP)) do
        terrain:FillBlock(
            CFrame.new(rect.centerX, carveCenterY, rect.centerZ),
            Vector3.new(rect.width, carveHeight, rect.depth),
            Enum.Material.Air
        )
    end
end

function WaterBuilder.BuildAll(parent, waters, originStuds, chunk)
    if not waters or #waters == 0 then
        return
    end
    local sampleGroundY = if chunk and chunk.terrain then GroundSampler.createSampler(chunk) else nil
    for _, water in ipairs(waters) do
        WaterBuilder.FallbackBuild(parent, water, originStuds, chunk, sampleGroundY)
    end
end

function WaterBuilder.Build(parent, water, originStuds, chunk, sampleGroundY)
    WaterBuilder.FallbackBuild(parent, water, originStuds, chunk, sampleGroundY)
end

function WaterBuilder.FallbackBuild(parent, water, originStuds, chunk, sampleGroundY)
    local terrain = Workspace.Terrain
    sampleGroundY = sampleGroundY or GroundSampler.createSampler(chunk)
    -- Intermittent water bodies (seasonal streambeds) render as dry sand
    local waterMaterial = Enum.Material.Water
    if water.intermittent then
        waterMaterial = Enum.Material.Sand
    end
    if water.points then
        local width = water.widthStuds or 8
        local resolvedPoints = table.create(#water.points)
        for i = 1, #water.points do
            local point = offsetPoint(water.points[i], originStuds)
            local surfaceY = resolveWaterSurfaceY(water, point.Y, chunk, point.X, point.Z)
            resolvedPoints[i] = Vector3.new(point.X, surfaceY, point.Z)
        end

        local detailParent = nil
        if not water.intermittent then
            detailParent = getWaterDetailParent(parent)
        end

        for _, segment in ipairs(mergeRibbonSegments(resolvedPoints, width, waterMaterial)) do
            local p1 = segment.p1
            local p2 = segment.p2
            local surfaceY1 = resolveWaterSurfaceY(water, p1.Y, chunk, p1.X, p1.Z)
            local surfaceY2 = resolveWaterSurfaceY(water, p2.Y, chunk, p2.X, p2.Z)
            local resolvedP1 = Vector3.new(p1.X, surfaceY1, p1.Z)
            local resolvedP2 = Vector3.new(p2.X, surfaceY2, p2.Z)
            paintRibbonSegment(terrain, resolvedP1, resolvedP2, segment.width, segment.material)
            -- Carve terrain below the ribbon channel after placing water material.
            carveRibbonChannel(terrain, resolvedP1, resolvedP2, segment.width)
            if detailParent then
                local delta = resolvedP2 - resolvedP1
                local segmentLength = delta.Magnitude
                if segmentLength >= 0.01 then
                    -- Use per-vertex Y so the surface Part tilts to follow river slope.
                    local startSurf = Vector3.new(resolvedP1.X, surfaceY1 + 0.05, resolvedP1.Z)
                    local endSurf = Vector3.new(resolvedP2.X, surfaceY2 + 0.05, resolvedP2.Z)
                    local midSurf = (startSurf + endSurf) * 0.5
                    createWaterSurface(
                        detailParent,
                        CFrame.lookAt(midSurf, endSurf),
                        Vector3.new(segment.width, 0.1, segmentLength),
                        "RibbonWaterSurface"
                    )
                end
            end
        end
    elseif water.footprint and #water.footprint >= 3 then
        -- Build world-space point array
        local worldPts = {}
        for _, p in ipairs(water.footprint) do
            table.insert(worldPts, Vector3.new(p.x + originStuds.x, 0, p.z + originStuds.z))
        end
        local surfaceY = water.surfaceY or estimatePolygonSurfaceY(chunk, worldPts, sampleGroundY)
        local cy = surfaceY - WATER_DEPTH * 0.5
        -- Scanline fill for accurate polygon shape
        paintPolygonScanline(terrain, worldPts, cy, waterMaterial)
        -- Restore islands: fill inner rings (holes) with terrain
        local holePtsList = nil
        if water.holes then
            holePtsList = {}
            for _, hole in ipairs(water.holes) do
                if #hole >= 3 then
                    -- Vector3 array for scanline fill (uses .X/.Z)
                    local holePtsV3 = {}
                    -- Plain {x, z} array for point-in-polygon test (uses .x/.z)
                    local holePtsXZ = {}
                    for _, p in ipairs(hole) do
                        local wx = p.x + originStuds.x
                        local wz = p.z + originStuds.z
                        table.insert(holePtsV3, Vector3.new(wx, cy, wz))
                        table.insert(holePtsXZ, { x = wx, z = wz })
                    end
                    paintPolygonScanline(terrain, holePtsV3, cy, Enum.Material.LeafyGrass)
                    table.insert(holePtsList, holePtsXZ)
                end
            end
        end
        -- Carve terrain below water surface after placing water material.
        -- Island polygons (holes) are excluded so they stay solid.
        carvePolygonBelow(terrain, worldPts, surfaceY, holePtsList)
        if not water.intermittent then
            emitPolygonWaterSurfaces(getWaterDetailParent(parent), worldPts, surfaceY)
        end
    end
end

return WaterBuilder
