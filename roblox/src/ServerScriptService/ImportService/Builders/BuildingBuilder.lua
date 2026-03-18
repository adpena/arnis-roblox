local Workspace = game:GetService("Workspace")

local GroundSampler = require(script.Parent.Parent.GroundSampler)

local BuildingBuilder = {}

local WALL_THICKNESS = 0.6 -- studs
local MIN_EDGE = 0.5 -- ignore edges shorter than this
local BUILDING_GROUND_SNAP_MAX_DELTA = 40
local ROOF_GRID_SIZE = 8
local ROOF_THICKNESS = 0.8

-- Material palette keyed by OSM building usage (used for wall Parts — any Enum.Material valid)
local USAGE_MATERIAL = {
    residential = Enum.Material.Brick,
    apartments = Enum.Material.Brick,
    house = Enum.Material.Brick,
    commercial = Enum.Material.Concrete,
    retail = Enum.Material.Concrete,
    office = Enum.Material.Glass,
    industrial = Enum.Material.Metal,
    warehouse = Enum.Material.Metal,
    church = Enum.Material.SmoothPlastic,
    school = Enum.Material.SmoothPlastic,
    hospital = Enum.Material.SmoothPlastic,
    yes = Enum.Material.Concrete,
    default = Enum.Material.Concrete,
}

-- Floor material for Terrain:FillBlock — must be a valid terrain material (no Glass/Metal/Neon)
local USAGE_FLOOR_MATERIAL = {
    residential = Enum.Material.Brick,
    apartments = Enum.Material.Brick,
    house = Enum.Material.Brick,
    commercial = Enum.Material.Concrete,
    retail = Enum.Material.Concrete,
    office = Enum.Material.Concrete, -- Glass → Concrete floor
    industrial = Enum.Material.Concrete, -- Metal → Concrete floor
    warehouse = Enum.Material.Concrete,
    church = Enum.Material.SmoothPlastic,
    school = Enum.Material.SmoothPlastic,
    hospital = Enum.Material.SmoothPlastic,
    yes = Enum.Material.Concrete,
    default = Enum.Material.Concrete,
}

local function getFloorMaterial(building)
    local usage = building.usage or building.kind or "default"
    return USAGE_FLOOR_MATERIAL[usage] or USAGE_FLOOR_MATERIAL.default
end

local function hashId(id)
    local h = 5381
    for i = 1, #id do
        h = ((h * 33) + string.byte(id, i)) % 2147483647
    end
    return h
end

-- Realistic building color palette for deterministic variety when OSM lacks colour tags
local BUILDING_PALETTE = {
    Color3.fromRGB(180, 150, 120), -- sandstone/tan
    Color3.fromRGB(160, 130, 100), -- warm brick
    Color3.fromRGB(140, 155, 165), -- cool grey concrete
    Color3.fromRGB(195, 185, 170), -- light limestone
    Color3.fromRGB(120, 125, 130), -- dark concrete
    Color3.fromRGB(175, 165, 150), -- warm concrete
    Color3.fromRGB(200, 190, 175), -- cream/white plaster
    Color3.fromRGB(155, 140, 125), -- medium brick
    Color3.fromRGB(130, 140, 150), -- steel grey
    Color3.fromRGB(165, 155, 140), -- buff limestone
}

local function getMaterial(building)
    -- First try the manifest material string directly
    if building.material then
        local ok, mat = pcall(function()
            return Enum.Material[building.material]
        end)
        if ok and mat then
            return mat
        end
    end
    -- Fall back to usage/kind lookup
    local usage = building.usage or building.kind or "default"
    return USAGE_MATERIAL[usage] or USAGE_MATERIAL.default
end

local function getColor(building)
    if building.color and building.color.r then
        local r, g, b = building.color.r, building.color.g, building.color.b
        -- Use the explicit color unless it is the OSM default grey placeholder
        if not (r == 170 and g == 170 and b == 170) then
            return Color3.fromRGB(r, g, b)
        end
    end
    -- Deterministic palette variety based on building ID
    local id = building.id or tostring(building)
    return BUILDING_PALETTE[(hashId(id) % #BUILDING_PALETTE) + 1]
end

local function pointInPolygon(px, pz, poly)
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local xi, zi = poly[i].x, poly[i].z
        local xj, zj = poly[j].x, poly[j].z
        if ((zi > pz) ~= (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function fillInterior(footprint, baseY, material)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(footprint) do
        if p.x < minX then
            minX = p.x
        end
        if p.z < minZ then
            minZ = p.z
        end
        if p.x > maxX then
            maxX = p.x
        end
        if p.z > maxZ then
            maxZ = p.z
        end
    end

    local GRID_SIZE = 4 -- 4-stud grid matching voxel resolution
    local x = minX + GRID_SIZE * 0.5
    while x < maxX do
        local z = minZ + GRID_SIZE * 0.5
        while z < maxZ do
            if pointInPolygon(x, z, footprint) then
                Workspace.Terrain:FillBlock(
                    CFrame.new(x, baseY, z),
                    Vector3.new(GRID_SIZE, GRID_SIZE, GRID_SIZE),
                    material
                )
            end
            z = z + GRID_SIZE
        end
        x = x + GRID_SIZE
    end
end

local function getRoofBasis(footprint)
    local centroid = Vector3.zero
    local longestEdge = Vector3.new(0, 0, 1)
    local longestEdgeLength = 0
    local count = #footprint

    for i, point in ipairs(footprint) do
        centroid += point

        local nextPoint = footprint[(i % count) + 1]
        local edge = Vector3.new(nextPoint.X - point.X, 0, nextPoint.Z - point.Z)
        local edgeLength = edge.Magnitude
        if edgeLength > longestEdgeLength then
            longestEdge = edge / edgeLength
            longestEdgeLength = edgeLength
        end
    end

    centroid /= count

    if longestEdgeLength <= 1e-3 then
        longestEdge = Vector3.new(0, 0, 1)
    end

    local rightAxis = Vector3.new(longestEdge.Z, 0, -longestEdge.X)
    if rightAxis.Magnitude <= 1e-3 then
        rightAxis = Vector3.new(1, 0, 0)
    else
        rightAxis = rightAxis.Unit
    end

    return centroid, rightAxis, longestEdge
end

local function collectUniqueRoofPoints(roofPoly)
    local uniquePoints = {}

    for _, point in ipairs(roofPoly) do
        local isDuplicate = false
        for _, existing in ipairs(uniquePoints) do
            if
                math.abs(existing.x - point.x) <= 0.05
                and math.abs(existing.z - point.z) <= 0.05
            then
                isDuplicate = true
                break
            end
        end

        if not isDuplicate then
            uniquePoints[#uniquePoints + 1] = point
        end
    end

    return uniquePoints
end

local function tryBuildSimpleFlatRoof(
    bldgName,
    roofPoly,
    centroid,
    rightAxis,
    forwardAxis,
    roofY,
    minX,
    minZ,
    maxX,
    maxZ,
    color,
    mat,
    parent
)
    local uniquePoints = collectUniqueRoofPoints(roofPoly)
    if #uniquePoints ~= 4 then
        return false
    end

    local expectedCorners = {
        { x = minX, z = minZ },
        { x = minX, z = maxZ },
        { x = maxX, z = minZ },
        { x = maxX, z = maxZ },
    }
    local usedCorners = {}

    for _, point in ipairs(uniquePoints) do
        local matched = false
        for cornerIndex, corner in ipairs(expectedCorners) do
            if
                not usedCorners[cornerIndex]
                and math.abs(point.x - corner.x) <= 0.1
                and math.abs(point.z - corner.z) <= 0.1
            then
                usedCorners[cornerIndex] = true
                matched = true
                break
            end
        end

        if not matched then
            return false
        end
    end

    local width = maxX - minX
    local depth = maxZ - minZ
    if width <= 0.5 or depth <= 0.5 then
        return false
    end

    local localCenter = rightAxis * ((minX + maxX) * 0.5) + forwardAxis * ((minZ + maxZ) * 0.5)
    local worldCenter = Vector3.new(centroid.X + localCenter.X, roofY, centroid.Z + localCenter.Z)

    local roof = Instance.new("Part")
    roof.Name = bldgName .. "_roof"
    roof.Anchored = true
    roof.CastShadow = false
    roof.Material = mat
    roof.Color = color
    roof.Size = Vector3.new(width, ROOF_THICKNESS, depth)
    roof.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
    roof.Parent = parent

    return true
end

local function buildFlatRoofFromFootprint(bldgName, footprint, topY, color, mat, parent)
    local centroid, rightAxis, forwardAxis = getRoofBasis(footprint)
    local roofPoly = table.create(#footprint)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge

    for _, point in ipairs(footprint) do
        local offset = point - centroid
        local localX = offset:Dot(rightAxis)
        local localZ = offset:Dot(forwardAxis)
        roofPoly[#roofPoly + 1] = {
            x = localX,
            z = localZ,
        }
        if localX < minX then
            minX = localX
        end
        if localZ < minZ then
            minZ = localZ
        end
        if localX > maxX then
            maxX = localX
        end
        if localZ > maxZ then
            maxZ = localZ
        end
    end

    local stripIndex = 0
    local roofY = topY + ROOF_THICKNESS * 0.5

    if
        tryBuildSimpleFlatRoof(
            bldgName,
            roofPoly,
            centroid,
            rightAxis,
            forwardAxis,
            roofY,
            minX,
            minZ,
            maxX,
            maxZ,
            color,
            mat,
            parent
        )
    then
        return
    end

    local function emitStrip(x, runStartZ, runEndZ)
        stripIndex += 1
        local localCenter = rightAxis * x + forwardAxis * ((runStartZ + runEndZ) * 0.5)
        local worldCenter =
            Vector3.new(centroid.X + localCenter.X, roofY, centroid.Z + localCenter.Z)

        local strip = Instance.new("Part")
        strip.Name = string.format("%s_roof_%d", bldgName, stripIndex)
        strip.Anchored = true
        strip.CastShadow = false
        strip.Material = mat
        strip.Color = color
        strip.Size =
            Vector3.new(ROOF_GRID_SIZE, ROOF_THICKNESS, runEndZ - runStartZ + ROOF_GRID_SIZE)
        strip.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
        strip.Parent = parent
    end

    local x = minX + ROOF_GRID_SIZE * 0.5
    while x <= maxX do
        local z = minZ + ROOF_GRID_SIZE * 0.5
        local runStartZ
        local runEndZ

        while z <= maxZ + ROOF_GRID_SIZE do
            local inside = z <= maxZ and pointInPolygon(x, z, roofPoly)

            if inside then
                if not runStartZ then
                    runStartZ = z
                end
                runEndZ = z
            elseif runStartZ and runEndZ then
                emitStrip(x, runStartZ, runEndZ)
                runStartZ = nil
                runEndZ = nil
            end

            z += ROOF_GRID_SIZE
        end

        x += ROOF_GRID_SIZE
    end

    if stripIndex == 0 then
        local worldCenter = Vector3.new(centroid.X, roofY, centroid.Z)
        local roof = Instance.new("Part")
        roof.Name = bldgName .. "_roof"
        roof.Anchored = true
        roof.CastShadow = false
        roof.Material = mat
        roof.Color = color
        roof.Size = Vector3.new(math.max(1, maxX - minX), ROOF_THICKNESS, math.max(1, maxZ - minZ))
        roof.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
        roof.Parent = parent
    end
end

local function getBuildingHeight(building)
    local METERS_PER_STUD = 0.3 -- 1 stud ≈ 0.3 meters (Roblox convention for real-world scale)
    if building.height_m and building.height_m > 0 then
        return math.max(4, building.height_m / METERS_PER_STUD)
    elseif building.levels and building.levels > 0 then
        return math.max(4, building.levels * 14) -- ~14 studs per floor (4.2m)
    else
        local USAGE_HEIGHT_M = {
            -- residential
            apartments = 15,
            house = 6,
            detached = 6,
            terrace = 6,
            residential = 9,
            dormitory = 12,
            bungalow = 4,
            -- commercial/civic
            commercial = 12,
            retail = 6,
            office = 20,
            bank = 10,
            supermarket = 8,
            mall = 12,
            hotel = 20,
            -- civic/public
            hospital = 23,
            school = 8,
            university = 12,
            civic = 10,
            government = 12,
            courthouse = 12,
            -- industrial
            industrial = 10,
            warehouse = 8,
            factory = 10,
            -- religious
            religious = 12,
            church = 15,
            cathedral = 25,
            mosque = 12,
            temple = 10,
            -- utility/misc
            garage = 3,
            shed = 2.5,
            barn = 6,
            greenhouse = 3,
            -- defaults by general category
            building = 10,
            yes = 10,
        }
        local heightM = USAGE_HEIGHT_M[building.usage] or 10
        return math.max(4, heightM / METERS_PER_STUD)
    end
end

local function resolveBuildingBaseY(chunk, footprint, originStuds, fallbackBaseY)
    if not chunk or not chunk.terrain or not footprint or #footprint == 0 then
        return fallbackBaseY
    end

    local minGroundY = math.huge
    local sumX = 0
    local sumZ = 0

    for _, point in ipairs(footprint) do
        local worldX = point.x + originStuds.x
        local worldZ = point.z + originStuds.z
        local groundY = GroundSampler.sampleWorldHeight(chunk, worldX, worldZ)
        if groundY < minGroundY then
            minGroundY = groundY
        end
        sumX += worldX
        sumZ += worldZ
    end

    local centroidGroundY =
        GroundSampler.sampleWorldHeight(chunk, sumX / #footprint, sumZ / #footprint)
    if centroidGroundY < minGroundY then
        minGroundY = centroidGroundY
    end

    if math.abs(fallbackBaseY - minGroundY) <= BUILDING_GROUND_SNAP_MAX_DELTA then
        return minGroundY
    end

    return fallbackBaseY
end

-- Build roof geometry based on building.roof shape.
-- footprint: array of world-space Vector3 points (worldPts)
local function buildRoof(building, footprint, baseY, height, color, mat, parent)
    local bldgName = building.id or "Building"
    local roofShape = (building.roof or "flat"):lower()

    -- Compute bounding box
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(footprint) do
        if p.X < minX then
            minX = p.X
        end
        if p.Z < minZ then
            minZ = p.Z
        end
        if p.X > maxX then
            maxX = p.X
        end
        if p.Z > maxZ then
            maxZ = p.Z
        end
    end
    local footprintW = math.max(1, maxX - minX)
    local footprintL = math.max(1, maxZ - minZ)
    local centerX = (minX + maxX) * 0.5
    local centerZ = (minZ + maxZ) * 0.5

    if roofShape == "gabled" or roofShape == "gambrel" then
        -- Ridge runs along the longer axis; panels tilt inward from both shorter edges.
        -- gambrel approximated as gabled (two panels, similar silhouette)
        local ridgeAxisIsZ = footprintL >= footprintW
        local shortExtent = ridgeAxisIsZ and footprintW or footprintL
        local longExtent = ridgeAxisIsZ and footprintL or footprintW
        local halfWidth = shortExtent * 0.5
        local rise = shortExtent * 0.3
        local angle = math.atan(rise / halfWidth)
        local panelW = halfWidth / math.cos(angle)
        local cy = baseY + height + rise * 0.5

        local p1 = Instance.new("Part")
        p1.Name = bldgName .. "_roof_p1"
        p1.Anchored = true
        p1.CastShadow = false
        p1.Material = mat
        p1.Color = color

        local p2 = Instance.new("Part")
        p2.Name = bldgName .. "_roof_p2"
        p2.Anchored = true
        p2.CastShadow = false
        p2.Material = mat
        p2.Color = color

        if ridgeAxisIsZ then
            -- Panels tilt around Z axis: left half (+angle), right half (-angle)
            p1.Size = Vector3.new(panelW, 0.8, longExtent)
            p1.CFrame = CFrame.new(centerX - halfWidth * 0.5, cy, centerZ)
                * CFrame.Angles(0, 0, angle)
            p2.Size = Vector3.new(panelW, 0.8, longExtent)
            p2.CFrame = CFrame.new(centerX + halfWidth * 0.5, cy, centerZ)
                * CFrame.Angles(0, 0, -angle)
        else
            -- Panels tilt around X axis: front half (-angle), back half (+angle)
            p1.Size = Vector3.new(longExtent, 0.8, panelW)
            p1.CFrame = CFrame.new(centerX, cy, centerZ - halfWidth * 0.5)
                * CFrame.Angles(-angle, 0, 0)
            p2.Size = Vector3.new(longExtent, 0.8, panelW)
            p2.CFrame = CFrame.new(centerX, cy, centerZ + halfWidth * 0.5)
                * CFrame.Angles(angle, 0, 0)
        end
        p1.Parent = parent
        p2.Parent = parent
        return
    elseif roofShape == "pyramidal" or roofShape == "hipped" then
        local rise = math.min(footprintW, footprintL) * 0.3
        local apex = Instance.new("Part")
        apex.Name = bldgName .. "_roof"
        apex.Anchored = true
        apex.Size = Vector3.new(footprintW, rise * 2, footprintL)
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.Wedge
        mesh.Parent = apex
        apex.CFrame = CFrame.new(centerX, baseY + height + rise, centerZ)
        apex.Material = mat
        apex.Color = color
        apex.CastShadow = false
        apex.Parent = parent
        return
    elseif roofShape == "dome" or roofShape == "onion" then
        local radius = math.min(footprintW, footprintL) * 0.5
        local dome = Instance.new("Part")
        dome.Name = bldgName .. "_roof"
        dome.Anchored = true
        dome.Shape = Enum.PartType.Ball
        dome.Size =
            Vector3.new(radius * 2, roofShape == "onion" and radius * 1.4 or radius, radius * 2)
        dome.CFrame = CFrame.new(centerX, baseY + height + radius * 0.5, centerZ)
        dome.Material = mat
        dome.Color = color
        dome.CastShadow = false
        dome.Parent = parent
        return
    elseif roofShape == "skillion" then
        -- Single-slope wedge across the short axis
        local rise = math.min(footprintW, footprintL) * 0.35
        local ridgeAxisIsZ = footprintL >= footprintW
        local wedge = Instance.new("WedgePart")
        wedge.Name = bldgName .. "_roof"
        wedge.Anchored = true
        wedge.CastShadow = false
        wedge.Material = mat
        wedge.Color = color
        if ridgeAxisIsZ then
            wedge.Size = Vector3.new(footprintW, rise, footprintL)
        else
            wedge.Size = Vector3.new(footprintL, rise, footprintW)
        end
        wedge.CFrame = CFrame.new(centerX, baseY + height + rise * 0.5, centerZ)
        wedge.Parent = parent
        return
    elseif roofShape == "mansard" then
        -- Flat deck (Slate) + four parapet/slope strips along the perimeter
        local slopeH = math.min(3.5, height * 0.35)
        local insetX = math.max(1, footprintW * 0.65)
        local insetZ = math.max(1, footprintL * 0.65)
        -- Flat central deck
        local deck = Instance.new("Part")
        deck.Name = bldgName .. "_roof"
        deck.Anchored = true
        deck.Size = Vector3.new(insetX, 0.5, insetZ)
        deck.CFrame = CFrame.new(centerX, baseY + height + slopeH + 0.25, centerZ)
        deck.Material = Enum.Material.Slate
        deck.Color = Color3.fromRGB(90, 90, 100)
        deck.CastShadow = false
        deck.Parent = parent
        -- Four sloped side strips
        local strips = {
            {
                Vector3.new(footprintW, slopeH, (footprintL - insetZ) * 0.5),
                centerX,
                minZ + (footprintL - insetZ) * 0.25,
            },
            {
                Vector3.new(footprintW, slopeH, (footprintL - insetZ) * 0.5),
                centerX,
                maxZ - (footprintL - insetZ) * 0.25,
            },
            {
                Vector3.new((footprintW - insetX) * 0.5, slopeH, insetZ),
                minX + (footprintW - insetX) * 0.25,
                centerZ,
            },
            {
                Vector3.new((footprintW - insetX) * 0.5, slopeH, insetZ),
                maxX - (footprintW - insetX) * 0.25,
                centerZ,
            },
        }
        for k, s in ipairs(strips) do
            if s[1].X > 0.1 and s[1].Z > 0.1 then
                local strip = Instance.new("Part")
                strip.Name = bldgName .. "_slope" .. k
                strip.Anchored = true
                strip.Size = s[1]
                strip.CFrame = CFrame.new(s[2], baseY + height + slopeH * 0.5, s[3])
                strip.Material = mat
                strip.Color = color
                strip.CastShadow = false
                strip.Parent = parent
            end
        end
        return
    elseif roofShape == "cone" then
        -- Conical roof: cylinder with cone SpecialMesh
        local rise = math.min(footprintW, footprintL) * 0.6
        local radius = math.min(footprintW, footprintL) * 0.5
        local cone = Instance.new("Part")
        cone.Name = bldgName .. "_roof"
        cone.Anchored = true
        cone.Size = Vector3.new(radius * 2, rise, radius * 2)
        cone.CFrame = CFrame.new(centerX, baseY + height + rise * 0.5, centerZ)
        cone.Material = mat
        cone.Color = color
        cone.CastShadow = false
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        mesh.MeshId = "rbxassetid://1078075" -- Roblox cone mesh
        mesh.Scale = Vector3.new(radius * 0.2, rise * 0.1, radius * 0.2)
        mesh.Parent = cone
        cone.Parent = parent
        return
    end

    -- Default / flat → flat slab
    buildFlatRoofFromFootprint(bldgName, footprint, baseY + height, color, mat, parent)
end

-- Build a single building as polygon wall Parts + roof
function BuildingBuilder.FallbackBuild(parent, building, originStuds, chunk)
    local fp = building.footprint
    if not fp or #fp < 2 then
        return
    end

    -- Seed RNG for deterministic output
    math.randomseed(hashId(building.id or tostring(building)))

    local baseY =
        resolveBuildingBaseY(chunk, fp, originStuds, originStuds.y + (building.baseY or 0))
    local height = getBuildingHeight(building)
    local mat = getMaterial(building)
    local color = getColor(building)
    local bldgName = building.id or "Building"

    local model = Instance.new("Model")
    model.Name = bldgName
    model.Parent = parent

    -- World coordinates of footprint vertices
    local worldPts = {}
    for _, p in ipairs(fp) do
        table.insert(worldPts, Vector3.new(p.x + originStuds.x, baseY, p.z + originStuds.z))
    end

    -- One wall Part per edge, plus corner posts at each vertex to eliminate gaps
    local n = #worldPts
    for i = 1, n do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % n) + 1]
        local dx = p2.X - p1.X
        local dz = p2.Z - p1.Z
        local edgeLen = math.sqrt(dx * dx + dz * dz)
        if edgeLen < MIN_EDGE then
            continue
        end

        local midX = (p1.X + p2.X) * 0.5
        local midZ = (p1.Z + p2.Z) * 0.5
        local midY = baseY + height * 0.5

        local wall = Instance.new("Part")
        wall.Name = bldgName .. "_wall" .. i
        wall.Anchored = true
        -- lookAt makes -Z face toward p2 (along wall), so Z=length, X=thickness
        wall.Size = Vector3.new(WALL_THICKNESS, height, edgeLen + WALL_THICKNESS)
        wall.CFrame = CFrame.lookAt(Vector3.new(midX, midY, midZ), Vector3.new(p2.X, midY, p2.Z))
        wall.Material = mat
        wall.Color = color
        wall.CastShadow = false
        wall.Parent = model

        -- Corner post at p1 vertex to seal the joint between this wall and the previous
        local post = Instance.new("Part")
        post.Name = bldgName .. "_corner" .. i
        post.Anchored = true
        post.Size = Vector3.new(WALL_THICKNESS, height, WALL_THICKNESS)
        post.CFrame = CFrame.new(p1.X, midY, p1.Z)
        post.Material = mat
        post.Color = color
        post.CastShadow = false
        post.Parent = model
    end

    -- Window bands for tall buildings (>= 3 floors, simple polygons only)
    local buildingMat = building.material or "Concrete"
    local isGlass = (buildingMat == "Glass" or buildingMat == "office")
    local bandColor = Color3.new(
        math.min(1, color.R + 0.15),
        math.min(1, color.G + 0.18),
        math.min(1, color.B + 0.25) -- slightly blue-tinted lighter
    )
    local FLOOR_H = 5
    local BAND_H = 2.5
    local numFloors = math.floor(height / FLOOR_H)
    if numFloors >= 3 and #worldPts <= 8 and (#worldPts * numFloors * 2) <= 100 then
        for floor = 1, math.min(numFloors - 1, 10) do
            local bandY = baseY + floor * FLOOR_H + BAND_H * 0.5
            for i = 1, n do
                local p1w = worldPts[i]
                local p2w = worldPts[(i % n) + 1]
                local dx = p2w.X - p1w.X
                local dz = p2w.Z - p1w.Z
                local eLen = math.sqrt(dx * dx + dz * dz)
                if eLen < MIN_EDGE then
                    continue
                end
                local band = Instance.new("Part")
                band.Name = bldgName .. "_win" .. i .. "_" .. floor
                band.Anchored = true
                band.Size = Vector3.new(WALL_THICKNESS * 0.5, BAND_H, eLen)
                band.CFrame = CFrame.lookAt(
                    Vector3.new((p1w.X + p2w.X) * 0.5, bandY, (p1w.Z + p2w.Z) * 0.5),
                    Vector3.new(p2w.X, bandY, p2w.Z)
                )
                band.Material = isGlass and Enum.Material.Glass or Enum.Material.SmoothPlastic
                band.Color = bandColor
                band.CastShadow = false
                band.Transparency = isGlass and 0.3 or 0.0
                band.Parent = model
            end
        end
    end

    -- Fill interior with terrain (uses terrain-safe floor materials only)
    local footprintRelative = {}
    for _, p in ipairs(fp) do
        table.insert(footprintRelative, { x = p.x + originStuds.x, z = p.z + originStuds.z })
    end
    fillInterior(footprintRelative, baseY, getFloorMaterial(building))

    buildRoof(building, worldPts, baseY, height, color, mat, model)
end

-- PartBuild is the same as FallbackBuild (polygon walls)
BuildingBuilder.PartBuild = BuildingBuilder.FallbackBuild

function BuildingBuilder.BuildAll(parent, buildings, originStuds, chunk)
    if not buildings or #buildings == 0 then
        return
    end
    for _, bldg in ipairs(buildings) do
        BuildingBuilder.FallbackBuild(parent, bldg, originStuds, chunk)
    end
end

function BuildingBuilder.Build(parent, building, originStuds, chunk)
    BuildingBuilder.FallbackBuild(parent, building, originStuds, chunk)
end

return BuildingBuilder
