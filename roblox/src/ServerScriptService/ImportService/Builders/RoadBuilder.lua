local Workspace = game:GetService("Workspace")

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

local function classifySegment(road, p1, p2, chunk)
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
local function paintSegment(terrain, p1, p2, road, width, material)
    local sidewalkWidth = RoadProfile.getSidewalkWidth(road, width)
    local edgeBuffer = RoadProfile.getEdgeBufferWidth(road, width)
    local totalPavedWidth = width + (sidewalkWidth + edgeBuffer) * 2
    local pavementMaterial = sidewalkWidth > 0 and Enum.Material.Pavement or material

    paintStrip(
        terrain,
        p1,
        p2,
        totalPavedWidth,
        PAVEMENT_THICKNESS,
        pavementMaterial,
        PAVEMENT_SURFACE_LIFT
    )
    paintStrip(terrain, p1, p2, width, ROAD_THICKNESS, material, ROAD_SURFACE_LIFT)

    if sidewalkWidth > 0 then
        local curbOffset = width * 0.5 + CURB_THICKNESS * 0.5
        paintStrip(
            terrain,
            p1,
            p2,
            CURB_THICKNESS,
            CURB_THICKNESS,
            Enum.Material.Concrete,
            CURB_SURFACE_LIFT,
            -curbOffset
        )
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
local function paintBridgeSegment(parent, p1, p2, width, material, chunk)
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
            post.CFrame =
                CFrame.new(centerPos + right * (width * 0.5 + BRIDGE_GUARDRAIL_OFFSET) * side)
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
        local groundY = GroundSampler.sampleWorldHeight(chunk, sx, sz)
        local clearance = deckY - groundY - ROAD_THICKNESS * 0.5
        if clearance > BRIDGE_MIN_PILLAR_CLEARANCE then
            local support = Instance.new("Part")
            support.Name = "BridgeSupport"
            support.Anchored = true
            support.CastShadow = true
            support.Material = Enum.Material.Concrete
            support.Color = Color3.fromRGB(150, 150, 160)
            support.Size =
                Vector3.new(math.max(1.2, width * 0.12), clearance, math.max(1.2, width * 0.12))
            support.CFrame = CFrame.new(sx, groundY + clearance * 0.5, sz)
            support.Parent = parent
        end
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
    local width = RoadProfile.getRoadWidth(road)

    for i = 1, #road.points - 1 do
        local p1 = offsetPoint(road.points[i], originStuds)
        local p2 = offsetPoint(road.points[i + 1], originStuds)

        local segmentMode, resolvedP1, resolvedP2 = classifySegment(road, p1, p2, chunk)
        if segmentMode == "bridge" then
            paintBridgeSegment(parent, resolvedP1, resolvedP2, width, material, chunk)
        elseif segmentMode == "ground" then
            paintSegment(terrain, resolvedP1, resolvedP2, road, width, material)
            paintCenterline(parent, resolvedP1, resolvedP2, width)
        end
    end
end

return RoadBuilder
