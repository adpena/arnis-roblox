local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InstancePool = require(script.Parent.Parent.InstancePool)
local GroundSampler = require(script.Parent.Parent.GroundSampler)
local RoadProfile = require(script.Parent.Parent.RoadProfile)
local SpatialQuery = require(script.Parent.Parent.SpatialQuery)

local PropBuilder = {}

local pools = {}
local ROADSIDE_EXTRA_OFFSETS = {
    street_lamp = 0.75,
    bus_stop = 1.5,
    traffic_signal = 0.5,
    fire_hydrant = 1.0,
    waste_basket = 0.5,
}

local function getPrefabFolder()
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then
        return nil
    end

    return assetsFolder:FindFirstChild("Prefabs")
end

local function hashId(id)
    local h = 5381
    for i = 1, #id do
        h = ((h * 33) + string.byte(id, i)) % 2147483647
    end
    return h
end

local function deterministicUnitFloat(seed)
    local nextSeed = (seed * 48271) % 2147483647
    return nextSeed / 2147483647
end

local function resolveBaseY(_chunk, _worldX, fallbackY, _worldZ)
    return fallbackY
end

local function alignRoadsideProp(prop, chunk, originStuds, wx, wz)
    if not chunk or not chunk.roads then
        return wx, wz
    end

    local nearestRoad = SpatialQuery.findNearestRoadSegment(chunk.roads, originStuds, wx, wz)
    if not nearestRoad then
        return wx, wz
    end

    local snapThreshold = math.max(2, nearestRoad.width * 0.35)
    if nearestRoad.distance > snapThreshold then
        return wx, wz
    end

    local normalX = -nearestRoad.dirZ
    local normalZ = nearestRoad.dirX
    local side = (wx - nearestRoad.projX) * normalX + (wz - nearestRoad.projZ) * normalZ
    if math.abs(side) < 0.01 then
        side = (hashId(prop.id or prop.kind) % 2 == 0) and 1 or -1
    else
        side = side > 0 and 1 or -1
    end

    local sidewalk = RoadProfile.getSidewalkWidth(nearestRoad.road, nearestRoad.width)
    local edgeBuffer = RoadProfile.getEdgeBufferWidth(nearestRoad.road, nearestRoad.width)
    local extraOffset = ROADSIDE_EXTRA_OFFSETS[prop.kind] or 0.5
    local offset = nearestRoad.width * 0.5 + sidewalk + edgeBuffer + extraOffset

    return nearestRoad.projX + normalX * offset * side, nearestRoad.projZ + normalZ * offset * side
end

local METERS_TO_STUDS = 1 / 0.3 -- ~3.33 studs per meter

local SPECIES_COLOR = {
    -- Conifers (dark green)
    conifer = BrickColor.new("Dark green"),
    pinus = BrickColor.new("Dark green"),
    picea = BrickColor.new("Dark green"),
    abies = BrickColor.new("Dark green"),
    juniperus = BrickColor.new("Dark green"),
    needleleaved = BrickColor.new("Dark green"),
    -- Palms (tropical)
    palm = BrickColor.new("Bright yellow"),
    phoenix = BrickColor.new("Bright yellow"),
    washingtonia = BrickColor.new("Bright yellow"),
    sabal = BrickColor.new("Bright yellow"),
    -- Oaks (medium green, common in Austin)
    quercus = BrickColor.new("Bright green"),
    oak = BrickColor.new("Bright green"),
    ["live oak"] = BrickColor.new("Olive green"),
    ["quercus virginiana"] = BrickColor.new("Olive green"),
    -- Deciduous broadleaf (medium)
    broadleaved_deciduous = BrickColor.new("Bright green"),
    maple = BrickColor.new("Bright orange"),
    acer = BrickColor.new("Bright orange"),
    elm = BrickColor.new("Lime green"),
    ulmus = BrickColor.new("Lime green"),
    -- Evergreen broadleaf
    broadleaved_evergreen = BrickColor.new("Olive green"),
    -- Fruit/flowering trees
    prunus = BrickColor.new("Pink"),
    magnolia = BrickColor.new("Dark green"),
    -- Austin-specific species
    pecan = BrickColor.new("Olive"),
    cypress = BrickColor.new("Forest green"),
    mesquite = BrickColor.new("Sage green"),
    crepe_myrtle = BrickColor.new("Lavender"),
    cedar = BrickColor.new("Dark green"),
    ash = BrickColor.new("Lime green"),
    birch = BrickColor.new("Lime green"),
    willow = BrickColor.new("Olive"),
    cottonwood = BrickColor.new("Bright green"),
    hackberry = BrickColor.new("Olive"),
    sycamore = BrickColor.new("Lime green"),
    -- Default (Austin's mix of live oak + cedar)
    default = BrickColor.new("Bright green"),
}

local SPECIES_SCALE = {
    conifer = 0.7,
    palm = 0.5,
    oak = 1.2,
    quercus = 1.2,
    -- Austin-specific species
    magnolia = 1.1,
    pecan = 1.3,
    cypress = 0.8,
    mesquite = 0.7,
    crepe_myrtle = 0.6,
    cedar = 0.9,
    elm = 1.2,
    ash = 1.0,
    birch = 0.8,
    willow = 1.4,
    cottonwood = 1.3,
    hackberry = 1.0,
    sycamore = 1.3,
    default = 1.0,
}

local function getCanopyColor(species)
    if not species then
        return SPECIES_COLOR.default
    end
    local s = species:lower()
    -- Try exact match first
    if SPECIES_COLOR[s] then
        return SPECIES_COLOR[s]
    end
    -- Try prefix match
    for key, color in pairs(SPECIES_COLOR) do
        if s:find(key, 1, true) then
            return color
        end
    end
    return SPECIES_COLOR.default
end

local function getCanopyScale(species)
    if not species then
        return 1.0
    end
    local s = species:lower()
    -- Try exact match first
    if SPECIES_SCALE[s] then
        return SPECIES_SCALE[s]
    end
    -- Try prefix match
    for key, scale in pairs(SPECIES_SCALE) do
        if s:find(key, 1, true) then
            return scale
        end
    end
    return 1.0
end

local function getTreeScale(prop)
    if prop.height and prop.height > 0 then
        -- Convert real-world meters to studs, then scale relative to default 20-stud tree
        local heightStuds = prop.height * METERS_TO_STUDS
        return math.clamp(heightStuds / 20, 0.5, 3.0)
    end
    return getCanopyScale(prop.species)
end

local function getOrCreatePool(kind)
    if pools[kind] then
        return pools[kind]
    end

    -- Strategy: Use prefabs from ReplicatedStorage if they exist, otherwise use generic placeholders
    local prefabFolder = getPrefabFolder()
    local prefab = if prefabFolder then prefabFolder:FindFirstChild(kind) else nil
    if prefab then
        pools[kind] = InstancePool.new(prefab)
    else
        -- Placeholder models
        pools[kind] = InstancePool.new("Model")
    end

    return pools[kind]
end

local function buildStreetLamp(x, y, z, parent)
    local model = Instance.new("Model")
    model.Name = "StreetLamp"
    model.Parent = parent

    -- Pole
    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Anchored = true
    pole.Size = Vector3.new(0.3, 10, 0.3)
    pole.CFrame = CFrame.new(x, y + 5, z)
    pole.Material = Enum.Material.Metal
    pole.Color = Color3.fromRGB(80, 80, 80)
    pole.CastShadow = false
    pole.Parent = model

    -- Arm
    local arm = Instance.new("Part")
    arm.Name = "Arm"
    arm.Anchored = true
    arm.Size = Vector3.new(1.5, 0.2, 0.2)
    arm.CFrame = CFrame.new(x + 0.75, y + 9.8, z)
    arm.Material = Enum.Material.Metal
    arm.Color = Color3.fromRGB(80, 80, 80)
    arm.CastShadow = false
    arm.Parent = model

    -- Light head
    local head = Instance.new("Part")
    head.Name = "LightHead"
    head.Anchored = true
    head.Size = Vector3.new(0.8, 0.4, 0.8)
    head.CFrame = CFrame.new(x + 1.5, y + 9.6, z)
    head.Material = Enum.Material.Neon
    head.Color = Color3.fromRGB(255, 240, 200)
    head.CastShadow = false
    head.Parent = model

    -- Point light
    local light = Instance.new("PointLight")
    light.Brightness = 3
    light.Range = 30
    light.Color = Color3.fromRGB(255, 240, 200)
    light.Shadows = true
    light.Parent = head

    return model
end

-- Builds a simple procedural tree model (trunk + canopy)
local function buildTree(parent, prop, originStuds, baseYOverride)
    local worldPos = Vector3.new(
        prop.position.x + originStuds.x,
        baseYOverride or (prop.position.y + originStuds.y),
        prop.position.z + originStuds.z
    )
    local yaw = math.rad(prop.yawDegrees or 0)
    -- prop.scale is an optional manifest override; getTreeScale derives scale from
    -- prop.height (real meters) when available, otherwise falls back to species table.
    local scale = prop.scale or getTreeScale(prop)
    local canopySeed = hashId(prop.id or tostring(prop.position.x) .. ":" .. tostring(prop.position.z))

    local model = Instance.new("Model")
    model.Name = prop.id or "Tree"

    local trunkH = 7 * scale
    local trunkR = 0.5 * scale
    local canopyR = (4 + deterministicUnitFloat(canopySeed) * 3) * scale

    -- Scale trunk radius from real-world circumference when available.
    if prop.circumference and prop.circumference > 0 then
        local diameterStuds = (prop.circumference / math.pi) * METERS_TO_STUDS
        trunkR = math.max(0.5, diameterStuds * 0.5)
    end

    -- Palm special case: thin trunk + frond cluster instead of sphere canopy
    local species = prop.species and prop.species:lower() or ""
    local leafType = prop.leafType or ""
    if species:find("palm") or leafType == "tropical" then
        local trunk = Instance.new("Part")
        trunk.Name = "Trunk"
        trunk.Anchored = true
        trunk.Size = Vector3.new(trunkR * 0.6 * 2, trunkH, trunkR * 0.6 * 2)
        trunk.Shape = Enum.PartType.Cylinder
        trunk.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH * 0.5, 0)) * CFrame.Angles(0, yaw, math.pi * 0.5)
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(139, 109, 75)
        trunk.CastShadow = false
        trunk.Parent = model

        local trunkTop = worldPos + Vector3.new(0, trunkH, 0)
        for i = 1, 4 do
            local frond = Instance.new("Part")
            frond.Name = "Frond" .. i
            frond.Size = Vector3.new(1, 0.5, canopyR * 1.5)
            frond.Color = Color3.fromRGB(34, 120, 50)
            frond.Material = Enum.Material.Grass
            frond.Anchored = true
            frond.CanCollide = false
            frond.CastShadow = false
            local angle = (i - 1) * 90
            frond.CFrame = CFrame.new(trunkTop)
                * CFrame.Angles(0, math.rad(angle), 0)
                * CFrame.Angles(math.rad(-30), 0, 0)
                * CFrame.new(0, 0, -canopyR * 0.5)
            frond.Parent = model
        end

        model.Parent = parent
        return model
    end

    -- Standard tree: trunk + shaped canopy
    -- Trunk: Cylinder is axis-Z by default; rotate 90° on Z to stand upright
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Anchored = true
    trunk.Size = Vector3.new(trunkR * 2, trunkH, trunkR * 2)
    trunk.Shape = Enum.PartType.Cylinder
    trunk.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH * 0.5, 0)) * CFrame.Angles(0, yaw, math.pi * 0.5)
    trunk.Material = Enum.Material.Wood
    trunk.Color = Color3.fromRGB(101, 79, 55)
    trunk.CastShadow = false
    trunk.Parent = model

    -- Canopy: shape depends on leafType
    local canopy = Instance.new("Part")
    canopy.Name = "Canopy"
    canopy.Anchored = true
    canopy.Material = Enum.Material.LeafyGrass
    canopy.BrickColor = getCanopyColor(prop.species)
    canopy.CastShadow = false

    if leafType == "needleleaved" then
        -- Cone-like: tall and narrow
        canopy.Shape = Enum.PartType.Ball
        canopy.Size = Vector3.new(canopyR * 1.2, canopyR * 2.5, canopyR * 1.2)
        canopy.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH + canopyR * 0.9, 0))
    else
        -- Broadleaved default: wide, round sphere
        canopy.Shape = Enum.PartType.Ball
        canopy.Size = Vector3.new(canopyR * 2, canopyR * 1.5, canopyR * 2)
        canopy.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH + canopyR * 0.5, 0))
    end

    canopy.Parent = model
    model.Parent = parent
    return model
end

function PropBuilder.Build(parent, prop, originStuds, chunk)
    if prop.kind == "tree" then
        -- Use manifest Y directly; DEM elevation is authoritative
        return buildTree(parent, prop, originStuds, prop.position.y + originStuds.y)
    end

    if prop.kind == "street_lamp" or prop.kind == "amenity_street_lamp" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        return buildStreetLamp(wx, wy, wz, parent)
    end

    if prop.kind == "bench" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local bench = Instance.new("Part")
        bench.Name = "Bench"
        bench.Anchored = true
        bench.CanCollide = false
        bench.CastShadow = false
        bench.Size = Vector3.new(2, 0.25, 0.6)
        bench.CFrame = CFrame.new(wx, wy + 0.8, wz) * CFrame.Angles(0, math.rad(prop.yawDegrees or 0), 0)
        bench.Material = Enum.Material.WoodPlanks
        bench.Color = Color3.fromRGB(139, 90, 43)
        bench.Parent = parent
        return bench
    end

    if prop.kind == "bus_stop" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local model = Instance.new("Model")
        model.Name = "BusStop"
        local pole = Instance.new("Part")
        pole.Anchored = true
        pole.CastShadow = false
        pole.CanCollide = false
        pole.Size = Vector3.new(0.2, 5, 0.2)
        pole.CFrame = CFrame.new(wx, wy + 2.5, wz)
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(180, 180, 190)
        pole.Parent = model
        local sign = Instance.new("Part")
        sign.Anchored = true
        sign.CastShadow = false
        sign.CanCollide = false
        sign.Size = Vector3.new(0.8, 0.5, 0.1)
        sign.CFrame = CFrame.new(wx, wy + 5.2, wz)
        sign.Material = Enum.Material.SmoothPlastic
        sign.Color = Color3.fromRGB(0, 80, 180)
        sign.Parent = model
        model.Parent = parent
        return model
    end

    if prop.kind == "traffic_signal" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local model = Instance.new("Model")
        model.Name = "TrafficSignal"
        local pole = Instance.new("Part")
        pole.Anchored = true
        pole.CastShadow = false
        pole.CanCollide = false
        pole.Size = Vector3.new(0.25, 9, 0.25)
        pole.CFrame = CFrame.new(wx, wy + 4.5, wz)
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(60, 60, 60)
        pole.Parent = model
        local head = Instance.new("Part")
        head.Anchored = true
        head.CastShadow = false
        head.CanCollide = false
        head.Size = Vector3.new(1, 2.5, 0.6)
        head.CFrame = CFrame.new(wx, wy + 9.5, wz)
        head.Material = Enum.Material.SmoothPlastic
        head.Color = Color3.fromRGB(30, 30, 30)
        head.Parent = model
        local light = Instance.new("Part")
        light.Anchored = true
        light.CastShadow = false
        light.CanCollide = false
        light.Size = Vector3.new(0.6, 0.6, 0.2)
        light.CFrame = CFrame.new(wx, wy + 9.0, wz + 0.3)
        light.Material = Enum.Material.Neon
        light.Color = Color3.fromRGB(0, 210, 80)
        light.Parent = model
        model.Parent = parent
        return model
    end

    if prop.kind == "waste_basket" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local bin = Instance.new("Part")
        bin.Name = "WasteBasket"
        bin.Anchored = true
        bin.CastShadow = false
        bin.CanCollide = false
        bin.Size = Vector3.new(0.8, 1.2, 0.8)
        bin.CFrame = CFrame.new(wx, wy + 0.6, wz)
        bin.Material = Enum.Material.Metal
        bin.Color = Color3.fromRGB(70, 70, 70)
        bin.Parent = parent
        return bin
    end

    if prop.kind == "fire_hydrant" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local hydrant = Instance.new("Part")
        hydrant.Name = "FireHydrant"
        hydrant.Anchored = true
        hydrant.CastShadow = false
        hydrant.CanCollide = false
        hydrant.Size = Vector3.new(0.6, 1.0, 0.6)
        hydrant.CFrame = CFrame.new(wx, wy + 0.5, wz)
        hydrant.Material = Enum.Material.SmoothPlastic
        hydrant.Color = Color3.fromRGB(220, 30, 30)
        hydrant.Parent = parent
        return hydrant
    end

    if prop.kind == "crossing" then
        -- Render a zebra crosswalk: 6-8 white stripes perpendicular to nearby road
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z

        -- Place striped crosswalk markings (simple: assume N-S direction,
        -- could be improved by finding nearest road direction)
        local stripeCount = 6
        local stripeWidth = 1.5
        local stripeLen = 12  -- studs across the road
        local gap = 1.2

        local crosswalkModel = Instance.new("Model")
        crosswalkModel.Name = prop.id

        for s = 1, stripeCount do
            local offset = (s - stripeCount / 2 - 0.5) * (stripeWidth + gap)
            local stripe = Instance.new("Part")
            stripe.Name = "CrosswalkStripe"
            stripe.Size = Vector3.new(stripeLen, 0.05, stripeWidth)
            stripe.Material = Enum.Material.SmoothPlastic
            stripe.Color = Color3.fromRGB(255, 255, 255)
            stripe.Anchored = true
            stripe.CanCollide = false
            stripe.CastShadow = false
            stripe.CFrame = CFrame.new(wx, wy + 0.15, wz + offset)
            stripe.Parent = crosswalkModel
        end

        crosswalkModel.Parent = parent
        return crosswalkModel
    end

    local pool = getOrCreatePool(prop.kind)
    local instance = pool:Acquire()

    instance.Name = prop.id or prop.kind
    instance:SetAttribute("PoolKind", prop.kind)

    local worldPos = Vector3.new(
        prop.position.x + originStuds.x,
        resolveBaseY(
            chunk,
            prop.position.x + originStuds.x,
            prop.position.y + originStuds.y,
            prop.position.z + originStuds.z
        ),
        prop.position.z + originStuds.z
    )

    instance:PivotTo(CFrame.new(worldPos) * CFrame.Angles(0, math.rad(prop.yawDegrees or 0), 0))
    instance.Parent = parent

    if prop.scale then
        -- Apply scale if the instance supports it (Models do via Scale property)
        if instance:IsA("Model") then
            instance:ScaleTo(prop.scale)
        end
    end

    return instance
end

function PropBuilder.Clear(kind)
    if pools[kind] then
        pools[kind]:Drain()
    end
end

function PropBuilder.ReleaseAll(parent)
    for _, child in ipairs(parent:GetChildren()) do
        local poolKind = child:GetAttribute("PoolKind")
        if poolKind and pools[poolKind] then
            pools[poolKind]:Release(child)
        else
            child:Destroy()
        end
    end
end

return PropBuilder
