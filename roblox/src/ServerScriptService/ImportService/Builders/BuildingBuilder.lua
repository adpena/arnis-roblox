local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local GeoUtils = require(script.Parent.Parent.GeoUtils)

local BuildingBuilder = {}
local editableMeshSetVertexNormalSupported = nil

local function trySetVertexNormal(mesh, vertexId, normal)
    if editableMeshSetVertexNormalSupported == false then
        return
    end

    local ok = pcall(function()
        mesh:SetVertexNormal(vertexId, normal)
    end)
    if ok then
        editableMeshSetVertexNormalSupported = true
    else
        editableMeshSetVertexNormalSupported = false
    end
end

-------------------------------------------------------------------------------
-- MeshAccumulator: batches quads/triangles and flushes to EditableMesh when
-- approaching the 20K triangle limit. One accumulator per (material, color).
-------------------------------------------------------------------------------
local MeshAccumulator = {}
MeshAccumulator.__index = MeshAccumulator

function MeshAccumulator.new(parent, materialName, material, color, options)
    local self = setmetatable({}, MeshAccumulator)
    options = options or {}
    self.parent = parent
    self.materialName = materialName
    self.material = material
    self.color = color
    self.canCollide = options.canCollide
    self.castShadow = options.castShadow
    self.vertices = {} -- array of Vector3
    self.normals = {} -- array of Vector3
    self.triangles = {} -- array of {v1_idx, v2_idx, v3_idx} (1-indexed)
    self.meshCount = 0
    self.MAX_TRIANGLES = 18000 -- headroom below 20K API limit
    return self
end

function MeshAccumulator:addQuad(p1, p2, p3, p4, normal)
    if #self.triangles + 2 > self.MAX_TRIANGLES then
        self:flush()
    end

    local base = #self.vertices
    self.vertices[base + 1] = p1
    self.vertices[base + 2] = p2
    self.vertices[base + 3] = p3
    self.vertices[base + 4] = p4
    self.normals[base + 1] = normal
    self.normals[base + 2] = normal
    self.normals[base + 3] = normal
    self.normals[base + 4] = normal

    -- Two triangles: (1,2,3) and (1,3,4)
    self.triangles[#self.triangles + 1] = { base + 1, base + 2, base + 3 }
    self.triangles[#self.triangles + 1] = { base + 1, base + 3, base + 4 }
end

function MeshAccumulator:addTriangle(p1, p2, p3, normal)
    if #self.triangles + 1 > self.MAX_TRIANGLES then
        self:flush()
    end

    local base = #self.vertices
    self.vertices[base + 1] = p1
    self.vertices[base + 2] = p2
    self.vertices[base + 3] = p3
    self.normals[base + 1] = normal
    self.normals[base + 2] = normal
    self.normals[base + 3] = normal

    self.triangles[#self.triangles + 1] = { base + 1, base + 2, base + 3 }
end

function MeshAccumulator:flush()
    if #self.triangles == 0 then
        return
    end

    local mesh = AssetService:CreateEditableMesh()

    -- Add all vertices and set normals
    local vertexIds = table.create(#self.vertices)
    for i, pos in ipairs(self.vertices) do
        vertexIds[i] = mesh:AddVertex(pos)
        trySetVertexNormal(mesh, vertexIds[i], self.normals[i])
    end

    -- Add all triangles
    for _, tri in ipairs(self.triangles) do
        mesh:AddTriangle(vertexIds[tri[1]], vertexIds[tri[2]], vertexIds[tri[3]])
    end

    -- Create host MeshPart and apply the mesh
    self.meshCount += 1
    local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
    part.Name = string.format("%s_mesh_%d", self.materialName, self.meshCount)
    part.Material = self.material
    part.Color = self.color
    part.Anchored = true
    part.CanCollide = if self.canCollide == nil then true else self.canCollide
    part.CastShadow = if self.castShadow == nil then false else self.castShadow
    part.Parent = self.parent

    -- Reset buffers for next batch
    self.vertices = {}
    self.normals = {}
    self.triangles = {}
end

local function addOrientedBox(acc, center, rightAxis, upAxis, forwardAxis, size)
    local hx = size.X * 0.5
    local hy = size.Y * 0.5
    local hz = size.Z * 0.5
    local right = rightAxis * hx
    local up = upAxis * hy
    local forward = forwardAxis * hz

    local leftBottomBack = center - right - up - forward
    local leftBottomFront = center - right - up + forward
    local leftTopBack = center - right + up - forward
    local leftTopFront = center - right + up + forward
    local rightBottomBack = center + right - up - forward
    local rightBottomFront = center + right - up + forward
    local rightTopBack = center + right + up - forward
    local rightTopFront = center + right + up + forward

    acc:addQuad(leftBottomFront, rightBottomFront, rightTopFront, leftTopFront, forwardAxis)
    acc:addQuad(rightBottomBack, leftBottomBack, leftTopBack, rightTopBack, -forwardAxis)
    acc:addQuad(rightBottomFront, rightBottomBack, rightTopBack, rightTopFront, rightAxis)
    acc:addQuad(leftBottomBack, leftBottomFront, leftTopFront, leftTopBack, -rightAxis)
    acc:addQuad(leftTopFront, rightTopFront, rightTopBack, leftTopBack, upAxis)
    acc:addQuad(leftBottomBack, rightBottomBack, rightBottomFront, leftBottomFront, -upAxis)
end

local WALL_THICKNESS = 0.6 -- studs
local MIN_EDGE = 0.5 -- ignore edges shorter than this
local ROOF_GRID_SIZE = 8
local ROOF_THICKNESS = 0.8

-- Material palette keyed by OSM building usage (used for wall Parts — any Enum.Material valid)
local USAGE_MATERIAL = {
    -- Residential
    residential = Enum.Material.Brick,
    apartments = Enum.Material.Brick,
    house = Enum.Material.WoodPlanks,
    detached = Enum.Material.WoodPlanks,
    terrace = Enum.Material.Brick,
    dormitory = Enum.Material.Brick,
    -- Commercial
    commercial = Enum.Material.Concrete,
    retail = Enum.Material.SmoothPlastic,
    office = Enum.Material.Glass,
    bank = Enum.Material.Marble,
    supermarket = Enum.Material.Concrete,
    mall = Enum.Material.SmoothPlastic,
    hotel = Enum.Material.Marble,
    -- Civic
    hospital = Enum.Material.SmoothPlastic,
    school = Enum.Material.Brick,
    university = Enum.Material.Limestone,
    civic = Enum.Material.Limestone,
    government = Enum.Material.Limestone,
    courthouse = Enum.Material.Marble,
    -- Industrial
    industrial = Enum.Material.DiamondPlate,
    warehouse = Enum.Material.DiamondPlate,
    factory = Enum.Material.DiamondPlate,
    -- Religious
    religious = Enum.Material.Limestone,
    church = Enum.Material.Cobblestone,
    cathedral = Enum.Material.Cobblestone,
    mosque = Enum.Material.Marble,
    temple = Enum.Material.Sandstone,
    -- Utility
    garage = Enum.Material.DiamondPlate,
    shed = Enum.Material.WoodPlanks,
    barn = Enum.Material.WoodPlanks,
    -- Default
    yes = Enum.Material.Concrete,
    default = Enum.Material.Concrete,
}

-- OSM building:material tag → Roblox material
local MATERIAL_TAG_MAP = {
    brick = Enum.Material.Brick,
    concrete = Enum.Material.Concrete,
    glass = Enum.Material.Glass,
    metal = Enum.Material.Metal,
    steel = Enum.Material.DiamondPlate,
    wood = Enum.Material.WoodPlanks,
    stone = Enum.Material.Cobblestone,
    granite = Enum.Material.Granite,
    limestone = Enum.Material.Limestone,
    sandstone = Enum.Material.Sandstone,
    marble = Enum.Material.Marble,
    plaster = Enum.Material.SmoothPlastic,
    stucco = Enum.Material.SmoothPlastic,
    render = Enum.Material.SmoothPlastic,
    cladding = Enum.Material.DiamondPlate,
    timber_framing = Enum.Material.WoodPlanks,
}

-- Floor material for Terrain:FillBlock — must be a valid terrain material (no Glass/Metal/Neon)
local USAGE_FLOOR_MATERIAL = {
    -- Residential
    residential = Enum.Material.Brick,
    apartments = Enum.Material.Brick,
    house = Enum.Material.Brick,
    detached = Enum.Material.Brick,
    terrace = Enum.Material.Brick,
    dormitory = Enum.Material.Brick,
    -- Commercial
    commercial = Enum.Material.Concrete,
    retail = Enum.Material.Concrete,
    office = Enum.Material.Concrete, -- Glass → Concrete floor
    bank = Enum.Material.Concrete,
    supermarket = Enum.Material.Concrete,
    mall = Enum.Material.Concrete,
    hotel = Enum.Material.Concrete,
    -- Civic
    hospital = Enum.Material.SmoothPlastic,
    school = Enum.Material.Concrete,
    university = Enum.Material.Concrete,
    civic = Enum.Material.Concrete,
    government = Enum.Material.Concrete,
    courthouse = Enum.Material.Concrete,
    -- Industrial
    industrial = Enum.Material.Concrete, -- DiamondPlate → Concrete floor
    warehouse = Enum.Material.Concrete, -- CorrugatedSteel → Concrete floor
    factory = Enum.Material.Concrete,
    -- Religious
    religious = Enum.Material.Concrete,
    church = Enum.Material.Cobblestone,
    cathedral = Enum.Material.Cobblestone,
    mosque = Enum.Material.Concrete,
    temple = Enum.Material.Sandstone,
    -- Utility
    garage = Enum.Material.Concrete,
    shed = Enum.Material.Concrete,
    barn = Enum.Material.Concrete,
    -- Default
    yes = Enum.Material.Concrete,
    default = Enum.Material.Concrete,
}

local function getFloorMaterial(building)
    local usage = building.usage or building.kind or "default"
    return USAGE_FLOOR_MATERIAL[usage] or USAGE_FLOOR_MATERIAL.default
end

local function getFacadeBandSpacing(usage)
    if usage == "office" then
        return 4
    elseif usage == "residential" or usage == "apartments" or usage == "house" then
        return 6
    elseif usage == "warehouse" or usage == "industrial" then
        return 12
    else
        return 8
    end
end

local function getFacadeInset(usage)
    if usage == "office" then
        return 0.6
    elseif usage == "warehouse" or usage == "industrial" then
        return 0.85
    else
        return 0.7
    end
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
    -- First try the manifest material string directly via Enum lookup
    if building.material then
        local ok, mat = pcall(function()
            return Enum.Material[building.material]
        end)
        if ok and mat then
            return mat
        end
        -- Also try the OSM tag map (lowercase match)
        local tagMat = MATERIAL_TAG_MAP[building.material:lower()]
        if tagMat then
            return tagMat
        end
    end
    -- Fall back to usage/kind lookup
    local usage = building.usage or building.kind or "default"
    return USAGE_MATERIAL[usage] or USAGE_MATERIAL.default
end

-- Per-material color palettes: each entry is {R, G, B} for Color3.fromRGB.
-- Index is chosen deterministically from the building ID hash so the same
-- building always gets the same shade, yet neighbouring buildings vary.
local MATERIAL_COLOR_RANGES = {
    [Enum.Material.Brick] = {
        { 180, 80, 60 },
        { 160, 90, 70 },
        { 200, 100, 75 },
        { 140, 75, 55 },
    },
    [Enum.Material.Concrete] = {
        { 180, 178, 175 },
        { 170, 168, 165 },
        { 190, 188, 185 },
        { 160, 158, 155 },
    },
    [Enum.Material.Limestone] = {
        { 230, 220, 200 },
        { 225, 215, 195 },
        { 235, 225, 205 },
        { 220, 210, 190 },
    },
    [Enum.Material.WoodPlanks] = {
        { 140, 100, 60 },
        { 130, 90, 55 },
        { 150, 110, 65 },
        { 120, 85, 50 },
    },
    [Enum.Material.Marble] = {
        { 240, 235, 230 },
        { 235, 230, 225 },
        { 245, 240, 235 },
    },
    [Enum.Material.Cobblestone] = {
        { 130, 125, 115 },
        { 120, 115, 105 },
        { 140, 135, 125 },
    },
    [Enum.Material.Sandstone] = {
        { 210, 185, 145 },
        { 200, 175, 135 },
        { 220, 195, 155 },
    },
    [Enum.Material.SmoothPlastic] = {
        { 200, 200, 198 },
        { 210, 208, 205 },
        { 190, 190, 188 },
    },
    [Enum.Material.DiamondPlate] = {
        { 165, 168, 172 },
        { 155, 158, 162 },
        { 175, 178, 182 },
    },
    [Enum.Material.Metal] = {
        { 155, 155, 150 },
        { 145, 145, 140 },
        { 165, 165, 160 },
    },
    [Enum.Material.Granite] = {
        { 130, 125, 120 },
        { 120, 115, 110 },
        { 140, 135, 130 },
    },
}

-- Return a deterministic color from MATERIAL_COLOR_RANGES for a given material,
-- or nil if that material has no defined palette (fall through to getColor).
local function getMaterialColor(material, buildingId)
    local ranges = MATERIAL_COLOR_RANGES[material]
    if not ranges then
        return nil
    end
    local idx = (hashId(buildingId) % #ranges) + 1
    local c = ranges[idx]
    return Color3.fromRGB(c[1], c[2], c[3])
end

local function getColor(building)
    if building.wallColor and building.wallColor.r then
        local r, g, b = building.wallColor.r, building.wallColor.g, building.wallColor.b
        -- Use the explicit color unless it is the OSM default grey placeholder
        if not (r == 170 and g == 170 and b == 170) then
            return Color3.fromRGB(r, g, b)
        end
    end
    -- Prefer a material-appropriate color palette for richer visual variety
    local id = building.id or tostring(building)
    local mat = getMaterial(building)
    local matColor = getMaterialColor(mat, id)
    if matColor then
        return matColor
    end
    -- Final fallback: generic building palette
    return BUILDING_PALETTE[(hashId(id) % #BUILDING_PALETTE) + 1]
end

local function getRoofColor(building, wallColor)
    if building.roofColor and building.roofColor.r then
        return Color3.fromRGB(building.roofColor.r, building.roofColor.g, building.roofColor.b)
    end
    -- Fallback: darken wall color by 20%
    if wallColor then
        return Color3.new(wallColor.R * 0.8, wallColor.G * 0.8, wallColor.B * 0.8)
    end
    return Color3.fromRGB(120, 120, 120) -- grey default
end

local ROOF_MATERIAL_LOOKUP = {
    Asphalt = Enum.Material.Asphalt,
    Metal = Enum.Material.Metal,
    Brick = Enum.Material.Brick,
    WoodPlanks = Enum.Material.WoodPlanks,
    Slate = Enum.Material.Slate,
    Concrete = Enum.Material.Concrete,
    tile = Enum.Material.Brick, -- closest to clay/concrete roof tiles
    thatch = Enum.Material.Grass,
    copper = Enum.Material.Metal,
    glass = Enum.Material.Glass,
    Limestone = Enum.Material.Limestone,
    Sandstone = Enum.Material.Sandstone,
    Marble = Enum.Material.Marble,
}

local function getRoofMaterial(building, wallMat)
    if building.roofMaterial then
        return ROOF_MATERIAL_LOOKUP[building.roofMaterial] or Enum.Material.Concrete
    end
    -- Fall back to wall material
    return wallMat or Enum.Material.Concrete
end

local function buildFootprintData(footprint, originStuds)
    local worldPts = table.create(#footprint)
    local footprintXZ = table.create(#footprint)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    local sumX = 0
    local sumZ = 0

    for index, point in ipairs(footprint) do
        local worldX = point.x + originStuds.x
        local worldZ = point.z + originStuds.z
        worldPts[index] = Vector3.new(worldX, 0, worldZ)
        footprintXZ[index] = { x = worldX, z = worldZ }
        sumX += worldX
        sumZ += worldZ

        if worldX < minX then
            minX = worldX
        end
        if worldZ < minZ then
            minZ = worldZ
        end
        if worldX > maxX then
            maxX = worldX
        end
        if worldZ > maxZ then
            maxZ = worldZ
        end
    end

    return {
        worldPts = worldPts,
        footprintXZ = footprintXZ,
        minX = minX,
        minZ = minZ,
        maxX = maxX,
        maxZ = maxZ,
        sumX = sumX,
        sumZ = sumZ,
        count = #footprint,
    }
end

local function fillInterior(footprintXZ, bounds, baseY, material)
    local minX = bounds.minX
    local minZ = bounds.minZ
    local maxX = bounds.maxX
    local maxZ = bounds.maxZ

    local GRID_SIZE = 4 -- 4-stud grid matching voxel resolution
    local x = minX + GRID_SIZE * 0.5
    while x < maxX do
        local z = minZ + GRID_SIZE * 0.5
        while z < maxZ do
            if GeoUtils.pointInPolygon(x, z, footprintXZ) then
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
            if math.abs(existing.x - point.x) <= 0.05 and math.abs(existing.z - point.z) <= 0.05 then
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

local function buildFlatRoofFromFootprint(bldgName, footprint, topY, color, mat, parent, roofColor, roofMat)
    local effectiveColor = roofColor or color
    local effectiveMat = roofMat or mat
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
            effectiveColor,
            effectiveMat,
            parent
        )
    then
        return
    end

    local function emitStrip(centerX, width, runStartZ, runEndZ)
        stripIndex += 1
        local localCenter = rightAxis * centerX + forwardAxis * ((runStartZ + runEndZ) * 0.5)
        local worldCenter = Vector3.new(centroid.X + localCenter.X, roofY, centroid.Z + localCenter.Z)

        local strip = Instance.new("Part")
        strip.Name = string.format("%s_roof_%d", bldgName, stripIndex)
        strip.Anchored = true
        strip.CastShadow = false
        strip.Material = effectiveMat
        strip.Color = effectiveColor
        strip.Size = Vector3.new(width, ROOF_THICKNESS, runEndZ - runStartZ + ROOF_GRID_SIZE)
        strip.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
        strip.Parent = parent
    end

    local stripSegments = table.create(0)
    local x = minX + ROOF_GRID_SIZE * 0.5
    while x <= maxX do
        local z = minZ + ROOF_GRID_SIZE * 0.5
        local runStartZ
        local runEndZ

        while z <= maxZ + ROOF_GRID_SIZE do
            local inside = z <= maxZ and GeoUtils.pointInPolygon(x, z, roofPoly)

            if inside then
                if not runStartZ then
                    runStartZ = z
                end
                runEndZ = z
            elseif runStartZ and runEndZ then
                stripSegments[#stripSegments + 1] = {
                    centerX = x,
                    width = ROOF_GRID_SIZE,
                    runStartZ = runStartZ,
                    runEndZ = runEndZ,
                }
                runStartZ = nil
                runEndZ = nil
            end

            z += ROOF_GRID_SIZE
        end

        x += ROOF_GRID_SIZE
    end

    if #stripSegments > 0 then
        local active = stripSegments[1]
        local function flushActive()
            emitStrip(active.centerX, active.width, active.runStartZ, active.runEndZ)
        end

        for index = 2, #stripSegments do
            local segment = stripSegments[index]
            local expectedCenterX = active.centerX + (active.width + segment.width) * 0.5
            if
                math.abs(segment.runStartZ - active.runStartZ) <= 1e-6
                and math.abs(segment.runEndZ - active.runEndZ) <= 1e-6
                and math.abs(segment.centerX - expectedCenterX) <= 1e-6
            then
                local combinedWidth = active.width + segment.width
                active.centerX = (active.centerX * active.width + segment.centerX * segment.width) / combinedWidth
                active.width = combinedWidth
            else
                flushActive()
                active = segment
            end
        end

        flushActive()
    end

    if stripIndex == 0 then
        local worldCenter = Vector3.new(centroid.X, roofY, centroid.Z)
        local roof = Instance.new("Part")
        roof.Name = bldgName .. "_roof"
        roof.Anchored = true
        roof.CastShadow = false
        roof.Material = effectiveMat
        roof.Color = effectiveColor
        roof.Size = Vector3.new(math.max(1, maxX - minX), ROOF_THICKNESS, math.max(1, maxZ - minZ))
        roof.CFrame = CFrame.lookAt(worldCenter, worldCenter + forwardAxis)
        roof.Parent = parent
    end
end

local function getBuildingHeight(building)
    -- Schema 0.4.0: building.height is already in studs at correct scale.
    -- No conversion needed.
    if building.height and building.height > 0 then
        return math.max(4, building.height)
    elseif building.levels and building.levels > 0 then
        return math.max(4, building.levels * 14)
    else
        return 33
    end
end

local function resolveBuildingBaseY(building, originStuds, _chunk)
    -- Schema 0.4.0: baseY is authoritative from DEM. Use directly.
    return originStuds.y + building.baseY
end

-- Build roof geometry based on building.roof shape.
-- footprint: array of world-space Vector3 points (worldPts)
local function buildRoof(building, footprint, bounds, baseY, height, color, mat, parent)
    local bldgName = building.id or "Building"
    local roofShape = (building.roof or "flat"):lower()
    -- Resolve roof-specific color and material (may differ from wall color/mat)
    local rc = getRoofColor(building, color)
    local rm = getRoofMaterial(building, mat)

    local minX = bounds.minX
    local minZ = bounds.minZ
    local maxX = bounds.maxX
    local maxZ = bounds.maxZ
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
        p1.Material = rm
        p1.Color = rc

        local p2 = Instance.new("Part")
        p2.Name = bldgName .. "_roof_p2"
        p2.Anchored = true
        p2.CastShadow = false
        p2.Material = rm
        p2.Color = rc

        if ridgeAxisIsZ then
            -- Panels tilt around Z axis: left half (+angle), right half (-angle)
            p1.Size = Vector3.new(panelW, 0.8, longExtent)
            p1.CFrame = CFrame.new(centerX - halfWidth * 0.5, cy, centerZ) * CFrame.Angles(0, 0, angle)
            p2.Size = Vector3.new(panelW, 0.8, longExtent)
            p2.CFrame = CFrame.new(centerX + halfWidth * 0.5, cy, centerZ) * CFrame.Angles(0, 0, -angle)
        else
            -- Panels tilt around X axis: front half (-angle), back half (+angle)
            p1.Size = Vector3.new(longExtent, 0.8, panelW)
            p1.CFrame = CFrame.new(centerX, cy, centerZ - halfWidth * 0.5) * CFrame.Angles(-angle, 0, 0)
            p2.Size = Vector3.new(longExtent, 0.8, panelW)
            p2.CFrame = CFrame.new(centerX, cy, centerZ + halfWidth * 0.5) * CFrame.Angles(angle, 0, 0)
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
        apex.Material = rm
        apex.Color = rc
        apex.CastShadow = false
        apex.Parent = parent
        return
    elseif roofShape == "dome" or roofShape == "onion" then
        local radius = math.min(footprintW, footprintL) * 0.5
        local dome = Instance.new("Part")
        dome.Name = bldgName .. "_roof"
        dome.Anchored = true
        dome.Shape = Enum.PartType.Ball
        dome.Size = Vector3.new(radius * 2, roofShape == "onion" and radius * 1.4 or radius, radius * 2)
        dome.CFrame = CFrame.new(centerX, baseY + height + radius * 0.5, centerZ)
        dome.Material = rm
        dome.Color = rc
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
        wedge.Material = rm
        wedge.Color = rc
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
        deck.Material = rm
        deck.Color = rc
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
                strip.Material = rm
                strip.Color = rc
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
        cone.Material = rm
        cone.Color = rc
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
    buildFlatRoofFromFootprint(bldgName, footprint, baseY + height, color, mat, parent, rc, rm)
end

local function buildFoundation(parent, worldPts, baseY)
    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeLen = (p2 - p1).Magnitude
        if edgeLen < 1 then
            continue
        end

        local mid = (p1 + p2) * 0.5
        local dir = (p2 - p1).Unit

        local foundation = Instance.new("Part")
        foundation.Name = "Foundation"
        foundation.Size = Vector3.new(edgeLen + 0.2, 1.5, 0.8)
        foundation.Material = Enum.Material.Concrete
        foundation.Color = Color3.fromRGB(160, 155, 148)
        foundation.Anchored = true
        foundation.CanCollide = true
        foundation.CastShadow = false
        foundation.CFrame = CFrame.lookAt(
            mid + Vector3.new(0, baseY + 0.75, 0),
            mid + Vector3.new(0, baseY + 0.75, 0) + dir
        ) * CFrame.new(0, 0, -0.1)
        foundation.Parent = parent
    end
end

local function buildCornice(parent, worldPts, topY)
    for i = 1, #worldPts do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % #worldPts) + 1]
        local edgeLen = (p2 - p1).Magnitude
        if edgeLen < 1 then
            continue
        end

        local mid = (p1 + p2) * 0.5
        local dir = (p2 - p1).Unit

        local cornice = Instance.new("Part")
        cornice.Name = "Cornice"
        cornice.Size = Vector3.new(edgeLen, 0.4, 0.6)
        cornice.Material = Enum.Material.Concrete
        cornice.Color = Color3.fromRGB(210, 205, 195)
        cornice.Anchored = true
        cornice.CanCollide = false
        cornice.CastShadow = false
        cornice.CFrame = CFrame.lookAt(mid + Vector3.new(0, topY, 0), mid + Vector3.new(0, topY, 0) + dir)
            * CFrame.new(0, 0, -0.15)
        cornice.Parent = parent
    end
end

local function buildPilasters(parent, worldPts, baseY, height, material, color)
    for _, pt in ipairs(worldPts) do
        local pilaster = Instance.new("Part")
        pilaster.Name = "Pilaster"
        pilaster.Size = Vector3.new(0.4, height, 0.4)
        pilaster.Material = material
        -- Slightly lighter than wall for contrast
        pilaster.Color =
            Color3.new(math.min(1, color.R * 1.15), math.min(1, color.G * 1.15), math.min(1, color.B * 1.15))
        pilaster.Anchored = true
        pilaster.CanCollide = false
        pilaster.CastShadow = true
        pilaster.CFrame = CFrame.new(pt.X, baseY + height * 0.5, pt.Z)
        pilaster.Parent = parent
    end
end

local function buildRooftopEquipment(parent, building, baseY, height, worldPts)
    if not building.levels or building.levels < 5 then
        return
    end

    local cx, cz = 0, 0
    for _, p in ipairs(worldPts) do
        cx = cx + p.X
        cz = cz + p.Z
    end
    cx = cx / #worldPts
    cz = cz / #worldPts

    local roofY = baseY + height

    local unitCount = math.min(3, math.floor(building.levels / 3))
    local seed = string.len(building.id or "")

    for i = 1, unitCount do
        local offsetX = ((seed * 7 + i * 13) % 20) - 10
        local offsetZ = ((seed * 11 + i * 17) % 20) - 10

        local unit = Instance.new("Part")
        unit.Name = "ACUnit"
        unit.Size = Vector3.new(3, 2, 3)
        unit.Material = Enum.Material.Metal
        unit.Color = Color3.fromRGB(160, 160, 165)
        unit.CFrame = CFrame.new(cx + offsetX * 0.3, roofY + 1, cz + offsetZ * 0.3)
        unit.Anchored = true
        unit.CanCollide = true
        unit.Parent = parent
    end
end

local function buildAwning(parent, building, baseY, worldPts)
    local usage = building.usage or building.kind or ""
    if usage ~= "commercial" and usage ~= "retail" and usage ~= "restaurant" then
        return
    end

    -- Find the longest edge (likely the storefront)
    local bestLen = 0
    local bestP1, bestP2
    local n = #worldPts
    for i = 1, n do
        local p1 = worldPts[i]
        local p2 = worldPts[(i % n) + 1]
        local dx = p2.X - p1.X
        local dz = p2.Z - p1.Z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > bestLen then
            bestLen = len
            bestP1 = p1
            bestP2 = p2
        end
    end

    if not bestP1 or bestLen < 6 then
        return
    end

    local mid = Vector3.new((bestP1.X + bestP2.X) * 0.5, 0, (bestP1.Z + bestP2.Z) * 0.5)
    local dx = bestP2.X - bestP1.X
    local dz = bestP2.Z - bestP1.Z
    local mag = math.sqrt(dx * dx + dz * dz)
    local dir = Vector3.new(dx / mag, 0, dz / mag)
    local outward = Vector3.new(-dir.Z, 0, dir.X)

    -- Deterministic awning color seeded from building ID
    local id = building.id or tostring(building)
    local h = hashId(id)
    local h2 = ((h * 33) + 7) % 2147483647
    local h3 = ((h2 * 33) + 13) % 2147483647
    local r = 120 + (h % 81) -- 120–200
    local g = 40 + (h2 % 41) -- 40–80
    local b = 30 + (h3 % 31) -- 30–60
    local awningColor = Color3.fromRGB(r, g, b)

    local awningDepth = 4 -- studs
    local awningY = baseY + 10 -- ~3m above ground floor

    local awning = Instance.new("Part")
    awning.Name = "Awning"
    awning.Size = Vector3.new(bestLen * 0.8, 0.3, awningDepth)
    awning.Material = Enum.Material.Fabric
    awning.Color = awningColor
    awning.Anchored = true
    awning.CanCollide = false
    awning.CFrame = CFrame.lookAt(
        mid + outward * (awningDepth * 0.5) + Vector3.new(0, awningY, 0),
        mid + outward * (awningDepth * 0.5) + Vector3.new(0, awningY, 0) + dir
    )
    awning.Parent = parent
end

-- Build a single building as polygon wall Parts + roof
-- windowBudget is an optional table { used = number, max = number } shared across a chunk.
function BuildingBuilder.FallbackBuild(parent, building, originStuds, chunk, windowBudget)
    local fp = building.footprint
    if not fp or #fp < 2 then
        return
    end

    local footprintData = buildFootprintData(fp, originStuds)
    local baseY = resolveBuildingBaseY(building, originStuds, chunk)
    local height = getBuildingHeight(building)
    local mat = getMaterial(building)
    local color = getColor(building)
    local bldgName = building.id or "Building"

    local model = Instance.new("Model")
    model.Name = bldgName
    model.Parent = parent
    model:SetAttribute("ArnisImportBuildingBaseY", baseY)
    model:SetAttribute("ArnisImportBuildingHeight", height)
    model:SetAttribute("ArnisImportBuildingTopY", baseY + height)
    local shellFolder = Instance.new("Folder")
    shellFolder.Name = "Shell"
    shellFolder.Parent = model
    local detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder.Parent = model
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")

    -- World coordinates of footprint vertices
    local worldPts = footprintData.worldPts
    for index, point in ipairs(worldPts) do
        worldPts[index] = Vector3.new(point.X, baseY, point.Z)
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
        if mat == Enum.Material.Glass then
            wall.Transparency = 0.3
            wall.Reflectance = 0.15
        end
        wall.Parent = shellFolder

        -- Corner post at p1 vertex to seal the joint between this wall and the previous
        local post = Instance.new("Part")
        post.Name = bldgName .. "_corner" .. i
        post.Anchored = true
        post.Size = Vector3.new(WALL_THICKNESS, height, WALL_THICKNESS)
        post.CFrame = CFrame.new(p1.X, midY, p1.Z)
        post.Material = mat
        post.Color = color
        post.CastShadow = false
        post.Parent = shellFolder
    end

    -- Pilaster columns at each footprint corner for facade depth (levels >= 2 only)
    if building.levels and building.levels >= 2 then
        buildPilasters(detailFolder, worldPts, baseY, height, mat, color)
    end

    -- Window bands for tall buildings (>= 3 floors, simple polygons only)
    -- Density varies by usage: read from WorldConfig.WindowSpacing when available,
    -- otherwise fall back to the local table. Gated by WorldConfig.EnableWindowRendering.
    local usage = building.usage or building.kind or "default"
    local WIN_SPACING = (WorldConfig.WindowSpacing and WorldConfig.WindowSpacing[usage])
        or (WorldConfig.WindowSpacing and WorldConfig.WindowSpacing.default)
        or getFacadeBandSpacing(usage)
    local FACADE_INSET = getFacadeInset(usage)
    local WIN_COLOR = Color3.fromRGB(40, 50, 70) -- dark blue-grey glass tint
    local FLOOR_H = 5
    local BAND_H = 2.5
    local numFloors = math.floor(height / FLOOR_H)
    local maxWindows = windowBudget and windowBudget.max
        or (WorldConfig.InstanceBudget and WorldConfig.InstanceBudget.MaxWindowsPerChunk)
        or 10000
    if
        WorldConfig.EnableWindowRendering ~= false
        and numFloors >= 1
        and #worldPts <= 8
        and (#worldPts * numFloors * 2) <= 100
    then
        local budgetExceeded = false
        for floor = 1, math.min(numFloors - 1, 10) do
            if budgetExceeded then
                break
            end
            local bandY = baseY + floor * FLOOR_H + BAND_H * 0.5
            for i = 1, n do
                if budgetExceeded then
                    break
                end
                local p1w = worldPts[i]
                local p2w = worldPts[(i % n) + 1]
                local dx = p2w.X - p1w.X
                local dz = p2w.Z - p1w.Z
                local eLen = math.sqrt(dx * dx + dz * dz)
                if eLen < MIN_EDGE then
                    continue
                end
                local edgeUnitX = dx / eLen
                local edgeUnitZ = dz / eLen
                local numPanes = math.max(1, math.floor(eLen / WIN_SPACING))
                local bandLen = eLen * FACADE_INSET
                if numPanes >= 1 and bandLen > MIN_EDGE then
                    if windowBudget then
                        if windowBudget.used >= maxWindows then
                            budgetExceeded = true
                            break
                        end
                        windowBudget.used += 1
                    end
                    local band = Instance.new("Part")
                    band.Name = bldgName .. "_facade_" .. i .. "_" .. floor
                    band.Anchored = true
                    band.Size = Vector3.new(WALL_THICKNESS * 0.35, BAND_H * 0.8, bandLen)
                    band.CFrame = CFrame.lookAt(
                        Vector3.new((p1w.X + p2w.X) * 0.5, bandY, (p1w.Z + p2w.Z) * 0.5),
                        Vector3.new((p1w.X + p2w.X) * 0.5 + edgeUnitX, bandY, (p1w.Z + p2w.Z) * 0.5 + edgeUnitZ)
                    )
                    band.Material = Enum.Material.Glass
                    band.Color = WIN_COLOR
                    band.CastShadow = false
                    band.Transparency = 0.35
                    band:SetAttribute("BaseTransparency", 0.35)
                    band:SetAttribute("ArnisFacadePaneCount", numPanes)
                    band.Parent = detailFolder

                    -- Window sill: thin concrete ledge below each facade band
                    local paneW = bandLen
                    local windowCFrame = band.CFrame
                    local sill = Instance.new("Part")
                    sill.Name = "WindowSill"
                    sill.Size = Vector3.new(paneW + 0.4, 0.2, 0.5)
                    sill.Material = Enum.Material.Concrete
                    sill.Color = Color3.fromRGB(200, 195, 185)
                    sill.Anchored = true
                    sill.CanCollide = false
                    sill.CastShadow = false
                    sill.CFrame = windowCFrame * CFrame.new(0, -BAND_H * 0.4 - 0.1, 0.15)
                    sill.Parent = detailFolder
                end
            end
        end
    end

    -- Foundation strip along the base of every wall edge
    buildFoundation(detailFolder, worldPts, baseY)

    -- Awning on commercial/retail/restaurant ground floors
    buildAwning(detailFolder, building, baseY, worldPts)

    -- Fill interior with terrain (uses terrain-safe floor materials only)
    fillInterior(footprintData.footprintXZ, footprintData, baseY, getFloorMaterial(building))

    buildRoof(building, worldPts, footprintData, baseY, height, color, mat, shellFolder)

    -- Cornice trim at the roofline
    buildCornice(detailFolder, worldPts, baseY + height)

    -- Rooftop equipment for tall buildings (>= 5 levels)
    buildRooftopEquipment(detailFolder, building, baseY, height, worldPts)

    -- Building name label (from OSM name tag)
    if building.name and building.name ~= "" then
        local nameLabel = Instance.new("BillboardGui")
        nameLabel.Name = "BuildingName"
        nameLabel.Size = UDim2.new(0, 200, 0, 30)
        nameLabel.StudsOffset = Vector3.new(0, height + 5, 0)
        nameLabel.AlwaysOnTop = false
        nameLabel.MaxDistance = 200

        local text = Instance.new("TextLabel")
        text.Size = UDim2.new(1, 0, 1, 0)
        text.BackgroundTransparency = 1
        text.Text = building.name
        text.TextColor3 = Color3.fromRGB(255, 255, 255)
        text.TextStrokeTransparency = 0.5
        text.TextScaled = true
        text.Font = Enum.Font.GothamBold
        text.Parent = nameLabel

        nameLabel.Parent = detailFolder
    end

    return model
end

-- PartBuild is the same as FallbackBuild (polygon walls)
BuildingBuilder.PartBuild = BuildingBuilder.FallbackBuild

function BuildingBuilder.BuildAll(parent, buildings, originStuds, chunk)
    if not buildings or #buildings == 0 then
        return {}
    end
    local windowBudget = {
        used = 0,
        max = WorldConfig.InstanceBudget and WorldConfig.InstanceBudget.MaxWindowsPerChunk or 10000,
    }
    local builtModelsById = {}
    for _, bldg in ipairs(buildings) do
        local model = BuildingBuilder.FallbackBuild(parent, bldg, originStuds, chunk, windowBudget)
        local buildingId = bldg.id
        if model and type(buildingId) == "string" and buildingId ~= "" then
            builtModelsById[buildingId] = model
        end
    end
    return builtModelsById
end

function BuildingBuilder.Build(parent, building, originStuds, chunk, windowBudget)
    return BuildingBuilder.FallbackBuild(parent, building, originStuds, chunk, windowBudget)
end

-------------------------------------------------------------------------------
-- MeshBuildAll: merge wall + flat-roof geometry into per-material EditableMeshes.
-- Windows, awnings, name labels, shaped roofs, foundations, cornices, and
-- rooftop equipment remain as individual Instances (glass needs transparency,
-- shaped roofs use SpecialMesh/WedgePart).
-- Returns builtModelsById for RoomBuilder integration.
-------------------------------------------------------------------------------
function BuildingBuilder.MeshBuildAll(parent, buildings, originStuds, chunk, config)
    if not buildings or #buildings == 0 then
        return {}
    end

    config = config or WorldConfig

    -- Per-(material, color) accumulators. Key = "MaterialName:R:G:B"
    local accumulators = {}
    local meshFolder = Instance.new("Folder")
    meshFolder.Name = "MergedMeshes"
    meshFolder.Parent = parent

    local function getAccumulator(mat, color)
        local r = math.floor(color.R * 255 + 0.5)
        local g = math.floor(color.G * 255 + 0.5)
        local b = math.floor(color.B * 255 + 0.5)
        local key = string.format("%s:%d:%d:%d", mat.Name, r, g, b)
        if not accumulators[key] then
            accumulators[key] = MeshAccumulator.new(meshFolder, key, mat, color)
        end
        return accumulators[key]
    end

    local windowBudget = {
        used = 0,
        max = (config.InstanceBudget and config.InstanceBudget.MaxWindowsPerChunk) or 10000,
    }

    -- Detail mesh accumulator: merges opaque concrete foundation and cornice quads
    -- across all buildings, replacing individual Part-based calls in this path.
    local detailAcc =
        MeshAccumulator.new(meshFolder, "detail_concrete", Enum.Material.Concrete, Color3.fromRGB(180, 175, 168))

    local builtModelsById = {}

    for _, building in ipairs(buildings) do
        local fp = building.footprint
        if not fp or #fp < 2 then
            continue
        end

        local footprintData = buildFootprintData(fp, originStuds)
        local baseY = resolveBuildingBaseY(building, originStuds, chunk)
        local height = getBuildingHeight(building)
        local mat = getMaterial(building)
        local color = getColor(building)
        local bldgName = building.id or "Building"

        -- Per-building model for metadata, detail children, and RoomBuilder
        local model = Instance.new("Model")
        model.Name = bldgName
        model.Parent = parent
        model:SetAttribute("ArnisImportBuildingBaseY", baseY)
        model:SetAttribute("ArnisImportBuildingHeight", height)
        model:SetAttribute("ArnisImportBuildingTopY", baseY + height)
        local detailFolder = Instance.new("Folder")
        detailFolder.Name = "Detail"
        detailFolder.Parent = model
        detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
        CollectionService:AddTag(detailFolder, "LOD_DetailGroup")
        local sillAcc =
            MeshAccumulator.new(detailFolder, "window_sill", Enum.Material.Concrete, Color3.fromRGB(200, 195, 185), {
                canCollide = false,
                castShadow = false,
            })

        local buildingId = building.id
        if model and type(buildingId) == "string" and buildingId ~= "" then
            builtModelsById[buildingId] = model
        end

        -- World-space footprint vertices
        local worldPts = footprintData.worldPts
        for index, point in ipairs(worldPts) do
            worldPts[index] = Vector3.new(point.X, baseY, point.Z)
        end

        -- Glass buildings can't be merged (need per-face transparency)
        local isGlass = (mat == Enum.Material.Glass)

        if isGlass then
            -- Glass buildings: individual Parts (same as FallbackBuild shell)
            local shellFolder = Instance.new("Folder")
            shellFolder.Name = "Shell"
            shellFolder.Parent = model
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
                wall.Size = Vector3.new(WALL_THICKNESS, height, edgeLen + WALL_THICKNESS)
                wall.CFrame = CFrame.lookAt(Vector3.new(midX, midY, midZ), Vector3.new(p2.X, midY, p2.Z))
                wall.Material = mat
                wall.Color = color
                wall.CastShadow = false
                wall.Transparency = 0.3
                wall.Reflectance = 0.15
                wall.Parent = shellFolder

                local post = Instance.new("Part")
                post.Name = bldgName .. "_corner" .. i
                post.Anchored = true
                post.Size = Vector3.new(WALL_THICKNESS, height, WALL_THICKNESS)
                post.CFrame = CFrame.new(p1.X, midY, p1.Z)
                post.Material = mat
                post.Color = color
                post.CastShadow = false
                post.Transparency = 0.3
                post.Reflectance = 0.15
                post.Parent = shellFolder
            end
            buildRoof(building, worldPts, footprintData, baseY, height, color, mat, shellFolder)
        else
            -- Merge opaque walls into EditableMesh accumulators
            local acc = getAccumulator(mat, color)
            local n = #worldPts
            local halfThick = WALL_THICKNESS * 0.5

            for i = 1, n do
                local p1 = worldPts[i]
                local p2 = worldPts[(i % n) + 1]
                local dx = p2.X - p1.X
                local dz = p2.Z - p1.Z
                local edgeLen = math.sqrt(dx * dx + dz * dz)
                if edgeLen < MIN_EDGE then
                    continue
                end

                -- Outward-facing normal (perpendicular to edge, horizontal)
                local outX = -dz / edgeLen
                local outZ = dx / edgeLen
                local normal = Vector3.new(outX, 0, outZ)

                -- Wall quad: outer face offset by half thickness
                local offX = outX * halfThick
                local offZ = outZ * halfThick
                local bottom1 = Vector3.new(p1.X + offX, baseY, p1.Z + offZ)
                local bottom2 = Vector3.new(p2.X + offX, baseY, p2.Z + offZ)
                local top1 = Vector3.new(p1.X + offX, baseY + height, p1.Z + offZ)
                local top2 = Vector3.new(p2.X + offX, baseY + height, p2.Z + offZ)
                acc:addQuad(bottom1, bottom2, top2, top1, normal)

                -- Corner post faces at p1 vertex (4 faces of a small column)
                local cx, cz = p1.X, p1.Z
                local ht = halfThick
                local cornerTop = baseY + height
                -- +X face
                acc:addQuad(
                    Vector3.new(cx + ht, baseY, cz - ht),
                    Vector3.new(cx + ht, baseY, cz + ht),
                    Vector3.new(cx + ht, cornerTop, cz + ht),
                    Vector3.new(cx + ht, cornerTop, cz - ht),
                    Vector3.new(1, 0, 0)
                )
                -- -X face
                acc:addQuad(
                    Vector3.new(cx - ht, baseY, cz + ht),
                    Vector3.new(cx - ht, baseY, cz - ht),
                    Vector3.new(cx - ht, cornerTop, cz - ht),
                    Vector3.new(cx - ht, cornerTop, cz + ht),
                    Vector3.new(-1, 0, 0)
                )
                -- +Z face
                acc:addQuad(
                    Vector3.new(cx + ht, baseY, cz + ht),
                    Vector3.new(cx - ht, baseY, cz + ht),
                    Vector3.new(cx - ht, cornerTop, cz + ht),
                    Vector3.new(cx + ht, cornerTop, cz + ht),
                    Vector3.new(0, 0, 1)
                )
                -- -Z face
                acc:addQuad(
                    Vector3.new(cx - ht, baseY, cz - ht),
                    Vector3.new(cx + ht, baseY, cz - ht),
                    Vector3.new(cx + ht, cornerTop, cz - ht),
                    Vector3.new(cx - ht, cornerTop, cz - ht),
                    Vector3.new(0, 0, -1)
                )
            end

            -- Merge flat roof geometry into mesh; shaped roofs stay as Parts
            local roofShape = (building.roof or "flat"):lower()
            if roofShape == "flat" then
                local rc = getRoofColor(building, color)
                local rm = getRoofMaterial(building, mat)
                local roofAcc = getAccumulator(rm, rc)
                local roofY = baseY + height + ROOF_THICKNESS * 0.5
                local upNormal = Vector3.new(0, 1, 0)

                -- Triangulate footprint as a fan from centroid
                local centroidX = footprintData.sumX / footprintData.count
                local centroidZ = footprintData.sumZ / footprintData.count
                local center = Vector3.new(centroidX, roofY, centroidZ)

                for i = 1, n do
                    local p1 = worldPts[i]
                    local p2 = worldPts[(i % n) + 1]
                    roofAcc:addTriangle(
                        Vector3.new(p1.X, roofY, p1.Z),
                        Vector3.new(p2.X, roofY, p2.Z),
                        center,
                        upNormal
                    )
                end
            else
                -- Non-flat roofs: individual Parts (SpecialMesh/WedgePart)
                local shellFolder = model:FindFirstChild("Shell")
                if not shellFolder then
                    shellFolder = Instance.new("Folder")
                    shellFolder.Name = "Shell"
                    shellFolder.Parent = model
                end
                buildRoof(building, worldPts, footprintData, baseY, height, color, mat, shellFolder)
            end
        end

        -- Window bands (individual glass Parts with transparency)
        local usage = building.usage or building.kind or "default"
        local WIN_SPACING = (config.WindowSpacing and config.WindowSpacing[usage])
            or (config.WindowSpacing and config.WindowSpacing.default)
            or getFacadeBandSpacing(usage)
        local FACADE_INSET = getFacadeInset(usage)
        local WIN_COLOR = Color3.fromRGB(40, 50, 70)
        local FLOOR_H = 5
        local BAND_H = 2.5
        local n = #worldPts
        local numFloors = math.floor(height / FLOOR_H)
        local maxWindows = windowBudget.max
        if config.EnableWindowRendering ~= false and numFloors >= 1 and n <= 8 and (n * numFloors * 2) <= 100 then
            local budgetExceeded = false
            for floor = 1, math.min(numFloors - 1, 10) do
                if budgetExceeded then
                    break
                end
                local bandY = baseY + floor * FLOOR_H + BAND_H * 0.5
                for i = 1, n do
                    if budgetExceeded then
                        break
                    end
                    local p1w = worldPts[i]
                    local p2w = worldPts[(i % n) + 1]
                    local dx = p2w.X - p1w.X
                    local dz = p2w.Z - p1w.Z
                    local eLen = math.sqrt(dx * dx + dz * dz)
                    if eLen < MIN_EDGE then
                        continue
                    end
                    local edgeUnitX = dx / eLen
                    local edgeUnitZ = dz / eLen
                    local numPanes = math.max(1, math.floor(eLen / WIN_SPACING))
                    local bandLen = eLen * FACADE_INSET
                    if numPanes >= 1 and bandLen > MIN_EDGE then
                        if windowBudget.used >= maxWindows then
                            budgetExceeded = true
                            break
                        end
                        windowBudget.used += 1
                        local band = Instance.new("Part")
                        band.Name = bldgName .. "_facade_" .. i .. "_" .. floor
                        band.Anchored = true
                        band.Size = Vector3.new(WALL_THICKNESS * 0.35, BAND_H * 0.8, bandLen)
                        band.CFrame = CFrame.lookAt(
                            Vector3.new((p1w.X + p2w.X) * 0.5, bandY, (p1w.Z + p2w.Z) * 0.5),
                            Vector3.new((p1w.X + p2w.X) * 0.5 + edgeUnitX, bandY, (p1w.Z + p2w.Z) * 0.5 + edgeUnitZ)
                        )
                        band.Material = Enum.Material.Glass
                        band.Color = WIN_COLOR
                        band.CastShadow = false
                        band.Transparency = 0.35
                        band:SetAttribute("BaseTransparency", 0.35)
                        band:SetAttribute("ArnisFacadePaneCount", numPanes)
                        band.Parent = detailFolder

                        local sillSize = Vector3.new(bandLen + 0.4, 0.2, 0.5)
                        local sillCenter = (band.CFrame * CFrame.new(0, -BAND_H * 0.4 - 0.1, 0.15)).Position
                        addOrientedBox(
                            sillAcc,
                            sillCenter,
                            band.CFrame.RightVector,
                            band.CFrame.UpVector,
                            band.CFrame.LookVector,
                            sillSize
                        )
                    end
                end
            end
        end

        -- Foundation and cornice quads merged into the shared detailAcc mesh
        do
            local nPts = #worldPts
            for i = 1, nPts do
                local p1 = worldPts[i]
                local p2 = worldPts[(i % nPts) + 1]
                local edgeVec = p2 - p1
                local edgeLen = edgeVec.Magnitude
                if edgeLen < 1 then
                    continue
                end

                local dir = edgeVec.Unit
                -- Outward normal (perpendicular to edge in XZ plane)
                local outward = Vector3.new(-dir.Z, 0, dir.X) * 0.1

                -- Foundation: slightly protruding quad at base (1.5 studs tall)
                detailAcc:addQuad(
                    p1 + outward + Vector3.new(0, baseY, 0),
                    p2 + outward + Vector3.new(0, baseY, 0),
                    p2 + outward + Vector3.new(0, baseY + 1.5, 0),
                    p1 + outward + Vector3.new(0, baseY + 1.5, 0),
                    outward.Unit
                )

                -- Cornice: thin strip at roofline (0.4 studs tall)
                detailAcc:addQuad(
                    p1 + outward + Vector3.new(0, baseY + height - 0.2, 0),
                    p2 + outward + Vector3.new(0, baseY + height - 0.2, 0),
                    p2 + outward + Vector3.new(0, baseY + height + 0.2, 0),
                    p1 + outward + Vector3.new(0, baseY + height + 0.2, 0),
                    outward.Unit
                )
            end
        end

        -- Awning on commercial/retail/restaurant ground floors
        buildAwning(detailFolder, building, baseY, worldPts)

        -- Fill interior with terrain
        fillInterior(footprintData.footprintXZ, footprintData, baseY, getFloorMaterial(building))

        -- Rooftop equipment for tall buildings
        buildRooftopEquipment(detailFolder, building, baseY, height, worldPts)

        -- Building name label
        if building.name and building.name ~= "" then
            local nameLabel = Instance.new("BillboardGui")
            nameLabel.Name = "BuildingName"
            nameLabel.Size = UDim2.new(0, 200, 0, 30)
            nameLabel.StudsOffset = Vector3.new(0, height + 5, 0)
            nameLabel.AlwaysOnTop = false
            nameLabel.MaxDistance = 200

            local text = Instance.new("TextLabel")
            text.Size = UDim2.new(1, 0, 1, 0)
            text.BackgroundTransparency = 1
            text.Text = building.name
            text.TextColor3 = Color3.fromRGB(255, 255, 255)
            text.TextStrokeTransparency = 0.5
            text.TextScaled = true
            text.Font = Enum.Font.GothamBold
            text.Parent = nameLabel

            nameLabel.Parent = detailFolder
        end

        sillAcc:flush()
    end

    -- Flush all remaining geometry in every accumulator
    for _, acc in pairs(accumulators) do
        acc:flush()
    end
    -- Flush the shared detail concrete accumulator (foundation + cornice quads)
    detailAcc:flush()

    return builtModelsById
end

return BuildingBuilder
