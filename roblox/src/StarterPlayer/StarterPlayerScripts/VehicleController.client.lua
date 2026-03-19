--[[
    VehicleController.client.lua
    AAA-grade player vehicle mechanics: car, jetpack, and parachute.

    Keybinds:
        V       Spawn car / enter nearby car / exit car
        J       Toggle jetpack
        P       Deploy / retract parachute (must be falling)
        WASD    Drive / steer (car) or directional thrust (jetpack/parachute)
        Space   Handbrake (car) / ascend (jetpack)
        LShift  Descend (jetpack)
        H       Horn (car)
        E       Exit vehicle (car)
        A/D     Bank left/right (parachute)
        S       Flare / increase angle of attack (parachute)

    Architecture:
        - SpringConstraint suspension per wheel
        - CylindricalConstraint motor per wheel
        - HingeConstraint steering pivots on front wheels
        - BodyForce-based jetpack with gradual thrust ramp
        - Aerodynamic parachute with glide ratio, stall, and wind
        - Custom chase camera with FOV scaling
        - Full HUD: speedometer, altimeter, fuel gauge, mode icon
        - TweenService for all animations
        - CollectionService tagging for cleanup
        - Complete cleanup on death/leave/respawn
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
local CAR_TAG = "PlayerVehiclePart"
local JETPACK_TAG = "JetpackPart"
local PARACHUTE_TAG = "ParachutePart"

-- Car physics
local CAR_MAX_SPEED = 120           -- studs/s
local CAR_TORQUE = 800
local CAR_STEER_ANGLE = 35          -- degrees
local CAR_STEER_SPEED = 4           -- how fast steering responds
local SUSPENSION_REST_LENGTH = 1.5
local SUSPENSION_STIFFNESS = 800
local SUSPENSION_DAMPING = 60
local DRIFT_GRIP_REDUCTION = 0.4
local ENGINE_IDLE_VIBRATION = 0.03

-- Jetpack physics
local JETPACK_MAX_THRUST = 6000
local JETPACK_RAMP_TIME = 0.3
local JETPACK_DAMPING = 0.92
local JETPACK_HOVER_FORCE_Y = 196.2 * 3  -- counteract gravity for ~3 mass
local JETPACK_FUEL_MAX = 30          -- seconds
local JETPACK_FUEL_RECHARGE_RATE = 0.5  -- per second on ground

-- Parachute physics
local CHUTE_GLIDE_RATIO = 3.0       -- 3 forward : 1 down
local CHUTE_DESCENT_RATE = -12
local CHUTE_FORWARD_SPEED = 36
local CHUTE_TURN_RATE = 2.5
local CHUTE_FLARE_LIFT = 8
local CHUTE_STALL_THRESHOLD = -0.7  -- normalized back input
local CHUTE_STALL_DESCENT = -40
local CHUTE_WIND_STRENGTH = 3

-- Camera
local CAR_CAM_OFFSET = Vector3.new(0, 8, 22)
local CAR_CAM_LERP = 0.08
local CAR_CAM_TILT_FACTOR = 0.04
local CAR_FOV_MIN = 70
local CAR_FOV_MAX = 95
local CAR_FOV_SPEED_RANGE = 100     -- speed at which FOV maxes out

local JETPACK_CAM_OFFSET = Vector3.new(0, 4, 16)
local JETPACK_CAM_LERP = 0.06
local JETPACK_CAM_SHAKE_INTENSITY = 0.15

local CHUTE_CAM_OFFSET = Vector3.new(0, 10, 24)
local CHUTE_CAM_LERP = 0.05
local CHUTE_FOV = 82

local DEFAULT_FOV = 70

-- HUD
local HUD_FADE_DELAY = 5
local HUD_FONT = Enum.Font.GothamBold
local HUD_BG_COLOR = Color3.fromRGB(15, 17, 25)
local HUD_TEXT_COLOR = Color3.fromRGB(220, 225, 235)
local HUD_ACCENT_COLOR = Color3.fromRGB(80, 180, 255)

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local mode = "none"  -- "none" | "car" | "jetpack" | "parachute"
local prevMode = "none"

-- Car state
local carModel = nil
local carBody = nil
local carSeat = nil
local carWheels = {}        -- { part, motor, spring, steerHinge (front only) }
local carBrakeLights = {}
local carExhaustEmitter = nil
local carEngineSound = nil
local carTireScreechSound = nil
local carHornSound = nil
local carIdleVibration = nil
local carSteerAngle = 0
local carPrevSpeed = 0
local carIsBraking = false
local carGyro = nil

-- Jetpack state
local jetpackForce = nil
local jetpackParts = {}
local jetpackNozzles = {}
local jetpackEmitters = {}
local jetpackLights = {}
local jetpackTrails = {}
local jetpackThrustSound = nil
local jetpackWindSound = nil
local jetpackFuel = JETPACK_FUEL_MAX
local jetpackThrustLevel = 0  -- 0..1 ramp
local jetpackActive = false

-- Parachute state
local chuteActive = false
local chuteCanopy = nil
local chuteLines = {}
local chuteForce = nil
local chuteLift = nil
local chuteGyro = nil
local chuteHeading = 0
local chuteStalled = false
local chuteStallTimer = 0
local chuteWindOffset = Vector3.new(0, 0, 0)
local chuteWindSound = nil
local chuteFlutterSound = nil
local chuteLandedConn = nil

-- Camera state
local customCamActive = false
local camTargetFOV = DEFAULT_FOV
local camCurrentPos = nil

-- Transition state
local transitionLock = false

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------
local function tagPart(part, tag)
    CollectionService:AddTag(part, tag)
end

local function cleanupByTag(tag)
    for _, obj in ipairs(CollectionService:GetTagged(tag)) do
        obj:Destroy()
    end
end

local function lerp(a, b, t)
    return a + (b - a) * math.clamp(t, 0, 1)
end

local function lerpVector3(a, b, t)
    return a:Lerp(b, math.clamp(t, 0, 1))
end

local function tweenProperty(obj, props, duration, style, direction)
    style = style or Enum.EasingStyle.Quad
    direction = direction or Enum.EasingDirection.Out
    local tween = TweenService:Create(obj, TweenInfo.new(duration, style, direction), props)
    tween:Play()
    return tween
end

local function makeSound(parent, name, looped, volume, soundId)
    local s = Instance.new("Sound")
    s.Name = name
    s.Looped = looped or false
    s.Volume = volume or 0.5
    -- Placeholder IDs: replace with real asset IDs
    -- Search terms for Roblox library:
    --   Engine loop: "car engine loop", "vehicle engine"
    --   Tire screech: "tire screech", "drift sound"
    --   Horn: "car horn"
    --   Jet thrust: "rocket thrust", "jet engine"
    --   Wind: "wind rushing", "wind ambient"
    --   Parachute flutter: "fabric flapping", "canvas wind"
    s.SoundId = soundId or ""
    s.Parent = parent
    return s
end

local function getCharacter()
    return player.Character
end

local function getHRP()
    local char = getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isOnGround()
    local hum = getHumanoid()
    if not hum then return false end
    local state = hum:GetState()
    return state == Enum.HumanoidStateType.Running
        or state == Enum.HumanoidStateType.Landed
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VehicleHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

-- Main container at bottom center
local hudContainer = Instance.new("Frame")
hudContainer.Name = "HUDContainer"
hudContainer.Size = UDim2.new(0, 500, 0, 120)
hudContainer.Position = UDim2.new(0.5, -250, 1, -130)
hudContainer.BackgroundTransparency = 1
hudContainer.Parent = screenGui

-- Control hints
local controlHints = Instance.new("TextLabel")
controlHints.Name = "ControlHints"
controlHints.Size = UDim2.new(1, 0, 0, 24)
controlHints.Position = UDim2.new(0, 0, 1, -24)
controlHints.BackgroundTransparency = 0.4
controlHints.BackgroundColor3 = HUD_BG_COLOR
controlHints.TextColor3 = HUD_TEXT_COLOR
controlHints.Font = HUD_FONT
controlHints.TextSize = 13
controlHints.Text = "[V] Car   [J] Jetpack   [P] Parachute"
controlHints.Parent = hudContainer
Instance.new("UICorner", controlHints).CornerRadius = UDim.new(0, 6)

-- Mode icon
local modeIcon = Instance.new("TextLabel")
modeIcon.Name = "ModeIcon"
modeIcon.Size = UDim2.new(0, 40, 0, 40)
modeIcon.Position = UDim2.new(0, 0, 0, 0)
modeIcon.BackgroundTransparency = 0.3
modeIcon.BackgroundColor3 = HUD_BG_COLOR
modeIcon.TextColor3 = HUD_ACCENT_COLOR
modeIcon.Font = HUD_FONT
modeIcon.TextSize = 22
modeIcon.Text = ""
modeIcon.Visible = false
modeIcon.Parent = hudContainer
Instance.new("UICorner", modeIcon).CornerRadius = UDim.new(0, 8)

-- Speedometer
local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "Speed"
speedLabel.Size = UDim2.new(0, 120, 0, 36)
speedLabel.Position = UDim2.new(0.5, -60, 0, 0)
speedLabel.BackgroundTransparency = 0.3
speedLabel.BackgroundColor3 = HUD_BG_COLOR
speedLabel.TextColor3 = HUD_TEXT_COLOR
speedLabel.Font = HUD_FONT
speedLabel.TextSize = 20
speedLabel.Text = ""
speedLabel.Visible = false
speedLabel.Parent = hudContainer
Instance.new("UICorner", speedLabel).CornerRadius = UDim.new(0, 8)

-- Altitude
local altLabel = Instance.new("TextLabel")
altLabel.Name = "Altitude"
altLabel.Size = UDim2.new(0, 100, 0, 30)
altLabel.Position = UDim2.new(1, -100, 0, 0)
altLabel.BackgroundTransparency = 0.3
altLabel.BackgroundColor3 = HUD_BG_COLOR
altLabel.TextColor3 = HUD_TEXT_COLOR
altLabel.Font = HUD_FONT
altLabel.TextSize = 16
altLabel.Text = ""
altLabel.Visible = false
altLabel.Parent = hudContainer
Instance.new("UICorner", altLabel).CornerRadius = UDim.new(0, 6)

-- Fuel bar (jetpack)
local fuelBarBg = Instance.new("Frame")
fuelBarBg.Name = "FuelBarBG"
fuelBarBg.Size = UDim2.new(0, 160, 0, 12)
fuelBarBg.Position = UDim2.new(0.5, -80, 0, 44)
fuelBarBg.BackgroundTransparency = 0.3
fuelBarBg.BackgroundColor3 = HUD_BG_COLOR
fuelBarBg.Visible = false
fuelBarBg.Parent = hudContainer
Instance.new("UICorner", fuelBarBg).CornerRadius = UDim.new(0, 4)

local fuelBarFill = Instance.new("Frame")
fuelBarFill.Name = "FuelFill"
fuelBarFill.Size = UDim2.new(1, -4, 1, -4)
fuelBarFill.Position = UDim2.new(0, 2, 0, 2)
fuelBarFill.BackgroundColor3 = HUD_ACCENT_COLOR
fuelBarFill.BorderSizePixel = 0
fuelBarFill.Parent = fuelBarBg
Instance.new("UICorner", fuelBarFill).CornerRadius = UDim.new(0, 3)

local controlHintTimer = 0
local controlHintsVisible = true

local function setHUDMode(newMode)
    local isCar = newMode == "car"
    local isJet = newMode == "jetpack"
    local isChute = newMode == "parachute"
    local isActive = isCar or isJet or isChute

    modeIcon.Visible = isActive
    speedLabel.Visible = isCar
    altLabel.Visible = isJet or isChute
    fuelBarBg.Visible = isJet

    if isCar then
        modeIcon.Text = "CAR"
        controlHints.Text = "[WASD] Drive   [Space] Brake   [H] Horn   [E] Exit"
    elseif isJet then
        modeIcon.Text = "JET"
        controlHints.Text = "[WASD] Move   [Space] Up   [Shift] Down   [J] Off"
    elseif isChute then
        modeIcon.Text = "GLI"
        controlHints.Text = "[A/D] Steer   [S] Flare   [P] Cut away"
    else
        modeIcon.Text = ""
        controlHints.Text = "[V] Car   [J] Jetpack   [P] Parachute"
    end

    -- Show hints, start fade timer
    controlHintTimer = HUD_FADE_DELAY
    if not controlHintsVisible then
        controlHintsVisible = true
        tweenProperty(controlHints, { TextTransparency = 0, BackgroundTransparency = 0.4 }, 0.3)
    end
end

local function updateHUDValues(dt)
    -- Control hints fade
    if controlHintTimer > 0 then
        controlHintTimer = controlHintTimer - dt
        if controlHintTimer <= 0 and controlHintsVisible then
            controlHintsVisible = false
            tweenProperty(controlHints, { TextTransparency = 1, BackgroundTransparency = 1 }, 0.8)
        end
    end

    local hrp = getHRP()
    if not hrp then return end

    -- Speed (car)
    if mode == "car" and carBody then
        local speed = carBody.AssemblyLinearVelocity.Magnitude
        speedLabel.Text = string.format("%d km/h", math.floor(speed * 0.5))
    end

    -- Altitude
    if mode == "jetpack" or mode == "parachute" then
        altLabel.Text = string.format("ALT %d", math.floor(hrp.Position.Y))
    end

    -- Fuel bar
    if mode == "jetpack" then
        local frac = math.clamp(jetpackFuel / JETPACK_FUEL_MAX, 0, 1)
        fuelBarFill.Size = UDim2.new(frac, -4 * (1 - frac), 1, -4)
        if frac < 0.2 then
            fuelBarFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
        elseif frac < 0.5 then
            fuelBarFill.BackgroundColor3 = Color3.fromRGB(255, 180, 50)
        else
            fuelBarFill.BackgroundColor3 = HUD_ACCENT_COLOR
        end
    end
end

--------------------------------------------------------------------------------
-- CAR CONSTRUCTION
--------------------------------------------------------------------------------
local function createCarBody(spawnCF)
    local model = Instance.new("Model")
    model.Name = "PlayerCar"

    -- Main chassis (lower body, heavy for stability)
    local chassis = Instance.new("Part")
    chassis.Name = "Chassis"
    chassis.Size = Vector3.new(7, 1.5, 15)
    chassis.Material = Enum.Material.SmoothPlastic
    chassis.Color = Color3.fromRGB(25, 25, 30)
    chassis.CFrame = spawnCF * CFrame.new(0, 1.2, 0)
    chassis.Anchored = false
    chassis.CustomPhysicalProperties = PhysicalProperties.new(8, 0.3, 0.1, 1, 1) -- heavy bottom
    chassis.Parent = model
    tagPart(chassis, CAR_TAG)

    -- Upper body shell
    local bodyLower = Instance.new("Part")
    bodyLower.Name = "BodyLower"
    bodyLower.Size = Vector3.new(7.4, 2.2, 15.2)
    bodyLower.Material = Enum.Material.SmoothPlastic
    bodyLower.Color = Color3.fromRGB(180, 28, 28)
    bodyLower.CFrame = spawnCF * CFrame.new(0, 2.8, 0)
    bodyLower.Anchored = false
    bodyLower.CanCollide = false
    bodyLower.Massless = true
    bodyLower.Parent = model
    tagPart(bodyLower, CAR_TAG)
    local bw1 = Instance.new("WeldConstraint")
    bw1.Part0 = chassis
    bw1.Part1 = bodyLower
    bw1.Parent = chassis

    -- Hood (sloped front)
    local hood = Instance.new("Part")
    hood.Name = "Hood"
    hood.Size = Vector3.new(6.8, 1.0, 5)
    hood.Material = Enum.Material.SmoothPlastic
    hood.Color = Color3.fromRGB(175, 25, 25)
    hood.CFrame = spawnCF * CFrame.new(0, 3.6, -5.5) * CFrame.Angles(math.rad(-12), 0, 0)
    hood.Anchored = false
    hood.CanCollide = false
    hood.Massless = true
    hood.Parent = model
    tagPart(hood, CAR_TAG)
    local hw = Instance.new("WeldConstraint")
    hw.Part0 = chassis
    hw.Part1 = hood
    hw.Parent = chassis

    -- Trunk (slightly sloped rear)
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Size = Vector3.new(6.8, 0.8, 4)
    trunk.Material = Enum.Material.SmoothPlastic
    trunk.Color = Color3.fromRGB(175, 25, 25)
    trunk.CFrame = spawnCF * CFrame.new(0, 3.6, 5) * CFrame.Angles(math.rad(6), 0, 0)
    trunk.Anchored = false
    trunk.CanCollide = false
    trunk.Massless = true
    trunk.Parent = model
    tagPart(trunk, CAR_TAG)
    local tw = Instance.new("WeldConstraint")
    tw.Part0 = chassis
    tw.Part1 = trunk
    tw.Parent = chassis

    -- Roof / cabin
    local cabin = Instance.new("Part")
    cabin.Name = "Cabin"
    cabin.Size = Vector3.new(6.6, 2.2, 6)
    cabin.Material = Enum.Material.SmoothPlastic
    cabin.Color = Color3.fromRGB(165, 22, 22)
    cabin.CFrame = spawnCF * CFrame.new(0, 5, 0.5)
    cabin.Anchored = false
    cabin.CanCollide = false
    cabin.Massless = true
    cabin.Parent = model
    tagPart(cabin, CAR_TAG)
    local cw = Instance.new("WeldConstraint")
    cw.Part0 = chassis
    cw.Part1 = cabin
    cw.Parent = chassis

    -- Windshield (glass, transparent, angled)
    local windshield = Instance.new("Part")
    windshield.Name = "Windshield"
    windshield.Size = Vector3.new(6.2, 2.4, 0.2)
    windshield.Material = Enum.Material.Glass
    windshield.Color = Color3.fromRGB(180, 210, 235)
    windshield.Transparency = 0.6
    windshield.CFrame = spawnCF * CFrame.new(0, 5, -2.6) * CFrame.Angles(math.rad(-20), 0, 0)
    windshield.Anchored = false
    windshield.CanCollide = false
    windshield.Massless = true
    windshield.Parent = model
    tagPart(windshield, CAR_TAG)
    local wsw = Instance.new("WeldConstraint")
    wsw.Part0 = chassis
    wsw.Part1 = windshield
    wsw.Parent = chassis

    -- Rear windshield
    local rearGlass = Instance.new("Part")
    rearGlass.Name = "RearGlass"
    rearGlass.Size = Vector3.new(6.2, 2.0, 0.2)
    rearGlass.Material = Enum.Material.Glass
    rearGlass.Color = Color3.fromRGB(170, 200, 225)
    rearGlass.Transparency = 0.65
    rearGlass.CFrame = spawnCF * CFrame.new(0, 5, 3.6) * CFrame.Angles(math.rad(15), 0, 0)
    rearGlass.Anchored = false
    rearGlass.CanCollide = false
    rearGlass.Massless = true
    rearGlass.Parent = model
    tagPart(rearGlass, CAR_TAG)
    local rgw = Instance.new("WeldConstraint")
    rgw.Part0 = chassis
    rgw.Part1 = rearGlass
    rgw.Parent = chassis

    -- Dashboard (visible through windshield)
    local dashboard = Instance.new("Part")
    dashboard.Name = "Dashboard"
    dashboard.Size = Vector3.new(5.8, 0.6, 2)
    dashboard.Material = Enum.Material.SmoothPlastic
    dashboard.Color = Color3.fromRGB(40, 40, 45)
    dashboard.CFrame = spawnCF * CFrame.new(0, 3.8, -1.5)
    dashboard.Anchored = false
    dashboard.CanCollide = false
    dashboard.Massless = true
    dashboard.Parent = model
    tagPart(dashboard, CAR_TAG)
    local dw = Instance.new("WeldConstraint")
    dw.Part0 = chassis
    dw.Part1 = dashboard
    dw.Parent = chassis

    -- VehicleSeat
    local seat = Instance.new("VehicleSeat")
    seat.Name = "DriveSeat"
    seat.Size = Vector3.new(4, 0.5, 3)
    seat.CFrame = spawnCF * CFrame.new(0, 2.5, 0.5)
    seat.Anchored = false
    seat.CanCollide = false
    seat.Massless = true
    seat.MaxSpeed = CAR_MAX_SPEED
    seat.Torque = 0  -- we drive motors manually
    seat.TurnSpeed = 0
    seat.Parent = model
    tagPart(seat, CAR_TAG)
    local sw = Instance.new("WeldConstraint")
    sw.Part0 = chassis
    sw.Part1 = seat
    sw.Parent = chassis

    -- Anti-flip gyro
    local gyro = Instance.new("BodyGyro")
    gyro.MaxTorque = Vector3.new(80000, 0, 80000)
    gyro.P = 6000
    gyro.D = 500
    gyro.CFrame = chassis.CFrame
    gyro.Parent = chassis

    -- Engine idle vibration
    local idleVib = Instance.new("BodyPosition")
    idleVib.MaxForce = Vector3.new(0, 50, 0)
    idleVib.P = 5000
    idleVib.D = 200
    idleVib.Position = chassis.Position
    idleVib.Parent = chassis

    -- Headlights
    for _, side in ipairs({ -2.5, 2.5 }) do
        local light = Instance.new("Part")
        light.Name = "Headlight"
        light.Shape = Enum.PartType.Ball
        light.Size = Vector3.new(1.2, 1.2, 1.2)
        light.Material = Enum.Material.Neon
        light.Color = Color3.fromRGB(255, 250, 230)
        light.CFrame = spawnCF * CFrame.new(side, 2.8, -7.8)
        light.Anchored = false
        light.CanCollide = false
        light.Massless = true
        light.Parent = model
        tagPart(light, CAR_TAG)
        local lw = Instance.new("WeldConstraint")
        lw.Part0 = chassis
        lw.Part1 = light
        lw.Parent = chassis

        local spot = Instance.new("SpotLight")
        spot.Range = 80
        spot.Brightness = 3
        spot.Angle = 50
        spot.Face = Enum.NormalId.Front
        spot.Color = Color3.fromRGB(255, 248, 225)
        spot.Parent = light
    end

    -- Brake / tail lights
    local brakeLights = {}
    for _, side in ipairs({ -2.8, 2.8 }) do
        local tail = Instance.new("Part")
        tail.Name = "BrakeLight"
        tail.Size = Vector3.new(1.6, 0.9, 0.3)
        tail.Material = Enum.Material.Neon
        tail.Color = Color3.fromRGB(80, 10, 10) -- dim by default
        tail.CFrame = spawnCF * CFrame.new(side, 2.8, 7.8)
        tail.Anchored = false
        tail.CanCollide = false
        tail.Massless = true
        tail.Parent = model
        tagPart(tail, CAR_TAG)
        local tlw = Instance.new("WeldConstraint")
        tlw.Part0 = chassis
        tlw.Part1 = tail
        tlw.Parent = chassis
        table.insert(brakeLights, tail)
    end

    -- Turn signal lights
    for _, data in ipairs({
        { side = -3.6, name = "TurnL" },
        { side = 3.6, name = "TurnR" },
    }) do
        local sig = Instance.new("Part")
        sig.Name = data.name
        sig.Size = Vector3.new(0.4, 0.6, 0.3)
        sig.Material = Enum.Material.Neon
        sig.Color = Color3.fromRGB(60, 40, 5) -- dim amber
        sig.CFrame = spawnCF * CFrame.new(data.side, 2.8, -7.5)
        sig.Anchored = false
        sig.CanCollide = false
        sig.Massless = true
        sig.Parent = model
        tagPart(sig, CAR_TAG)
        local sigw = Instance.new("WeldConstraint")
        sigw.Part0 = chassis
        sigw.Part1 = sig
        sigw.Parent = chassis
    end

    -- Exhaust particles
    local exhaustAttach = Instance.new("Attachment")
    exhaustAttach.Position = Vector3.new(2, 0.5, 7.8)
    exhaustAttach.Parent = chassis

    local exhaust = Instance.new("ParticleEmitter")
    exhaust.Rate = 15
    exhaust.Speed = NumberRange.new(2, 5)
    exhaust.Lifetime = NumberRange.new(0.4, 1.0)
    exhaust.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1.2),
    })
    exhaust.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 120, 130)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 80, 85)),
    })
    exhaust.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    exhaust.LightEmission = 0
    exhaust.SpreadAngle = Vector2.new(10, 10)
    exhaust.Parent = exhaustAttach

    -- Sounds
    local engineSnd = makeSound(chassis, "Engine", true, 0.4)
    -- Search: "car engine idle loop"
    local screechSnd = makeSound(chassis, "TireScreech", false, 0.3)
    -- Search: "tire screech drift"
    local hornSnd = makeSound(chassis, "Horn", false, 0.6)
    -- Search: "car horn honk"

    model.PrimaryPart = chassis

    return {
        model = model,
        chassis = chassis,
        seat = seat,
        gyro = gyro,
        idleVib = idleVib,
        brakeLights = brakeLights,
        exhaust = exhaust,
        engineSound = engineSnd,
        screechSound = screechSnd,
        hornSound = hornSnd,
    }
end

local function createWheelWithSuspension(model, chassis, spawnCF, offset, isFront)
    -- Wheel axle (invisible anchor for suspension)
    local axle = Instance.new("Part")
    axle.Name = "Axle_" .. tostring(offset)
    axle.Size = Vector3.new(0.5, 0.5, 0.5)
    axle.Transparency = 1
    axle.CanCollide = false
    axle.Massless = true
    axle.CFrame = spawnCF * CFrame.new(offset)
    axle.Anchored = false
    axle.Parent = model
    tagPart(axle, CAR_TAG)

    -- Wheel part
    local wheel = Instance.new("Part")
    wheel.Name = "Wheel"
    wheel.Shape = Enum.PartType.Cylinder
    wheel.Size = Vector3.new(2.2, 2.8, 2.8)
    wheel.Material = Enum.Material.SmoothPlastic
    wheel.Color = Color3.fromRGB(30, 30, 35)
    wheel.CFrame = spawnCF * CFrame.new(offset) * CFrame.Angles(0, 0, math.pi / 2)
    wheel.Anchored = false
    wheel.CustomPhysicalProperties = PhysicalProperties.new(
        isFront and 1.5 or (1.5 * (1 - DRIFT_GRIP_REDUCTION * 0.3)),
        isFront and 1.2 or 0.6,   -- rear wheels: less friction for drift
        0.15, 1, 1
    )
    wheel.Parent = model
    tagPart(wheel, CAR_TAG)

    -- Hub cap (visual detail)
    local hub = Instance.new("Part")
    hub.Name = "Hub"
    hub.Shape = Enum.PartType.Cylinder
    hub.Size = Vector3.new(0.3, 2.0, 2.0)
    hub.Material = Enum.Material.Metal
    hub.Color = Color3.fromRGB(160, 165, 175)
    hub.CFrame = wheel.CFrame
    hub.Anchored = false
    hub.CanCollide = false
    hub.Massless = true
    hub.Parent = model
    tagPart(hub, CAR_TAG)
    local hubWeld = Instance.new("WeldConstraint")
    hubWeld.Part0 = wheel
    hubWeld.Part1 = hub
    hubWeld.Parent = wheel

    -- Suspension: SpringConstraint between chassis and axle
    local chassisAttach = Instance.new("Attachment")
    chassisAttach.Position = offset + Vector3.new(0, 0.5, 0)
    chassisAttach.Parent = chassis

    local axleAttach = Instance.new("Attachment")
    axleAttach.Position = Vector3.new(0, 0, 0)
    axleAttach.Parent = axle

    local spring = Instance.new("SpringConstraint")
    spring.Attachment0 = chassisAttach
    spring.Attachment1 = axleAttach
    spring.FreeLength = SUSPENSION_REST_LENGTH
    spring.Stiffness = SUSPENSION_STIFFNESS
    spring.Damping = SUSPENSION_DAMPING
    spring.LimitsEnabled = true
    spring.MinLength = 0.5
    spring.MaxLength = 2.5
    spring.Visible = false
    spring.Parent = chassis

    -- Prismatic constraint to keep wheel under the chassis (vertical only)
    local prismatic = Instance.new("PrismaticConstraint")
    prismatic.Attachment0 = chassisAttach
    prismatic.Attachment1 = axleAttach
    prismatic.LimitsEnabled = true
    prismatic.LowerLimit = -1.5
    prismatic.UpperLimit = 0.5
    prismatic.Parent = chassis

    -- Motor: CylindricalConstraint for spinning
    local motorAttach0 = Instance.new("Attachment")
    motorAttach0.Parent = axle

    local motorAttach1 = Instance.new("Attachment")
    motorAttach1.Parent = wheel

    local motor = Instance.new("CylindricalConstraint")
    motor.Attachment0 = motorAttach0
    motor.Attachment1 = motorAttach1
    motor.MotorType = Enum.ActuatorType.Motor
    motor.AngularVelocity = 0
    motor.MotorMaxTorque = CAR_TORQUE
    motor.MotorMaxAngularAcceleration = 200
    motor.InclinationAngle = 90
    motor.RotationAxisVisible = false
    motor.Parent = axle

    -- Steering hinge (front wheels only)
    local steerHinge = nil
    if isFront then
        local hingeA0 = Instance.new("Attachment")
        hingeA0.Parent = chassis
        hingeA0.CFrame = CFrame.new(offset)

        local hingeA1 = Instance.new("Attachment")
        hingeA1.Parent = axle

        steerHinge = Instance.new("HingeConstraint")
        steerHinge.Attachment0 = hingeA0
        steerHinge.Attachment1 = hingeA1
        steerHinge.ActuatorType = Enum.ActuatorType.Servo
        steerHinge.TargetAngle = 0
        steerHinge.AngularSpeed = math.rad(120)
        steerHinge.ServoMaxTorque = 20000
        steerHinge.LimitsEnabled = true
        steerHinge.LowerAngle = -CAR_STEER_ANGLE
        steerHinge.UpperAngle = CAR_STEER_ANGLE
        steerHinge.Parent = chassis
    else
        -- Rear wheels: weld axle to chassis with spring only (no steering)
        -- The prismatic + spring handles vertical motion
    end

    return {
        part = wheel,
        axle = axle,
        motor = motor,
        spring = spring,
        steerHinge = steerHinge,
        isFront = isFront,
    }
end

local function spawnCar()
    local hrp = getHRP()
    if not hrp then return end

    local spawnPos = hrp.Position + hrp.CFrame.LookVector * 14
    local spawnCF = CFrame.new(spawnPos)

    local carData = createCarBody(spawnCF)
    local mdl = carData.model
    local chassis = carData.chassis

    -- Create wheels with suspension
    local wheelOffsets = {
        { offset = Vector3.new(-3.5, -0.5, -5.5), front = true },
        { offset = Vector3.new(3.5, -0.5, -5.5), front = true },
        { offset = Vector3.new(-3.5, -0.5, 5.5), front = false },
        { offset = Vector3.new(3.5, -0.5, 5.5), front = false },
    }

    local wheels = {}
    for _, wd in ipairs(wheelOffsets) do
        local w = createWheelWithSuspension(mdl, chassis, spawnCF, wd.offset, wd.front)
        table.insert(wheels, w)
    end

    mdl.Parent = workspace

    carModel = mdl
    carBody = chassis
    carSeat = carData.seat
    carWheels = wheels
    carBrakeLights = carData.brakeLights
    carExhaustEmitter = carData.exhaust
    carEngineSound = carData.engineSound
    carTireScreechSound = carData.screechSound
    carHornSound = carData.hornSound
    carGyro = carData.gyro
    carIdleVibration = carData.idleVib
    carSteerAngle = 0
    carPrevSpeed = 0
    carIsBraking = false

    -- Start engine sound
    carEngineSound:Play()

    return carData.seat
end

local function destroyCar()
    if carModel then
        -- Fade out engine
        if carEngineSound and carEngineSound.IsPlaying then
            tweenProperty(carEngineSound, { Volume = 0 }, 0.3)
            task.delay(0.35, function()
                if carModel then
                    carModel:Destroy()
                end
            end)
        else
            carModel:Destroy()
        end
    end

    carModel = nil
    carBody = nil
    carSeat = nil
    carWheels = {}
    carBrakeLights = {}
    carExhaustEmitter = nil
    carEngineSound = nil
    carTireScreechSound = nil
    carHornSound = nil
    carGyro = nil
    carIdleVibration = nil
    cleanupByTag(CAR_TAG)
end

local function enterCar(seat)
    local hum = getHumanoid()
    if not hum or not seat then return end

    -- Tween player toward seat before sitting
    local hrp = getHRP()
    if hrp then
        local targetCF = seat.CFrame * CFrame.new(0, 1, 0)
        local entryTween = tweenProperty(hrp, { CFrame = targetCF }, 0.25, Enum.EasingStyle.Quad)
        entryTween.Completed:Wait()
    end

    seat:Sit(hum)
    mode = "car"
    customCamActive = true
    setHUDMode("car")
end

local function exitCar()
    local hum = getHumanoid()
    if hum then
        hum.Sit = false
        -- Small upward impulse on exit
        local hrp = getHRP()
        if hrp then
            task.defer(function()
                hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + Vector3.new(0, 10, 0)
            end)
        end
    end
    mode = "none"
    customCamActive = false
    camera.CameraType = Enum.CameraType.Custom
    camera.FieldOfView = DEFAULT_FOV
    setHUDMode("none")
end

--------------------------------------------------------------------------------
-- CAR UPDATE (per-frame)
--------------------------------------------------------------------------------
local function updateCar(dt)
    if mode ~= "car" or not carBody or not carSeat then return end

    local throttle = carSeat.ThrottleFloat  -- -1 to 1 from VehicleSeat
    local steer = carSeat.SteerFloat        -- -1 to 1

    local velocity = carBody.AssemblyLinearVelocity
    local speed = velocity.Magnitude
    local forwardSpeed = carBody.CFrame.LookVector:Dot(velocity)

    -- Steering
    local targetSteer = steer * CAR_STEER_ANGLE
    carSteerAngle = lerp(carSteerAngle, targetSteer, dt * CAR_STEER_SPEED)

    -- Handbrake (space)
    local handbrake = UserInputService:IsKeyDown(Enum.KeyCode.Space)

    -- Update wheels
    for _, w in ipairs(carWheels) do
        -- Motor drive
        local motorSpeed = throttle * CAR_MAX_SPEED * 0.5 -- angular velocity
        if handbrake and not w.isFront then
            -- Lock rear wheels for drift
            w.motor.AngularVelocity = 0
            w.motor.MotorMaxTorque = CAR_TORQUE * 5  -- strong lock
        else
            w.motor.AngularVelocity = motorSpeed
            w.motor.MotorMaxTorque = CAR_TORQUE
        end

        -- Steering (front wheels)
        if w.steerHinge then
            w.steerHinge.TargetAngle = carSteerAngle
        end
    end

    -- Brake lights: activate on deceleration or handbrake
    local decelerating = speed > 2 and (speed < carPrevSpeed - 0.5 or throttle < -0.1)
    carIsBraking = decelerating or handbrake
    for _, bl in ipairs(carBrakeLights) do
        bl.Color = carIsBraking
            and Color3.fromRGB(255, 20, 20)
            or Color3.fromRGB(80, 10, 10)
    end

    -- Turn signals
    if carModel then
        local turnL = carModel:FindFirstChild("TurnL")
        local turnR = carModel:FindFirstChild("TurnR")
        if turnL then
            turnL.Color = (steer < -0.5)
                and Color3.fromRGB(255, 180, 20)
                or Color3.fromRGB(60, 40, 5)
        end
        if turnR then
            turnR.Color = (steer > 0.5)
                and Color3.fromRGB(255, 180, 20)
                or Color3.fromRGB(60, 40, 5)
        end
    end

    -- Exhaust: more particles when accelerating
    if carExhaustEmitter then
        carExhaustEmitter.Rate = math.abs(throttle) > 0.1 and 40 or 12
    end

    -- Engine sound pitch scales with speed
    if carEngineSound then
        carEngineSound.PlaybackSpeed = 0.8 + (speed / CAR_MAX_SPEED) * 1.2
        carEngineSound.Volume = 0.3 + (speed / CAR_MAX_SPEED) * 0.4
    end

    -- Tire screech on hard turns at speed or handbrake
    if carTireScreechSound then
        local shouldScreech = (math.abs(steer) > 0.7 and speed > 30) or (handbrake and speed > 15)
        if shouldScreech and not carTireScreechSound.IsPlaying then
            carTireScreechSound:Play()
        elseif not shouldScreech and carTireScreechSound.IsPlaying then
            carTireScreechSound:Stop()
        end
    end

    -- Anti-flip gyro: keep upright
    if carGyro then
        carGyro.CFrame = CFrame.new(carBody.Position) * CFrame.Angles(0, select(2, carBody.CFrame:ToEulerAnglesYXZ()), 0)
    end

    -- Engine idle vibration
    if carIdleVibration then
        local vibAmt = ENGINE_IDLE_VIBRATION * (1 + speed * 0.005)
        carIdleVibration.Position = carBody.Position + Vector3.new(0, math.sin(tick() * 30) * vibAmt, 0)
    end

    carPrevSpeed = speed

    -- Chase camera
    if customCamActive then
        local carCF = carBody.CFrame
        local targetPos = (carCF * CFrame.new(
            -steer * 2,  -- slight offset into turn
            CAR_CAM_OFFSET.Y,
            CAR_CAM_OFFSET.Z
        )).Position

        if camCurrentPos then
            camCurrentPos = lerpVector3(camCurrentPos, targetPos, CAR_CAM_LERP)
        else
            camCurrentPos = targetPos
        end

        -- Tilt into turns
        local tiltAngle = -steer * CAR_CAM_TILT_FACTOR
        local lookTarget = carCF.Position + carCF.LookVector * 20

        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.new(camCurrentPos, lookTarget) * CFrame.Angles(0, 0, tiltAngle)

        -- Speed-based FOV
        local fovTarget = CAR_FOV_MIN + (speed / CAR_FOV_SPEED_RANGE) * (CAR_FOV_MAX - CAR_FOV_MIN)
        camTargetFOV = math.clamp(fovTarget, CAR_FOV_MIN, CAR_FOV_MAX)
        camera.FieldOfView = lerp(camera.FieldOfView, camTargetFOV, 0.05)
    end
end

--------------------------------------------------------------------------------
-- JETPACK CONSTRUCTION
--------------------------------------------------------------------------------
local function deployJetpack()
    local hrp = getHRP()
    local char = getCharacter()
    if not hrp or not char then return end

    jetpackActive = true
    jetpackThrustLevel = 0

    -- Backpack model
    local pack = Instance.new("Part")
    pack.Name = "JetpackBody"
    pack.Size = Vector3.new(3, 3.5, 1.5)
    pack.Material = Enum.Material.Metal
    pack.Color = Color3.fromRGB(60, 62, 68)
    pack.CFrame = hrp.CFrame * CFrame.new(0, 0, 1)
    pack.Anchored = false
    pack.CanCollide = false
    pack.Massless = true
    pack.Parent = char
    tagPart(pack, JETPACK_TAG)
    local packWeld = Instance.new("WeldConstraint")
    packWeld.Part0 = hrp
    packWeld.Part1 = pack
    packWeld.Parent = hrp
    table.insert(jetpackParts, pack)

    -- Nozzles
    for _, offset in ipairs({ Vector3.new(-0.8, -1.5, 0.3), Vector3.new(0.8, -1.5, 0.3) }) do
        local nozzle = Instance.new("Part")
        nozzle.Name = "Nozzle"
        nozzle.Shape = Enum.PartType.Cylinder
        nozzle.Size = Vector3.new(1.2, 0.8, 0.8)
        nozzle.Material = Enum.Material.Metal
        nozzle.Color = Color3.fromRGB(45, 45, 50)
        nozzle.CFrame = pack.CFrame * CFrame.new(offset) * CFrame.Angles(math.rad(90), 0, 0)
        nozzle.Anchored = false
        nozzle.CanCollide = false
        nozzle.Massless = true
        nozzle.Parent = char
        tagPart(nozzle, JETPACK_TAG)
        local nw = Instance.new("WeldConstraint")
        nw.Part0 = pack
        nw.Part1 = nozzle
        nw.Parent = pack
        table.insert(jetpackNozzles, nozzle)

        -- Flame particles per nozzle
        local attach = Instance.new("Attachment")
        attach.Position = Vector3.new(0, -0.5, 0)
        attach.Parent = nozzle

        local emitter = Instance.new("ParticleEmitter")
        emitter.Rate = 120
        emitter.Speed = NumberRange.new(12, 25)
        emitter.Lifetime = NumberRange.new(0.15, 0.4)
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1.8),
            NumberSequenceKeypoint.new(0.3, 1.0),
            NumberSequenceKeypoint.new(1, 0),
        })
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(130, 180, 255)),    -- blue core
            ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 200, 60)),   -- orange mantle
            ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 100, 20)),   -- deep orange
            ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 40, 20)),       -- dark smoke tip
        })
        emitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.6, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        emitter.LightEmission = 1
        emitter.LightInfluence = 0
        emitter.SpreadAngle = Vector2.new(8, 8)
        emitter.Parent = attach
        table.insert(jetpackEmitters, emitter)

        -- Heat shimmer (second emitter with high LightEmission)
        local shimmer = Instance.new("ParticleEmitter")
        shimmer.Rate = 40
        shimmer.Speed = NumberRange.new(5, 10)
        shimmer.Lifetime = NumberRange.new(0.3, 0.6)
        shimmer.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 3),
            NumberSequenceKeypoint.new(1, 5),
        })
        shimmer.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.85),
            NumberSequenceKeypoint.new(1, 1),
        })
        shimmer.LightEmission = 1
        shimmer.LightInfluence = 0
        shimmer.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200))
        shimmer.Parent = attach

        -- Nozzle glow
        local glow = Instance.new("PointLight")
        glow.Range = 12
        glow.Brightness = 2
        glow.Color = Color3.fromRGB(255, 180, 60)
        glow.Parent = nozzle
        table.insert(jetpackLights, glow)
    end

    -- Trail
    local trailA0 = Instance.new("Attachment")
    trailA0.Position = Vector3.new(-1, -2, 1)
    trailA0.Parent = hrp
    tagPart(trailA0, JETPACK_TAG)

    local trailA1 = Instance.new("Attachment")
    trailA1.Position = Vector3.new(1, -2, 1)
    trailA1.Parent = hrp
    tagPart(trailA1, JETPACK_TAG)

    local trail = Instance.new("Trail")
    trail.Attachment0 = trailA0
    trail.Attachment1 = trailA1
    trail.Lifetime = 0.8
    trail.MinLength = 0.1
    trail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 60, 20)),
    })
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.LightEmission = 0.5
    trail.FaceCamera = true
    trail.Parent = hrp
    table.insert(jetpackTrails, trail)
    table.insert(jetpackTrails, trailA0)
    table.insert(jetpackTrails, trailA1)

    -- Physics force
    jetpackForce = Instance.new("BodyForce")
    jetpackForce.Force = Vector3.new(0, 0, 0)
    jetpackForce.Parent = hrp
    tagPart(jetpackForce, JETPACK_TAG)

    -- Sounds
    jetpackThrustSound = makeSound(hrp, "JetThrust", true, 0.3)
    -- Search: "rocket engine loop", "jet thrust loop"
    jetpackThrustSound:Play()
    tagPart(jetpackThrustSound, JETPACK_TAG)

    jetpackWindSound = makeSound(hrp, "JetWind", true, 0)
    -- Search: "wind rushing loop", "high speed wind"
    jetpackWindSound:Play()
    tagPart(jetpackWindSound, JETPACK_TAG)

    -- Startup whoosh
    local startupSnd = makeSound(hrp, "JetStart", false, 0.5)
    -- Search: "whoosh", "jet startup"
    startupSnd:Play()
    Debris:AddItem(startupSnd, 2)

    mode = "jetpack"
    customCamActive = true
    setHUDMode("jetpack")
end

local function cleanupJetpack()
    if not jetpackActive then return end
    jetpackActive = false

    -- Shutdown sound
    local hrp = getHRP()
    if hrp then
        local shutdownSnd = makeSound(hrp, "JetStop", false, 0.4)
        shutdownSnd:Play()
        Debris:AddItem(shutdownSnd, 2)
    end

    -- Cleanup all tagged parts
    cleanupByTag(JETPACK_TAG)

    jetpackForce = nil
    jetpackParts = {}
    jetpackNozzles = {}
    jetpackEmitters = {}
    jetpackLights = {}
    jetpackTrails = {}
    jetpackThrustSound = nil
    jetpackWindSound = nil
    jetpackThrustLevel = 0

    if mode == "jetpack" then
        mode = "none"
        customCamActive = false
        camera.CameraType = Enum.CameraType.Custom
        camera.FieldOfView = DEFAULT_FOV
        setHUDMode("none")
    end
end

--------------------------------------------------------------------------------
-- JETPACK UPDATE (per-frame)
--------------------------------------------------------------------------------
local function updateJetpack(dt)
    if not jetpackActive or not jetpackForce then return end

    local hrp = getHRP()
    if not hrp then return end

    -- Fuel
    jetpackFuel = jetpackFuel - dt
    if jetpackFuel <= 0 then
        jetpackFuel = 0
        cleanupJetpack()
        return
    end

    -- Input
    local cam = workspace.CurrentCamera
    local look = cam.CFrame.LookVector
    local right = cam.CFrame.RightVector

    local thrustDir = Vector3.new(0, 0, 0)
    local isThrusting = false

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        thrustDir = thrustDir + Vector3.new(look.X, 0, look.Z).Unit
        isThrusting = true
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        thrustDir = thrustDir - Vector3.new(look.X, 0, look.Z).Unit
        isThrusting = true
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        thrustDir = thrustDir - Vector3.new(right.X, 0, right.Z).Unit
        isThrusting = true
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        thrustDir = thrustDir + Vector3.new(right.X, 0, right.Z).Unit
        isThrusting = true
    end

    local verticalThrust = 0
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        verticalThrust = 1
        isThrusting = true
    elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        verticalThrust = -0.5
        isThrusting = true
    end

    -- Thrust ramp (gradual buildup over JETPACK_RAMP_TIME)
    if isThrusting then
        jetpackThrustLevel = math.min(1, jetpackThrustLevel + dt / JETPACK_RAMP_TIME)
    else
        jetpackThrustLevel = math.max(0, jetpackThrustLevel - dt / (JETPACK_RAMP_TIME * 2))
    end

    -- Calculate force
    local mass = hrp.AssemblyMass
    local gravityCompensation = Vector3.new(0, mass * workspace.Gravity, 0)

    local horizontalForce = Vector3.new(0, 0, 0)
    if thrustDir.Magnitude > 0.01 then
        horizontalForce = thrustDir.Unit * JETPACK_MAX_THRUST * jetpackThrustLevel
    end

    local verticalForce = Vector3.new(0, verticalThrust * JETPACK_MAX_THRUST * jetpackThrustLevel, 0)

    -- Hover when idle (counteract gravity + small oscillation)
    local hoverForce = Vector3.new(0, 0, 0)
    if not isThrusting then
        hoverForce = gravityCompensation + Vector3.new(0, math.sin(tick() * 3) * 40, 0)
    else
        hoverForce = gravityCompensation * 0.95  -- partial gravity compensation when thrusting
    end

    -- Air resistance / damping at high speed
    local vel = hrp.AssemblyLinearVelocity
    local dampingForce = -vel * mass * (1 - JETPACK_DAMPING)

    jetpackForce.Force = horizontalForce + verticalForce + hoverForce + dampingForce

    -- Character tilt based on movement
    -- (Uses a subtle approach: adjust the force direction slightly)

    -- Particle intensity scales with thrust
    for _, em in ipairs(jetpackEmitters) do
        em.Rate = 40 + jetpackThrustLevel * 160
        local baseSize = 0.5 + jetpackThrustLevel * 1.5
        em.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, baseSize),
            NumberSequenceKeypoint.new(0.3, baseSize * 0.6),
            NumberSequenceKeypoint.new(1, 0),
        })
        em.Speed = NumberRange.new(5 + jetpackThrustLevel * 20, 10 + jetpackThrustLevel * 25)
    end

    -- Nozzle glow intensity
    for _, gl in ipairs(jetpackLights) do
        gl.Brightness = 0.5 + jetpackThrustLevel * 3
        gl.Range = 6 + jetpackThrustLevel * 10
    end

    -- Sound: pitch and volume scale with thrust
    if jetpackThrustSound then
        jetpackThrustSound.Volume = 0.15 + jetpackThrustLevel * 0.5
        jetpackThrustSound.PlaybackSpeed = 0.7 + jetpackThrustLevel * 0.8
    end

    -- Wind sound at high speed
    if jetpackWindSound then
        local speedFrac = math.clamp(vel.Magnitude / 100, 0, 1)
        jetpackWindSound.Volume = speedFrac * 0.4
        jetpackWindSound.PlaybackSpeed = 0.8 + speedFrac * 0.4
    end

    -- Camera
    if customCamActive then
        local targetPos = (hrp.CFrame * CFrame.new(
            0,
            JETPACK_CAM_OFFSET.Y,
            JETPACK_CAM_OFFSET.Z
        )).Position

        if camCurrentPos then
            camCurrentPos = lerpVector3(camCurrentPos, targetPos, JETPACK_CAM_LERP)
        else
            camCurrentPos = targetPos
        end

        -- Slight shake at full thrust
        local shake = Vector3.new(0, 0, 0)
        if jetpackThrustLevel > 0.7 then
            local shakeAmt = (jetpackThrustLevel - 0.7) / 0.3 * JETPACK_CAM_SHAKE_INTENSITY
            shake = Vector3.new(
                (math.random() - 0.5) * shakeAmt,
                (math.random() - 0.5) * shakeAmt,
                0
            )
        end

        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.new(camCurrentPos + shake, hrp.Position + hrp.CFrame.LookVector * 10)

        -- Pull FOV back slightly
        local jetFov = DEFAULT_FOV + jetpackThrustLevel * 8
        camera.FieldOfView = lerp(camera.FieldOfView, jetFov, 0.05)
    end
end

--------------------------------------------------------------------------------
-- PARACHUTE CONSTRUCTION
--------------------------------------------------------------------------------
local function deployParachute()
    local hrp = getHRP()
    local hum = getHumanoid()
    local char = getCharacter()
    if not hrp or not hum or not char then return end

    -- Only deploy when falling
    if hrp.AssemblyLinearVelocity.Y > -5 then return end

    chuteActive = true
    chuteStalled = false
    chuteStallTimer = 0
    chuteHeading = select(2, hrp.CFrame:ToEulerAnglesYXZ())

    -- Random wind offset
    chuteWindOffset = Vector3.new(
        (math.random() - 0.5) * CHUTE_WIND_STRENGTH * 2,
        0,
        (math.random() - 0.5) * CHUTE_WIND_STRENGTH * 2
    )

    -- Rectangular canopy from multiple panels
    local canopyRoot = Instance.new("Part")
    canopyRoot.Name = "CanopyRoot"
    canopyRoot.Size = Vector3.new(1, 1, 1)
    canopyRoot.Transparency = 1
    canopyRoot.CanCollide = false
    canopyRoot.Massless = true
    canopyRoot.Anchored = false
    canopyRoot.CFrame = hrp.CFrame * CFrame.new(0, 18, 0)
    canopyRoot.Parent = char
    tagPart(canopyRoot, PARACHUTE_TAG)

    -- Weld canopy root to follow player (via RodConstraint for sway)
    local rootAttachHRP = Instance.new("Attachment")
    rootAttachHRP.Position = Vector3.new(0, 2, 0)
    rootAttachHRP.Parent = hrp
    tagPart(rootAttachHRP, PARACHUTE_TAG)

    local rootAttachCanopy = Instance.new("Attachment")
    rootAttachCanopy.Position = Vector3.new(0, 0, 0)
    rootAttachCanopy.Parent = canopyRoot
    tagPart(rootAttachCanopy, PARACHUTE_TAG)

    local mainRod = Instance.new("RodConstraint")
    mainRod.Attachment0 = rootAttachHRP
    mainRod.Attachment1 = rootAttachCanopy
    mainRod.Length = 16
    mainRod.Visible = false
    mainRod.Parent = canopyRoot

    chuteCanopy = canopyRoot

    -- Canopy panels (rectangular, alternating orange and white)
    local panelCount = 7
    local panelWidth = 3.5
    local totalWidth = panelWidth * panelCount
    local panelHeight = 0.4
    local panelDepth = 8

    for i = 1, panelCount do
        local panel = Instance.new("Part")
        panel.Name = "Panel" .. i
        panel.Size = Vector3.new(panelWidth - 0.1, panelHeight, panelDepth)
        panel.Material = Enum.Material.Fabric

        if i % 2 == 0 then
            panel.Color = Color3.fromRGB(255, 255, 255)
        else
            panel.Color = Color3.fromRGB(255, 120, 30)
        end

        local xOff = (i - (panelCount + 1) / 2) * panelWidth
        panel.CFrame = canopyRoot.CFrame * CFrame.new(xOff, 0, 0)
        panel.Anchored = false
        panel.CanCollide = false
        panel.Massless = true
        panel.Parent = char
        tagPart(panel, PARACHUTE_TAG)

        local pw = Instance.new("WeldConstraint")
        pw.Part0 = canopyRoot
        pw.Part1 = panel
        pw.Parent = canopyRoot

        -- Lines from each panel edge to player
        for _, lineXOff in ipairs({ -panelWidth / 2 + 0.3, panelWidth / 2 - 0.3 }) do
            local lineAttachTop = Instance.new("Attachment")
            lineAttachTop.Position = Vector3.new(xOff + lineXOff, -panelHeight / 2, 0)
            lineAttachTop.Parent = canopyRoot

            local lineAttachBot = Instance.new("Attachment")
            lineAttachBot.Position = Vector3.new(
                (xOff + lineXOff) * 0.15,  -- converge toward center at player
                2, 0
            )
            lineAttachBot.Parent = hrp
            tagPart(lineAttachBot, PARACHUTE_TAG)

            local beam = Instance.new("Beam")
            beam.Attachment0 = lineAttachTop
            beam.Attachment1 = lineAttachBot
            beam.Width0 = 0.05
            beam.Width1 = 0.05
            beam.Color = ColorSequence.new(Color3.fromRGB(180, 180, 180))
            beam.FaceCamera = true
            beam.Parent = canopyRoot
            table.insert(chuteLines, beam)
        end
    end

    -- Physics: BodyForce for lift, BodyVelocity for descent rate limiting
    chuteForce = Instance.new("BodyForce")
    chuteForce.Force = Vector3.new(0, 0, 0)
    chuteForce.Parent = hrp
    tagPart(chuteForce, PARACHUTE_TAG)

    chuteLift = Instance.new("BodyVelocity")
    chuteLift.MaxForce = Vector3.new(0, 15000, 0)
    chuteLift.Velocity = Vector3.new(0, CHUTE_DESCENT_RATE, 0)
    chuteLift.Parent = hrp
    tagPart(chuteLift, PARACHUTE_TAG)

    -- Gyro for controlled heading
    chuteGyro = Instance.new("BodyGyro")
    chuteGyro.MaxTorque = Vector3.new(10000, 10000, 10000)
    chuteGyro.P = 3000
    chuteGyro.D = 200
    chuteGyro.Parent = hrp
    tagPart(chuteGyro, PARACHUTE_TAG)

    -- Sounds
    chuteWindSound = makeSound(hrp, "ChuteWind", true, 0.3)
    -- Search: "wind rushing loop"
    chuteWindSound:Play()
    tagPart(chuteWindSound, PARACHUTE_TAG)

    chuteFlutterSound = makeSound(hrp, "ChuteFlutter", true, 0.15)
    -- Search: "fabric flapping wind", "canvas wind"
    chuteFlutterSound:Play()
    tagPart(chuteFlutterSound, PARACHUTE_TAG)

    -- Deploy whoosh
    local deploySnd = makeSound(hrp, "ChuteDeploy", false, 0.5)
    deploySnd:Play()
    Debris:AddItem(deploySnd, 2)

    -- Auto-retract on landing
    chuteLandedConn = hum.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Landed
            or newState == Enum.HumanoidStateType.Running then
            retractParachute()
        end
    end)

    mode = "parachute"
    customCamActive = true
    setHUDMode("parachute")
end

function retractParachute()
    if not chuteActive then return end
    chuteActive = false

    if chuteLandedConn then
        chuteLandedConn:Disconnect()
        chuteLandedConn = nil
    end

    -- Fade out canopy over 1 second
    local canopyParts = CollectionService:GetTagged(PARACHUTE_TAG)
    for _, obj in ipairs(canopyParts) do
        if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart" then
            tweenProperty(obj, { Transparency = 1 }, 1.0)
        end
    end

    task.delay(1.1, function()
        cleanupByTag(PARACHUTE_TAG)
    end)

    chuteCanopy = nil
    chuteLines = {}
    chuteForce = nil
    chuteLift = nil
    chuteGyro = nil
    chuteWindSound = nil
    chuteFlutterSound = nil

    if mode == "parachute" then
        mode = "none"
        customCamActive = false
        camera.CameraType = Enum.CameraType.Custom
        camera.FieldOfView = DEFAULT_FOV
        setHUDMode("none")
    end
end

--------------------------------------------------------------------------------
-- PARACHUTE UPDATE (per-frame)
--------------------------------------------------------------------------------
local function updateParachute(dt)
    if not chuteActive or not chuteForce or not chuteLift then return end

    local hrp = getHRP()
    if not hrp then return end

    local vel = hrp.AssemblyLinearVelocity
    local mass = hrp.AssemblyMass

    -- Steering input
    local steerInput = 0
    local flareInput = 0

    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        steerInput = -1
    elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then
        steerInput = 1
    end

    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        flareInput = 1
    end

    -- Update heading
    chuteHeading = chuteHeading + steerInput * CHUTE_TURN_RATE * dt

    -- Stall detection
    if flareInput > CHUTE_STALL_THRESHOLD and chuteStallTimer > 2 then
        if not chuteStalled then
            chuteStalled = true
            chuteStallTimer = 0
        end
    end

    if chuteStalled then
        chuteStallTimer = chuteStallTimer + dt
        if chuteStallTimer > 1.5 then
            -- Re-inflate
            chuteStalled = false
            chuteStallTimer = 0
        end
    else
        chuteStallTimer = chuteStallTimer + dt * flareInput  -- accumulate flare time
    end

    -- Calculate forces
    local headingDir = Vector3.new(math.sin(chuteHeading), 0, math.cos(chuteHeading))

    local descentRate = CHUTE_DESCENT_RATE
    local forwardSpeed = CHUTE_FORWARD_SPEED

    if chuteStalled then
        -- Canopy collapsed: rapid descent, minimal forward
        descentRate = CHUTE_STALL_DESCENT
        forwardSpeed = CHUTE_FORWARD_SPEED * 0.2
    elseif flareInput > 0 then
        -- Flare: slow descent, reduce forward speed
        descentRate = CHUTE_DESCENT_RATE + CHUTE_FLARE_LIFT * flareInput
        forwardSpeed = CHUTE_FORWARD_SPEED * (1 - flareInput * 0.4)
    end

    -- BodyVelocity controls descent rate
    chuteLift.Velocity = Vector3.new(0, descentRate, 0)

    -- BodyForce for forward glide + wind
    local forwardForce = headingDir * forwardSpeed * mass * 0.5
    local windForce = chuteWindOffset * mass * 0.3
    -- Drag: oppose horizontal velocity proportional to speed
    local horizVel = Vector3.new(vel.X, 0, vel.Z)
    local dragForce = -horizVel * mass * 0.1

    chuteForce.Force = forwardForce + windForce + dragForce

    -- Bank angle (gyro)
    if chuteGyro then
        local bankAngle = steerInput * math.rad(15)
        chuteGyro.CFrame = CFrame.new(hrp.Position)
            * CFrame.Angles(0, chuteHeading, bankAngle)
            * CFrame.Angles(math.rad(-10 - flareInput * 15), 0, 0)  -- slight forward lean, more on flare
    end

    -- Canopy position follows player (above)
    if chuteCanopy then
        local targetCF = hrp.CFrame * CFrame.new(0, 16, 0) * CFrame.Angles(0, chuteHeading, 0)
        chuteCanopy.CFrame = chuteCanopy.CFrame:Lerp(targetCF, 0.1)

        -- Canopy billowing: scale Y with speed
        local speedFrac = math.clamp(vel.Magnitude / 50, 0.5, 1.5)
        -- We can't scale weld children easily, but we can slightly adjust the
        -- rod length to simulate billow
    end

    -- Sound
    if chuteWindSound then
        local speedFrac = math.clamp(vel.Magnitude / 60, 0, 1)
        chuteWindSound.Volume = 0.15 + speedFrac * 0.35
        chuteWindSound.PlaybackSpeed = 0.8 + speedFrac * 0.4
    end

    if chuteFlutterSound then
        chuteFlutterSound.Volume = chuteStalled and 0.4 or 0.15
    end

    -- Camera: wide FOV, above and behind, looking down slightly
    if customCamActive then
        local behindOffset = -headingDir * CHUTE_CAM_OFFSET.Z + Vector3.new(0, CHUTE_CAM_OFFSET.Y, 0)
        local targetPos = hrp.Position + behindOffset

        if camCurrentPos then
            camCurrentPos = lerpVector3(camCurrentPos, targetPos, CHUTE_CAM_LERP)
        else
            camCurrentPos = targetPos
        end

        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.new(camCurrentPos, hrp.Position + Vector3.new(0, -3, 0))
        camera.FieldOfView = lerp(camera.FieldOfView, CHUTE_FOV, 0.04)
    end
end

--------------------------------------------------------------------------------
-- TRANSITIONS
--------------------------------------------------------------------------------
local function transitionToJetpack()
    if transitionLock then return end
    transitionLock = true

    local hrp = getHRP()

    -- If in car, eject upward
    if mode == "car" then
        exitCar()
        if hrp then
            task.wait(0.1)
            hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity + Vector3.new(0, 40, 0)
            task.wait(0.2)
        end
    end

    -- If parachute active, retract first
    if mode == "parachute" then
        retractParachute()
        task.wait(0.15)
    end

    deployJetpack()
    transitionLock = false
end

local function transitionToParachute()
    if transitionLock then return end
    transitionLock = true

    -- If jetpack active, swap seamlessly
    if mode == "jetpack" then
        cleanupJetpack()
        task.wait(0.1)
    end

    -- If in car, eject first
    if mode == "car" then
        exitCar()
        task.wait(0.2)
    end

    deployParachute()
    transitionLock = false
end

local function transitionToCar()
    if transitionLock then return end
    transitionLock = true

    -- Clean up other modes
    if mode == "jetpack" then
        cleanupJetpack()
        task.wait(0.1)
    end
    if mode == "parachute" then
        retractParachute()
        task.wait(0.1)
    end

    -- Check if a car already exists nearby (proximity entry)
    if carModel and carSeat then
        local hrp = getHRP()
        if hrp and (hrp.Position - carSeat.Position).Magnitude < 15 then
            enterCar(carSeat)
            transitionLock = false
            return
        else
            -- Too far, destroy old car and spawn new
            destroyCar()
        end
    end

    if not carModel then
        local seat = spawnCar()
        if seat then
            task.wait(0.3)  -- brief pause for physics to settle
            enterCar(seat)
        end
    end

    transitionLock = false
end

--------------------------------------------------------------------------------
-- CLEANUP ON DEATH / RESPAWN
--------------------------------------------------------------------------------
local function fullCleanup()
    if mode == "car" then
        exitCar()
    end
    cleanupJetpack()
    retractParachute()
    destroyCar()

    mode = "none"
    customCamActive = false
    camCurrentPos = nil
    jetpackFuel = JETPACK_FUEL_MAX

    camera.CameraType = Enum.CameraType.Custom
    camera.FieldOfView = DEFAULT_FOV

    setHUDMode("none")
end

local function onCharacterAdded(character)
    fullCleanup()

    local hum = character:WaitForChild("Humanoid", 10)
    if hum then
        hum.Died:Connect(function()
            fullCleanup()
        end)
    end
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end

-- Cleanup on leave
Players.PlayerRemoving:Connect(function(p)
    if p == player then
        fullCleanup()
    end
end)

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local character = getCharacter()
    if not character then return end

    local keyCode = input.KeyCode

    if keyCode == Enum.KeyCode.V then
        if mode == "car" then
            exitCar()
        else
            task.spawn(transitionToCar)
        end

    elseif keyCode == Enum.KeyCode.J then
        if mode == "jetpack" then
            cleanupJetpack()
        else
            task.spawn(transitionToJetpack)
        end

    elseif keyCode == Enum.KeyCode.P then
        if mode == "parachute" then
            retractParachute()
        else
            task.spawn(transitionToParachute)
        end

    elseif keyCode == Enum.KeyCode.E and mode == "car" then
        exitCar()

    elseif keyCode == Enum.KeyCode.H and mode == "car" then
        if carHornSound and not carHornSound.IsPlaying then
            carHornSound:Play()
        end
    end
end)

--------------------------------------------------------------------------------
-- MAIN RENDER LOOP
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
    local character = getCharacter()
    if not character then return end
    local hrp = getHRP()
    if not hrp then return end

    -- Update active mode
    updateCar(dt)
    updateJetpack(dt)
    updateParachute(dt)

    -- Update HUD values
    updateHUDValues(dt)

    -- Jetpack fuel recharge on ground
    if not jetpackActive and isOnGround() then
        jetpackFuel = math.min(JETPACK_FUEL_MAX, jetpackFuel + JETPACK_FUEL_RECHARGE_RATE * dt)
    end

    -- Detect if player fell out of car seat
    if mode == "car" and carSeat then
        local hum = getHumanoid()
        if hum and not hum.Sit then
            mode = "none"
            customCamActive = false
            camera.CameraType = Enum.CameraType.Custom
            camera.FieldOfView = DEFAULT_FOV
            setHUDMode("none")
        end
    end

    -- Camera transition smoothing when switching modes
    if mode ~= prevMode then
        camCurrentPos = nil  -- reset so camera doesn't jump
        prevMode = mode
    end
end)
