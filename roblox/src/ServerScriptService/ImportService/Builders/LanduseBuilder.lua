local Workspace = game:GetService("Workspace")

local GroundSampler = require(script.Parent.Parent.GroundSampler)
local GeoUtils = require(script.Parent.Parent.GeoUtils)
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

local function collectCells(landuse, originStuds, chunk)
    local worldPoly = table.create(#landuse.footprint)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(landuse.footprint) do
        local wx = p.x + originStuds.x
        local wz = p.z + originStuds.z
        worldPoly[#worldPoly + 1] = { x = wx, z = wz }
        minX = math.min(minX, wx)
        minZ = math.min(minZ, wz)
        maxX = math.max(maxX, wx)
        maxZ = math.max(maxZ, wz)
    end

    local cells = {}
    local roadIndex = nil
    local sampleGroundY = GroundSampler.createSampler(chunk)
    if chunk and chunk.roads and #chunk.roads > 0 then
        roadIndex = SpatialQuery.GetRoadIndex(chunk.roads, originStuds)
    end
    local x = minX + GRID_SIZE * 0.5
    local sampledCells = 0
    while x <= maxX do
        local z = minZ + GRID_SIZE * 0.5
        while z <= maxZ do
            sampledCells += 1
            if sampledCells % CELL_COLLECTION_YIELD_INTERVAL == 0 then
                task.wait()
            end

            if GeoUtils.pointInPolygon(x, z, worldPoly) then
                local isNearRoad = false
                if roadIndex then
                    isNearRoad = SpatialQuery.isPointNearRoadIndex(roadIndex, x, z)
                end

                if not isNearRoad then
                    cells[#cells + 1] = {
                        x = x,
                        z = z,
                        y = sampleGroundY(x, z),
                    }
                end
            end
            z = z + GRID_SIZE
        end
        x = x + GRID_SIZE
    end

    return cells
end

local function placeParkingStalls(parent, cells, id)
    -- Place white line markings in a grid pattern, deterministically
    local stallDepth = 16 -- studs (~4.8m)
    local state = hashSeed((id or "") .. #cells)
    for _, cell in ipairs(cells) do
        -- Skip ~40% of cells to avoid overdoing it (deterministic)
        local unit
        state, unit = nextRandomUnit(state)
        if unit > 0.6 then continue end

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
    end
end

local function placeParkFurniture(cells, parent)
    local area = #cells * GRID_SIZE * GRID_SIZE
    local count = math.min(8, math.floor(area / 400))
    if count <= 0 then
        return
    end
    local state = hashSeed(#cells * 7919)
    local used = {}
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
        bench.CFrame = CFrame.new(cell.x, cell.y + 0.15, cell.z) * CFrame.Angles(0, yawUnit * math.pi, 0)
        bench.Material = Enum.Material.WoodPlanks
        bench.Color = Color3.fromRGB(139, 90, 43)
        bench.CastShadow = false
        bench.Parent = parent
    end
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
        return
    end
    local area = #cells * GRID_SIZE * GRID_SIZE
    local count = math.min(60, math.floor(area * density))
    if count <= 0 then
        return
    end
    local canopyColor = FOREST_CANOPY[kind] or BrickColor.new("Bright green")

    local state = hashSeed(#cells * 997 + kind:byte(1, 1))
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

        local trunk = Instance.new("Part")
        trunk.Anchored = true
        trunk.CanCollide = false
        trunk.CastShadow = false
        trunk.Size = Vector3.new(0.8 * scale, trunkH, 0.8 * scale)
        trunk.Shape = Enum.PartType.Cylinder
        trunk.CFrame = CFrame.new(tx, cell.y + trunkH * 0.5, tz) * CFrame.Angles(0, 0, math.pi * 0.5)
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(90, 65, 40)
        trunk.Parent = model

        local canopy = Instance.new("Part")
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
    end
end

function LanduseBuilder.BuildOne(landuse, originStuds, parent, chunk)
    if not landuse.footprint or #landuse.footprint < 3 then
        return
    end

    local terrain = Workspace.Terrain
    local mat = getMaterial(landuse.kind, landuse.material)
    local cells = collectCells(landuse, originStuds, chunk)
    if #cells == 0 then
        return
    end

    local filledCells = 0
    for _, cell in ipairs(cells) do
        terrain:FillBlock(
            CFrame.new(cell.x, cell.y - FILL_DEPTH * 0.5, cell.z),
            Vector3.new(GRID_SIZE, FILL_DEPTH, GRID_SIZE),
            mat
        )

        filledCells += 1
        if filledCells % FILL_YIELD_INTERVAL == 0 then
            task.wait()
        end
    end

    -- Parking stall markings
    if landuse.kind == "parking" then
        placeParkingStalls(parent or Workspace, cells, landuse.id)
    end

    -- Scatter benches in parks
    if landuse.kind == "park" or landuse.kind == "garden" then
        placeParkFurniture(cells, parent or Workspace)
    end

    -- Scatter trees in vegetation areas
    placeVegetation(landuse.kind, cells, parent or Workspace)
end

function LanduseBuilder.BuildAll(landuseList, originStuds, parent, chunk)
    if not landuseList or #landuseList == 0 then
        return
    end
    for _, landuse in ipairs(landuseList) do
        LanduseBuilder.BuildOne(landuse, originStuds, parent, chunk)
    end
end

return LanduseBuilder
