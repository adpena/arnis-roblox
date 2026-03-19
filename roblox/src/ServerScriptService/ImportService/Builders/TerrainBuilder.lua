local Workspace = game:GetService("Workspace")

local TerrainBuilder = {}
local BUILD_PLAN_CACHE_KEY = "__terrainBuildPlan"

TerrainBuilder.DEFAULT_CLEAR_HEIGHT = 512

function TerrainBuilder.Clear(chunk, plan)
    local terrainGrid = chunk.terrain
    if not terrainGrid then
        return
    end

    local terrain = Workspace.Terrain
    local resolvedPlan = plan or rawget(chunk, BUILD_PLAN_CACHE_KEY)
    local cellSize = if resolvedPlan then resolvedPlan.cellSize else terrainGrid.cellSizeStuds
    local origin = if resolvedPlan then resolvedPlan.origin else chunk.originStuds

    local footprintWidth = if resolvedPlan then resolvedPlan.totalWidth else terrainGrid.width * cellSize
    local footprintDepth = if resolvedPlan then resolvedPlan.totalDepth else terrainGrid.depth * cellSize

    local clearSize = Vector3.new(footprintWidth, TerrainBuilder.DEFAULT_CLEAR_HEIGHT, footprintDepth)
    local clearCFrame = CFrame.new(origin.x + footprintWidth * 0.5, origin.y, origin.z + footprintDepth * 0.5)
    terrain:FillBlock(clearCFrame, clearSize, Enum.Material.Air)
end

-- Configurable via WorldConfig; defaults favor maximum fidelity
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local VOXEL_SIZE = WorldConfig.VoxelSize or 1
local TERRAIN_THICKNESS = WorldConfig.TerrainThickness or 8

local function snap(v, down)
    if down then
        return math.floor(v / VOXEL_SIZE) * VOXEL_SIZE
    else
        return math.ceil(v / VOXEL_SIZE) * VOXEL_SIZE
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
    local rMaxY = snap(origin.y + maxH + VOXEL_SIZE, false)
    local rMaxZ = snap(origin.z + totalDepth, false)

    if rMaxX <= rMinX then
        rMaxX = rMinX + VOXEL_SIZE
    end
    if rMaxY <= rMinY then
        rMaxY = rMinY + VOXEL_SIZE
    end
    if rMaxZ <= rMinZ then
        rMaxZ = rMinZ + VOXEL_SIZE
    end

    local dimX = (rMaxX - rMinX) / VOXEL_SIZE
    local dimY = (rMaxY - rMinY) / VOXEL_SIZE
    local dimZ = (rMaxZ - rMinZ) / VOXEL_SIZE

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
        if terrainGrid.materials then
            local idx = z * gridW + x + 1
            local name = terrainGrid.materials[idx]
            if name then
                local ok, m = pcall(function()
                    return Enum.Material[name]
                end)
                if ok and m then
                    baseMat = m
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
            vx0 = math.max(1, math.floor((wx0 - rMinX) / VOXEL_SIZE) + 1),
            vx1 = math.min(dimX, math.ceil((wx1 - rMinX) / VOXEL_SIZE)),
        }
    end

    local cellZRanges = table.create(gridD)
    local cellMaterials = table.create(gridD)
    for cellZ = 0, gridD - 1 do
        local wz0 = origin.z + cellZ * cellSize
        local wz1 = wz0 + cellSize
        cellZRanges[cellZ + 1] = {
            wz0 = wz0,
            vz0 = math.max(1, math.floor((wz0 - rMinZ) / VOXEL_SIZE) + 1),
            vz1 = math.min(dimZ, math.ceil((wz1 - rMinZ) / VOXEL_SIZE)),
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
    if cachedPlan ~= nil and cachedPlan.terrainGrid == chunk.terrain and cachedPlan.origin == chunk.originStuds then
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
    -- At VoxelSize=1, a 256-stud chunk reduces peak allocation ~16x.
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
                    local voxelWorldX = rMinX + (ix - 0.5) * VOXEL_SIZE
                    local fracX = math.clamp((voxelWorldX - wx0) / cellSize, 0, 1)

                    for globalIz = stripVz0, stripVz1 do
                        local localIz = globalIz - izBase + 1 -- 1-indexed within strip

                        local voxelWorldZ = rMinZ + (globalIz - 0.5) * VOXEL_SIZE
                        local fracZ = math.clamp((voxelWorldZ - wz0) / cellSize, 0, 1)

                        -- Interpolated surface height for this (X, Z) column
                        local interpH = sampleInterpolatedHeight(cellX, cellZ, fracX, fracZ)
                        local worldSurfY = origin.y + interpH
                        local worldBotY = worldSurfY - TERRAIN_THICKNESS

                        local vy0 = math.max(1, math.floor((worldBotY - rMinY) / VOXEL_SIZE) + 1)
                        local vy1 = math.min(dimY, math.ceil((worldSurfY - rMinY) / VOXEL_SIZE))

                        for iy = vy0, vy1 do
                            stripMat[ix][iy][localIz] = mat
                            stripOcc[ix][iy][localIz] = 1
                        end
                    end
                end
            end
        end

        -- Write this strip to Roblox terrain.
        local zWorldMin = rMinZ + (izBase - 1) * VOXEL_SIZE
        local zWorldMax = rMinZ + izEnd * VOXEL_SIZE
        local stripRegion = Region3.new(Vector3.new(rMinX, rMinY, zWorldMin), Vector3.new(rMaxX, rMaxY, zWorldMax))
        terrain:WriteVoxels(stripRegion, VOXEL_SIZE, stripMat, stripOcc)

        izBase = izEnd + 1
    end
end

function TerrainBuilder.ImprintRoads(roads, originStuds, _chunk)
    local terrain = Workspace.Terrain
    local function tryMergeSegment(active, nextSegment)
        if not active then
            return nextSegment
        end

        local activeDir = (active.p2 - active.p1).Unit
        local nextDir = (nextSegment.p2 - nextSegment.p1).Unit
        local alignment = activeDir:Dot(nextDir)
        if alignment < 0.999 then
            return nil
        end

        if math.abs(active.width - nextSegment.width) > 1e-6 then
            return nil
        end

        if math.abs(active.p2.X - nextSegment.p1.X) > 1e-6 or math.abs(active.p2.Z - nextSegment.p1.Z) > 1e-6 then
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
        -- Use per-endpoint Y: tilt the imprint block to follow the slope
        local startPos = Vector3.new(segment.p1.X, segment.p1.Y - 1, segment.p1.Z)
        local endPos = Vector3.new(segment.p2.X, segment.p2.Y - 1, segment.p2.Z)
        local midpoint = (startPos + endPos) * 0.5
        terrain:FillBlock(CFrame.lookAt(midpoint, endPos), Vector3.new(segment.width, 2, segLen), segment.material)
    end

    for _, road in ipairs(roads) do
        if road.tunnel then
            continue
        end -- don't imprint tunnels

        local width = road.widthStuds or 10
        local roadMat = Enum.Material.Asphalt
        if road.material then
            pcall(function()
                roadMat = Enum.Material[road.material]
            end)
        end
        local activeSegment = nil

        for i = 1, #road.points - 1 do
            local p1 = road.points[i]
            local p2 = road.points[i + 1]

            local worldP1 = Vector3.new(p1.x + originStuds.x, p1.y + originStuds.y, p1.z + originStuds.z)
            local worldP2 = Vector3.new(p2.x + originStuds.x, p2.y + originStuds.y, p2.z + originStuds.z)

            -- Compute segment direction and length
            local dir = (worldP2 - worldP1)
            local segLen = dir.Magnitude
            if segLen < 0.1 then
                continue
            end
            dir = dir.Unit

            local nextSegment = {
                p1 = worldP1,
                p2 = worldP2,
                width = width,
                material = roadMat,
            }
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
end

return TerrainBuilder
