local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")

local MinimapService = {}

local UserInputService = game:GetService("UserInputService")

-- Minimap configuration
local MAP_SIZE = 200          -- pixels (square)
local MAP_DISPLAY_SIZE = 180  -- pixel size on screen (small mode)
local MAP_FULLSCREEN_SIZE = 600 -- pixel size on screen (fullscreen mode)
local MAP_RADIUS = 400        -- world studs visible in minimap radius (small)
local MAP_RADIUS_FULL = 1600  -- world studs visible (fullscreen)
local UPDATE_INTERVAL = 0.2   -- seconds between minimap updates
local BORDER_WIDTH = 3
local isFullscreen = false

-- Colors (RGBA bytes)
local COLORS = {
    background = {30, 35, 45, 255},      -- dark blue-grey
    road = {255, 255, 255, 255},          -- white roads (Google Maps style)
    road_minor = {220, 220, 220, 255},    -- lighter for minor roads
    building = {210, 200, 185, 255},      -- warm beige
    water = {170, 210, 240, 255},         -- light blue
    park = {180, 220, 170, 255},          -- light green
    forest = {140, 190, 140, 255},        -- darker green
    parking = {230, 225, 215, 255},       -- light grey
    player = {65, 130, 240, 255},         -- bright blue dot
    player_dir = {65, 130, 240, 200},     -- direction indicator
    border = {50, 55, 65, 255},           -- border color
}

-- State
local chunks = {}       -- stored chunk data for rendering
local editableImage = nil
local screenGui = nil
local imageLabel = nil
local lastUpdate = 0

-- Pixel buffer (flattened RGBA)
local pixelBuffer = nil

local function initBuffer()
    pixelBuffer = buffer.create(MAP_SIZE * MAP_SIZE * 4)
end

local function clearBuffer()
    -- Fill with background color
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
    if x < 0 or x >= MAP_SIZE or y < 0 or y >= MAP_SIZE then return end
    local offset = (y * MAP_SIZE + x) * 4
    buffer.writeu8(pixelBuffer, offset, color[1])
    buffer.writeu8(pixelBuffer, offset + 1, color[2])
    buffer.writeu8(pixelBuffer, offset + 2, color[3])
    buffer.writeu8(pixelBuffer, offset + 3, color[4])
end

-- Draw a thick line between two pixel coordinates
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

-- Draw a filled rectangle
local function drawRect(x1, y1, x2, y2, color)
    for y = math.max(0, math.floor(y1)), math.min(MAP_SIZE - 1, math.floor(y2)) do
        for x = math.max(0, math.floor(x1)), math.min(MAP_SIZE - 1, math.floor(x2)) do
            setPixel(x, y, color)
        end
    end
end

-- Draw a filled circle
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

-- Convert world XZ to minimap pixel coordinates
local function worldToPixel(worldX, worldZ, camX, camZ, camYaw)
    -- Translate relative to camera
    local rx = worldX - camX
    local rz = worldZ - camZ

    -- Rotate by camera yaw (so map rotates with player view)
    local cosY = math.cos(-camYaw)
    local sinY = math.sin(-camYaw)
    local rotX = rx * cosY - rz * sinY
    local rotZ = rx * sinY + rz * cosY

    -- Scale to pixel space
    local activeRadius = isFullscreen and MAP_RADIUS_FULL or MAP_RADIUS
    local scale = MAP_SIZE / (activeRadius * 2)
    local px = MAP_SIZE / 2 + rotX * scale
    local py = MAP_SIZE / 2 + rotZ * scale

    return math.floor(px), math.floor(py)
end

-- Render all stored chunks to the pixel buffer
local function renderMap(camX, camZ, camYaw)
    clearBuffer()

    for _, chunk in ipairs(chunks) do
        local ox = chunk.originStuds.x
        local oz = chunk.originStuds.z

        -- Render landuse first (background layer)
        for _, lu in ipairs(chunk.landuse or {}) do
            local color = COLORS.park
            if lu.kind == "forest" or lu.kind == "wood" then
                color = COLORS.forest
            elseif lu.kind == "parking" then
                color = COLORS.parking
            end
            -- Simple bounding box fill for landuse
            local fp = lu.footprint
            if fp and #fp >= 3 then
                local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
                for _, pt in ipairs(fp) do
                    minX = math.min(minX, pt.x + ox)
                    maxX = math.max(maxX, pt.x + ox)
                    minZ = math.min(minZ, pt.z + oz)
                    maxZ = math.max(maxZ, pt.z + oz)
                end
                local px1, py1 = worldToPixel(minX, minZ, camX, camZ, camYaw)
                local px2, py2 = worldToPixel(maxX, maxZ, camX, camZ, camYaw)
                drawRect(math.min(px1, px2), math.min(py1, py2), math.max(px1, px2), math.max(py1, py2), color)
            end
        end

        -- Render water
        for _, water in ipairs(chunk.water or {}) do
            if water.footprint then
                local fp = water.footprint
                local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
                for _, pt in ipairs(fp) do
                    minX = math.min(minX, pt.x + ox)
                    maxX = math.max(maxX, pt.x + ox)
                    minZ = math.min(minZ, pt.z + oz)
                    maxZ = math.max(maxZ, pt.z + oz)
                end
                local px1, py1 = worldToPixel(minX, minZ, camX, camZ, camYaw)
                local px2, py2 = worldToPixel(maxX, maxZ, camX, camZ, camYaw)
                drawRect(math.min(px1, px2), math.min(py1, py2), math.max(px1, px2), math.max(py1, py2), COLORS.water)
            elseif water.points then
                for i = 1, #water.points - 1 do
                    local p1 = water.points[i]
                    local p2 = water.points[i + 1]
                    local px1, py1 = worldToPixel(p1.x + ox, p1.z + oz, camX, camZ, camYaw)
                    local px2, py2 = worldToPixel(p2.x + ox, p2.z + oz, camX, camZ, camYaw)
                    local widthPx = math.max(2, math.floor((water.widthStuds or 8) * MAP_SIZE / (activeRadius * 2)))
                    drawLine(px1, py1, px2, py2, COLORS.water, widthPx)
                end
            end
        end

        -- Render buildings
        for _, building in ipairs(chunk.buildings or {}) do
            local fp = building.footprint
            if fp and #fp >= 3 then
                local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
                for _, pt in ipairs(fp) do
                    minX = math.min(minX, pt.x + ox)
                    maxX = math.max(maxX, pt.x + ox)
                    minZ = math.min(minZ, pt.z + oz)
                    maxZ = math.max(maxZ, pt.z + oz)
                end
                local px1, py1 = worldToPixel(minX, minZ, camX, camZ, camYaw)
                local px2, py2 = worldToPixel(maxX, maxZ, camX, camZ, camYaw)
                drawRect(math.min(px1, px2), math.min(py1, py2), math.max(px1, px2), math.max(py1, py2), COLORS.building)
            end
        end

        -- Render roads (on top of everything else)
        for _, road in ipairs(chunk.roads or {}) do
            local color = COLORS.road
            local majorKinds = {primary=true, secondary=true, tertiary=true, trunk=true, motorway=true}
            if not majorKinds[road.kind] then
                color = COLORS.road_minor
            end
            local widthPx = math.max(1, math.floor((road.widthStuds or 10) * MAP_SIZE / (activeRadius * 2) * 0.5))
            widthPx = math.min(widthPx, 4) -- cap line thickness

            for i = 1, #road.points - 1 do
                local p1 = road.points[i]
                local p2 = road.points[i + 1]
                local px1, py1 = worldToPixel(p1.x + ox, p1.z + oz, camX, camZ, camYaw)
                local px2, py2 = worldToPixel(p2.x + ox, p2.z + oz, camX, camZ, camYaw)
                drawLine(px1, py1, px2, py2, color, widthPx)
            end
        end
    end

    -- Draw player dot (center)
    drawCircle(MAP_SIZE / 2, MAP_SIZE / 2, 4, COLORS.player)

    -- Draw direction indicator (small triangle ahead of player)
    local dirLen = 8
    setPixel(MAP_SIZE / 2, MAP_SIZE / 2 - dirLen, COLORS.player_dir)
    setPixel(MAP_SIZE / 2 - 1, MAP_SIZE / 2 - dirLen + 1, COLORS.player_dir)
    setPixel(MAP_SIZE / 2 + 1, MAP_SIZE / 2 - dirLen + 1, COLORS.player_dir)

    -- Draw border
    for i = 0, MAP_SIZE - 1 do
        for t = 0, BORDER_WIDTH - 1 do
            setPixel(i, t, COLORS.border)
            setPixel(i, MAP_SIZE - 1 - t, COLORS.border)
            setPixel(t, i, COLORS.border)
            setPixel(MAP_SIZE - 1 - t, i, COLORS.border)
        end
    end
end

-- Store chunk data for minimap rendering
function MinimapService.RegisterChunk(chunkData)
    table.insert(chunks, chunkData)
end

-- Create the ScreenGui minimap display
function MinimapService.CreateGui(player)
    if screenGui then screenGui:Destroy() end

    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MinimapGui"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true

    -- Container frame (rounded corners via UICorner)
    local frame = Instance.new("Frame")
    frame.Name = "MinimapFrame"
    frame.Size = UDim2.new(0, MAP_DISPLAY_SIZE + 10, 0, MAP_DISPLAY_SIZE + 10)
    -- Bottom-left corner
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

    -- Map image
    imageLabel = Instance.new("ImageLabel")
    imageLabel.Name = "MapImage"
    imageLabel.Size = UDim2.new(0, MAP_DISPLAY_SIZE, 0, MAP_DISPLAY_SIZE)
    imageLabel.Position = UDim2.new(0, 5, 0, 5)
    imageLabel.BackgroundTransparency = 1
    imageLabel.ScaleType = Enum.ScaleType.Stretch
    imageLabel.Parent = frame

    -- Create EditableImage
    editableImage = AssetService:CreateEditableImage({Size = Vector2.new(MAP_SIZE, MAP_SIZE)})
    imageLabel.ImageContent = Content.fromObject(editableImage)

    -- "MAP" label
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

    screenGui.Parent = player.PlayerGui

    -- M key toggles fullscreen
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.M then
            isFullscreen = not isFullscreen
            if isFullscreen then
                -- Expand to fullscreen center
                local size = MAP_FULLSCREEN_SIZE + 10
                frame.Size = UDim2.new(0, size, 0, size)
                frame.Position = UDim2.new(0.5, -size / 2, 0.5, -size / 2)
                imageLabel.Size = UDim2.new(0, MAP_FULLSCREEN_SIZE, 0, MAP_FULLSCREEN_SIZE)
                label.Text = "MAP  [M to close]"
            else
                -- Collapse to bottom-left mini
                local size = MAP_DISPLAY_SIZE + 10
                frame.Size = UDim2.new(0, size, 0, size)
                frame.Position = UDim2.new(0, 10, 1, -size - 10)
                imageLabel.Size = UDim2.new(0, MAP_DISPLAY_SIZE, 0, MAP_DISPLAY_SIZE)
                label.Text = "MAP"
            end
        end
    end)
end

-- Start the minimap update loop
function MinimapService.Start()
    initBuffer()

    -- Create GUI for all current players
    for _, player in ipairs(Players:GetPlayers()) do
        MinimapService.CreateGui(player)
    end
    Players.PlayerAdded:Connect(function(player)
        MinimapService.CreateGui(player)
    end)

    -- Update loop
    RunService.Heartbeat:Connect(function(dt)
        lastUpdate = lastUpdate + dt
        if lastUpdate < UPDATE_INTERVAL then return end
        lastUpdate = 0

        if not editableImage then return end

        -- Get camera position and direction
        local camera = workspace.CurrentCamera
        if not camera then return end
        local camPos = camera.CFrame.Position
        local camLook = camera.CFrame.LookVector
        local camYaw = math.atan2(camLook.X, camLook.Z)

        -- Render map centered on camera
        renderMap(camPos.X, camPos.Z, camYaw)

        -- Write to EditableImage
        editableImage:WritePixels(Vector2.zero, Vector2.new(MAP_SIZE, MAP_SIZE), pixelBuffer)
    end)
end

function MinimapService.Stop()
    if screenGui then
        screenGui:Destroy()
        screenGui = nil
    end
    editableImage = nil
    chunks = {}
end

return MinimapService
