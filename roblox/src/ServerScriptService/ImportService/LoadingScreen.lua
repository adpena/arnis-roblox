local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LoadingScreen = {}

local screenGui = nil
local progressBar = nil
local statusLabel = nil
local cityLabel = nil

function LoadingScreen.Show(worldName)
    -- Create for all players
    for _, player in ipairs(Players:GetPlayers()) do
        local gui = Instance.new("ScreenGui")
        gui.Name = "LoadingScreen"
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 100
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        -- Full screen dark background
        local bg = Instance.new("Frame")
        bg.Name = "Background"
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
        bg.BorderSizePixel = 0
        bg.Parent = gui

        -- City name (large, centered)
        local title = Instance.new("TextLabel")
        title.Name = "CityName"
        title.Size = UDim2.new(0.8, 0, 0, 60)
        title.Position = UDim2.new(0.1, 0, 0.35, 0)
        title.BackgroundTransparency = 1
        title.Text = worldName or "Loading World"
        title.TextColor3 = Color3.fromRGB(240, 242, 248)
        title.TextSize = 42
        title.Font = Enum.Font.GothamBold
        title.Parent = bg
        cityLabel = title

        -- Subtitle
        local subtitle = Instance.new("TextLabel")
        subtitle.Name = "Subtitle"
        subtitle.Size = UDim2.new(0.8, 0, 0, 24)
        subtitle.Position = UDim2.new(0.1, 0, 0.35, 65)
        subtitle.BackgroundTransparency = 1
        subtitle.Text = "Generated from OpenStreetMap"
        subtitle.TextColor3 = Color3.fromRGB(120, 125, 140)
        subtitle.TextSize = 16
        subtitle.Font = Enum.Font.Gotham
        subtitle.Parent = bg

        -- Progress bar background
        local barBg = Instance.new("Frame")
        barBg.Name = "ProgressBg"
        barBg.Size = UDim2.new(0.4, 0, 0, 4)
        barBg.Position = UDim2.new(0.3, 0, 0.55, 0)
        barBg.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
        barBg.BorderSizePixel = 0
        barBg.Parent = bg

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 2)
        barCorner.Parent = barBg

        -- Progress bar fill
        local barFill = Instance.new("Frame")
        barFill.Name = "ProgressFill"
        barFill.Size = UDim2.new(0, 0, 1, 0)
        barFill.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
        barFill.BorderSizePixel = 0
        barFill.Parent = barBg

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 2)
        fillCorner.Parent = barFill

        progressBar = barFill

        -- Status text
        local status = Instance.new("TextLabel")
        status.Name = "Status"
        status.Size = UDim2.new(0.8, 0, 0, 20)
        status.Position = UDim2.new(0.1, 0, 0.55, 15)
        status.BackgroundTransparency = 1
        status.Text = "Initializing..."
        status.TextColor3 = Color3.fromRGB(100, 105, 120)
        status.TextSize = 13
        status.Font = Enum.Font.Gotham
        status.Parent = bg
        statusLabel = status

        -- Controls hint at bottom
        local controls = Instance.new("TextLabel")
        controls.Name = "Controls"
        controls.Size = UDim2.new(0.8, 0, 0, 40)
        controls.Position = UDim2.new(0.1, 0, 0.85, 0)
        controls.BackgroundTransparency = 1
        controls.Text = "[V] Car   [J] Jetpack   [P] Parachute   [M] Map   [C] Cinematic"
        controls.TextColor3 = Color3.fromRGB(70, 75, 90)
        controls.TextSize = 12
        controls.Font = Enum.Font.Gotham
        controls.Parent = bg

        gui.Parent = player.PlayerGui
        screenGui = gui
    end
end

function LoadingScreen.UpdateProgress(fraction, statusText)
    if progressBar then
        TweenService:Create(progressBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
        }):Play()
    end
    if statusLabel and statusText then
        statusLabel.Text = statusText
    end
end

function LoadingScreen.Hide()
    if not screenGui then return end
    -- Fade out
    local bg = screenGui:FindFirstChild("Background")
    if bg then
        TweenService:Create(bg, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
            BackgroundTransparency = 1
        }):Play()
        -- Fade all children
        for _, child in ipairs(bg:GetDescendants()) do
            if child:IsA("TextLabel") then
                TweenService:Create(child, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
                    TextTransparency = 1
                }):Play()
            elseif child:IsA("Frame") then
                TweenService:Create(child, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
                    BackgroundTransparency = 1
                }):Play()
            end
        end
    end
    task.delay(2, function()
        if screenGui then screenGui:Destroy(); screenGui = nil end
    end)
end

return LoadingScreen
