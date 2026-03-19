local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)

local DayNightCycle = {}

local CYCLE_SPEED = 1 -- 1 = real-time, 60 = 1 minute per second, 0 = frozen
local DAWN_HOUR = 6.5
local DUSK_HOUR = 19.5
local UPDATE_INTERVAL = 0.5 -- seconds between lighting updates

local isNight = false
local lastUpdate = 0

local function isDusk(hour)
    return hour >= DUSK_HOUR or hour < DAWN_HOUR
end

local function updateLighting(hour)
    local night = isDusk(hour)
    if night == isNight then return end -- no change
    isNight = night

    -- Toggle street lights
    for _, part in ipairs(CollectionService:GetTagged("StreetLight")) do
        local light = part:FindFirstChildOfClass("PointLight")
        if light then
            light.Enabled = night
        end
    end

    -- Toggle building window glow
    -- Windows tagged LOD_Detail with Glass material get a warm glow at night
    for _, part in ipairs(CollectionService:GetTagged("LOD_Detail")) do
        if part:IsA("BasePart") and part.Material == Enum.Material.Glass then
            if night then
                part.Color = Color3.fromRGB(255, 220, 150) -- warm interior glow
                part.Transparency = 0.1
            else
                part.Color = Color3.fromRGB(40, 50, 70) -- dark daytime glass
                part.Transparency = part:GetAttribute("BaseTransparency") or 0.35
            end
        end
    end

    -- Adjust atmosphere
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere then
        if night then
            atmosphere.Density = 0.4
            atmosphere.Color = Color3.fromRGB(50, 55, 80)
            atmosphere.Decay = Color3.fromRGB(30, 35, 55)
        else
            atmosphere.Density = 0.3
            atmosphere.Color = Color3.fromRGB(199, 210, 225)
            atmosphere.Decay = Color3.fromRGB(106, 112, 125)
        end
    end

    -- Adjust bloom for night
    local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
    if bloom then
        bloom.Intensity = night and 0.8 or 0.5
        bloom.Threshold = night and 1.0 or 2.0
    end
end

function DayNightCycle.Start(speed)
    CYCLE_SPEED = speed or WorldConfig.DayNightSpeed or 60
    if CYCLE_SPEED == 0 then return end -- frozen time

    RunService.Heartbeat:Connect(function(dt)
        -- Advance clock
        local minutesPerSecond = CYCLE_SPEED / 60
        Lighting.ClockTime = (Lighting.ClockTime + minutesPerSecond * dt / 60) % 24

        -- Periodic lighting update
        lastUpdate = lastUpdate + dt
        if lastUpdate >= UPDATE_INTERVAL then
            lastUpdate = 0
            updateLighting(Lighting.ClockTime)
        end
    end)

    -- Initial state
    updateLighting(Lighting.ClockTime)
end

function DayNightCycle.Stop()
    CYCLE_SPEED = 0
end

function DayNightCycle.SetTime(hour)
    Lighting.ClockTime = hour
    updateLighting(hour)
end

return DayNightCycle
