local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local GroundSampler = require(script.Parent.Parent.GroundSampler)
local RoadProfile = require(script.Parent.Parent.RoadProfile)

local RoadBuilder = {}

-- Maps OSM surface tag → Roblox terrain material (checked before kind fallback)
local SURFACE_MATERIAL = {
    asphalt = Enum.Material.Asphalt,
    concrete = Enum.Material.Concrete,
    ["concrete:plates"] = Enum.Material.Concrete,
    cobblestone = Enum.Material.Cobblestone,
    paving_stones = Enum.Material.Pavement,
    bricks = Enum.Material.Cobblestone,
    sett = Enum.Material.Cobblestone,
    gravel = Enum.Material.Ground,
    fine_gravel = Enum.Material.Ground,
    compacted = Enum.Material.Ground,
    pebblestone = Enum.Material.Ground,
    rock = Enum.Material.Rock,
    unpaved = Enum.Material.Mud,
    dirt = Enum.Material.Mud,
    earth = Enum.Material.Mud,
    grass = Enum.Material.Grass,
    wood = Enum.Material.SmoothPlastic,
    stepping_stones = Enum.Material.Pavement,
    paved = Enum.Material.Concrete,
    sand = Enum.Material.Sand,
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
local LANE_WIDTH = 12 -- studs (~3.6 m at 0.3 m/stud)
local STREET_LIGHT_INTERVAL = 50 -- studs between lamp posts
local STREET_LIGHT_RANGE = 40
local STREET_LIGHT_BRIGHTNESS = 1
local STREET_LIGHT_COLOR = Color3.fromRGB(255, 244, 214) -- warm white

-- Returns "both", "left", "right", or "no".
local function getSidewalkMode(road)
    if road.sidewalk then
        return road.sidewalk -- explicit manifest value takes priority
    end
    return road.hasSidewalk and "both" or "no"
end

-- Returns the effective road-surface width in studs.
-- When lane count is available it overrides the raw widthStuds estimate.
local function getEffectiveWidth(road, profileWidth)
    if road.lanes and road.lanes > 0 then
        return road.lanes * LANE_WIDTH
    end
    return profileWidth
end

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

local function offsetPoint(point, origin)
    return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
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

    local surfaceY = (p1.Y + p2.Y) * 0.5 + surfaceLift
    local midY = surfaceY - thickness * 0.5
    local midPos = Vector3.new((p1.X + p2.X) * 0.5, midY, (p1.Z + p2.Z) * 0.5)
    local cf = CFrame.lookAt(midPos, Vector3.new(p2.X, midY, p2.Z))
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

    local hasSidewalkLeft  = (sidewalkMode == "both" or sidewalkMode == "left")  and sidewalkWidth > 0
    local hasSidewalkRight = (sidewalkMode == "both" or sidewalkMode == "right") and sidewalkWidth > 0

    -- Base pavement slab spans the full kerb-to-kerb width for the sides that
    -- have a sidewalk; if both, it's symmetric; if one-sided, expand only that way.
    local leftExtra  = hasSidewalkLeft  and (sidewalkWidth + edgeBuffer) or 0
    local rightExtra = hasSidewalkRight and (sidewalkWidth + edgeBuffer) or 0
    local totalPavedWidth = width + leftExtra + rightExtra
    local pavementMaterial = (hasSidewalkLeft or hasSidewalkRight) and Enum.Material.Pavement or material

    -- When one-sided the base slab needs to be off-centre by half the asymmetry.
    local baseOffset = (rightExtra - leftExtra) * 0.5
    paintStrip(terrain, p1, p2, totalPavedWidth, PAVEMENT_THICKNESS, pavementMaterial, PAVEMENT_SURFACE_LIFT, baseOffset ~= 0 and baseOffset or nil)
    paintStrip(terrain, p1, p2, width, ROAD_THICKNESS, material, ROAD_SURFACE_LIFT)

    -- Curb on left side (negative offset)
    if hasSidewalkLeft then
        local curbOffset = -(width * 0.5 + CURB_THICKNESS * 0.5)
        paintStrip(terrain, p1, p2, CURB_THICKNESS, CURB_THICKNESS, Enum.Material.Concrete, CURB_SURFACE_LIFT, curbOffset)
    end

    -- Curb on right side (positive offset)
    if hasSidewalkRight then
        local curbOffset = width * 0.5 + CURB_THICKNESS * 0.5
        paintStrip(terrain, p1, p2, CURB_THICKNESS, CURB_THICKNESS, Enum.Material.Concrete, CURB_SURFACE_LIFT, curbOffset)
    end
end

-- Build an elevated bridge/tunnel segment as a Part slab (not terrain).
-- Bridges use a concrete deck Part; tunnels are skipped (underground).
local function paintBridgeSegment(parent, p1, p2, width, material, chunk, sampleGroundY)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    local midX = (p1.X + p2.X) * 0.5
    local midZ = (p1.Z + p2.Z) * 0.5
    local midY = (p1.Y + p2.Y) * 0.5
    local midPos = Vector3.new(midX, midY, midZ)
    local cf = CFrame.lookAt(midPos, Vector3.new(p2.X, midY, p2.Z))
    local right = cf.RightVector

    local deck = Instance.new("Part")
    deck.Anchored = true
    deck.CastShadow = true -- bridge deck casts meaningful shadows
    deck.Size = Vector3.new(width, ROAD_THICKNESS, length + 0.1)
    deck.Material = material
    deck.CFrame = cf
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
local function paintOnewayArrows(parent, p1, p2, width, road)
    if not road.oneway then return end

    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 20 then return end  -- too short for arrows
    dir = dir.Unit

    -- Place arrows every 30 studs along the segment
    local interval = 30
    for dist = interval, segLen - interval, interval do
        local pos = p1 + dir * dist
        local arrow = Instance.new("Part")
        arrow.Name = "OnewayArrow"
        arrow.Size = Vector3.new(4, 0.05, 6)
        arrow.Material = Enum.Material.SmoothPlastic
        arrow.Color = Color3.fromRGB(255, 255, 255)
        arrow.Anchored = true
        arrow.CanCollide = false
        arrow.CastShadow = false
        -- Orient arrow in road direction, flat on surface
        arrow.CFrame = CFrame.lookAt(pos + Vector3.new(0, 0.2, 0), pos + Vector3.new(0, 0.2, 0) + dir)
        CollectionService:AddTag(arrow, "LOD_Detail")
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

        local dash = Instance.new("Part")
        dash.Anchored = true
        dash.CastShadow = false
        dash.CanCollide = false
        dash.Size = Vector3.new(0.4, 0.1, math.min(3, length / numDashes * 0.6))
        dash.Material = Enum.Material.SmoothPlastic
        dash.Color = Color3.fromRGB(255, 255, 255)
        dash.CFrame = CFrame.lookAt(Vector3.new(cx, cy, cz), Vector3.new(p2.X, cy, p2.Z))
        dash.Parent = parent
    end
end

-- Paint a tunnel segment: road surface plus ceiling and side walls.
local function paintTunnelSegment(parent, p1, p2, width, road)
    local dir = (p2 - p1)
    local segLen = dir.Magnitude
    if segLen < 0.1 then return end
    dir = dir.Unit

    local midpoint = (p1 + p2) * 0.5
    local surfaceY = midpoint.Y

    -- Road surface (same as ground road but underground)
    local roadPart = Instance.new("Part")
    roadPart.Name = "TunnelRoad"
    roadPart.Size = Vector3.new(width, 0.5, segLen)
    roadPart.Material = Enum.Material.Asphalt
    roadPart.Color = Color3.fromRGB(60, 60, 60)
    roadPart.Anchored = true
    roadPart.CanCollide = true
    roadPart.CFrame = CFrame.lookAt(midpoint, p2) * CFrame.new(0, -0.25, 0)
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
    for _, side in ipairs({-1, 1}) do
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

-- Place PointLight lamp posts along a ground-level segment at fixed intervals.
local function placeStreetLights(parent, p1, p2, width)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 1 then
        return
    end

    local midY = (p1.Y + p2.Y) * 0.5
    local cf = CFrame.lookAt(Vector3.new(p1.X, midY, p1.Z), Vector3.new(p2.X, midY, p2.Z))
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
        CollectionService:AddTag(pole, "LOD_Detail")
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
        CollectionService:AddTag(head, "LOD_Detail")
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
    if segLen < 1 then return end
    dir = dir.Unit

    -- Compute height difference (steps have varying Y)
    local heightDiff = math.abs(p2.Y - p1.Y)
    local stepCount = math.max(2, math.floor(heightDiff / 0.5))  -- ~0.5 stud per step (~0.15m)
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
        step.CFrame = CFrame.lookAt(
            Vector3.new(stepPos.X, stepY, stepPos.Z),
            Vector3.new(stepPos.X + dir.X, stepY, stepPos.Z + dir.Z)
        )
        step.Parent = parent
    end
end

-- Build ALL roads in a chunk by painting them into the terrain.
function RoadBuilder.BuildAll(parent, roads, originStuds, chunk)
    if not roads or #roads == 0 then
        return
    end
    for _, road in ipairs(roads) do
        RoadBuilder.FallbackBuild(parent, road, originStuds, chunk)
    end
end

function RoadBuilder.Build(parent, road, originStuds, chunk)
    RoadBuilder.FallbackBuild(parent, road, originStuds, chunk)
end

function RoadBuilder.FallbackBuild(parent, road, originStuds, chunk)
    local terrain = Workspace.Terrain
    local material = getMaterial(road)
    local profileWidth = RoadProfile.getRoadWidth(road)
    local width = getEffectiveWidth(road, profileWidth)
    local sidewalkMode = getSidewalkMode(road)
    local sampleGroundY = if chunk then GroundSampler.createSampler(chunk) else nil

    -- Steps: render as stacked Part slabs rather than a flat road surface.
    if road.kind == "steps" then
        local ox, oy, oz = originStuds.x, originStuds.y, originStuds.z
        for i = 1, #road.points - 1 do
            local p1 = Vector3.new(road.points[i].x + ox, road.points[i].y + oy, road.points[i].z + oz)
            local p2 = Vector3.new(road.points[i+1].x + ox, road.points[i+1].y + oy, road.points[i+1].z + oz)
            paintSteps(parent, p1, p2, width)
        end
        return  -- don't render as a normal road
    end

    -- Overpasses: elevate road by layer * 8 studs when layer > 0.
    local layerElevation = 0
    if road.layer and road.layer > 0 then
        layerElevation = road.layer * 8
    end

    for i = 1, #road.points - 1 do
        local p1 = offsetPoint(road.points[i], originStuds)
        local p2 = offsetPoint(road.points[i + 1], originStuds)

        -- Apply layer elevation to surface Y for visual separation of stacked roads.
        if layerElevation > 0 then
            local surfaceY = (p1.Y + p2.Y) * 0.5 + layerElevation
            p1 = Vector3.new(p1.X, surfaceY, p1.Z)
            p2 = Vector3.new(p2.X, surfaceY, p2.Z)
        end

        local segmentMode, resolvedP1, resolvedP2 = classifySegment(road, p1, p2, chunk)
        if segmentMode == "bridge" then
            paintBridgeSegment(parent, resolvedP1, resolvedP2, width, material, chunk, sampleGroundY)
        elseif segmentMode == "tunnel" then
            paintTunnelSegment(parent, resolvedP1, resolvedP2, width, road)
        elseif segmentMode == "ground" then
            paintSegment(terrain, resolvedP1, resolvedP2, road, width, material, sidewalkMode)
            paintCenterline(parent, resolvedP1, resolvedP2, width)
            paintOnewayArrows(parent, resolvedP1, resolvedP2, width, road)
            if road.lit then
                placeStreetLights(parent, resolvedP1, resolvedP2, width)
            end
        end
    end

    -- Crosswalk markings at road endpoints for main roads (width > 15 studs).
    if width > 15 and #road.points >= 2 then
        local firstP1 = offsetPoint(road.points[1], originStuds)
        local firstP2 = offsetPoint(road.points[2], originStuds)
        local firstDir = (firstP2 - firstP1)
        if firstDir.Magnitude > 0.01 then
            firstDir = firstDir.Unit
            paintCrosswalk(parent, firstP1, firstDir, width)
        end

        local lastP1 = offsetPoint(road.points[#road.points - 1], originStuds)
        local lastP2 = offsetPoint(road.points[#road.points], originStuds)
        local lastDir = (lastP2 - lastP1)
        if lastDir.Magnitude > 0.01 then
            lastDir = lastDir.Unit
            paintCrosswalk(parent, lastP2, lastDir, width)
        end
    end
end

return RoadBuilder
