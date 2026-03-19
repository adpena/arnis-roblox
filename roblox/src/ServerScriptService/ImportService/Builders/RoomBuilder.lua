local GeoUtils = require(script.Parent.Parent.GeoUtils)

local RoomBuilder = {}

local ROOM_STRIP_SIZE = 8
local ROOM_MIN_STRIP_DEPTH = 0.5
local DEFAULT_ROOM_FLOOR_MATERIAL = Enum.Material.WoodPlanks
local DEFAULT_ROOM_FLOOR_COLOR = Color3.fromRGB(138, 111, 84)
local DEFAULT_CEILING_COLOR = Color3.fromRGB(240, 238, 232)
local DEFAULT_WALL_COLOR = Color3.fromRGB(230, 225, 215)
local WALL_THICKNESS = 0.3
local MIN_EDGE = 1.0
local DOOR_WIDTH = 4
local DOOR_HEIGHT = 10
local WINDOW_WIDTH = 3
local WINDOW_HEIGHT = 5
local WINDOW_SILL_HEIGHT = 3
local EDGE_KEY_SCALE = 1000

local function getRoomFloorMaterial(room)
    if room.floorMaterial then
        local ok, material = pcall(function()
            return Enum.Material[room.floorMaterial]
        end)
        if ok and material then
            return material
        end
    end

    return DEFAULT_ROOM_FLOOR_MATERIAL
end

local function getBuildingHeight(building)
    if building.height and building.height > 0 then
        return math.max(4, building.height)
    elseif building.levels and building.levels > 0 then
        return math.max(4, building.levels * 14)
    else
        return 33
    end
end

local function resolveBuildingBaseY(buildingModel)
    local attributedBaseY = buildingModel:GetAttribute("ArnisImportBuildingBaseY")
    if type(attributedBaseY) == "number" then
        return attributedBaseY
    end

    local _, buildingSize = buildingModel:GetBoundingBox()
    local buildingPivot = buildingModel:GetPivot()
    return buildingPivot.Position.Y - buildingSize.Y * 0.5
end

local function resolveBuildingShellHeight(buildingModel, building)
    local attributedHeight = buildingModel:GetAttribute("ArnisImportBuildingHeight")
    if type(attributedHeight) == "number" then
        return attributedHeight
    end

    return getBuildingHeight(building)
end

local function buildWorldFootprint(footprint, originStuds)
    local worldPoly = table.create(#footprint)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge

    for index, point in ipairs(footprint) do
        local worldX = point.x + originStuds.x
        local worldZ = point.z + originStuds.z
        worldPoly[index] = { x = worldX, z = worldZ }

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

    return worldPoly, minX, minZ, maxX, maxZ
end

local function getRectExtents(poly)
    if #poly ~= 4 then
        return nil
    end

    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for _, point in ipairs(poly) do
        minX = math.min(minX, point.x)
        minZ = math.min(minZ, point.z)
        maxX = math.max(maxX, point.x)
        maxZ = math.max(maxZ, point.z)
    end

    if maxX <= minX or maxZ <= minZ then
        return nil
    end

    local seenMinMin = false
    local seenMinMax = false
    local seenMaxMin = false
    local seenMaxMax = false
    for _, point in ipairs(poly) do
        local isMinX = point.x == minX
        local isMaxX = point.x == maxX
        local isMinZ = point.z == minZ
        local isMaxZ = point.z == maxZ
        if isMinX and isMinZ then
            seenMinMin = true
        elseif isMinX and isMaxZ then
            seenMinMax = true
        elseif isMaxX and isMinZ then
            seenMaxMin = true
        elseif isMaxX and isMaxZ then
            seenMaxMax = true
        else
            return nil
        end
    end

    if not (seenMinMin and seenMinMax and seenMaxMin and seenMaxMax) then
        return nil
    end

    return minX, minZ, maxX, maxZ
end

local function quantizeEdgeCoord(value)
    if value >= 0 then
        return math.floor(value * EDGE_KEY_SCALE + 0.5)
    end

    return math.ceil(value * EDGE_KEY_SCALE - 0.5)
end

local function edgeKey(p1, p2)
    if p1.x > p2.x or (p1.x == p2.x and p1.z > p2.z) then
        p1, p2 = p2, p1
    end

    return tostring(quantizeEdgeCoord(p1.x))
        .. ":"
        .. tostring(quantizeEdgeCoord(p1.z))
        .. "|"
        .. tostring(quantizeEdgeCoord(p2.x))
        .. ":"
        .. tostring(quantizeEdgeCoord(p2.z))
end

local function buildEdgeSet(footprint)
    local edges = {}
    if not footprint or #footprint < 2 then
        return edges
    end

    for index = 1, #footprint do
        local p1 = footprint[index]
        local p2 = footprint[(index % #footprint) + 1]
        edges[edgeKey(p1, p2)] = true
    end

    return edges
end

local function collectPartitionEdges(building)
    local partitionEdges = {}
    local rooms = building.rooms or {}

    for _, room in ipairs(rooms) do
        local footprint = room.footprint
        if footprint and #footprint >= 2 then
            for index = 1, #footprint do
                local p1 = footprint[index]
                local p2 = footprint[(index % #footprint) + 1]
                local key = edgeKey(p1, p2)
                local partition = partitionEdges[key]
                if not partition then
                    partitionEdges[key] = {
                        p1 = p1,
                        p2 = p2,
                        room = room,
                        rooms = { room },
                        sharedCount = 1,
                        hasDoor = room.hasDoor == true and index == 1,
                        hasWindow = room.hasWindow == true,
                    }
                else
                    partition.rooms[#partition.rooms + 1] = room
                    partition.sharedCount += 1
                    partition.hasDoor = partition.hasDoor or (room.hasDoor == true and index == 1)
                    partition.hasWindow = partition.hasWindow or room.hasWindow == true
                    local currentKey = partition.room.id or partition.room.name or ""
                    local nextKey = room.id or room.name or ""
                    if nextKey ~= "" and (currentKey == "" or nextKey < currentKey) then
                        partition.room = room
                    end
                end
            end
        end
    end

    return partitionEdges
end

local function emitSurfacePart(
    parent,
    name,
    centerX,
    centerY,
    centerZ,
    width,
    depth,
    thickness,
    material,
    color,
    canCollide
)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = canCollide
    part.CastShadow = false
    part.Material = material
    part.Color = color
    part.Size = Vector3.new(width, thickness, depth)
    part.CFrame = CFrame.new(centerX, centerY, centerZ)
    part.Parent = parent
end

local function buildRoomSurface(
    parent,
    roomName,
    footprint,
    originStuds,
    centerY,
    thickness,
    material,
    color,
    canCollide,
    partLabel
)
    if not footprint or #footprint < 3 then
        return 0
    end

    local worldPoly, minX, minZ, maxX, maxZ = buildWorldFootprint(footprint, originStuds)
    local surfaceIndex = 0
    local roomWidth = maxX - minX
    local roomDepth = maxZ - minZ
    local stripSize = math.max(ROOM_MIN_STRIP_DEPTH, math.min(ROOM_STRIP_SIZE, roomWidth, roomDepth))

    local rectMinX, rectMinZ, rectMaxX, rectMaxZ = getRectExtents(worldPoly)
    if rectMinX then
        emitSurfacePart(
            parent,
            string.format("%s_%s_%d", roomName, partLabel, 1),
            (rectMinX + rectMaxX) * 0.5,
            centerY,
            (rectMinZ + rectMaxZ) * 0.5,
            rectMaxX - rectMinX,
            rectMaxZ - rectMinZ,
            thickness,
            material,
            color,
            canCollide
        )
        return 1
    end

    local x = minX + stripSize * 0.5
    while x <= maxX do
        local z = minZ + stripSize * 0.5
        local runStartZ = nil
        local runEndZ = nil

        while z <= maxZ + stripSize do
            local inside = z <= maxZ and GeoUtils.pointInPolygon(x, z, worldPoly)
            if inside then
                if not runStartZ then
                    runStartZ = z
                end
                runEndZ = z
            elseif runStartZ and runEndZ then
                local depth = runEndZ - runStartZ + stripSize
                if depth >= ROOM_MIN_STRIP_DEPTH then
                    surfaceIndex += 1
                    emitSurfacePart(
                        parent,
                        string.format("%s_%s_%d", roomName, partLabel, surfaceIndex),
                        x,
                        centerY,
                        (runStartZ + runEndZ) * 0.5,
                        stripSize,
                        depth,
                        thickness,
                        material,
                        color,
                        canCollide
                    )
                end
                runStartZ = nil
                runEndZ = nil
            end

            z += stripSize
        end

        x += stripSize
    end

    return surfaceIndex
end

local function makeSurfaceBatchKey(centerY, thickness, material, color, canCollide)
    return table.concat({
        string.format("%.3f", centerY),
        string.format("%.3f", thickness),
        material.Name,
        string.format("%d,%d,%d", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255)),
        canCollide and "1" or "0",
    }, "|")
end

local function addSurfaceBatch(
    batches,
    parent,
    partLabel,
    footprint,
    originStuds,
    centerY,
    thickness,
    material,
    color,
    canCollide
)
    local key = makeSurfaceBatchKey(centerY, thickness, material, color, canCollide)
    local batch = batches[key]
    if not batch then
        batch = {
            parent = parent,
            partLabel = partLabel,
            centerY = centerY,
            thickness = thickness,
            material = material,
            color = color,
            canCollide = canCollide,
            surfaces = {},
        }
        batches[key] = batch
    end

    batch.surfaces[#batch.surfaces + 1] = {
        footprint = footprint,
        originStuds = originStuds,
    }
end

local function buildMergedSurfaceBatch(batch)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    local stripSize = ROOM_STRIP_SIZE
    local worldPolys = table.create(#batch.surfaces)

    for index, surface in ipairs(batch.surfaces) do
        local worldPoly, polyMinX, polyMinZ, polyMaxX, polyMaxZ =
            buildWorldFootprint(surface.footprint, surface.originStuds)
        worldPolys[index] = worldPoly
        minX = math.min(minX, polyMinX)
        minZ = math.min(minZ, polyMinZ)
        maxX = math.max(maxX, polyMaxX)
        maxZ = math.max(maxZ, polyMaxZ)
        stripSize =
            math.min(stripSize, math.max(ROOM_MIN_STRIP_DEPTH, math.min(polyMaxX - polyMinX, polyMaxZ - polyMinZ)))
    end

    local mergedCount = 0
    local x = minX + stripSize * 0.5
    while x <= maxX do
        local z = minZ + stripSize * 0.5
        local runStartZ = nil
        local runEndZ = nil

        while z <= maxZ + stripSize do
            local inside = false
            if z <= maxZ then
                for _, worldPoly in ipairs(worldPolys) do
                    if GeoUtils.pointInPolygon(x, z, worldPoly) then
                        inside = true
                        break
                    end
                end
            end

            if inside then
                if not runStartZ then
                    runStartZ = z
                end
                runEndZ = z
            elseif runStartZ and runEndZ then
                local depth = runEndZ - runStartZ + stripSize
                if depth >= ROOM_MIN_STRIP_DEPTH then
                    mergedCount += 1
                    emitSurfacePart(
                        batch.parent,
                        string.format("%s_%d", batch.partLabel, mergedCount),
                        x,
                        batch.centerY,
                        (runStartZ + runEndZ) * 0.5,
                        stripSize,
                        depth,
                        batch.thickness,
                        batch.material,
                        batch.color,
                        batch.canCollide
                    )
                end
                runStartZ = nil
                runEndZ = nil
            end

            z += stripSize
        end

        x += stripSize
    end

    if mergedCount > 0 then
        return mergedCount
    end

    local fallbackIndex = 0
    for _, surface in ipairs(batch.surfaces) do
        fallbackIndex += buildRoomSurface(
            batch.parent,
            batch.partLabel,
            surface.footprint,
            surface.originStuds,
            batch.centerY,
            batch.thickness,
            batch.material,
            batch.color,
            batch.canCollide,
            "surface"
        )
    end
    return fallbackIndex
end

local function buildRoomFloor(parent, room, originStuds, buildingBaseY)
    if not room.footprint or #room.footprint < 3 then
        return nil
    end

    local material = getRoomFloorMaterial(room)
    local floorHeight = room.height or 0.2
    local centerY = buildingBaseY + (room.floorY or 0) + floorHeight * 0.5
    return {
        parent = parent,
        partLabel = "floor",
        footprint = room.footprint,
        originStuds = originStuds,
        centerY = centerY,
        thickness = 0.2,
        material = material,
        color = DEFAULT_ROOM_FLOOR_COLOR,
        canCollide = false,
    }
end

local function getWallMaterial(room)
    if room.wallMaterial then
        local ok, material = pcall(function()
            return Enum.Material[room.wallMaterial]
        end)
        if ok and material then
            return material
        end
    end
    return Enum.Material.SmoothPlastic
end

-- Build a single interior partition wall edge
local function buildPartitionWall(parent, partition, originStuds, buildingBaseY, floorHeight)
    local room = partition.room
    local p1 = partition.p1
    local p2 = partition.p2
    if not room or not p1 or not p2 then
        return
    end

    local wallMat = getWallMaterial(room)
    local sharedBottomY = -math.huge
    local sharedTopY = math.huge
    for _, touchingRoom in ipairs(partition.rooms or { room }) do
        local roomFloorY = touchingRoom.floorY or 0
        local roomSlabThickness = touchingRoom.height or 0.2
        sharedBottomY = math.max(sharedBottomY, buildingBaseY + roomFloorY + roomSlabThickness)
        sharedTopY = math.min(sharedTopY, buildingBaseY + roomFloorY + floorHeight)
    end

    local slabTop = sharedBottomY
    local wallHeight = sharedTopY - sharedBottomY
    if wallHeight < 2 then
        return
    end

    local dx = p2.x - p1.x
    local dz = p2.z - p1.z
    local edgeLen = math.sqrt(dx * dx + dz * dz)
    if edgeLen < MIN_EDGE then
        return
    end

    local midX = originStuds.x + (p1.x + p2.x) * 0.5
    local midZ = originStuds.z + (p1.z + p2.z) * 0.5
    local midY = slabTop + wallHeight * 0.5
    local angle = math.atan2(dx, dz)

    if partition.hasDoor and edgeLen > DOOR_WIDTH * 2 then
        local leftLen = (edgeLen - DOOR_WIDTH) * 0.5
        local rightLen = leftLen

        local aboveDoor = Instance.new("Part")
        aboveDoor.Name = "WallAboveDoor"
        aboveDoor.Size = Vector3.new(DOOR_WIDTH, wallHeight - DOOR_HEIGHT, WALL_THICKNESS)
        aboveDoor.Material = wallMat
        aboveDoor.Color = DEFAULT_WALL_COLOR
        aboveDoor.Anchored = true
        aboveDoor.CanCollide = true
        aboveDoor.CFrame = CFrame.new(midX, slabTop + DOOR_HEIGHT + (wallHeight - DOOR_HEIGHT) * 0.5, midZ)
            * CFrame.Angles(0, angle, 0)
        aboveDoor.Parent = parent

        if leftLen > MIN_EDGE then
            local leftWall = Instance.new("Part")
            leftWall.Name = "Wall"
            leftWall.Size = Vector3.new(leftLen, wallHeight, WALL_THICKNESS)
            leftWall.Material = wallMat
            leftWall.Color = DEFAULT_WALL_COLOR
            leftWall.Anchored = true
            leftWall.CanCollide = true
            leftWall.CFrame = CFrame.new(midX, midY, midZ)
                * CFrame.Angles(0, angle, 0)
                * CFrame.new(-(edgeLen * 0.5 - leftLen * 0.5), 0, 0)
            leftWall.Parent = parent
        end

        if rightLen > MIN_EDGE then
            local rightWall = Instance.new("Part")
            rightWall.Name = "Wall"
            rightWall.Size = Vector3.new(rightLen, wallHeight, WALL_THICKNESS)
            rightWall.Material = wallMat
            rightWall.Color = DEFAULT_WALL_COLOR
            rightWall.Anchored = true
            rightWall.CanCollide = true
            rightWall.CFrame = CFrame.new(midX, midY, midZ)
                * CFrame.Angles(0, angle, 0)
                * CFrame.new(edgeLen * 0.5 - rightLen * 0.5, 0, 0)
            rightWall.Parent = parent
        end
    elseif partition.hasWindow and edgeLen > WINDOW_WIDTH * 2 then
        local sillY = slabTop + WINDOW_SILL_HEIGHT
        local lintelY = sillY + WINDOW_HEIGHT

        if WINDOW_SILL_HEIGHT > 0.5 then
            local belowWin = Instance.new("Part")
            belowWin.Name = "WallBelowWindow"
            belowWin.Size = Vector3.new(edgeLen, WINDOW_SILL_HEIGHT, WALL_THICKNESS)
            belowWin.Material = wallMat
            belowWin.Color = DEFAULT_WALL_COLOR
            belowWin.Anchored = true
            belowWin.CanCollide = true
            belowWin.CFrame = CFrame.new(midX, slabTop + WINDOW_SILL_HEIGHT * 0.5, midZ) * CFrame.Angles(0, angle, 0)
            belowWin.Parent = parent
        end

        local aboveHeight = wallHeight - WINDOW_SILL_HEIGHT - WINDOW_HEIGHT
        if aboveHeight > 0.5 then
            local aboveWin = Instance.new("Part")
            aboveWin.Name = "WallAboveWindow"
            aboveWin.Size = Vector3.new(edgeLen, aboveHeight, WALL_THICKNESS)
            aboveWin.Material = wallMat
            aboveWin.Color = DEFAULT_WALL_COLOR
            aboveWin.Anchored = true
            aboveWin.CanCollide = true
            aboveWin.CFrame = CFrame.new(midX, lintelY + aboveHeight * 0.5, midZ) * CFrame.Angles(0, angle, 0)
            aboveWin.Parent = parent
        end

        local windowPane = Instance.new("Part")
        windowPane.Name = "WindowPane"
        windowPane.Size = Vector3.new(WINDOW_WIDTH, WINDOW_HEIGHT, WALL_THICKNESS * 0.3)
        windowPane.Material = Enum.Material.Glass
        windowPane.Color = Color3.fromRGB(140, 170, 200)
        windowPane.Transparency = 0.4
        windowPane.Anchored = true
        windowPane.CanCollide = false
        windowPane.CFrame = CFrame.new(midX, sillY + WINDOW_HEIGHT * 0.5, midZ) * CFrame.Angles(0, angle, 0)
        windowPane.Parent = parent

        local sideWidth = (edgeLen - WINDOW_WIDTH) * 0.5
        if sideWidth > MIN_EDGE then
            for _, sign in ipairs({ -1, 1 }) do
                local sidePart = Instance.new("Part")
                sidePart.Name = "WallSide"
                sidePart.Size = Vector3.new(sideWidth, WINDOW_HEIGHT, WALL_THICKNESS)
                sidePart.Material = wallMat
                sidePart.Color = DEFAULT_WALL_COLOR
                sidePart.Anchored = true
                sidePart.CanCollide = true
                sidePart.CFrame = CFrame.new(midX, sillY + WINDOW_HEIGHT * 0.5, midZ)
                    * CFrame.Angles(0, angle, 0)
                    * CFrame.new(sign * (WINDOW_WIDTH * 0.5 + sideWidth * 0.5), 0, 0)
                sidePart.Parent = parent
            end
        end
    else
        local wall = Instance.new("Part")
        wall.Name = "Wall"
        wall.Size = Vector3.new(edgeLen, wallHeight, WALL_THICKNESS)
        wall.Material = wallMat
        wall.Color = DEFAULT_WALL_COLOR
        wall.Anchored = true
        wall.CanCollide = true
        wall.CFrame = CFrame.new(midX, midY, midZ) * CFrame.Angles(0, angle, 0)
        wall.Parent = parent
    end
end

-- Build a ceiling slab (thin part at the top of the room)
local function buildCeiling(parent, room, originStuds, buildingBaseY, floorHeight)
    local fp = room.footprint
    if not fp or #fp < 3 then
        return nil
    end

    local ceilingY = buildingBaseY + (room.floorY or 0) + floorHeight
    return {
        parent = parent,
        partLabel = "ceiling",
        footprint = fp,
        originStuds = originStuds,
        centerY = ceilingY,
        thickness = 0.2,
        material = Enum.Material.SmoothPlastic,
        color = DEFAULT_CEILING_COLOR,
        canCollide = true,
    }
end

function RoomBuilder.BuildAll(parent, buildings, originStuds, builtModelsById)
    if not buildings or #buildings == 0 then
        return
    end

    builtModelsById = builtModelsById or {}

    for _, building in ipairs(buildings) do
        local rooms = building.rooms
        if rooms and #rooms > 0 then
            local buildingName = building.id or "Building"
            local buildingModel = builtModelsById[buildingName] or parent:FindFirstChild(buildingName)
            if buildingModel and buildingModel:IsA("Model") then
                local buildingBaseY = resolveBuildingBaseY(buildingModel)
                local buildingHeight = resolveBuildingShellHeight(buildingModel, building)
                local exteriorEdges = buildEdgeSet(building.footprint)
                local partitionEdges = collectPartitionEdges(building)
                local roomsFolder = Instance.new("Folder")
                roomsFolder.Name = "Rooms"
                roomsFolder.Parent = buildingModel
                local floorsFolder = Instance.new("Folder")
                floorsFolder.Name = "Floors"
                floorsFolder.Parent = roomsFolder
                local ceilingsFolder = Instance.new("Folder")
                ceilingsFolder.Name = "Ceilings"
                ceilingsFolder.Parent = roomsFolder
                local partitionsFolder = Instance.new("Folder")
                partitionsFolder.Name = "Partitions"
                partitionsFolder.Parent = roomsFolder
                local floorBatches = {}
                local ceilingBatches = {}

                -- Compute floor height from building dimensions
                local levels = building.levels or #rooms
                local floorHeight = buildingHeight / math.max(1, levels)

                local partitionKeys = table.create(0)
                for edgeId in pairs(partitionEdges) do
                    partitionKeys[#partitionKeys + 1] = edgeId
                end
                table.sort(partitionKeys)
                for _, edgeId in ipairs(partitionKeys) do
                    local partition = partitionEdges[edgeId]
                    if partition.sharedCount > 1 and not exteriorEdges[edgeId] then
                        buildPartitionWall(partitionsFolder, partition, originStuds, buildingBaseY, floorHeight)
                    end
                end

                for _, room in ipairs(rooms) do
                    local floorSurface = buildRoomFloor(floorsFolder, room, originStuds, buildingBaseY)
                    if floorSurface then
                        addSurfaceBatch(
                            floorBatches,
                            floorSurface.parent,
                            floorSurface.partLabel,
                            floorSurface.footprint,
                            floorSurface.originStuds,
                            floorSurface.centerY,
                            floorSurface.thickness,
                            floorSurface.material,
                            floorSurface.color,
                            floorSurface.canCollide
                        )
                    end

                    local ceilingSurface = buildCeiling(ceilingsFolder, room, originStuds, buildingBaseY, floorHeight)
                    if ceilingSurface then
                        addSurfaceBatch(
                            ceilingBatches,
                            ceilingSurface.parent,
                            ceilingSurface.partLabel,
                            ceilingSurface.footprint,
                            ceilingSurface.originStuds,
                            ceilingSurface.centerY,
                            ceilingSurface.thickness,
                            ceilingSurface.material,
                            ceilingSurface.color,
                            ceilingSurface.canCollide
                        )
                    end
                end

                local floorBatchKeys = table.create(0)
                for batchKey in pairs(floorBatches) do
                    floorBatchKeys[#floorBatchKeys + 1] = batchKey
                end
                table.sort(floorBatchKeys)
                for _, batchKey in ipairs(floorBatchKeys) do
                    buildMergedSurfaceBatch(floorBatches[batchKey])
                end

                local ceilingBatchKeys = table.create(0)
                for batchKey in pairs(ceilingBatches) do
                    ceilingBatchKeys[#ceilingBatchKeys + 1] = batchKey
                end
                table.sort(ceilingBatchKeys)
                for _, batchKey in ipairs(ceilingBatchKeys) do
                    buildMergedSurfaceBatch(ceilingBatches[batchKey])
                end
            end
        end
    end
end

return RoomBuilder
