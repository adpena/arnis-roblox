--[[
    VehicleController.client.lua
    Player movement mechanics: driveable car, jetpack, and parachute/glider.
    Keybinds:
        V  - Spawn / despawn car
        J  - Toggle jetpack
        P  - Deploy / retract parachute (must be falling)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local currentCar = nil

local jetpackActive = false
local jetpackForce = nil
local jetpackParticles = {}

local parachuteActive = false
local parachutePart = nil
local parachuteForce = nil
local parachuteBodyAttach = nil
local parachuteLandedConn = nil

-------------------------------------------------------------------------------
-- HUD
-------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VehicleHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local hudLabel = Instance.new("TextLabel")
hudLabel.Name = "ControlsLabel"
hudLabel.Size = UDim2.new(0, 360, 0, 30)
hudLabel.Position = UDim2.new(0.5, -180, 1, -44)
hudLabel.BackgroundTransparency = 0.5
hudLabel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
hudLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
hudLabel.Font = Enum.Font.GothamBold
hudLabel.TextSize = 14
hudLabel.Text = "[V] Car  [J] Jetpack  [P] Parachute"
hudLabel.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 6)
uiCorner.Parent = hudLabel

local function updateHUD()
    local parts = {}
    if currentCar then
        table.insert(parts, "[V] CAR SPAWNED")
    else
        table.insert(parts, "[V] Car")
    end
    if jetpackActive then
        table.insert(parts, "[J] JETPACK ON")
    else
        table.insert(parts, "[J] Jetpack")
    end
    if parachuteActive then
        table.insert(parts, "[P] GLIDING")
    else
        table.insert(parts, "[P] Parachute")
    end
    hudLabel.Text = table.concat(parts, "  ")
end

-------------------------------------------------------------------------------
-- Car
-------------------------------------------------------------------------------
local function createCar(position)
    local car = Instance.new("Model")
    car.Name = "PlayerCar"

    -- Body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(8, 3, 16)
    body.Material = Enum.Material.SmoothPlastic
    body.Color = Color3.fromRGB(180, 30, 30)
    body.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
    body.Anchored = false
    body.Parent = car

    -- Roof
    local roof = Instance.new("Part")
    roof.Name = "Roof"
    roof.Size = Vector3.new(7, 2, 8)
    roof.Material = Enum.Material.SmoothPlastic
    roof.Color = Color3.fromRGB(160, 25, 25)
    roof.CFrame = body.CFrame * CFrame.new(0, 2.5, -1)
    roof.Anchored = false
    roof.Parent = car

    local roofWeld = Instance.new("WeldConstraint")
    roofWeld.Part0 = body
    roofWeld.Part1 = roof
    roofWeld.Parent = body

    -- VehicleSeat
    local seat = Instance.new("VehicleSeat")
    seat.Name = "DriveSeat"
    seat.Size = Vector3.new(4, 1, 4)
    seat.CFrame = body.CFrame * CFrame.new(0, 0.5, -2)
    seat.Anchored = false
    seat.MaxSpeed = 80
    seat.Torque = 20
    seat.TurnSpeed = 3
    seat.Parent = car

    local seatWeld = Instance.new("WeldConstraint")
    seatWeld.Part0 = body
    seatWeld.Part1 = seat
    seatWeld.Parent = body

    -- Wheels
    local wheelOffsets = {
        Vector3.new(-3.5, -1.5, -5),
        Vector3.new(3.5, -1.5, -5),
        Vector3.new(-3.5, -1.5, 5),
        Vector3.new(3.5, -1.5, 5),
    }

    for i, offset in ipairs(wheelOffsets) do
        local wheel = Instance.new("Part")
        wheel.Name = "Wheel" .. i
        wheel.Shape = Enum.PartType.Cylinder
        wheel.Size = Vector3.new(2, 2.5, 2.5)
        wheel.Material = Enum.Material.SmoothPlastic
        wheel.Color = Color3.fromRGB(30, 30, 35)
        wheel.CFrame = body.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.pi / 2)
        wheel.Anchored = false
        wheel.CustomPhysicalProperties = PhysicalProperties.new(1.0, 0.8, 0.2, 1, 1)
        wheel.Parent = car

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = body
        weld.Part1 = wheel
        weld.Parent = body
    end

    -- Headlights
    for _, side in ipairs({ -2.5, 2.5 }) do
        local light = Instance.new("Part")
        light.Name = "Headlight"
        light.Shape = Enum.PartType.Ball
        light.Size = Vector3.new(1, 1, 1)
        light.Material = Enum.Material.Neon
        light.Color = Color3.fromRGB(255, 250, 230)
        light.CFrame = body.CFrame * CFrame.new(side, -0.5, -8.2)
        light.Anchored = false
        light.CanCollide = false
        light.Parent = car

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = body
        weld.Part1 = light
        weld.Parent = body

        local spot = Instance.new("SpotLight")
        spot.Range = 60
        spot.Brightness = 2
        spot.Angle = 45
        spot.Face = Enum.NormalId.Front
        spot.Color = Color3.fromRGB(255, 245, 220)
        spot.Parent = light
    end

    -- Tail lights
    for _, side in ipairs({ -2.5, 2.5 }) do
        local tail = Instance.new("Part")
        tail.Name = "TailLight"
        tail.Size = Vector3.new(1.5, 0.8, 0.3)
        tail.Material = Enum.Material.Neon
        tail.Color = Color3.fromRGB(200, 20, 20)
        tail.CFrame = body.CFrame * CFrame.new(side, -0.5, 8.2)
        tail.Anchored = false
        tail.CanCollide = false
        tail.Parent = car

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = body
        weld.Part1 = tail
        weld.Parent = body
    end

    car.PrimaryPart = body
    return car
end

-------------------------------------------------------------------------------
-- Jetpack
-------------------------------------------------------------------------------
local function cleanupJetpack()
    if jetpackForce then
        jetpackForce:Destroy()
        jetpackForce = nil
    end
    for _, p in ipairs(jetpackParticles) do
        p.attachment:Destroy()
    end
    jetpackParticles = {}
    jetpackActive = false
end

local function toggleJetpack(character)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if jetpackActive then
        cleanupJetpack()
        return
    end

    -- Deploying jetpack retracts parachute
    if parachuteActive then
        retractParachute(character)
    end

    jetpackActive = true

    jetpackForce = Instance.new("BodyVelocity")
    jetpackForce.MaxForce = Vector3.new(10000, 40000, 10000)
    jetpackForce.Velocity = Vector3.new(0, 30, 0)
    jetpackForce.Parent = hrp

    -- Flame particle emitters on back
    for _, offset in ipairs({ Vector3.new(-0.8, -1, 0.5), Vector3.new(0.8, -1, 0.5) }) do
        local attachment = Instance.new("Attachment")
        attachment.Position = offset
        attachment.Parent = hrp

        local emitter = Instance.new("ParticleEmitter")
        emitter.Rate = 100
        emitter.Speed = NumberRange.new(10, 20)
        emitter.Lifetime = NumberRange.new(0.2, 0.5)
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1.5),
            NumberSequenceKeypoint.new(1, 0),
        })
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 20)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 50, 20)),
        })
        emitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        })
        emitter.LightEmission = 1
        emitter.LightInfluence = 0
        emitter.Parent = attachment

        table.insert(jetpackParticles, { attachment = attachment, emitter = emitter })
    end
end

-------------------------------------------------------------------------------
-- Parachute
-------------------------------------------------------------------------------

-- Forward-declared so toggleJetpack can call it
function retractParachute(_character)
    if not parachuteActive then return end
    parachuteActive = false

    if parachutePart then
        parachutePart:Destroy()
        parachutePart = nil
    end
    if parachuteForce then
        parachuteForce:Destroy()
        parachuteForce = nil
    end
    if parachuteBodyAttach then
        parachuteBodyAttach:Destroy()
        parachuteBodyAttach = nil
    end
    if parachuteLandedConn then
        parachuteLandedConn:Disconnect()
        parachuteLandedConn = nil
    end
end

local function deployParachute(character)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return end

    -- Only deploy when falling
    if hrp.AssemblyLinearVelocity.Y > -5 then return end

    -- Deploying parachute disables jetpack
    if jetpackActive then
        cleanupJetpack()
    end

    parachuteActive = true

    -- Canopy
    parachutePart = Instance.new("Part")
    parachutePart.Name = "Parachute"
    parachutePart.Shape = Enum.PartType.Ball
    parachutePart.Size = Vector3.new(20, 10, 20)
    parachutePart.Material = Enum.Material.Fabric
    parachutePart.Color = Color3.fromRGB(255, 120, 30)
    parachutePart.Transparency = 0.3
    parachutePart.Anchored = false
    parachutePart.CanCollide = false
    parachutePart.Massless = true
    parachutePart.CastShadow = true
    parachutePart.Parent = character

    local ropeAttach = Instance.new("Attachment")
    ropeAttach.Position = Vector3.new(0, -5, 0)
    ropeAttach.Parent = parachutePart

    parachuteBodyAttach = Instance.new("Attachment")
    parachuteBodyAttach.Position = Vector3.new(0, 2, 0)
    parachuteBodyAttach.Parent = hrp

    local rod = Instance.new("RodConstraint")
    rod.Attachment0 = parachuteBodyAttach
    rod.Attachment1 = ropeAttach
    rod.Length = 15
    rod.Visible = true
    rod.Thickness = 0.1
    rod.Parent = parachutePart

    -- Drag / glide force
    parachuteForce = Instance.new("BodyVelocity")
    parachuteForce.MaxForce = Vector3.new(8000, 15000, 8000)
    parachuteForce.Velocity = Vector3.new(0, -8, 0)
    parachuteForce.Parent = hrp

    -- Auto-retract on landing
    parachuteLandedConn = humanoid.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Landed
            or newState == Enum.HumanoidStateType.Running then
            retractParachute(character)
            updateHUD()
        end
    end)
end

-------------------------------------------------------------------------------
-- Cleanup on death / respawn
-------------------------------------------------------------------------------
local function onCharacterAdded(character)
    -- Reset all state
    currentCar = nil
    cleanupJetpack()
    parachuteActive = false
    parachutePart = nil
    parachuteForce = nil
    parachuteBodyAttach = nil
    if parachuteLandedConn then
        parachuteLandedConn:Disconnect()
        parachuteLandedConn = nil
    end
    updateHUD()

    character:WaitForChild("Humanoid").Died:Connect(function()
        if currentCar then
            currentCar:Destroy()
            currentCar = nil
        end
    end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end

-------------------------------------------------------------------------------
-- Input
-------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local character = player.Character
    if not character then return end

    if input.KeyCode == Enum.KeyCode.V then
        if currentCar then
            currentCar:Destroy()
            currentCar = nil
        else
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local spawnPos = hrp.Position + hrp.CFrame.LookVector * 12
                currentCar = createCar(spawnPos)
                currentCar.Parent = workspace
            end
        end
        updateHUD()

    elseif input.KeyCode == Enum.KeyCode.J then
        toggleJetpack(character)
        updateHUD()

    elseif input.KeyCode == Enum.KeyCode.P then
        if parachuteActive then
            retractParachute(character)
        else
            deployParachute(character)
        end
        updateHUD()
    end
end)

-------------------------------------------------------------------------------
-- Per-frame updates
-------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    local character = player.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- Jetpack steering
    if jetpackActive and jetpackForce then
        local camera = workspace.CurrentCamera
        local look = camera.CFrame.LookVector
        local upSpeed = 25

        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            upSpeed = 50
        elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            upSpeed = -10
        end

        jetpackForce.Velocity = Vector3.new(look.X * 40, upSpeed, look.Z * 40)
    end

    -- Parachute steering
    if parachuteActive and parachuteForce then
        local camera = workspace.CurrentCamera
        local look = camera.CFrame.LookVector
        parachuteForce.Velocity = Vector3.new(look.X * 30, -8, look.Z * 30)

        -- Keep canopy above player
        if parachutePart then
            parachutePart.CFrame = hrp.CFrame * CFrame.new(0, 15, 0)
        end
    end
end)
