local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local GroundSampler = require(script.Parent.Parent.GroundSampler)
local PolygonBatcher = require(script.Parent.Parent.PolygonBatcher)
local Profiler = require(script.Parent.Parent.Profiler)
local SpatialQuery = require(script.Parent.Parent.SpatialQuery)

local LanduseBuilder = {}

local FILL_DEPTH = 2 -- studs deep (thin overlay on terrain surface)
local GRID_SIZE = 4
local CELL_COLLECTION_YIELD_INTERVAL = 2048
local FILL_YIELD_INTERVAL = 512

-- Maps landuse/natural kind → Roblox terrain material
-- Full palette: Grass, LeafyGrass, Sand, Rock, Mud, Ground, Concrete, Asphalt,
--   Pavement, Cobblestone, Slate, Sandstone, Brick, Granite, Limestone, Basalt,
--   SmoothPlastic, Snow, Ice, Glacier, CrackedLava, Water
local KIND_MATERIAL = {
    -- Green spaces
    park = Enum.Material.Grass,
    garden = Enum.Material.Grass,
    recreation_ground = Enum.Material.Grass,
    village_green = Enum.Material.Grass,
    grass = Enum.Material.Grass,
    meadow = Enum.Material.Grass,
    flowerbed = Enum.Material.Grass,
    leisure = Enum.Material.Grass,
    -- Dense vegetation
    forest = Enum.Material.LeafyGrass,
    wood = Enum.Material.LeafyGrass,
    scrub = Enum.Material.LeafyGrass,
    heath = Enum.Material.LeafyGrass,
    greenfield = Enum.Material.LeafyGrass,
    -- Agriculture
    farmland = Enum.Material.Mud,
    farmyard = Enum.Material.Mud,
    orchard = Enum.Material.Mud,
    vineyard = Enum.Material.Mud,
    allotments = Enum.Material.Mud,
    greenhouse_horticulture = Enum.Material.Mud,
    -- Arid / exposed ground
    beach = Enum.Material.Sand,
    sand = Enum.Material.Sand,
    dune = Enum.Material.Sand,
    bare_rock = Enum.Material.Rock,
    cliff = Enum.Material.Rock,
    scree = Enum.Material.Granite,
    shingle = Enum.Material.Slate,
    -- Volcanic
    lava = Enum.Material.CrackedLava,
    volcano = Enum.Material.Basalt,
    -- Frozen
    glacier = Enum.Material.Glacier,
    ice = Enum.Material.Ice,
    snow = Enum.Material.Snow,
    -- Wetlands / water-adjacent
    wetland = Enum.Material.Mud,
    marsh = Enum.Material.Mud,
    swamp = Enum.Material.Mud,
    -- Residential / civic
    residential = Enum.Material.Ground,
    cemetery = Enum.Material.Sandstone,
    religious = Enum.Material.Sandstone,
    -- Commercial / urban
    commercial = Enum.Material.Limestone,
    retail = Enum.Material.Limestone,
    civic = Enum.Material.Concrete,
    office = Enum.Material.Concrete,
    education = Enum.Material.Brick,
    hospital = Enum.Material.SmoothPlastic,
    -- Industrial / infrastructure
    industrial = Enum.Material.SmoothPlastic,
    warehouse = Enum.Material.SmoothPlastic,
    railway = Enum.Material.Slate,
    military = Enum.Material.Concrete,
    -- Paved / transport
    parking = Enum.Material.Asphalt,
    road = Enum.Material.Asphalt,
    airport = Enum.Material.Concrete,
    aerodrome = Enum.Material.Concrete,
    port = Enum.Material.Cobblestone,
    marina = Enum.Material.Cobblestone,
    -- Degraded / brownfield
    brownfield = Enum.Material.Mud,
    landfill = Enum.Material.Mud,
    quarry = Enum.Material.Sandstone,
    construction = Enum.Material.Ground,
    -- Salt flats / mineral
    salt_pond = Enum.Material.Sand,
    plateau = Enum.Material.Sandstone,
}

local function getMaterial(kind, materialName)
    -- Try the pre-computed material name from the manifest first
    if materialName then
        local ok, m = pcall(function()
            return Enum.Material[materialName]
        end)
        if ok and m then
            return m
        end
    end
    return KIND_MATERIAL[kind] or Enum.Material.Ground
end

local function getLanduseDetailParent(parent)
    local detailFolder = parent and parent:FindFirstChild("Detail")
    if detailFolder then
        return detailFolder
    end

    detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")
    detailFolder.Parent = parent or Workspace
    return detailFolder
end

local function hashSeed(value)
    local text = tostring(value)
    local h = 2166136261
    for i = 1, #text do
        h = bit32.band(bit32.bxor(h, string.byte(text, i)) * 16777619, 0xFFFFFFFF)
    end
    return h
end

local function nextRandomUnit(state)
    state = (1103515245 * state + 12345) % 2147483648
    return state, state / 2147483648
end

local function nextRandomIndex(state, maxInclusive)
    local unit
    state, unit = nextRandomUnit(state)
    local index = math.floor(unit * maxInclusive) + 1
    if index > maxInclusive then
        index = maxInclusive
    end
    return state, index
end

local function makePlanningContext(originStuds, chunk)
    local planningContext = {
        originStuds = originStuds,
        chunk = chunk,
        sampleGroundY = GroundSampler.createSampler(chunk),
        roadIndex = nil,
    }

    if chunk and chunk.roads and #chunk.roads > 0 then
        planningContext.roadIndex = SpatialQuery.GetRoadIndex(chunk.roads, originStuds)
    end

    return planningContext
end

local function clipPolygonAgainstVerticalEdge(points, boundX, keepGreater)
    if not points or #points < 3 then
        return {}
    end

    local clipped = {}
    for index = 1, #points do
        local current = points[index]
        local previous = points[((index - 2) % #points) + 1]
        local currentInside = if keepGreater then current.x >= boundX else current.x <= boundX
        local previousInside = if keepGreater then previous.x >= boundX else previous.x <= boundX

        if currentInside ~= previousInside then
            local dx = current.x - previous.x
            if math.abs(dx) > 1e-9 then
                local t = (boundX - previous.x) / dx
                clipped[#clipped + 1] = {
                    x = boundX,
                    z = previous.z + (current.z - previous.z) * t,
                }
            end
        end

        if currentInside then
            clipped[#clipped + 1] = current
        end
    end

    return clipped
end

local function clipPolygonAgainstHorizontalEdge(points, boundZ, keepGreater)
    if not points or #points < 3 then
        return {}
    end

    local clipped = {}
    for index = 1, #points do
        local current = points[index]
        local previous = points[((index - 2) % #points) + 1]
        local currentInside = if keepGreater then current.z >= boundZ else current.z <= boundZ
        local previousInside = if keepGreater then previous.z >= boundZ else previous.z <= boundZ

        if currentInside ~= previousInside then
            local dz = current.z - previous.z
            if math.abs(dz) > 1e-9 then
                local t = (boundZ - previous.z) / dz
                clipped[#clipped + 1] = {
                    x = previous.x + (current.x - previous.x) * t,
                    z = boundZ,
                }
            end
        end

        if currentInside then
            clipped[#clipped + 1] = current
        end
    end

    return clipped
end

local function clipPolygonToBounds(points, bounds)
    if type(bounds) ~= "table" then
        return points
    end

    local minX = bounds.minX
    local minY = bounds.minY
    local maxX = bounds.maxX
    local maxY = bounds.maxY
    if
        type(minX) ~= "number"
        or type(minY) ~= "number"
        or type(maxX) ~= "number"
        or type(maxY) ~= "number"
    then
        return points
    end

    local clipped = clipPolygonAgainstVerticalEdge(points, minX, true)
    clipped = clipPolygonAgainstVerticalEdge(clipped, maxX, false)
    clipped = clipPolygonAgainstHorizontalEdge(clipped, minY, true)
    clipped = clipPolygonAgainstHorizontalEdge(clipped, maxY, false)
    if #clipped < 3 then
        return {}
    end
    return clipped
end

local function collectCells(landuse, planningContext)
    local originStuds = planningContext.originStuds
    local worldPoly = table.create(#landuse.footprint)
    for _, p in ipairs(landuse.footprint) do
        local wx = p.x + originStuds.x
        local wz = p.z + originStuds.z
        worldPoly[#worldPoly + 1] = { x = wx, z = wz }
    end

    local subplanBounds = landuse.subplanBounds
    if subplanBounds ~= nil then
        worldPoly = clipPolygonToBounds(worldPoly, subplanBounds)
        if #worldPoly < 3 then
            return {}
        end
    end

    local cells = {}
    local roadIndex = planningContext.roadIndex
    local sampleGroundY = planningContext.sampleGroundY
    local sampledCells = 0
    for _, cell in ipairs(PolygonBatcher.BuildGridCells(worldPoly, GRID_SIZE)) do
        sampledCells += 1
        if sampledCells % CELL_COLLECTION_YIELD_INTERVAL == 0 then
            task.wait()
        end

        local isNearRoad = false
        if roadIndex then
            isNearRoad = SpatialQuery.isPointNearRoadIndex(roadIndex, cell.x, cell.z)
        end

        if not isNearRoad then
            cells[#cells + 1] = {
                x = cell.x,
                z = cell.z,
                y = sampleGroundY(cell.x, cell.z),
            }
        end
    end

    return cells
end

local function buildTerrainRects(cells)
    local cellsByYKey = {}
    for _, cell in ipairs(cells) do
        local key = math.floor(cell.y * 1000 + 0.5)
        local bucket = cellsByYKey[key]
        if not bucket then
            bucket = {
                y = cell.y,
                cells = {},
            }
            cellsByYKey[key] = bucket
        end
        bucket.cells[#bucket.cells + 1] = cell
    end

    local terrainRects = {}
    local rectCount = 0
    for _, bucket in pairs(cellsByYKey) do
        local fillRects = PolygonBatcher.BuildRectsFromCells(bucket.cells, GRID_SIZE)
        rectCount += #fillRects
        terrainRects[#terrainRects + 1] = {
            y = bucket.y,
            rects = fillRects,
        }
    end

    table.sort(terrainRects, function(a, b)
        if a.y == b.y then
            return #a.rects < #b.rects
        end
        return a.y < b.y
    end)

    return terrainRects, rectCount
end

local function placeParkingStalls(parent, cells, id)
    -- Place white line markings in a grid pattern, deterministically
    local stallDepth = 16 -- studs (~4.8m)
    local state = hashSeed((id or "") .. #cells)
    local created = 0
    for _, cell in ipairs(cells) do
        -- Skip ~40% of cells to avoid overdoing it (deterministic)
        local unit
        state, unit = nextRandomUnit(state)
        if unit > 0.6 then
            continue
        end

        local line = Instance.new("Part")
        line.Name = "ParkingLine"
        line.Size = Vector3.new(0.3, 0.05, stallDepth)
        line.Material = Enum.Material.SmoothPlastic
        line.Color = Color3.fromRGB(255, 255, 255)
        line.Anchored = true
        line.CanCollide = false
        line.CastShadow = false
        line.CFrame = CFrame.new(cell.x, cell.y + 0.1, cell.z)
        line.Parent = parent
        created += 1
    end

    return created
end

local function placeParkFurniture(cells, parent)
    local area = #cells * GRID_SIZE * GRID_SIZE
    local count = math.min(8, math.floor(area / 400))
    if count <= 0 then
        return 0
    end
    local state = hashSeed(#cells * 7919)
    local used = {}
    local created = 0
    for _ = 1, count do
        local idx
        state, idx = nextRandomIndex(state, #cells)
        local attempts = 0
        while used[idx] and attempts < #cells do
            state, idx = nextRandomIndex(state, #cells)
            attempts += 1
        end
        used[idx] = true
        local cell = cells[idx]
        local bench = Instance.new("Part")
        bench.Name = "ParkBench"
        bench.Anchored = true
        bench.CanCollide = false
        bench.Size = Vector3.new(3, 0.3, 0.6)
        local yawUnit
        state, yawUnit = nextRandomUnit(state)
        bench.CFrame = CFrame.new(cell.x, cell.y + 0.15, cell.z)
            * CFrame.Angles(0, yawUnit * math.pi, 0)
        bench.Material = Enum.Material.WoodPlanks
        bench.Color = Color3.fromRGB(139, 90, 43)
        bench.CastShadow = false
        bench.Parent = parent
        created += 1
    end

    return created
end

-- Tree density per square stud by kind
local TREE_DENSITY = {
    forest = 1 / 80, -- ~1 tree per 80 sq studs (dense canopy)
    wood = 1 / 80,
    scrub = 1 / 160, -- sparse scrub
    heath = 1 / 200,
    park = 1 / 250, -- scattered park trees
    garden = 1 / 300,
}

-- Canopy colors by terrain type
local FOREST_CANOPY = {
    forest = BrickColor.new("Bright green"),
    wood = BrickColor.new("Dark green"),
    scrub = BrickColor.new("Olive"),
    heath = BrickColor.new("Sand green"),
    park = BrickColor.new("Bright green"),
    garden = BrickColor.new("Bright green"),
}

-- Scatter procedural trees across a vegetation area.
local function placeVegetation(kind, cells, parent)
    local density = TREE_DENSITY[kind]
    if not density then
        return 0
    end
    local area = #cells * GRID_SIZE * GRID_SIZE
    local count = math.min(60, math.floor(area * density))
    if count <= 0 then
        return 0
    end
    local canopyColor = FOREST_CANOPY[kind] or BrickColor.new("Bright green")

    local state = hashSeed(#cells * 997 + kind:byte(1, 1))
    local created = 0
    for _ = 1, count do
        local cellIndex
        state, cellIndex = nextRandomIndex(state, #cells)
        local cell = cells[cellIndex]
        local offsetX
        state, offsetX = nextRandomUnit(state)
        local offsetZ
        state, offsetZ = nextRandomUnit(state)
        local scaleUnit
        state, scaleUnit = nextRandomUnit(state)
        local canopyUnit
        state, canopyUnit = nextRandomUnit(state)
        local tx = cell.x + (offsetX - 0.5) * GRID_SIZE * 0.6
        local tz = cell.z + (offsetZ - 0.5) * GRID_SIZE * 0.6
        local scale = 0.7 + scaleUnit * 0.6
        local trunkH = 6 * scale
        local canopyR = (3.5 + canopyUnit * 2.5) * scale

        local model = Instance.new("Model")
        model.Name = kind .. "_tree"
        model:SetAttribute("ArnisProceduralVegetationKind", kind)

        local trunk = Instance.new("Part")
        trunk.Name = "Trunk"
        trunk.Anchored = true
        trunk.CanCollide = false
        trunk.CastShadow = false
        trunk.Size = Vector3.new(0.8 * scale, trunkH, 0.8 * scale)
        trunk.Shape = Enum.PartType.Cylinder
        trunk.CFrame = CFrame.new(tx, cell.y + trunkH * 0.5, tz)
            * CFrame.Angles(0, 0, math.pi * 0.5)
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(90, 65, 40)
        trunk.Parent = model

        local canopy = Instance.new("Part")
        canopy.Name = "Canopy"
        canopy.Anchored = true
        canopy.CanCollide = false
        canopy.CastShadow = false
        canopy.Shape = Enum.PartType.Ball
        canopy.Size = Vector3.new(canopyR * 2, canopyR * 2, canopyR * 2)
        canopy.CFrame = CFrame.new(tx, cell.y + trunkH + canopyR * 0.6, tz)
        canopy.Material = Enum.Material.LeafyGrass
        canopy.BrickColor = canopyColor
        canopy.Parent = model

        model.Parent = parent
        created += 1
    end

    return created
end

function LanduseBuilder.PlanOne(landuse, planningContext)
    if not landuse.footprint or #landuse.footprint < 3 then
        return nil
    end

    local mat = getMaterial(landuse.kind, landuse.material)
    local cells = collectCells(landuse, planningContext)
    if #cells == 0 then
        return nil
    end
    local terrainRects, rectCount = buildTerrainRects(cells)

    return {
        id = landuse.id,
        kind = landuse.kind,
        material = mat,
        cells = cells,
        terrainRects = terrainRects,
        wantsParkingStalls = landuse.kind == "parking",
        wantsParkFurniture = landuse.kind == "park" or landuse.kind == "garden",
        vegetationKind = landuse.kind,
        stats = {
            cellCount = #cells,
            rectCount = rectCount,
        },
    }
end

function LanduseBuilder.ExecutePlan(plan, parent)
    if not plan or not plan.items or #plan.items == 0 then
        return {
            terrainFillRects = 0,
            detailInstances = 0,
            terrainFillMs = 0,
            detailMs = 0,
        }
    end

    local terrain = Workspace.Terrain
    local detailParent = nil
    local filledRects = 0
    local detailInstances = 0
    local terrainFillStartedAt = os.clock()

    local function ensureDetailParent()
        if not detailParent then
            detailParent = getLanduseDetailParent(parent)
        end
        return detailParent
    end

    for _, item in ipairs(plan.items) do
        for _, bucket in ipairs(item.terrainRects) do
            for _, rect in ipairs(bucket.rects) do
                terrain:FillBlock(
                    CFrame.new(rect.centerX, bucket.y - FILL_DEPTH * 0.5, rect.centerZ),
                    Vector3.new(rect.width, FILL_DEPTH, rect.depth),
                    item.material
                )

                filledRects += 1
                if filledRects % FILL_YIELD_INTERVAL == 0 then
                    task.wait()
                end
            end
        end
    end
    local terrainFillMs = (os.clock() - terrainFillStartedAt) * 1000

    local detailStartedAt = os.clock()
    for _, item in ipairs(plan.items) do
        if item.wantsParkingStalls then
            detailInstances += placeParkingStalls(ensureDetailParent(), item.cells, item.id)
        end
        if item.wantsParkFurniture then
            detailInstances += placeParkFurniture(item.cells, ensureDetailParent())
        end
        detailInstances += placeVegetation(item.vegetationKind, item.cells, ensureDetailParent())
    end
    local detailMs = (os.clock() - detailStartedAt) * 1000

    return {
        terrainFillRects = filledRects,
        detailInstances = detailInstances,
        terrainFillMs = terrainFillMs,
        detailMs = detailMs,
    }
end

function LanduseBuilder.PlanAll(landuseList, originStuds, chunk)
    if not landuseList or #landuseList == 0 then
        return {
            items = {},
            stats = {
                featureCount = 0,
                cellCount = 0,
                rectCount = 0,
            },
        }
    end

    local planningContext = makePlanningContext(originStuds, chunk)
    local items = {}
    local stats = {
        featureCount = 0,
        cellCount = 0,
        rectCount = 0,
    }

    for _, landuse in ipairs(landuseList) do
        local plan = LanduseBuilder.PlanOne(landuse, planningContext)
        if plan then
            items[#items + 1] = plan
            stats.featureCount += 1
            stats.cellCount += plan.stats.cellCount
            stats.rectCount += plan.stats.rectCount
        end
    end

    table.sort(items, function(a, b)
        local aId = a.id or ""
        local bId = b.id or ""
        if aId == bId then
            return (a.kind or "") < (b.kind or "")
        end
        return aId < bId
    end)

    return {
        items = items,
        stats = stats,
    }
end

function LanduseBuilder.BuildOne(landuse, originStuds, parent, chunk)
    local plan = LanduseBuilder.PlanAll({ landuse }, originStuds, chunk)
    return LanduseBuilder.ExecutePlan(plan, parent)
end

function LanduseBuilder.BuildAll(landuseList, originStuds, parent, chunk, preparedPlan)
    if not landuseList or #landuseList == 0 then
        return {
            featureCount = 0,
            cellCount = 0,
            rectCount = 0,
            terrainFillRects = 0,
            detailInstances = 0,
            planMs = 0,
            executeMs = 0,
            terrainFillMs = 0,
            detailMs = 0,
        }
    end

    local planProfile = Profiler.begin("PlanLanduse")
    local plan = preparedPlan or LanduseBuilder.PlanAll(landuseList, originStuds, chunk)
    local planResult = Profiler.finish(planProfile, plan.stats)

    local executeProfile = Profiler.begin("ExecuteLanduse")
    local executionStats = LanduseBuilder.ExecutePlan(plan, parent)
    local executeResult = Profiler.finish(executeProfile, {
        featureCount = plan.stats.featureCount,
        cellCount = plan.stats.cellCount,
        rectCount = plan.stats.rectCount,
        terrainFillRects = executionStats.terrainFillRects,
        detailInstances = executionStats.detailInstances,
    })

    return {
        featureCount = plan.stats.featureCount,
        cellCount = plan.stats.cellCount,
        rectCount = plan.stats.rectCount,
        terrainFillRects = executionStats.terrainFillRects,
        detailInstances = executionStats.detailInstances,
        planMs = planResult.elapsedMs,
        executeMs = executeResult.elapsedMs,
        terrainFillMs = executionStats.terrainFillMs or 0,
        detailMs = executionStats.detailMs or 0,
    }
end

return LanduseBuilder
