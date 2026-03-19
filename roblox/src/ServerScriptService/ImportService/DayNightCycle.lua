local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local ChunkLoader = require(script.Parent.ChunkLoader)

local DayNightCycle = {}

local CYCLE_SPEED = 1 -- 1 = real-time, 60 = 1 minute per second, 0 = frozen
local connection = nil
local DAWN_HOUR = 6.5
local DUSK_HOUR = 19.5
local UPDATE_INTERVAL = 0.5 -- seconds between lighting updates

local isNight = false
local lastUpdate = 0

local function isDusk(hour)
    return hour >= DUSK_HOUR or hour < DAWN_HOUR
end

local function forEachReactive(reactiveKind, visitor)
    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks()) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId)
        local reactives = chunkEntry and chunkEntry.reactives and chunkEntry.reactives[reactiveKind]
        if reactives then
            for _, reactive in ipairs(reactives) do
                if reactive:IsDescendantOf(game) then
                    visitor(reactive)
                end
            end
        end
    end
end

local function updateReactiveVisibility(reactiveKind, night)
    if reactiveKind == "streetLights" then
        forEachReactive("streetLights", function(part)
            local light = part:FindFirstChildOfClass("PointLight")
            if light then
                light.Enabled = night
            end
        end)
        return
    end

    if reactiveKind == "nightWindows" then
        forEachReactive("nightWindows", function(part)
            if night then
                part.Color = Color3.fromRGB(255, 220, 150)
                part.Transparency = 0.1
            else
                part.Color = Color3.fromRGB(40, 50, 70)
                part.Transparency = part:GetAttribute("BaseTransparency") or 0.35
            end
        end)
    end
end

local function updateLighting(hour)
    local night = isDusk(hour)
    if night == isNight then
        return
    end -- no change
    isNight = night

    updateReactiveVisibility("streetLights", night)
    updateReactiveVisibility("nightWindows", night)

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
    if CYCLE_SPEED == 0 then
        return
    end -- frozen time

    if connection then
        connection:Disconnect()
    end
    connection = RunService.Heartbeat:Connect(function(dt)
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
    if connection then
        connection:Disconnect()
        connection = nil
    end
end

function DayNightCycle.SetTime(hour)
    Lighting.ClockTime = hour
    updateLighting(hour)
end

--- Configure sun position from geographic coordinates and datetime.
--- Called automatically by ImportService after manifest is loaded.
--- @param latitude number Degrees (positive = N, negative = S)
--- @param longitude number Degrees (positive = E, negative = W)
--- @param datetime string|nil ISO format "YYYY-MM-DDTHH:MM" or nil for current system time
function DayNightCycle.Configure(latitude, longitude, datetime)
    -- Set geographic latitude (controls sun arc/zenith angle)
    Lighting.GeographicLatitude = latitude

    -- Parse datetime or use system time
    local hour = 14 -- default: 2 PM
    if datetime and datetime ~= "auto" then
        -- Parse "YYYY-MM-DDTHH:MM" format
        local h, m = datetime:match("T(%d+):(%d+)")
        if h and m then
            hour = tonumber(h) + tonumber(m) / 60
        end
    elseif datetime == "auto" or datetime == nil then
        -- Use system time converted to local solar time
        -- Solar time approximation: UTC + longitude/15
        local utcTime = os.date("!*t")
        local utcHour = utcTime.hour + utcTime.min / 60
        local solarOffset = longitude / 15  -- rough solar time offset
        hour = (utcHour + solarOffset) % 24
    end

    Lighting.ClockTime = hour

    -- Adjust sun color warmth based on hour (golden hour effect)
    if hour < 7 or hour > 18 then
        -- Night/twilight
        Lighting.OutdoorAmbient = Color3.fromRGB(30, 35, 50)
        Lighting.Ambient = Color3.fromRGB(20, 22, 30)
    elseif hour < 8 or hour > 17 then
        -- Golden hour
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 140, 90)
        Lighting.Ambient = Color3.fromRGB(60, 45, 30)
    else
        -- Daytime
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        Lighting.Ambient = Color3.fromRGB(40, 40, 40)
    end

    -- Update the lighting state immediately
    updateLighting(hour)
end

return DayNightCycle
