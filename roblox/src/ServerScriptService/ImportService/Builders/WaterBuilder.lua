local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundSampler = require(script.Parent.Parent.GroundSampler)
local _Logger = require(ReplicatedStorage.Shared.Logger)

local WaterBuilder = {}

-- Water fills 2 studs deep from the surface so it looks like a body of water.
local WATER_DEPTH = 2
-- How many studs below the water surface to carve terrain.
local CARVE_DEPTH = 4

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

-- Returns true if the point (px, pz) is inside the polygon defined by pts
-- using the ray-casting algorithm.
local function pointInPolygon(px, pz, pts)
    local n = #pts
    local inside = false
    local j = n
    for i = 1, n do
        local xi, zi = pts[i].X, pts[i].Z
        local xj, zj = pts[j].X, pts[j].Z
        if ((zi > pz) ~= (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Paint a ribbon water feature (river/stream) into terrain.
local function paintRibbonSegment(terrain, p1, p2, width)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    local midY = p1.Y - WATER_DEPTH * 0.5
    local midPos = Vector3.new((p1.X + p2.X) * 0.5, midY, (p1.Z + p2.Z) * 0.5)
    local cf = CFrame.lookAt(midPos, Vector3.new(p2.X, midY, p2.Z))
    terrain:FillBlock(cf, Vector3.new(width, WATER_DEPTH, length), Enum.Material.Water)
end

-- Carve a channel of Air below a ribbon water segment.
local function carveRibbonChannel(terrain, p1, p2, width)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    -- Carve starts just below the water surface and goes down CARVE_DEPTH studs.
    local carveY = p1.Y - WATER_DEPTH - CARVE_DEPTH * 0.5
    local midPos = Vector3.new((p1.X + p2.X) * 0.5, carveY, (p1.Z + p2.Z) * 0.5)
    local cf = CFrame.lookAt(midPos, Vector3.new(p2.X, carveY, p2.Z))
    terrain:FillBlock(cf, Vector3.new(width, CARVE_DEPTH, length), Enum.Material.Air)
end

-- Scanline polygon rasterisation: fills the actual polygon shape row by row.
-- material defaults to Water; pass Enum.Material.LeafyGrass etc. to cut islands.
local SCAN_STEP = 4 -- studs resolution per scanline row
local function paintPolygonScanline(terrain, worldPts, cy, material)
    material = material or Enum.Material.Water
    if #worldPts < 3 then
        return
    end
    local n = #worldPts
    local minZ, maxZ = math.huge, -math.huge
    for _, p in ipairs(worldPts) do
        minZ = math.min(minZ, p.Z)
        maxZ = math.max(maxZ, p.Z)
    end
    local z = minZ + SCAN_STEP * 0.5
    while z <= maxZ do
        -- Find X intersections with all edges at this Z
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
        while i + 1 <= #xs do
            local x0, x1 = xs[i], xs[i + 1]
            if x1 - x0 > 0.1 then
                terrain:FillBlock(
                    CFrame.new((x0 + x1) * 0.5, cy, z),
                    Vector3.new(x1 - x0, WATER_DEPTH, SCAN_STEP),
                    material
                )
            end
            i = i + 2
        end
        z = z + SCAN_STEP
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
        while i + 1 <= #xs do
            local x0, x1 = xs[i], xs[i + 1]
            if x1 - x0 > 0.1 then
                local cx = (x0 + x1) * 0.5

                -- Skip this cell if it falls inside any island polygon.
                local inHole = false
                if holePtsList then
                    for _, holePts in ipairs(holePtsList) do
                        if pointInPolygon(cx, z, holePts) then
                            inHole = true
                            break
                        end
                    end
                end

                if not inHole then
                    terrain:FillBlock(
                        CFrame.new(cx, carveCenterY, z),
                        Vector3.new(x1 - x0, carveHeight, SCAN_STEP),
                        Enum.Material.Air
                    )
                end
            end
            i = i + 2
        end
        z = z + SCAN_STEP
    end
end

function WaterBuilder.BuildAll(parent, waters, originStuds, chunk)
    if not waters or #waters == 0 then
        return
    end
    for _, water in ipairs(waters) do
        WaterBuilder.FallbackBuild(parent, water, originStuds, chunk)
    end
end

function WaterBuilder.Build(parent, water, originStuds, chunk)
    WaterBuilder.FallbackBuild(parent, water, originStuds, chunk)
end

function WaterBuilder.FallbackBuild(_parent, water, originStuds, chunk)
    local terrain = Workspace.Terrain
    local sampleGroundY = GroundSampler.createSampler(chunk)
    if water.points then
        local width = water.widthStuds or 8
        for i = 1, #water.points - 1 do
            local p1 = offsetPoint(water.points[i], originStuds)
            local p2 = offsetPoint(water.points[i + 1], originStuds)
            local surfaceY1 = resolveWaterSurfaceY(water, p1.Y, chunk, p1.X, p1.Z)
            local surfaceY2 = resolveWaterSurfaceY(water, p2.Y, chunk, p2.X, p2.Z)
            local resolvedP1 = Vector3.new(p1.X, surfaceY1, p1.Z)
            local resolvedP2 = Vector3.new(p2.X, surfaceY2, p2.Z)
            paintRibbonSegment(terrain, resolvedP1, resolvedP2, width)
            -- Carve terrain below the ribbon channel after placing water material.
            carveRibbonChannel(terrain, resolvedP1, resolvedP2, width)
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
        paintPolygonScanline(terrain, worldPts, cy, Enum.Material.Water)
        -- Restore islands: fill inner rings (holes) with terrain
        local holePtsList = nil
        if water.holes then
            holePtsList = {}
            for _, hole in ipairs(water.holes) do
                if #hole >= 3 then
                    local holePts = {}
                    for _, p in ipairs(hole) do
                        table.insert(holePts, Vector3.new(p.x + originStuds.x, cy, p.z + originStuds.z))
                    end
                    paintPolygonScanline(terrain, holePts, cy, Enum.Material.LeafyGrass)
                    table.insert(holePtsList, holePts)
                end
            end
        end
        -- Carve terrain below water surface after placing water material.
        -- Island polygons (holes) are excluded so they stay solid.
        carvePolygonBelow(terrain, worldPts, surfaceY, holePtsList)
    end
end

return WaterBuilder
