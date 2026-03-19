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

local function emitRoomStrip(parent, roomName, stripIndex, centerX, centerY, centerZ, width, depth, material)
    local strip = Instance.new("Part")
    strip.Name = string.format("%s_floor_%d", roomName, stripIndex)
    strip.Anchored = true
    strip.CanCollide = false
    strip.CastShadow = false
    strip.Material = material
    strip.Color = DEFAULT_ROOM_FLOOR_COLOR
    strip.Size = Vector3.new(width, 0.2, depth)
    strip.CFrame = CFrame.new(centerX, centerY, centerZ)
    strip.Parent = parent
end

local function buildRoomFloor(parent, room, originStuds)
    if not room.footprint or #room.footprint < 3 then
        return
    end

    local roomName = room.id or room.name or "Room"
    local material = getRoomFloorMaterial(room)
    -- Parent directly to the provided folder (room folder created by BuildAll)
    local roomModel = parent

    local worldPoly, minX, minZ, maxX, maxZ = buildWorldFootprint(room.footprint, originStuds)
    local floorHeight = room.height or 0.2
    local centerY = originStuds.y + (room.floorY or 0) + floorHeight * 0.5
    local stripIndex = 0

    local x = minX + ROOM_STRIP_SIZE * 0.5
    while x <= maxX do
        local z = minZ + ROOM_STRIP_SIZE * 0.5
        local runStartZ = nil
        local runEndZ = nil

        while z <= maxZ + ROOM_STRIP_SIZE do
            local inside = z <= maxZ and pointInPolygon(x, z, worldPoly)
            if inside then
                if not runStartZ then
                    runStartZ = z
                end
                runEndZ = z
            elseif runStartZ and runEndZ then
                local depth = runEndZ - runStartZ + ROOM_STRIP_SIZE
                if depth >= ROOM_MIN_STRIP_DEPTH then
                    stripIndex += 1
                    emitRoomStrip(
                        roomModel,
                        roomName,
                        stripIndex,
                        x,
                        centerY,
                        (runStartZ + runEndZ) * 0.5,
                        ROOM_STRIP_SIZE,
                        depth,
                        material
                    )
                end
                runStartZ = nil
                runEndZ = nil
            end

            z += ROOM_STRIP_SIZE
        end

        x += ROOM_STRIP_SIZE
    end

    if stripIndex == 0 then
        stripIndex = 1
        emitRoomStrip(
            roomModel,
            roomName,
            stripIndex,
            (minX + maxX) * 0.5,
            centerY,
            (minZ + maxZ) * 0.5,
            math.max(1, maxX - minX),
            math.max(1, maxZ - minZ),
            material
        )
    end
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

-- Build interior partition walls along room footprint edges
local function buildRoomWalls(parent, room, originStuds, floorHeight)
    local fp = room.footprint
    if not fp or #fp < 3 then
        return
    end

    local wallMat = getWallMaterial(room)
    local slabTop = originStuds.y + (room.floorY or 0) + (room.height or 0.2)
    local wallHeight = floorHeight - (room.height or 0.2)
    if wallHeight < 2 then
        return
    end

    for i = 1, #fp do
        local p1 = fp[i]
        local p2 = fp[(i % #fp) + 1]

        local dx = p2.x - p1.x
        local dz = p2.z - p1.z
        local edgeLen = math.sqrt(dx * dx + dz * dz)
        if edgeLen < MIN_EDGE then
            continue
        end

        local midX = originStuds.x + (p1.x + p2.x) * 0.5
        local midZ = originStuds.z + (p1.z + p2.z) * 0.5
        local midY = slabTop + wallHeight * 0.5
        local angle = math.atan2(dx, dz)

        -- Check for door on ground floor (first edge only)
        if room.hasDoor and i == 1 and edgeLen > DOOR_WIDTH * 2 then
            -- Split wall into two segments with a door gap
            local leftLen = (edgeLen - DOOR_WIDTH) * 0.5
            local rightLen = leftLen

            -- Wall above door
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

            -- Left wall segment
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

            -- Right wall segment
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
        elseif room.hasWindow and edgeLen > WINDOW_WIDTH * 2 then
            -- Wall with window opening: below-sill, above-lintel, and sides
            local sillY = slabTop + WINDOW_SILL_HEIGHT
            local lintelY = sillY + WINDOW_HEIGHT

            -- Wall below window
            if WINDOW_SILL_HEIGHT > 0.5 then
                local belowWin = Instance.new("Part")
                belowWin.Name = "WallBelowWindow"
                belowWin.Size = Vector3.new(edgeLen, WINDOW_SILL_HEIGHT, WALL_THICKNESS)
                belowWin.Material = wallMat
                belowWin.Color = DEFAULT_WALL_COLOR
                belowWin.Anchored = true
                belowWin.CanCollide = true
                belowWin.CFrame = CFrame.new(midX, slabTop + WINDOW_SILL_HEIGHT * 0.5, midZ)
                    * CFrame.Angles(0, angle, 0)
                belowWin.Parent = parent
            end

            -- Wall above window
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

            -- Window glass pane
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

            -- Side pilasters (left and right of window)
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
            -- Simple solid wall
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
end

-- Build a ceiling slab (thin part at the top of the room)
local function buildCeiling(parent, room, originStuds, floorHeight)
    local fp = room.footprint
    if not fp or #fp < 3 then
        return
    end

    local minX, maxX = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge
    for _, pt in ipairs(fp) do
        minX = math.min(minX, pt.x)
        maxX = math.max(maxX, pt.x)
        minZ = math.min(minZ, pt.z)
        maxZ = math.max(maxZ, pt.z)
    end

    local width = maxX - minX
    local depth = maxZ - minZ
    if width < MIN_EDGE or depth < MIN_EDGE then
        return
    end

    local worldX = originStuds.x + (minX + maxX) * 0.5
    local worldZ = originStuds.z + (minZ + maxZ) * 0.5
    local ceilingY = originStuds.y + (room.floorY or 0) + floorHeight

    local ceiling = Instance.new("Part")
    ceiling.Name = "Ceiling"
    ceiling.Size = Vector3.new(width, 0.2, depth)
    ceiling.CFrame = CFrame.new(worldX, ceilingY, worldZ)
    ceiling.Material = Enum.Material.SmoothPlastic
    ceiling.Color = DEFAULT_CEILING_COLOR
    ceiling.Anchored = true
    ceiling.CanCollide = true
    ceiling.Parent = parent
end

function RoomBuilder.BuildAll(parent, buildings, originStuds)
    if not buildings or #buildings == 0 then
        return
    end

    for _, building in ipairs(buildings) do
        local rooms = building.rooms
        if rooms and #rooms > 0 then
            local buildingName = building.id or "Building"
            local buildingModel = parent:FindFirstChild(buildingName)
            if buildingModel and buildingModel:IsA("Model") then
                local roomsFolder = Instance.new("Folder")
                roomsFolder.Name = "Rooms"
                roomsFolder.Parent = buildingModel

                -- Compute floor height from building dimensions
                local levels = building.levels or #rooms
                local floorHeight = building.height / math.max(1, levels)

                for _, room in ipairs(rooms) do
                    local roomFolder = Instance.new("Folder")
                    roomFolder.Name = room.name or room.id or "Room"

                    -- Floor slab (scanline-based polygon fill)
                    buildRoomFloor(roomFolder, room, originStuds)

                    -- Interior partition walls with door/window openings
                    buildRoomWalls(roomFolder, room, originStuds, floorHeight)

                    -- Ceiling slab
                    buildCeiling(roomFolder, room, originStuds, floorHeight)

                    roomFolder.Parent = roomsFolder
                end
            end
        end
    end
end

return RoomBuilder
