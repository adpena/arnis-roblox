local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local AssetService = game:GetService("AssetService")

local RoadChunkPlan = require(script.Parent.Parent.RoadChunkPlan)
local RoadProfile = require(script.Parent.Parent.RoadProfile)
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)

local RoadBuilder = {}

-- Maps OSM surface tag → physical properties for road Parts and MeshParts.
-- Surface physics tuned for realistic vehicle handling.
-- Roblox Friction range 0-2; real tire-on-surface coefficients mapped to this range.
-- Density affects mass/inertia. Elasticity affects bounce (low for all roads).
-- FrictionWeight=1 means equal influence between wheel and surface.
--
-- Reference (dry conditions, rubber tires):
--   Real asphalt μ ≈ 0.7-0.8  →  Roblox 0.75
--   Real concrete μ ≈ 0.6-0.7 →  Roblox 0.65
--   Real cobble μ  ≈ 0.5-0.6  →  Roblox 0.55
--   Real gravel μ  ≈ 0.3-0.5  →  Roblox 0.40
--   Real dirt μ    ≈ 0.3-0.4  →  Roblox 0.30
--   Real sand μ    ≈ 0.2-0.3  →  Roblox 0.20
--   Real ice μ     ≈ 0.1-0.2  →  Roblox 0.12

local SURFACE_PHYSICS = {
    -- Paved surfaces (high grip)
    asphalt         = PhysicalProperties.new(2.4, 0.75, 0.08, 1, 1),
    concrete        = PhysicalProperties.new(2.4, 0.65, 0.10, 1, 1),
    asphalt_smooth  = PhysicalProperties.new(2.4, 0.70, 0.08, 1, 1),  -- newer asphalt

    -- Stone surfaces (medium-high grip, some bump)
    paving_stones   = PhysicalProperties.new(2.4, 0.58, 0.12, 1, 1),
    cobblestone     = PhysicalProperties.new(2.4, 0.50, 0.12, 1, 1),  -- uneven, bumpy
    sett            = PhysicalProperties.new(2.4, 0.52, 0.10, 1, 1),  -- cut stone blocks
    unhewn_cobblestone = PhysicalProperties.new(2.4, 0.45, 0.14, 1, 1), -- rough, very bumpy

    -- Loose surfaces (low grip, vehicles slide)
    gravel          = PhysicalProperties.new(1.8, 0.38, 0.04, 1, 1),
    fine_gravel     = PhysicalProperties.new(1.8, 0.42, 0.04, 1, 1),
    pebblestone     = PhysicalProperties.new(1.8, 0.35, 0.05, 1, 1),
    compacted       = PhysicalProperties.new(2.0, 0.48, 0.05, 1, 1),  -- packed earth, decent grip

    -- Unpaved (low grip)
    unpaved         = PhysicalProperties.new(1.6, 0.32, 0.04, 1, 1),
    dirt            = PhysicalProperties.new(1.6, 0.28, 0.04, 1, 1),
    earth           = PhysicalProperties.new(1.6, 0.28, 0.04, 1, 1),
    mud             = PhysicalProperties.new(1.4, 0.18, 0.02, 1, 1),  -- very slippery
    sand            = PhysicalProperties.new(1.4, 0.20, 0.02, 1, 1),  -- wheels sink + slide
    grass           = PhysicalProperties.new(1.2, 0.30, 0.08, 1, 1),  -- damp grass, moderate grip

    -- Special surfaces
    wood            = PhysicalProperties.new(0.8, 0.45, 0.15, 1, 1),  -- boardwalk, slightly bouncy
    metal           = PhysicalProperties.new(3.0, 0.35, 0.10, 1, 1),  -- bridge grating, slippery
    rubber          = PhysicalProperties.new(1.2, 0.90, 0.20, 1, 1),  -- playground, high grip
    tartan          = PhysicalProperties.new(1.2, 0.85, 0.15, 1, 1),  -- running track
    ice             = PhysicalProperties.new(2.4, 0.12, 0.02, 1, 1),  -- future: winter mode
    snow            = PhysicalProperties.new(1.0, 0.18, 0.05, 1, 1),  -- future: winter mode
}

-- Default for roads with no surface tag (treated as good asphalt).
local DEFAULT_ROAD_PHYSICS = PhysicalProperties.new(2.4, 0.75, 0.08, 1, 1)

-- Concrete physics for bridge decks and tunnel surfaces.
local CONCRETE_PHYSICS = PhysicalProperties.new(2.4, 0.65, 0.10, 1, 1)

-- Extra-grip physics for steps/stairs (textured concrete, anti-slip).
local STEPS_PHYSICS = PhysicalProperties.new(2.4, 0.85, 0.08, 1, 1)

-- Sidewalk physics (smooth concrete, good walking grip).
local SIDEWALK_PHYSICS = PhysicalProperties.new(2.4, 0.70, 0.10, 1, 1)

-- Returns the appropriate physical properties for a road entry.
local function getPhysicsProperties(road)
    if road.surface and SURFACE_PHYSICS[road.surface] then
        return SURFACE_PHYSICS[road.surface]
    end
    if road.kind == "footway" or road.kind == "path" then
        return SURFACE_PHYSICS.compacted
    elseif road.kind == "track" then
        return SURFACE_PHYSICS.gravel
    end
    return DEFAULT_ROAD_PHYSICS
end

-- Maps OSM surface tag → Roblox terrain material (checked before kind fallback)
local SURFACE_MATERIAL = {
    asphalt = Enum.Material.Asphalt,
    concrete = Enum.Material.Concrete,
    ["concrete:plates"] = Enum.Material.Concrete,
    cobblestone = Enum.Material.Cobblestone,
    paving_stones = Enum.Material.Cobblestone,
    bricks = Enum.Material.Cobblestone,
    sett = Enum.Material.Cobblestone,
    gravel = Enum.Material.Pebble,
    fine_gravel = Enum.Material.Pebble,
    compacted = Enum.Material.Ground,
    pebblestone = Enum.Material.Pebble,
    rock = Enum.Material.Rock,
    unpaved = Enum.Material.Ground,
    dirt = Enum.Material.Ground,
    earth = Enum.Material.Ground,
    grass = Enum.Material.Grass,
    wood = Enum.Material.WoodPlanks,
    stepping_stones = Enum.Material.Pavement,
    paved = Enum.Material.Concrete,
    sand = Enum.Material.Sand,
    metal = Enum.Material.DiamondPlate,
}

-- Maps road kind → Roblox terrain material for Terrain:FillBlock
local ROAD_MATERIAL = {
    -- Highways: smooth concrete
    motorway = Enum.Material.Concrete,
    motorway_link = Enum.Material.Concrete,
    trunk = Enum.Material.Concrete,
    trunk_link = Enum.Material.Concrete,
    -- Primary/secondary: asphalt
    primary = Enum.Material.Asphalt,
    primary_link = Enum.Material.Asphalt,
    secondary = Enum.Material.Asphalt,
    secondary_link = Enum.Material.Asphalt,
    -- Local streets: asphalt (slightly different feel via paint order)
    tertiary = Enum.Material.Asphalt,
    tertiary_link = Enum.Material.Asphalt,
    residential = Enum.Material.Asphalt,
    living_street = Enum.Material.Pavement,
    service = Enum.Material.Limestone,
    -- Pedestrian / cycling
    footway = Enum.Material.Pavement,
    path = Enum.Material.Cobblestone,
    pedestrian = Enum.Material.SmoothPlastic,
    cycleway = Enum.Material.Sandstone,
    steps = Enum.Material.Slate,
    bridleway = Enum.Material.Ground,
    -- Unpaved
    track = Enum.Material.Mud,
    unclassified = Enum.Material.Ground,
    road = Enum.Material.Ground,
    default = Enum.Material.Asphalt,
}

local ROAD_THICKNESS = 1 -- studs; road fills 0.5 studs into terrain + 0.5 above
local PAVEMENT_THICKNESS = 0.7
local CURB_THICKNESS = 0.35
local ROAD_SURFACE_LIFT = 0.15
local PAVEMENT_SURFACE_LIFT = 0.25
local CURB_SURFACE_LIFT = 0.45
local BRIDGE_PILLAR_SPACING = 24
local BRIDGE_MIN_PILLAR_CLEARANCE = 2.5
local BRIDGE_GUARDRAIL_OFFSET = 0.15
local STREET_LIGHT_INTERVAL = WorldConfig.StreetLightInterval or 50 -- studs between lamp posts
local STREET_LIGHT_RANGE = WorldConfig.StreetLightRange or 40
local STREET_LIGHT_BRIGHTNESS = 1
local STREET_LIGHT_COLOR = Color3.fromRGB(255, 244, 214) -- warm white

local function getRoadDetailParent(parent)
    local detailFolder = parent:FindFirstChild("Detail")
    if detailFolder and detailFolder:IsA("Folder") then
        return detailFolder
    end

    detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")
    detailFolder.Parent = parent
    return detailFolder
end

-- Returns "both", "left", "right", or "no".
local function getMaterial(road)
    -- 1. OSM surface tag takes priority (most specific physical description)
    if road.surface then
        local m = SURFACE_MATERIAL[road.surface]
        if m then
            return m
        end
    end
    -- 2. Legacy manifest material name (Enum.Material string)
    if road.material then
        local ok, m = pcall(function()
            return Enum.Material[road.material]
        end)
        if ok and m then
            return m
        end
    end
    -- 3. Road kind fallback
    return ROAD_MATERIAL[road.kind] or ROAD_MATERIAL.default
end

-- Maps road kind → approximate surface color for EditableMesh parts.
-- These approximate the visual tones of Roblox terrain materials.
local ROAD_COLOR = {
    motorway = Color3.fromRGB(100, 100, 110),
    motorway_link = Color3.fromRGB(100, 100, 110),
    trunk = Color3.fromRGB(100, 100, 110),
    trunk_link = Color3.fromRGB(100, 100, 110),
    primary = Color3.fromRGB(80, 80, 85),
    primary_link = Color3.fromRGB(80, 80, 85),
    secondary = Color3.fromRGB(80, 80, 85),
    secondary_link = Color3.fromRGB(80, 80, 85),
    tertiary = Color3.fromRGB(80, 80, 85),
    tertiary_link = Color3.fromRGB(80, 80, 85),
    residential = Color3.fromRGB(80, 80, 85),
    living_street = Color3.fromRGB(160, 155, 145),
    service = Color3.fromRGB(185, 175, 160),
    footway = Color3.fromRGB(160, 155, 145),
    path = Color3.fromRGB(140, 130, 115),
    pedestrian = Color3.fromRGB(200, 195, 185),
    cycleway = Color3.fromRGB(175, 170, 150),
    steps = Color3.fromRGB(180, 175, 168),
    bridleway = Color3.fromRGB(120, 105, 85),
    track = Color3.fromRGB(110, 95, 75),
    unclassified = Color3.fromRGB(110, 100, 90),
    road = Color3.fromRGB(100, 95, 90),
    default = Color3.fromRGB(80, 80, 85),
}

local function getRoadColor(road)
    return ROAD_COLOR[road.kind] or ROAD_COLOR.default
end

local function classifySegment(road, p1, p2, _chunk)
    if road.elevated then
        return "bridge", p1, p2
    elseif road.tunnel then
        return "tunnel", p1, p2
    else
        return "ground", p1, p2
    end
end

local function paintStrip(terrain, p1, p2, width, thickness, material, surfaceLift, sideOffset)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return nil, 0
    end

    -- Per-endpoint Y: follow the slope instead of averaging to a flat surface
    local y1 = p1.Y + surfaceLift
    local y2 = p2.Y + surfaceLift
    local startPos = Vector3.new(p1.X, y1 - thickness * 0.5, p1.Z)
    local endPos = Vector3.new(p2.X, y2 - thickness * 0.5, p2.Z)
    local midPos = (startPos + endPos) * 0.5

    -- CFrame.lookAt tilts the part to follow the slope between p1 and p2
    local cf = CFrame.lookAt(midPos, endPos)
    if sideOffset and math.abs(sideOffset) > 1e-6 then
        cf = cf * CFrame.new(sideOffset, 0, 0)
    end

    terrain:FillBlock(cf, Vector3.new(width, thickness, length + 0.25), material)
    return cf, length
end

-- Paint one road segment into terrain using FillBlock (ground-level roads).
-- sidewalkMode: "both" | "left" | "right" | "no"
-- Left side  → negative sideOffset (CFrame local X < 0)
-- Right side → positive sideOffset (CFrame local X > 0)
local function paintSegment(terrain, p1, p2, road, width, material, sidewalkMode)
    local sidewalkWidth = RoadProfile.getSidewalkWidth(road, width)
    local edgeBuffer = RoadProfile.getEdgeBufferWidth(road, width)

    local hasSidewalkLeft = (sidewalkMode == "both" or sidewalkMode == "left") and sidewalkWidth > 0
    local hasSidewalkRight = (sidewalkMode == "both" or sidewalkMode == "right") and sidewalkWidth > 0

    -- Base pavement slab spans the full kerb-to-kerb width for the sides that
    -- have a sidewalk; if both, it's symmetric; if one-sided, expand only that way.
    local leftExtra = hasSidewalkLeft and (sidewalkWidth + edgeBuffer) or 0
    local rightExtra = hasSidewalkRight and (sidewalkWidth + edgeBuffer) or 0
    local totalPavedWidth = width + leftExtra + rightExtra
    local pavementMaterial = (hasSidewalkLeft or hasSidewalkRight) and Enum.Material.Pavement or material

    -- When one-sided the base slab needs to be off-centre by half the asymmetry.
    local baseOffset = (rightExtra - leftExtra) * 0.5
    paintStrip(
        terrain,
        p1,
        p2,
        totalPavedWidth,
        PAVEMENT_THICKNESS,
        pavementMaterial,
        PAVEMENT_SURFACE_LIFT,
        baseOffset ~= 0 and baseOffset or nil
    )
    paintStrip(terrain, p1, p2, width, ROAD_THICKNESS, material, ROAD_SURFACE_LIFT)

    -- Curb on left side (negative offset)
    if hasSidewalkLeft then
        local curbOffset = -(width * 0.5 + CURB_THICKNESS * 0.5)
        paintStrip(
            terrain,
            p1,
            p2,
            CURB_THICKNESS,
            CURB_THICKNESS,
            Enum.Material.Concrete,
            CURB_SURFACE_LIFT,
            curbOffset
        )
    end

    -- Curb on right side (positive offset)
    if hasSidewalkRight then
        local curbOffset = width * 0.5 + CURB_THICKNESS * 0.5
        paintStrip(
            terrain,
            p1,
            p2,
            CURB_THICKNESS,
            CURB_THICKNESS,
            Enum.Material.Concrete,
            CURB_SURFACE_LIFT,
            curbOffset
        )
    end
end

-- Build an elevated bridge/tunnel segment as a Part slab (not terrain).
-- Bridges use a concrete deck Part; tunnels are skipped (underground).
local function paintBridgeSegment(parent, p1, p2, width, material, chunk, sampleGroundY, road)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    local midPos = (p1 + p2) * 0.5
    -- CFrame.lookAt tilts the deck to follow the slope between p1 and p2
    local cf = CFrame.lookAt(midPos, p2)
    local right = cf.RightVector

    local deck = Instance.new("Part")
    deck.Anchored = true
    deck.CastShadow = true -- bridge deck casts meaningful shadows
    deck.Size = Vector3.new(width, ROAD_THICKNESS, length + 0.1)
    deck.Material = material
    deck.CFrame = cf
    -- Apply physics: use road-surface properties when available, else concrete deck default.
    deck.CustomPhysicalProperties = road and getPhysicsProperties(road) or CONCRETE_PHYSICS
    -- Tag for vehicle AI
    CollectionService:AddTag(deck, "Road")
    if road then
        if road.oneway then
            deck:SetAttribute("Oneway", true)
        end
        if road.maxspeed then
            deck:SetAttribute("MaxSpeed", road.maxspeed)
        end
        if road.lanes then
            deck:SetAttribute("Lanes", road.lanes)
        end
    end
    deck.Parent = parent

    -- Guardrail posts every 8 studs on each side
    local numPosts = math.floor(length / 8)
    for k = 0, numPosts do
        local t = (numPosts > 0) and (k / numPosts) or 0
        local px = p1.X + (p2.X - p1.X) * t
        local pz = p1.Z + (p2.Z - p1.Z) * t
        local py = p1.Y + (p2.Y - p1.Y) * t
        local railY = py + 1.5
        local centerPos = Vector3.new(px, railY, pz)
        for _, side in ipairs({ -1, 1 }) do
            local post = Instance.new("Part")
            post.Name = "BridgeRailPost"
            post.Anchored = true
            post.CastShadow = false
            post.Size = Vector3.new(0.3, 3, 0.3)
            post.Material = Enum.Material.Concrete
            post.Color = Color3.fromRGB(180, 180, 190)
            post.CFrame = CFrame.new(centerPos + right * (width * 0.5 + BRIDGE_GUARDRAIL_OFFSET) * side)
            post.Parent = parent
        end
    end

    if not chunk then
        return
    end

    local supportCount = math.max(0, math.floor(length / BRIDGE_PILLAR_SPACING))
    for k = 1, supportCount do
        local t = k / (supportCount + 1)
        local sx = p1.X + (p2.X - p1.X) * t
        local sz = p1.Z + (p2.Z - p1.Z) * t
        local deckY = p1.Y + (p2.Y - p1.Y) * t
        local groundY = sampleGroundY(sx, sz)
        local clearance = deckY - groundY - ROAD_THICKNESS * 0.5
        if clearance > BRIDGE_MIN_PILLAR_CLEARANCE then
            local support = Instance.new("Part")
            support.Name = "BridgeSupport"
            support.Anchored = true
            support.CastShadow = true
            support.Material = Enum.Material.Concrete
            support.Color = Color3.fromRGB(150, 150, 160)
            support.Size = Vector3.new(math.max(1.2, width * 0.12), clearance, math.max(1.2, width * 0.12))
            support.CFrame = CFrame.new(sx, groundY + clearance * 0.5, sz)
            support.Parent = parent
        end
    end
end

-- Place directional arrow markers on oneway roads every 30 studs.
local function paintOnewayArrows(parent, p1, p2, _width, road)
    if not road.oneway then
        return
    end

    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 20 then
        return
    end -- too short for arrows
    dir = dir.Unit

    -- Place arrows every 30 studs along the segment
    local interval = 30
    for dist = interval, segLen - interval, interval do
        local t = dist / segLen
        -- Interpolate Y along the slope
        local arrowY = p1.Y + (p2.Y - p1.Y) * t + 0.2
        local pos = Vector3.new(p1.X + (p2.X - p1.X) * t, arrowY, p1.Z + (p2.Z - p1.Z) * t)
        -- Look-at target further along the slope for tilt
        local tEnd = math.min(1, (dist + 1) / segLen)
        local endPos =
            Vector3.new(p1.X + (p2.X - p1.X) * tEnd, p1.Y + (p2.Y - p1.Y) * tEnd + 0.2, p1.Z + (p2.Z - p1.Z) * tEnd)

        local arrow = Instance.new("Part")
        arrow.Name = "OnewayArrow"
        arrow.Size = Vector3.new(4, 0.05, 6)
        arrow.Material = Enum.Material.SmoothPlastic
        arrow.Color = Color3.fromRGB(255, 255, 255)
        arrow.Anchored = true
        arrow.CanCollide = false
        arrow.CastShadow = false
        -- Orient arrow following the slope
        arrow.CFrame = CFrame.lookAt(pos, endPos)
        arrow.Parent = parent
    end
end

-- Add a white dashed centerline stripe on roads wider than 12 studs.
local function paintCenterline(parent, p1, p2, width)
    if width < 12 then
        return
    end
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 4 then
        return
    end

    local numDashes = math.floor(length / 6)
    if numDashes < 1 then
        return
    end
    for k = 0, numDashes - 1 do
        local t = (k + 0.5) / numDashes
        local cx = p1.X + (p2.X - p1.X) * t
        local cz = p1.Z + (p2.Z - p1.Z) * t
        local cy = p1.Y + (p2.Y - p1.Y) * t + 0.05 -- just above road surface

        -- Look toward the next point along the slope for tilt
        local tEnd = math.min(1, (k + 1) / numDashes)
        local endX = p1.X + (p2.X - p1.X) * tEnd
        local endZ = p1.Z + (p2.Z - p1.Z) * tEnd
        local endY = p1.Y + (p2.Y - p1.Y) * tEnd + 0.05

        local dash = Instance.new("Part")
        dash.Name = "CenterlineDash"
        dash.Anchored = true
        dash.CastShadow = false
        dash.CanCollide = false
        dash.Size = Vector3.new(0.4, 0.1, math.min(3, length / numDashes * 0.6))
        dash.Material = Enum.Material.SmoothPlastic
        dash.Color = Color3.fromRGB(255, 255, 255)
        dash.CFrame = CFrame.lookAt(Vector3.new(cx, cy, cz), Vector3.new(endX, endY, endZ))
        dash.Parent = parent
    end
end

-- Paint a tunnel segment: road surface plus ceiling and side walls.
local function paintTunnelSegment(parent, p1, p2, width, road)
    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 0.1 then
        return
    end
    dir = dir.Unit

    local midpoint = (p1 + p2) * 0.5
    -- Road surface (same as ground road but underground)
    local roadPart = Instance.new("Part")
    roadPart.Name = "TunnelRoad"
    roadPart.Size = Vector3.new(width, 0.5, segLen)
    roadPart.Material = Enum.Material.Asphalt
    roadPart.Color = Color3.fromRGB(60, 60, 60)
    roadPart.Anchored = true
    roadPart.CanCollide = true
    roadPart.CFrame = CFrame.lookAt(midpoint, p2) * CFrame.new(0, -0.25, 0)
    -- Apply physics properties and tag for vehicle AI
    roadPart.CustomPhysicalProperties = road and getPhysicsProperties(road) or DEFAULT_ROAD_PHYSICS
    CollectionService:AddTag(roadPart, "Road")
    if road then
        if road.oneway then
            roadPart:SetAttribute("Oneway", true)
        end
        if road.maxspeed then
            roadPart:SetAttribute("MaxSpeed", road.maxspeed)
        end
        if road.lanes then
            roadPart:SetAttribute("Lanes", road.lanes)
        end
    end
    roadPart.Parent = parent

    -- Tunnel ceiling
    local tunnelHeight = 12 -- studs clearance
    local ceiling = Instance.new("Part")
    ceiling.Name = "TunnelCeiling"
    ceiling.Size = Vector3.new(width + 2, 1, segLen)
    ceiling.Material = Enum.Material.Concrete
    ceiling.Color = Color3.fromRGB(140, 140, 140)
    ceiling.Anchored = true
    ceiling.CanCollide = true
    ceiling.CFrame = CFrame.lookAt(midpoint + Vector3.new(0, tunnelHeight, 0), p2 + Vector3.new(0, tunnelHeight, 0))
    ceiling.Parent = parent

    -- Tunnel walls (left and right)
    for _, side in ipairs({ -1, 1 }) do
        local wall = Instance.new("Part")
        wall.Name = "TunnelWall"
        wall.Size = Vector3.new(1, tunnelHeight, segLen)
        wall.Material = Enum.Material.Concrete
        wall.Color = Color3.fromRGB(160, 160, 160)
        wall.Anchored = true
        wall.CanCollide = true
        wall.CFrame = CFrame.lookAt(
            midpoint + Vector3.new(side * (width * 0.5 + 0.5), tunnelHeight * 0.5, 0),
            p2 + Vector3.new(side * (width * 0.5 + 0.5), tunnelHeight * 0.5, 0)
        )
        wall.Parent = parent
    end
end

-- Paint crosswalk stripes at a road endpoint for roads wider than 15 studs.
local function paintCrosswalk(parent, position, direction, width)
    local stripeCount = math.floor(width / 3)
    local stripeWidth = 1.5
    local stripeGap = 1.5

    local perpDir = Vector3.new(-direction.Z, 0, direction.X) -- perpendicular

    for i = 1, stripeCount do
        local offset = (i - stripeCount / 2 - 0.5) * (stripeWidth + stripeGap)
        local stripe = Instance.new("Part")
        stripe.Name = "CrosswalkStripe"
        stripe.Size = Vector3.new(stripeWidth, 0.05, 4)
        stripe.Material = Enum.Material.SmoothPlastic
        stripe.Color = Color3.fromRGB(255, 255, 255)
        stripe.Anchored = true
        stripe.CanCollide = false
        stripe.CastShadow = false
        stripe.CFrame = CFrame.lookAt(
            position + perpDir * offset + Vector3.new(0, 0.15, 0),
            position + perpDir * offset + Vector3.new(0, 0.15, 0) + direction
        )
        stripe.Parent = parent
    end
end

-- Scatter manhole covers along the centre of major road segments.
-- Placement is fully deterministic: no math.random is used.
local function scatterManholes(parent, p1, p2, width, road)
    local majorKinds = { primary = true, secondary = true, tertiary = true, trunk = true }
    if not majorKinds[road.kind] then
        return
    end

    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 40 then
        return
    end
    dir = dir.Unit

    local interval = 60
    local seed = string.len(road.id or "")

    for dist = 30, segLen - 30, interval do
        -- Deterministic lateral offset derived from seed and integer distance
        local lateralOffset = ((seed * 7 + math.floor(dist)) % 10 - 5) * (width * 0.06)
        local pos = p1 + dir * dist
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        local surfaceY = pos.Y + 0.15

        local manhole = Instance.new("Part")
        manhole.Name = "Manhole"
        manhole.Shape = Enum.PartType.Cylinder
        manhole.Size = Vector3.new(0.05, 2.5, 2.5)
        manhole.Material = Enum.Material.DiamondPlate
        manhole.Color = Color3.fromRGB(50, 50, 55)
        manhole.Anchored = true
        manhole.CanCollide = false
        manhole.CastShadow = false
        manhole.CFrame = CFrame.new(pos.X + perp.X * lateralOffset, surfaceY, pos.Z + perp.Z * lateralOffset)
            * CFrame.Angles(0, 0, math.pi / 2)
        CollectionService:AddTag(manhole, "LOD_Detail")
        manhole.Parent = parent
    end
end

-- Scatter drain grates along curb lines on roads with sidewalks.
-- Placement is fully deterministic: no math.random is used.
local function scatterDrainGrates(parent, p1, p2, width, sidewalkMode)
    if sidewalkMode == "no" then
        return
    end

    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 30 then
        return
    end
    dir = dir.Unit
    local perp = Vector3.new(-dir.Z, 0, dir.X)

    local interval = 40
    local halfWidth = width * 0.5

    for dist = 20, segLen - 20, interval do
        local pos = p1 + dir * dist
        local surfaceY = pos.Y + 0.12

        for _, side in ipairs({ -1, 1 }) do
            local wantLeft = (sidewalkMode == "both" or sidewalkMode == "left")
            local wantRight = (sidewalkMode == "both" or sidewalkMode == "right")
            if (side == -1 and wantLeft) or (side == 1 and wantRight) then
                local grate = Instance.new("Part")
                grate.Name = "DrainGrate"
                grate.Size = Vector3.new(1.5, 0.05, 0.8)
                grate.Material = Enum.Material.DiamondPlate
                grate.Color = Color3.fromRGB(40, 40, 45)
                grate.Anchored = true
                grate.CanCollide = false
                grate.CastShadow = false
                grate.CFrame = CFrame.lookAt(
                    Vector3.new(
                        pos.X + perp.X * halfWidth * side * 0.95,
                        surfaceY,
                        pos.Z + perp.Z * halfWidth * side * 0.95
                    ),
                    Vector3.new(
                        pos.X + perp.X * halfWidth * side * 0.95,
                        surfaceY,
                        pos.Z + perp.Z * halfWidth * side * 0.95
                    ) + dir
                )
                CollectionService:AddTag(grate, "LOD_Detail")
                grate.Parent = parent
            end
        end
    end
end

-- Place PointLight lamp posts along a ground-level segment at fixed intervals.
local function placeStreetLights(parent, p1, p2, width)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 1 then
        return
    end

    -- Use horizontal direction for the perpendicular offset (lights stay vertical)
    local horizDir = Vector3.new(delta.X, 0, delta.Z)
    if horizDir.Magnitude < 0.01 then
        return
    end
    local cf = CFrame.lookAt(Vector3.new(p1.X, 0, p1.Z), Vector3.new(p2.X, 0, p2.Z))
    local right = cf.RightVector

    local numLights = math.max(1, math.floor(length / STREET_LIGHT_INTERVAL))
    for k = 0, numLights - 1 do
        local t = (k + 0.5) / numLights
        local lx = p1.X + (p2.X - p1.X) * t
        local lz = p1.Z + (p2.Z - p1.Z) * t
        local ly = p1.Y + (p2.Y - p1.Y) * t + 8 -- pole height above road

        -- Alternate sides for a staggered look
        local side = (k % 2 == 0) and 1 or -1
        local lampPos = Vector3.new(lx, ly, lz) + right * (width * 0.5 + 1) * side

        local pole = Instance.new("Part")
        pole.Name = "StreetLight"
        pole.Anchored = true
        pole.CastShadow = false
        pole.CanCollide = false
        pole.Size = Vector3.new(0.3, 8, 0.3)
        pole.Material = Enum.Material.SmoothPlastic
        pole.Color = Color3.fromRGB(80, 80, 85)
        pole.CFrame = CFrame.new(Vector3.new(lx, p1.Y + (p2.Y - p1.Y) * t + 4, lz) + right * (width * 0.5 + 1) * side)
        pole.Parent = parent

        local head = Instance.new("Part")
        head.Name = "StreetLightHead"
        head.Anchored = true
        head.CastShadow = false
        head.CanCollide = false
        head.Size = Vector3.new(0.6, 0.3, 0.6)
        head.Material = Enum.Material.SmoothPlastic
        head.Color = Color3.fromRGB(220, 220, 220)
        head.CFrame = CFrame.new(lampPos)
        CollectionService:AddTag(head, "StreetLight")
        head.Parent = parent

        local light = Instance.new("PointLight")
        light.Range = STREET_LIGHT_RANGE
        light.Brightness = STREET_LIGHT_BRIGHTNESS
        light.Color = STREET_LIGHT_COLOR
        light.Parent = head
    end
end

-- Render stairway steps as stacked Part slabs between two points.
local function paintSteps(parent, p1, p2, width)
    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 1 then
        return
    end
    dir = dir.Unit

    -- Compute height difference (steps have varying Y)
    local heightDiff = math.abs(p2.Y - p1.Y)

    -- Flat path: no meaningful height change — render as a single flat slab.
    if heightDiff < 0.5 then
        local flatPart = Instance.new("Part")
        flatPart.Name = "FlatPath"
        flatPart.Size = Vector3.new(width, 0.3, segLen)
        flatPart.Material = Enum.Material.Concrete
        flatPart.Color = Color3.fromRGB(180, 175, 168)
        flatPart.Anchored = true
        flatPart.CanCollide = true
        flatPart.CustomPhysicalProperties = STEPS_PHYSICS
        flatPart.CFrame = CFrame.lookAt(
            Vector3.new((p1.X + p2.X) * 0.5, (p1.Y + p2.Y) * 0.5, (p1.Z + p2.Z) * 0.5),
            Vector3.new(p2.X, (p1.Y + p2.Y) * 0.5, p2.Z)
        )
        flatPart.Parent = parent
        return
    end

    local stepCount = math.max(2, math.floor(heightDiff / 0.5)) -- ~0.5 stud per step (~0.15m)
    local stepDepth = segLen / stepCount
    local stepHeight = heightDiff / stepCount
    local goingUp = p2.Y > p1.Y

    for i = 0, stepCount - 1 do
        local t = i / stepCount
        local stepPos = p1 + dir * (t * segLen + stepDepth * 0.5)
        local stepY = p1.Y + (goingUp and 1 or -1) * (i * stepHeight) + stepHeight * 0.5

        local step = Instance.new("Part")
        step.Name = "Step"
        step.Size = Vector3.new(width, stepHeight, stepDepth)
        step.Material = Enum.Material.Concrete
        step.Color = Color3.fromRGB(180, 175, 168)
        step.Anchored = true
        step.CanCollide = true
        step.CustomPhysicalProperties = STEPS_PHYSICS -- extra grip for stairs
        step.CFrame = CFrame.lookAt(
            Vector3.new(stepPos.X, stepY, stepPos.Z),
            Vector3.new(stepPos.X + dir.X, stepY, stepPos.Z + dir.Z)
        )
        step.Parent = parent
    end
end

local function buildChunkPlan(roads, originStuds, chunk)
    return RoadChunkPlan.build(roads, originStuds, chunk, {
        classifySegment = classifySegment,
        getMaterial = getMaterial,
        getRoadColor = getRoadColor,
    })
end

local function executeRoadPlan(parent, detailParent, roadPlan)
    local road = roadPlan.road
    local width = roadPlan.width
    local material = roadPlan.material
    local sidewalkMode = roadPlan.sidewalkMode

    if road.kind == "steps" then
        for _, segment in ipairs(roadPlan.segments) do
            paintSteps(parent, segment.p1, segment.p2, width)
        end
        return
    end

    for _, segment in ipairs(roadPlan.segments) do
        if segment.mode == "bridge" then
            paintBridgeSegment(
                parent,
                segment.p1,
                segment.p2,
                width,
                material,
                roadPlan.chunk,
                roadPlan.sampleGroundY,
                road
            )
        elseif segment.mode == "tunnel" then
            paintTunnelSegment(parent, segment.p1, segment.p2, width, road)
        elseif segment.mode == "ground" then
            paintSegment(Workspace.Terrain, segment.p1, segment.p2, road, width, material, sidewalkMode)
            paintCenterline(detailParent, segment.p1, segment.p2, width)
            paintOnewayArrows(detailParent, segment.p1, segment.p2, width, road)
            scatterManholes(detailParent, segment.p1, segment.p2, width, road)
            scatterDrainGrates(detailParent, segment.p1, segment.p2, width, sidewalkMode)
            if road.lit and WorldConfig.EnableStreetLighting ~= false then
                placeStreetLights(detailParent, segment.p1, segment.p2, width)
            end
        end
    end

    if width > 15 and roadPlan.firstEndpoint and roadPlan.firstDirection then
        paintCrosswalk(detailParent, roadPlan.firstEndpoint, roadPlan.firstDirection, width)
    end
    if width > 15 and roadPlan.lastEndpoint and roadPlan.lastDirection then
        paintCrosswalk(detailParent, roadPlan.lastEndpoint, roadPlan.lastDirection, width)
    end
end

-- Build ALL roads in a chunk by painting them into the terrain.
function RoadBuilder.BuildAll(parent, roads, originStuds, chunk, maybeYield, preparedChunkPlan)
    if not roads or #roads == 0 then
        return
    end
    local detailParent = getRoadDetailParent(parent)
    local chunkPlan = preparedChunkPlan or buildChunkPlan(roads, originStuds, chunk)
    for _, roadPlan in ipairs(chunkPlan.roads) do
        executeRoadPlan(parent, detailParent, roadPlan)
        if maybeYield then
            maybeYield(false)
        end
    end
end

function RoadBuilder.Build(parent, road, originStuds, chunk, preparedChunkPlan)
    local detailParent = getRoadDetailParent(parent)
    local chunkPlan = preparedChunkPlan or buildChunkPlan({ road }, originStuds, chunk)
    if chunkPlan.roads[1] then
        executeRoadPlan(parent, detailParent, chunkPlan.roads[1])
    end
end

function RoadBuilder.FallbackBuild(parent, road, originStuds, chunk, detailParent, preparedChunkPlan)
    detailParent = detailParent or getRoadDetailParent(parent)
    local chunkPlan = preparedChunkPlan or buildChunkPlan({ road }, originStuds, chunk)
    if chunkPlan.roads[1] then
        executeRoadPlan(parent, detailParent, chunkPlan.roads[1])
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- EditableMesh accumulator: collects quad strips and flushes to MeshPart when
-- the triangle budget is reached or at the end of a chunk.
-- ──────────────────────────────────────────────────────────────────────────────

local RoadMeshAccumulator = {}
RoadMeshAccumulator.__index = RoadMeshAccumulator

function RoadMeshAccumulator.new(parent, name, material, color, physicsProps)
    local self = setmetatable({}, RoadMeshAccumulator)
    self.parent = parent
    self.name = name
    self.material = material
    self.color = color
    self.physicsProps = physicsProps or DEFAULT_ROAD_PHYSICS
    self.vertices = {}
    self.normals = {}
    self.triangles = {}
    self.meshCount = 0
    self.MAX_TRIANGLES = 18000
    return self
end

function RoadMeshAccumulator:addQuad(p1, p2, p3, p4)
    if #self.triangles + 2 > self.MAX_TRIANGLES then
        self:flush()
    end
    local base = #self.vertices
    local up = Vector3.new(0, 1, 0)
    self.vertices[base + 1] = p1
    self.vertices[base + 2] = p2
    self.vertices[base + 3] = p3
    self.vertices[base + 4] = p4
    self.normals[base + 1] = up
    self.normals[base + 2] = up
    self.normals[base + 3] = up
    self.normals[base + 4] = up
    table.insert(self.triangles, { base + 1, base + 2, base + 3 })
    table.insert(self.triangles, { base + 1, base + 3, base + 4 })
end

function RoadMeshAccumulator:addRoadStrip(p1, p2, width, surfaceLift)
    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 0.1 then
        return
    end
    -- Horizontal direction for perpendicular offset (keep perp flat)
    local horizDir = Vector3.new(dir.X, 0, dir.Z)
    if horizDir.Magnitude < 0.01 then
        return
    end
    horizDir = horizDir.Unit
    local perp = Vector3.new(-horizDir.Z, 0, horizDir.X) * (width * 0.5)

    -- Per-endpoint Y: vertices at p1 and p2 follow the slope
    local y1 = p1.Y + (surfaceLift or 0.15)
    local y2 = p2.Y + (surfaceLift or 0.15)

    local v1 = Vector3.new(p1.X, y1, p1.Z) - perp
    local v2 = Vector3.new(p1.X, y1, p1.Z) + perp
    local v3 = Vector3.new(p2.X, y2, p2.Z) + perp
    local v4 = Vector3.new(p2.X, y2, p2.Z) - perp

    self:addQuad(v1, v2, v3, v4)
end

function RoadMeshAccumulator:flush()
    if #self.triangles == 0 then
        return
    end

    local mesh = AssetService:CreateEditableMesh()
    local vids = {}
    for i, pos in ipairs(self.vertices) do
        vids[i] = mesh:AddVertex(pos)
        mesh:SetVertexNormal(vids[i], self.normals[i])
    end
    for _, tri in ipairs(self.triangles) do
        mesh:AddTriangle(vids[tri[1]], vids[tri[2]], vids[tri[3]])
    end

    self.meshCount = self.meshCount + 1
    local part = Instance.new("MeshPart")
    part.Name = string.format("%s_mesh_%d", self.name, self.meshCount)
    part.Material = self.material
    part.Color = self.color
    part.Anchored = true
    part.CanCollide = true
    part.Size = Vector3.new(1, 1, 1)
    part.CustomPhysicalProperties = self.physicsProps
    CollectionService:AddTag(part, "Road")
    part:ApplyMesh(mesh)
    part.Parent = self.parent

    self.vertices = {}
    self.normals = {}
    self.triangles = {}
end

-- MeshBuildAll: render road SURFACES as merged EditableMesh quads.
-- Only ground-level, non-tunnel, non-step roads are merged.
-- Bridges, tunnels, and steps fall back to per-part rendering.
-- Decorations (centerlines, arrows, lights, crosswalks) are NOT included here;
-- call MeshBuildDecorations in a separate pass.
function RoadBuilder.MeshBuildAll(parent, roads, originStuds, chunk, preparedChunkPlan)
    if not roads or #roads == 0 then
        return
    end

    local accumulators = {}

    local function getAccumulator(material, color, physicsProps)
        -- Include physics identity in the key so roads with different grip
        -- levels are not merged into the same MeshPart.
        local key = tostring(material) .. "_" .. tostring(color) .. "_" .. tostring(physicsProps)
        if not accumulators[key] then
            accumulators[key] = RoadMeshAccumulator.new(parent, key, material, color, physicsProps)
        end
        return accumulators[key]
    end

    local chunkPlan = preparedChunkPlan or buildChunkPlan(roads, originStuds, chunk)

    for _, roadPlan in ipairs(chunkPlan.roads) do
        local road = roadPlan.road
        if road.kind == "steps" or road.tunnel then
            continue
        end

        local roadPhysics = getPhysicsProperties(road)
        local acc = getAccumulator(roadPlan.material, roadPlan.color, roadPhysics)
        for _, segment in ipairs(roadPlan.segments) do
            if segment.mode == "bridge" then
                paintBridgeSegment(
                    parent,
                    segment.p1,
                    segment.p2,
                    roadPlan.width,
                    roadPlan.material,
                    roadPlan.chunk,
                    roadPlan.sampleGroundY,
                    road
                )
            elseif segment.mode == "ground" then
                acc:addRoadStrip(segment.p1, segment.p2, roadPlan.width, ROAD_SURFACE_LIFT)
            end
        end
    end

    -- Commit all accumulated geometry to MeshParts.
    for _, acc in pairs(accumulators) do
        acc:flush()
    end
end

-- MeshBuildDecorations: per-road decoration pass for mesh mode.
-- Renders steps, tunnels, centerlines, oneway arrows, street lights,
-- and crosswalk markings.  Road surfaces are handled by MeshBuildAll.
-- Detail items (arrows, lights, crosswalks) are placed in the grouped detail
-- sub-folder consistent with the FallbackBuild pattern.
function RoadBuilder.MeshBuildDecorations(parent, roads, originStuds, chunk, preparedChunkPlan)
    if not roads or #roads == 0 then
        return
    end

    local detailParent = getRoadDetailParent(parent)
    local chunkPlan = preparedChunkPlan or buildChunkPlan(roads, originStuds, chunk)

    for _, roadPlan in ipairs(chunkPlan.roads) do
        local road = roadPlan.road
        if road.kind == "steps" then
            for _, segment in ipairs(roadPlan.segments) do
                paintSteps(parent, segment.p1, segment.p2, roadPlan.width)
            end
            continue
        end

        if road.tunnel then
            for _, segment in ipairs(roadPlan.segments) do
                paintTunnelSegment(parent, segment.p1, segment.p2, roadPlan.width, road)
            end
            continue
        end

        for _, segment in ipairs(roadPlan.segments) do
            if segment.mode == "ground" then
                paintCenterline(detailParent, segment.p1, segment.p2, roadPlan.width)
                paintOnewayArrows(detailParent, segment.p1, segment.p2, roadPlan.width, road)
                scatterManholes(detailParent, segment.p1, segment.p2, roadPlan.width, road)
                scatterDrainGrates(detailParent, segment.p1, segment.p2, roadPlan.width, roadPlan.sidewalkMode)
                if road.lit and WorldConfig.EnableStreetLighting ~= false then
                    placeStreetLights(detailParent, segment.p1, segment.p2, roadPlan.width)
                end
            end
        end

        if roadPlan.width > 15 and roadPlan.firstEndpoint and roadPlan.firstDirection then
            paintCrosswalk(detailParent, roadPlan.firstEndpoint, roadPlan.firstDirection, roadPlan.width)
        end
        if roadPlan.width > 15 and roadPlan.lastEndpoint and roadPlan.lastDirection then
            paintCrosswalk(detailParent, roadPlan.lastEndpoint, roadPlan.lastDirection, roadPlan.width)
        end
    end
end

return RoadBuilder
