local Workspace = game:GetService("Workspace")

local TerrainBuilder = {}
local BUILD_PLAN_CACHE_KEY = "__terrainBuildPlan"
local TERRAIN_WRITE_RESOLUTION = 4

TerrainBuilder.DEFAULT_CLEAR_HEIGHT = 512
TerrainBuilder._fillBlock = function(terrain, cf, size, material)
    terrain:FillBlock(cf, size, material)
end

function TerrainBuilder.Clear(chunk, plan)
    local terrainGrid = chunk.terrain
    if not terrainGrid then
        return
    end

    local terrain = Workspace.Terrain
    local resolvedPlan = plan or rawget(chunk, BUILD_PLAN_CACHE_KEY)
    local cellSize = if resolvedPlan then resolvedPlan.cellSize else terrainGrid.cellSizeStuds
    local origin = if resolvedPlan then resolvedPlan.origin else chunk.originStuds

    local footprintWidth = if resolvedPlan
        then resolvedPlan.totalWidth
        else terrainGrid.width * cellSize
    local footprintDepth = if resolvedPlan
        then resolvedPlan.totalDepth
        else terrainGrid.depth * cellSize

    local clearSize =
        Vector3.new(footprintWidth, TerrainBuilder.DEFAULT_CLEAR_HEIGHT, footprintDepth)
    local clearCFrame =
        CFrame.new(origin.x + footprintWidth * 0.5, origin.y, origin.z + footprintDepth * 0.5)
    TerrainBuilder._fillBlock(terrain, clearCFrame, clearSize, Enum.Material.Air)
end

-- Configurable via WorldConfig; defaults favor maximum fidelity
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local REQUESTED_SAMPLE_RESOLUTION = WorldConfig.VoxelSize or 1
local TERRAIN_THICKNESS = WorldConfig.TerrainThickness or 8

local function snap(v, down)
    if down then
        return math.floor(v / TERRAIN_WRITE_RESOLUTION) * TERRAIN_WRITE_RESOLUTION
    else
        return math.ceil(v / TERRAIN_WRITE_RESOLUTION) * TERRAIN_WRITE_RESOLUTION
    end
end

local function buildChunkPlan(chunk)
    local terrainGrid = chunk.terrain
    if not terrainGrid then
        return nil
    end

    local cellSize = terrainGrid.cellSizeStuds
    local origin = chunk.originStuds
    local totalWidth = terrainGrid.width * cellSize
    local totalDepth = terrainGrid.depth * cellSize
    local gridW = terrainGrid.width
    local gridD = terrainGrid.depth
    local heights = terrainGrid.heights

    local minH = 0
    local maxH = 0
    for _, h in ipairs(heights) do
        if h < minH then
            minH = h
        end
        if h > maxH then
            maxH = h
        end
    end

    local rMinX = snap(origin.x, true)
    local rMinY = snap(origin.y + minH - TERRAIN_THICKNESS, true)
    local rMinZ = snap(origin.z, true)
    local rMaxX = snap(origin.x + totalWidth, false)
    local rMaxY = snap(origin.y + maxH + TERRAIN_WRITE_RESOLUTION, false)
    local rMaxZ = snap(origin.z + totalDepth, false)

    if rMaxX <= rMinX then
        rMaxX = rMinX + TERRAIN_WRITE_RESOLUTION
    end
    if rMaxY <= rMinY then
        rMaxY = rMinY + TERRAIN_WRITE_RESOLUTION
    end
    if rMaxZ <= rMinZ then
        rMaxZ = rMinZ + TERRAIN_WRITE_RESOLUTION
    end

    local dimX = (rMaxX - rMinX) / TERRAIN_WRITE_RESOLUTION
    local dimY = (rMaxY - rMinY) / TERRAIN_WRITE_RESOLUTION
    local dimZ = (rMaxZ - rMinZ) / TERRAIN_WRITE_RESOLUTION

    local function sampleInterpolatedHeight(cellX, cellZ, fracX, fracZ)
        local function getH(cx, cz)
            cx = math.max(0, math.min(gridW - 1, cx))
            cz = math.max(0, math.min(gridD - 1, cz))
            return heights[cz * gridW + cx + 1] or 0
        end

        local h00 = getH(cellX, cellZ)
        local h10 = getH(cellX + 1, cellZ)
        local h01 = getH(cellX, cellZ + 1)
        local h11 = getH(cellX + 1, cellZ + 1)
        local h0 = h00 + (h10 - h00) * fracX
        local h1 = h01 + (h11 - h01) * fracX
        return h0 + (h1 - h0) * fracZ
    end

    local function computeSlope(cx, cz)
        local function getH(x, z)
            x = math.max(0, math.min(gridW - 1, x))
            z = math.max(0, math.min(gridD - 1, z))
            return heights[z * gridW + x + 1] or 0
        end

        local dhdx = (getH(cx + 1, cz) - getH(cx - 1, cz)) / (2 * cellSize)
        local dhdz = (getH(cx, cz + 1) - getH(cx, cz - 1)) / (2 * cellSize)
        return math.sqrt(dhdx * dhdx + dhdz * dhdz)
    end

    local function getMat(x, z)
        local baseMat
        local hasExplicitCellMaterial = false
        if terrainGrid.materials then
            local idx = z * gridW + x + 1
            local name = terrainGrid.materials[idx]
            if name then
                local ok, m = pcall(function()
                    return Enum.Material[name]
                end)
                if ok and m then
                    baseMat = m
                    hasExplicitCellMaterial = true
                end
            end
        end
        if not baseMat then
            local name = terrainGrid.material
            local ok, m = pcall(function()
                return Enum.Material[name]
            end)
            if ok and m then
                baseMat = m
            else
                baseMat = Enum.Material.Grass
            end
        end

        if hasExplicitCellMaterial then
            return baseMat
        end

        local slope = computeSlope(x, z)
        if slope > (WorldConfig.SlopeRockThreshold or 1.0) then
            return Enum.Material.Rock
        elseif slope > (WorldConfig.SlopeGroundThreshold or 0.47) then
            return Enum.Material.Ground
        end
        return baseMat
    end

    local cellXRanges = table.create(gridW)
    for cellX = 0, gridW - 1 do
        local wx0 = origin.x + cellX * cellSize
        local wx1 = wx0 + cellSize
        cellXRanges[cellX + 1] = {
            wx0 = wx0,
            vx0 = math.max(1, math.floor((wx0 - rMinX) / TERRAIN_WRITE_RESOLUTION) + 1),
            vx1 = math.min(dimX, math.ceil((wx1 - rMinX) / TERRAIN_WRITE_RESOLUTION)),
        }
    end

    local cellZRanges = table.create(gridD)
    local cellMaterials = table.create(gridD)
    for cellZ = 0, gridD - 1 do
        local wz0 = origin.z + cellZ * cellSize
        local wz1 = wz0 + cellSize
        cellZRanges[cellZ + 1] = {
            wz0 = wz0,
            vz0 = math.max(1, math.floor((wz0 - rMinZ) / TERRAIN_WRITE_RESOLUTION) + 1),
            vz1 = math.min(dimZ, math.ceil((wz1 - rMinZ) / TERRAIN_WRITE_RESOLUTION)),
        }

        local materialRow = table.create(gridW)
        for cellX = 0, gridW - 1 do
            materialRow[cellX + 1] = getMat(cellX, cellZ)
        end
        cellMaterials[cellZ + 1] = materialRow
    end

    return {
        terrainGrid = terrainGrid,
        origin = origin,
        cellSize = cellSize,
        totalWidth = totalWidth,
        totalDepth = totalDepth,
        heights = heights,
        gridW = gridW,
        gridD = gridD,
        rMinX = rMinX,
        rMinY = rMinY,
        rMinZ = rMinZ,
        rMaxX = rMaxX,
        rMaxY = rMaxY,
        rMaxZ = rMaxZ,
        dimX = dimX,
        dimY = dimY,
        dimZ = dimZ,
        writeResolution = TERRAIN_WRITE_RESOLUTION,
        requestedSampleResolution = REQUESTED_SAMPLE_RESOLUTION,
        cellXRanges = cellXRanges,
        cellZRanges = cellZRanges,
        cellMaterials = cellMaterials,
        sampleInterpolatedHeight = sampleInterpolatedHeight,
    }
end

function TerrainBuilder.PrepareChunk(chunk)
    if not chunk or not chunk.terrain then
        return nil
    end

    local cachedPlan = rawget(chunk, BUILD_PLAN_CACHE_KEY)
    if
        cachedPlan ~= nil
        and cachedPlan.terrainGrid == chunk.terrain
        and cachedPlan.origin == chunk.originStuds
    then
        return cachedPlan
    end

    local plan = buildChunkPlan(chunk)
    rawset(chunk, BUILD_PLAN_CACHE_KEY, plan)
    return plan
end

function TerrainBuilder.GetPreparedChunkPlan(chunk)
    return rawget(chunk, BUILD_PLAN_CACHE_KEY)
end

function TerrainBuilder.Build(_parent, chunk, preparedPlan)
    local plan = preparedPlan or TerrainBuilder.PrepareChunk(chunk)
    if not plan then
        return
    end

    TerrainBuilder.Clear(chunk, plan)

    local terrain = Workspace.Terrain
    local cellSize = plan.cellSize
    local origin = plan.origin
    local rMinX = plan.rMinX
    local rMinY = plan.rMinY
    local rMinZ = plan.rMinZ
    local rMaxX = plan.rMaxX
    local rMaxY = plan.rMaxY
    local dimX = plan.dimX
    local dimY = plan.dimY
    local dimZ = plan.dimZ
    local gridW = plan.gridW
    local gridD = plan.gridD
    local cellXRanges = plan.cellXRanges
    local cellZRanges = plan.cellZRanges
    local cellMaterials = plan.cellMaterials
    local sampleInterpolatedHeight = plan.sampleInterpolatedHeight

    -- Strip-based WriteVoxels: process 16 Z-voxels at a time so peak memory is
    -- O(dimX * dimY * STRIP_DEPTH) instead of O(dimX * dimY * dimZ).
    -- Roblox terrain requires a 4-stud write resolution.
    local STRIP_DEPTH = 16

    -- Reusable strip buffers, allocated once and refilled each iteration.
    local stripMat = nil
    local stripOcc = nil

    local izBase = 1 -- 1-indexed global Z voxel, start of current strip
    while izBase <= dimZ do
        local izEnd = math.min(izBase + STRIP_DEPTH - 1, dimZ) -- inclusive, 1-indexed
        local stripLen = izEnd - izBase + 1 -- number of Z slices in this strip

        -- Allocate buffers on the first strip; reuse on subsequent strips.
        -- Inner Z dimension is always STRIP_DEPTH except possibly the last strip,
        -- so we allocate fresh when stripLen changes (only the final strip differs).
        if stripMat == nil or #stripMat[1][1] ~= stripLen then
            stripMat = table.create(dimX)
            stripOcc = table.create(dimX)
            for ix = 1, dimX do
                stripMat[ix] = table.create(dimY)
                stripOcc[ix] = table.create(dimY)
                for iy = 1, dimY do
                    stripMat[ix][iy] = table.create(stripLen, Enum.Material.Air)
                    stripOcc[ix][iy] = table.create(stripLen, 0)
                end
            end
        else
            -- Clear buffers back to Air/0 for reuse.
            for ix = 1, dimX do
                for iy = 1, dimY do
                    local mRow = stripMat[ix][iy]
                    local oRow = stripOcc[ix][iy]
                    for s = 1, stripLen do
                        mRow[s] = Enum.Material.Air
                        oRow[s] = 0
                    end
                end
            end
        end

        -- Fill this strip by iterating over terrain cells that overlap the strip's Z range.
        -- Global voxel Z range covered by this strip: [izBase, izEnd] (1-indexed).
        for cellZ = 0, gridD - 1 do
            local zRange = cellZRanges[cellZ + 1]
            local wz0 = zRange.wz0

            -- Clamp to current strip window
            local stripVz0 = math.max(zRange.vz0, izBase)
            local stripVz1 = math.min(zRange.vz1, izEnd)
            if stripVz0 > stripVz1 then
                continue
            end

            for cellX = 0, gridW - 1 do
                local mat = cellMaterials[cellZ + 1][cellX + 1]
                local xRange = cellXRanges[cellX + 1]
                local wx0 = xRange.wx0
                local vx0 = xRange.vx0
                local vx1 = xRange.vx1

                for ix = vx0, vx1 do
                    local voxelWorldX = rMinX + (ix - 0.5) * TERRAIN_WRITE_RESOLUTION
                    local fracX = math.clamp((voxelWorldX - wx0) / cellSize, 0, 1)

                    for globalIz = stripVz0, stripVz1 do
                        local localIz = globalIz - izBase + 1 -- 1-indexed within strip

                        local voxelWorldZ = rMinZ + (globalIz - 0.5) * TERRAIN_WRITE_RESOLUTION
                        local fracZ = math.clamp((voxelWorldZ - wz0) / cellSize, 0, 1)

                        -- Interpolated surface height for this (X, Z) column
                        local interpH = sampleInterpolatedHeight(cellX, cellZ, fracX, fracZ)
                        local worldSurfY = origin.y + interpH
                        local worldBotY = worldSurfY - TERRAIN_THICKNESS

                        local vy0 = math.max(
                            1,
                            math.floor((worldBotY - rMinY) / TERRAIN_WRITE_RESOLUTION) + 1
                        )
                        local vy1 = math.min(
                            dimY,
                            math.ceil((worldSurfY - rMinY) / TERRAIN_WRITE_RESOLUTION)
                        )

                        for iy = vy0, vy1 do
                            local voxelCenterY = rMinY + (iy - 0.5) * TERRAIN_WRITE_RESOLUTION
                            local occupancy = 1

                            if iy == vy0 then
                                local bottomOccupancy = math.clamp(
                                    0.5 + (voxelCenterY - worldBotY) / TERRAIN_WRITE_RESOLUTION,
                                    0,
                                    1
                                )
                                occupancy = math.min(occupancy, bottomOccupancy)
                            end

                            if iy == vy1 then
                                local topOccupancy = math.clamp(
                                    0.5 + (worldSurfY - voxelCenterY) / TERRAIN_WRITE_RESOLUTION,
                                    0,
                                    1
                                )
                                occupancy = math.min(occupancy, topOccupancy)
                            end

                            if occupancy > 0 then
                                stripMat[ix][iy][localIz] = mat
                                stripOcc[ix][iy][localIz] = occupancy
                            end
                        end
                    end
                end
            end
        end

        -- Write this strip to Roblox terrain.
        local zWorldMin = rMinZ + (izBase - 1) * TERRAIN_WRITE_RESOLUTION
        local zWorldMax = rMinZ + izEnd * TERRAIN_WRITE_RESOLUTION
        local stripRegion =
            Region3.new(Vector3.new(rMinX, rMinY, zWorldMin), Vector3.new(rMaxX, rMaxY, zWorldMax))
        terrain:WriteVoxels(stripRegion, TERRAIN_WRITE_RESOLUTION, stripMat, stripOcc)

        izBase = izEnd + 1
    end
end

function TerrainBuilder.ImprintRoads(roads, originStuds, _chunk)
    local terrain = Workspace.Terrain

    local function addRoadSegments(target, road)
        if type(road) ~= "table" then
            return
        end

        if type(road.segments) == "table" then
            local width = road.width or (road.road and road.road.widthStuds) or 10
            local material = road.material or Enum.Material.Asphalt
            for _, segment in ipairs(road.segments) do
                if
                    segment.mode == "ground"
                    and typeof(segment.p1) == "Vector3"
                    and typeof(segment.p2) == "Vector3"
                then
                    target[#target + 1] = {
                        p1 = segment.p1,
                        p2 = segment.p2,
                        width = width,
                        material = material,
                    }
                end
            end
            return
        end

        if road.tunnel then
            return
        end -- don't imprint tunnels

        if type(road.points) ~= "table" or #road.points < 2 then
            return
        end

        local width = road.widthStuds or 10
        local roadMat = Enum.Material.Asphalt
        if road.material then
            pcall(function()
                roadMat = Enum.Material[road.material]
            end)
        end

        for i = 1, #road.points - 1 do
            local p1 = road.points[i]
            local p2 = road.points[i + 1]
            if type(p1) ~= "table" or type(p2) ~= "table" then
                continue
            end
            if type(p1.x) ~= "number" or type(p1.y) ~= "number" or type(p1.z) ~= "number" then
                continue
            end
            if type(p2.x) ~= "number" or type(p2.y) ~= "number" or type(p2.z) ~= "number" then
                continue
            end

            local worldP1 =
                Vector3.new(p1.x + originStuds.x, p1.y + originStuds.y, p1.z + originStuds.z)
            local worldP2 =
                Vector3.new(p2.x + originStuds.x, p2.y + originStuds.y, p2.z + originStuds.z)
            local segLen = (worldP2 - worldP1).Magnitude
            if segLen >= 0.1 then
                target[#target + 1] = {
                    p1 = worldP1,
                    p2 = worldP2,
                    width = width,
                    material = roadMat,
                }
            end
        end
    end

    local segments = {}
    for _, road in ipairs(roads or {}) do
        addRoadSegments(segments, road)
    end

    local function tryMergeSegment(active, nextSegment)
        if not active or not nextSegment then
            return nextSegment
        end

        if not active.p1 or not active.p2 or not nextSegment.p1 or not nextSegment.p2 then
            return nil
        end

        local activeDelta = active.p2 - active.p1
        local nextDelta = nextSegment.p2 - nextSegment.p1
        if activeDelta.Magnitude < 1e-6 or nextDelta.Magnitude < 1e-6 then
            return nil
        end

        local activeDir = activeDelta.Unit
        local nextDir = nextDelta.Unit
        local alignment = activeDir:Dot(nextDir)
        if alignment < 0.999 then
            return nil
        end

        if math.abs(active.width - nextSegment.width) > 1e-6 then
            return nil
        end

        if
            math.abs(active.p2.X - nextSegment.p1.X) > 1e-6
            or math.abs(active.p2.Z - nextSegment.p1.Z) > 1e-6
        then
            return nil
        end

        return {
            p1 = active.p1,
            p2 = nextSegment.p2,
            width = active.width,
            material = active.material,
        }
    end

    local function emitImprint(segment)
        local dir = (segment.p2 - segment.p1)
        local segLen = dir.Magnitude
        if segLen < 0.1 then
            return
        end
        -- Carve a shallow ribbon of Air above the road centerline so terrain
        -- collision cannot sit on top of the imported road mesh.
        local startPos = Vector3.new(segment.p1.X, segment.p1.Y + 1, segment.p1.Z)
        local endPos = Vector3.new(segment.p2.X, segment.p2.Y + 1, segment.p2.Z)
        local midpoint = (startPos + endPos) * 0.5
        TerrainBuilder._fillBlock(
            terrain,
            CFrame.lookAt(midpoint, endPos),
            Vector3.new(segment.width, 2, segLen),
            Enum.Material.Air
        )
    end

    local activeSegment = nil
    for _, nextSegment in ipairs(segments) do
        local merged = tryMergeSegment(activeSegment, nextSegment)
        if merged then
            activeSegment = merged
        else
            if activeSegment then
                emitImprint(activeSegment)
            end
            activeSegment = nextSegment
        end
    end

    if activeSegment then
        emitImprint(activeSegment)
    end
end

return TerrainBuilder
