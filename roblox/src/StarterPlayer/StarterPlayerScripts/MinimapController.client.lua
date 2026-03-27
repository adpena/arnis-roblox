local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EditableImageCompat = require(ReplicatedStorage.Shared.EditableImageCompat)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAP_SIZE = 200
local MAP_DISPLAY_SIZE = 180
local MAP_FULLSCREEN_SIZE = 600
local MAP_RADIUS = 400
local MAP_RADIUS_FULL = 1600
local UPDATE_INTERVAL = 0.2
local MIN_RENDER_MOVE_STUDS = 4
local HEADING_BUCKET_DEGREES = 6
local BORDER_WIDTH = 2
local WORLD_ROOT_ATTR = "ArnisMinimapWorldRootName"
local ENABLED_ATTR = "ArnisMinimapEnabled"
local CHUNK_JSON_ATTR = "ArnisMinimapChunkJson"
local TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local COLORS = table.freeze({
    background = { 30, 35, 45, 255 },
    road = { 255, 255, 255, 255 },
    road_minor = { 220, 220, 220, 255 },
    building = { 210, 200, 185, 255 },
    water = { 170, 210, 240, 255 },
    park = { 180, 220, 170, 255 },
    forest = { 140, 190, 140, 255 },
    parking = { 230, 225, 215, 255 },
    player = { 65, 130, 240, 255 },
    player_dir = { 65, 130, 240, 200 },
    border = { 50, 55, 65, 255 },
})

local screenGui = nil
local imageLabel = nil
local mapLabel = nil
local editableImage = nil
local pixelBuffer = nil
local lastUpdate = 0
local isFullscreen = false
local currentWorldRoot = nil
local chunkConnections = {}
local chunkSnapshotsByFolder = {}
local worldRootConnections = {}
local lastTelemetry = {}
local chunkSnapshotRevision = 0
local lastRenderedSnapshotRevision = -1
local lastRenderedFullscreen = nil
local lastRenderedCamX = nil
local lastRenderedCamZ = nil
local lastRenderedHeadingBucket = nil

local function markSnapshotsDirty()
    chunkSnapshotRevision += 1
end

local function setPlayerAttributeIfChanged(name, nextValue)
    if player:GetAttribute(name) == nextValue then
        return
    end
    player:SetAttribute(name, nextValue)
end

local function publishMinimapTelemetry(extra)
    local payload = {
        enabled = Workspace:GetAttribute(ENABLED_ATTR) == true,
        guiReady = screenGui ~= nil and screenGui.Parent == playerGui and screenGui.Enabled == true,
        worldRootName = Workspace:GetAttribute(WORLD_ROOT_ATTR),
        snapshotCount = 0,
        fullscreen = isFullscreen,
        error = extra and extra.error or nil,
    }

    for _ in pairs(chunkSnapshotsByFolder) do
        payload.snapshotCount += 1
    end

    local changed = false
    local structuralChange = false
    local attributes = {
        ArnisMinimapEnabled = payload.enabled,
        ArnisMinimapGuiReady = payload.guiReady,
        ArnisMinimapWorldRootName = payload.worldRootName,
        ArnisMinimapSnapshotCount = payload.snapshotCount,
        ArnisMinimapFullscreen = payload.fullscreen,
        ArnisMinimapError = payload.error,
    }

    for attributeName, nextValue in pairs(attributes) do
        if lastTelemetry[attributeName] ~= nextValue then
            setPlayerAttributeIfChanged(attributeName, nextValue)
            lastTelemetry[attributeName] = nextValue
            changed = true
            if attributeName ~= "ArnisMinimapSnapshotCount" then
                structuralChange = true
            end
        end
    end

    if changed and (structuralChange or payload.snapshotCount <= 1 or payload.snapshotCount % 10 == 0) then
        print("ARNIS_CLIENT_MINIMAP " .. HttpService:JSONEncode(payload))
    end
end

local function disconnectConnections(connections)
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
end

local function initBuffer()
    pixelBuffer = buffer.create(MAP_SIZE * MAP_SIZE * 4)
end

local function clearBuffer()
    local bg = COLORS.background
    for i = 0, MAP_SIZE * MAP_SIZE - 1 do
        local offset = i * 4
        buffer.writeu8(pixelBuffer, offset, bg[1])
        buffer.writeu8(pixelBuffer, offset + 1, bg[2])
        buffer.writeu8(pixelBuffer, offset + 2, bg[3])
        buffer.writeu8(pixelBuffer, offset + 3, bg[4])
    end
end

local function setPixel(x, y, color)
    if x < 0 or x >= MAP_SIZE or y < 0 or y >= MAP_SIZE then
        return
    end
    local offset = (y * MAP_SIZE + x) * 4
    buffer.writeu8(pixelBuffer, offset, color[1])
    buffer.writeu8(pixelBuffer, offset + 1, color[2])
    buffer.writeu8(pixelBuffer, offset + 2, color[3])
    buffer.writeu8(pixelBuffer, offset + 3, color[4])
end

local function drawLine(x1, y1, x2, y2, color, thickness)
    thickness = thickness or 1
    local dx = x2 - x1
    local dy = y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps == 0 then
        setPixel(x1, y1, color)
        return
    end
    local xInc = dx / steps
    local yInc = dy / steps
    local half = math.floor(thickness / 2)
    for i = 0, steps do
        local px = math.floor(x1 + xInc * i)
        local py = math.floor(y1 + yInc * i)
        for t = -half, half do
            setPixel(px + t, py, color)
            setPixel(px, py + t, color)
        end
    end
end

local function drawRect(x1, y1, x2, y2, color)
    for y = math.max(0, math.floor(y1)), math.min(MAP_SIZE - 1, math.floor(y2)) do
        for x = math.max(0, math.floor(x1)), math.min(MAP_SIZE - 1, math.floor(x2)) do
            setPixel(x, y, color)
        end
    end
end

local function drawCircle(cx, cy, radius, color)
    local r2 = radius * radius
    for dy = -radius, radius do
        for dx = -radius, radius do
            if dx * dx + dy * dy <= r2 then
                setPixel(math.floor(cx + dx), math.floor(cy + dy), color)
            end
        end
    end
end

local function worldToPixel(worldX, worldZ, camX, camZ)
    local rx = worldX - camX
    local rz = worldZ - camZ
    local activeRadius = isFullscreen and MAP_RADIUS_FULL or MAP_RADIUS
    local scale = MAP_SIZE / (activeRadius * 2)
    local px = MAP_SIZE / 2 + rx * scale
    local py = MAP_SIZE / 2 - rz * scale
    return math.floor(px), math.floor(py)
end

local function footprintToPixelPoints(footprint, ox, oz, camX, camZ)
    local pixelPoints = table.create(#(footprint or {}))
    for index, point in ipairs(footprint or {}) do
        local px, py = worldToPixel(point.x + ox, point.z + oz, camX, camZ)
        pixelPoints[index] = {
            x = px,
            y = py,
        }
    end
    return pixelPoints
end

local function drawFilledPolygon(pixelPoints, color)
    if #pixelPoints < 3 then
        return
    end

    local minY = math.huge
    local maxY = -math.huge
    for _, point in ipairs(pixelPoints) do
        minY = math.min(minY, point.y)
        maxY = math.max(maxY, point.y)
    end

    minY = math.max(0, math.floor(minY))
    maxY = math.min(MAP_SIZE - 1, math.ceil(maxY))

    for y = minY, maxY do
        local intersections = {}
        for index = 1, #pixelPoints do
            local p1 = pixelPoints[index]
            local p2 = pixelPoints[index % #pixelPoints + 1]
            local y1 = p1.y
            local y2 = p2.y
            if (y1 <= y and y2 > y) or (y2 <= y and y1 > y) then
                local t = (y - y1) / (y2 - y1)
                intersections[#intersections + 1] = p1.x + (p2.x - p1.x) * t
            end
        end

        table.sort(intersections)
        for index = 1, #intersections, 2 do
            local startX = intersections[index]
            local endX = intersections[index + 1]
            if startX and endX then
                drawRect(startX, y, endX, y, color)
            end
        end
    end
end

local function drawPlayerHeading(camYaw)
    drawCircle(MAP_SIZE / 2, MAP_SIZE / 2, 4, COLORS.player)

    local dirLen = 10
    local dirX = math.sin(camYaw)
    local dirY = -math.cos(camYaw)
    local centerX = MAP_SIZE / 2
    local centerY = MAP_SIZE / 2
    local tipX = centerX + dirX * dirLen
    local tipY = centerY + dirY * dirLen
    drawLine(centerX, centerY, tipX, tipY, COLORS.player_dir, 2)

    local leftX = tipX - dirY * 2
    local leftY = tipY + dirX * 2
    local rightX = tipX + dirY * 2
    local rightY = tipY - dirX * 2
    drawLine(tipX, tipY, leftX, leftY, COLORS.player_dir, 1)
    drawLine(tipX, tipY, rightX, rightY, COLORS.player_dir, 1)
end

local function iterChunkSnapshots()
    local snapshots = {}
    for _, snapshot in pairs(chunkSnapshotsByFolder) do
        snapshots[#snapshots + 1] = snapshot
    end
    return snapshots
end

local function renderMap(camX, camZ)
    clearBuffer()
    local activeRadius = isFullscreen and MAP_RADIUS_FULL or MAP_RADIUS

    for _, chunk in ipairs(iterChunkSnapshots()) do
        local ox = ((chunk.originStuds or {}).x or 0)
        local oz = ((chunk.originStuds or {}).z or 0)

        for _, lu in ipairs(chunk.landuse or {}) do
            local color = COLORS.park
            if lu.kind == "forest" or lu.kind == "wood" then
                color = COLORS.forest
            elseif lu.kind == "parking" then
                color = COLORS.parking
            end
            local fp = lu.footprint
            if fp and #fp >= 3 then
                drawFilledPolygon(footprintToPixelPoints(fp, ox, oz, camX, camZ), color)
            end
        end

        for _, water in ipairs(chunk.water or {}) do
            if water.footprint and #water.footprint >= 3 then
                drawFilledPolygon(footprintToPixelPoints(water.footprint, ox, oz, camX, camZ), COLORS.water)
            elseif water.points then
                for i = 1, #water.points - 1 do
                    local p1 = water.points[i]
                    local p2 = water.points[i + 1]
                    local px1, py1 = worldToPixel(p1.x + ox, p1.z + oz, camX, camZ)
                    local px2, py2 = worldToPixel(p2.x + ox, p2.z + oz, camX, camZ)
                    local widthPx = math.max(2, math.floor((water.widthStuds or 8) * MAP_SIZE / (activeRadius * 2)))
                    drawLine(px1, py1, px2, py2, COLORS.water, widthPx)
                end
            end
        end

        for _, building in ipairs(chunk.buildings or {}) do
            local fp = building.footprint
            if fp and #fp >= 3 then
                drawFilledPolygon(footprintToPixelPoints(fp, ox, oz, camX, camZ), COLORS.building)
            end
        end

        for _, road in ipairs(chunk.roads or {}) do
            local color = COLORS.road
            local majorKinds = { primary = true, secondary = true, tertiary = true, trunk = true, motorway = true }
            if not majorKinds[road.kind] then
                color = COLORS.road_minor
            end
            local widthPx = math.max(1, math.floor((road.widthStuds or 10) * MAP_SIZE / (activeRadius * 2) * 0.5))
            widthPx = math.min(widthPx, 4)
            for i = 1, #(road.points or {}) - 1 do
                local p1 = road.points[i]
                local p2 = road.points[i + 1]
                local px1, py1 = worldToPixel(p1.x + ox, p1.z + oz, camX, camZ)
                local px2, py2 = worldToPixel(p2.x + ox, p2.z + oz, camX, camZ)
                drawLine(px1, py1, px2, py2, color, widthPx)
            end
        end
    end

    for i = 0, MAP_SIZE - 1 do
        for t = 0, BORDER_WIDTH - 1 do
            setPixel(i, t, COLORS.border)
            setPixel(i, MAP_SIZE - 1 - t, COLORS.border)
            setPixel(t, i, COLORS.border)
            setPixel(MAP_SIZE - 1 - t, i, COLORS.border)
        end
    end
end

local function ensureGui()
    if screenGui then
        return
    end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MinimapGui"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true

    local frame = Instance.new("Frame")
    frame.Name = "MinimapFrame"
    frame.Size = UDim2.new(0, MAP_DISPLAY_SIZE + 10, 0, MAP_DISPLAY_SIZE + 10)
    frame.Position = UDim2.new(0, 10, 1, -MAP_DISPLAY_SIZE - 20)
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 65, 80)
    stroke.Thickness = 2
    stroke.Parent = frame

    imageLabel = Instance.new("ImageLabel")
    imageLabel.Name = "MapImage"
    imageLabel.Size = UDim2.new(0, MAP_DISPLAY_SIZE, 0, MAP_DISPLAY_SIZE)
    imageLabel.Position = UDim2.new(0, 5, 0, 5)
    imageLabel.BackgroundTransparency = 1
    imageLabel.ScaleType = Enum.ScaleType.Stretch
    imageLabel.Parent = frame

    local ok, imageOrError = pcall(function()
        return AssetService:CreateEditableImage({ Size = Vector2.new(MAP_SIZE, MAP_SIZE) })
    end)
    if not ok or not imageOrError then
        publishMinimapTelemetry({
            error = ok and "editable_image_unavailable" or tostring(imageOrError),
        })
        return
    end
    editableImage = imageOrError
    imageLabel.ImageContent = Content.fromObject(editableImage)

    local label = Instance.new("TextLabel")
    label.Name = "Title"
    label.Size = UDim2.new(1, 0, 0, 16)
    label.Position = UDim2.new(0, 0, 1, -16)
    label.BackgroundTransparency = 1
    label.Text = "MAP"
    label.TextColor3 = Color3.fromRGB(140, 145, 160)
    label.TextSize = 11
    label.Font = Enum.Font.GothamBold
    label.Parent = frame
    mapLabel = label

    screenGui.Parent = playerGui
    publishMinimapTelemetry()
end

local function setGuiEnabled(enabled)
    if enabled then
        ensureGui()
    end

    if screenGui then
        screenGui.Enabled = enabled
    end
    publishMinimapTelemetry()
end

local function toggleFullscreen()
    if not screenGui then
        return
    end

    local frame = screenGui:FindFirstChild("MinimapFrame")
    if not frame or not imageLabel or not mapLabel then
        return
    end

    isFullscreen = not isFullscreen
    if isFullscreen then
        local size = MAP_FULLSCREEN_SIZE + 10
        mapLabel.Text = "MAP  [M to close]"
        TweenService:Create(frame, TWEEN_INFO, {
            Size = UDim2.new(0, size, 0, size),
            Position = UDim2.new(0.5, -size / 2, 0.5, -size / 2),
        }):Play()
        TweenService:Create(imageLabel, TWEEN_INFO, {
            Size = UDim2.new(0, MAP_FULLSCREEN_SIZE, 0, MAP_FULLSCREEN_SIZE),
        }):Play()
    else
        local size = MAP_DISPLAY_SIZE + 10
        mapLabel.Text = "MAP"
        TweenService:Create(frame, TWEEN_INFO, {
            Size = UDim2.new(0, size, 0, size),
            Position = UDim2.new(0, 10, 1, -size - 10),
        }):Play()
        TweenService:Create(imageLabel, TWEEN_INFO, {
            Size = UDim2.new(0, MAP_DISPLAY_SIZE, 0, MAP_DISPLAY_SIZE),
        }):Play()
    end
    publishMinimapTelemetry()
end

local function decodeChunkSnapshot(folder)
    local payload = folder:GetAttribute(CHUNK_JSON_ATTR)
    if type(payload) ~= "string" or payload == "" then
        chunkSnapshotsByFolder[folder] = nil
        return
    end

    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, payload)
    if ok and type(decoded) == "table" then
        chunkSnapshotsByFolder[folder] = decoded
    else
        chunkSnapshotsByFolder[folder] = nil
    end
    markSnapshotsDirty()
    publishMinimapTelemetry()
end

local function attachChunkFolder(folder)
    if not folder or not folder:IsA("Folder") or chunkConnections[folder] then
        return
    end

    decodeChunkSnapshot(folder)
    chunkConnections[folder] = {
        folder:GetAttributeChangedSignal(CHUNK_JSON_ATTR):Connect(function()
            decodeChunkSnapshot(folder)
        end),
        folder.Destroying:Connect(function()
            chunkSnapshotsByFolder[folder] = nil
            disconnectConnections(chunkConnections[folder] or {})
            chunkConnections[folder] = nil
            markSnapshotsDirty()
        end),
    }
end

local function detachAllChunks()
    for folder, connections in pairs(chunkConnections) do
        disconnectConnections(connections)
        chunkConnections[folder] = nil
        chunkSnapshotsByFolder[folder] = nil
    end
    markSnapshotsDirty()
    publishMinimapTelemetry()
end

local function bindWorldRoot(worldRoot)
    if currentWorldRoot == worldRoot then
        return
    end

    disconnectConnections(worldRootConnections)
    detachAllChunks()
    currentWorldRoot = worldRoot

    if not currentWorldRoot then
        publishMinimapTelemetry()
        return
    end

    for _, child in ipairs(currentWorldRoot:GetChildren()) do
        attachChunkFolder(child)
    end

    worldRootConnections[#worldRootConnections + 1] = currentWorldRoot.ChildAdded:Connect(attachChunkFolder)
    worldRootConnections[#worldRootConnections + 1] = currentWorldRoot.ChildRemoved:Connect(function(child)
        local connections = chunkConnections[child]
        if connections then
            disconnectConnections(connections)
            chunkConnections[child] = nil
        end
        chunkSnapshotsByFolder[child] = nil
        markSnapshotsDirty()
        publishMinimapTelemetry()
    end)
    publishMinimapTelemetry()
end

local function resolveWorldRoot()
    local worldRootName = Workspace:GetAttribute(WORLD_ROOT_ATTR)
    if type(worldRootName) ~= "string" or worldRootName == "" then
        return nil
    end
    return Workspace:FindFirstChild(worldRootName)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end
    if input.KeyCode == Enum.KeyCode.M then
        toggleFullscreen()
    end
end)

Workspace:GetAttributeChangedSignal(WORLD_ROOT_ATTR):Connect(function()
    bindWorldRoot(resolveWorldRoot())
end)

Workspace:GetAttributeChangedSignal(ENABLED_ATTR):Connect(function()
    setGuiEnabled(Workspace:GetAttribute(ENABLED_ATTR) == true)
end)

initBuffer()
setGuiEnabled(Workspace:GetAttribute(ENABLED_ATTR) == true)
bindWorldRoot(resolveWorldRoot())
publishMinimapTelemetry()

RunService.Heartbeat:Connect(function(dt)
    lastUpdate += dt
    if lastUpdate < UPDATE_INTERVAL then
        return
    end
    lastUpdate = 0

    if Workspace:GetAttribute(ENABLED_ATTR) ~= true or not editableImage or not screenGui or not screenGui.Enabled then
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local camPos = camera.CFrame.Position
    local camLook = camera.CFrame.LookVector
    local camYaw = math.atan2(camLook.X, camLook.Z)
    local heading = math.floor((camYaw * 180 / math.pi) % 360)
    local headingBucket = math.floor(heading / HEADING_BUCKET_DEGREES)
    local movedEnough = if lastRenderedCamX == nil or lastRenderedCamZ == nil
        then true
        else ((camPos.X - lastRenderedCamX) ^ 2 + (camPos.Z - lastRenderedCamZ) ^ 2) >= (MIN_RENDER_MOVE_STUDS ^ 2)
    local needsRender = movedEnough
        or lastRenderedSnapshotRevision ~= chunkSnapshotRevision
        or lastRenderedFullscreen ~= isFullscreen
        or lastRenderedHeadingBucket ~= headingBucket

    if not needsRender then
        if not isFullscreen and mapLabel then
            local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
            local dirIdx = math.floor((heading + 22.5) / 45) % 8 + 1
            mapLabel.Text = string.format("MAP  %s %d°", dirs[dirIdx], heading)
        end
        return
    end

    renderMap(camPos.X, camPos.Z)
    drawPlayerHeading(camYaw)
    EditableImageCompat.WritePixels(editableImage, Vector2.zero, Vector2.new(MAP_SIZE, MAP_SIZE), pixelBuffer)
    lastRenderedCamX = camPos.X
    lastRenderedCamZ = camPos.Z
    lastRenderedSnapshotRevision = chunkSnapshotRevision
    lastRenderedFullscreen = isFullscreen
    lastRenderedHeadingBucket = headingBucket

    if not isFullscreen and mapLabel then
        local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
        local dirIdx = math.floor((heading + 22.5) / 45) % 8 + 1
        mapLabel.Text = string.format("MAP  %s %d°", dirs[dirIdx], heading)
    end
end)
