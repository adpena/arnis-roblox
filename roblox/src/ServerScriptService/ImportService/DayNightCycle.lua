local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local ChunkLoader = require(script.Parent.ChunkLoader)

local DayNightCycle = {}

local CYCLE_SPEED = 1 -- 1 = real-time, 60 = 1 minute per second, 0 = frozen
local connection = nil
local UPDATE_INTERVAL = 0.5 -- seconds between lighting updates

local lastUpdate = 0
local currentPhase = nil -- tracks last applied phase to avoid redundant reactive calls

-- ---------------------------------------------------------------------------
-- Time-of-day phase classification
-- ---------------------------------------------------------------------------

local function getTimePhase(hour)
    if hour >= 5.5 and hour < 7.5 then
        return "dawn"
    elseif hour >= 7.5 and hour < 17 then
        return "day"
    elseif hour >= 17 and hour < 19.5 then
        return "golden"
    elseif hour >= 19.5 and hour < 21 then
        return "dusk"
    else
        return "night"
    end
end

-- Per-phase atmospheric targets.
local PHASE_SETTINGS = {
    dawn = {
        density = 0.5,
        haze = 2,
        atmosphereColor = Color3.fromRGB(220, 180, 140),
        decayColor = Color3.fromRGB(180, 120, 80),
        bloomIntensity = 0.8,
        bloomThreshold = 1.0,
        sunRaysIntensity = 0.4,
        sunRaysSpread = 1.0,
        outdoorAmbient = Color3.fromRGB(180, 140, 90),
        lightsOn = false,
    },
    day = {
        density = 0.25,
        haze = 0.8,
        atmosphereColor = Color3.fromRGB(199, 210, 225),
        decayColor = Color3.fromRGB(106, 112, 125),
        bloomIntensity = 0.4,
        bloomThreshold = 2.5,
        sunRaysIntensity = 0.12,
        sunRaysSpread = 0.7,
        outdoorAmbient = Color3.fromRGB(128, 128, 128),
        lightsOn = false,
    },
    golden = {
        density = 0.3,
        haze = 1.2,
        atmosphereColor = Color3.fromRGB(240, 200, 150),
        decayColor = Color3.fromRGB(200, 130, 70),
        bloomIntensity = 0.7,
        bloomThreshold = 1.5,
        sunRaysIntensity = 0.3,
        sunRaysSpread = 1.0,
        outdoorAmbient = Color3.fromRGB(200, 160, 100),
        lightsOn = false,
    },
    dusk = {
        density = 0.35,
        haze = 1.5,
        atmosphereColor = Color3.fromRGB(120, 100, 140),
        decayColor = Color3.fromRGB(60, 50, 80),
        bloomIntensity = 0.6,
        bloomThreshold = 1.5,
        sunRaysIntensity = 0.2,
        sunRaysSpread = 0.8,
        outdoorAmbient = Color3.fromRGB(80, 70, 100),
        lightsOn = true,
    },
    night = {
        density = 0.4,
        haze = 0.5,
        atmosphereColor = Color3.fromRGB(30, 35, 55),
        decayColor = Color3.fromRGB(15, 18, 30),
        bloomIntensity = 0.9,
        bloomThreshold = 0.8,
        sunRaysIntensity = 0,
        sunRaysSpread = 0,
        outdoorAmbient = Color3.fromRGB(25, 28, 40),
        lightsOn = true,
    },
}

-- ---------------------------------------------------------------------------
-- Reactive object helpers (street lights, night windows)
-- ---------------------------------------------------------------------------

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

-- Deterministic per-window lit/dark decision based on world position.
-- Same windows will always be lit or dark across server restarts.
-- ~65% of windows are lit, ~35% are dark, matching a real office district at night.
local function isWindowLit(part)
    local pos = part.Position
    local hash = math.floor(math.abs(pos.X * 7 + pos.Z * 13)) % 100
    return hash < 65
end

local function updateReactiveVisibility(reactiveKind, lightsOn)
    if reactiveKind == "streetLights" then
        forEachReactive("streetLights", function(part)
            local light = part:FindFirstChildOfClass("PointLight")
            if light then
                light.Enabled = lightsOn
            end
        end)
        return
    end

    if reactiveKind == "nightWindows" then
        forEachReactive("nightWindows", function(part)
            if lightsOn then
                if isWindowLit(part) then
                    -- Deterministic warm tone derived from position hash
                    local pos = part.Position
                    local warmHash = math.floor(math.abs(pos.X * 17 + pos.Z * 31)) % 100
                    local g = 200 + math.floor(warmHash * 0.30)  -- 200-230
                    local b = 140 + math.floor(warmHash * 0.30)  -- 140-170
                    part.Color = Color3.fromRGB(255, g, b)
                    part.Transparency = 0.1
                else
                    -- Dark window: slightly reflective glass, no glow
                    part.Color = Color3.fromRGB(30, 35, 45)
                    part.Transparency = 0.6
                end
            else
                part.Color = Color3.fromRGB(40, 50, 70)
                part.Transparency = part:GetAttribute("BaseTransparency") or 0.35
            end
        end)
    end

    -- Toggle interior room lights
    for _, part in ipairs(CollectionService:GetTagged("InteriorLight")) do
        if part:IsDescendantOf(game) then
            local light = part:FindFirstChildOfClass("PointLight")
            if light then
                light.Enabled = lightsOn
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Color lerp helper
-- ---------------------------------------------------------------------------

local function lerpColor(a, b, t)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

-- ---------------------------------------------------------------------------
-- Core lighting update: lerps current Lighting values toward phase targets.
-- Reactive objects (street lights, windows) are only toggled when the phase
-- changes so we don't thrash them on every heartbeat tick.
-- ---------------------------------------------------------------------------

local LERP_SPEED = 0.12 -- fraction per update interval; feels smooth, not jarring

local function updateLighting(hour)
    local phase = getTimePhase(hour)
    local settings = PHASE_SETTINGS[phase]

    -- Drive reactive objects only when the phase boundary is crossed.
    if phase ~= currentPhase then
        updateReactiveVisibility("streetLights", settings.lightsOn)
        updateReactiveVisibility("nightWindows", settings.lightsOn)
        currentPhase = phase
    end

    -- Atmosphere
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere then
        atmosphere.Density = atmosphere.Density + (settings.density - atmosphere.Density) * LERP_SPEED
        atmosphere.Haze = atmosphere.Haze + (settings.haze - atmosphere.Haze) * LERP_SPEED
        atmosphere.Color = lerpColor(atmosphere.Color, settings.atmosphereColor, LERP_SPEED)
        atmosphere.Decay = lerpColor(atmosphere.Decay, settings.decayColor, LERP_SPEED)
    end

    -- Bloom
    local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
    if bloom then
        bloom.Intensity = bloom.Intensity + (settings.bloomIntensity - bloom.Intensity) * LERP_SPEED
        bloom.Threshold = bloom.Threshold + (settings.bloomThreshold - bloom.Threshold) * LERP_SPEED
    end

    -- Sun rays
    local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
    if sunRays then
        sunRays.Intensity = sunRays.Intensity + (settings.sunRaysIntensity - sunRays.Intensity) * LERP_SPEED
        sunRays.Spread = sunRays.Spread + (settings.sunRaysSpread - sunRays.Spread) * LERP_SPEED
    end

    -- Outdoor ambient
    Lighting.OutdoorAmbient = lerpColor(Lighting.OutdoorAmbient, settings.outdoorAmbient, LERP_SPEED)
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

    -- Set initial outdoor ambient from the phase table so Configure and the
    -- heartbeat loop use consistent values rather than hard-coded fallbacks.
    local phase = getTimePhase(hour)
    local settings = PHASE_SETTINGS[phase]
    Lighting.OutdoorAmbient = settings.outdoorAmbient
    Lighting.Ambient = Color3.fromRGB(40, 40, 40) -- neutral fill; phase system owns OutdoorAmbient

    -- Update the lighting state immediately
    updateLighting(hour)
end

return DayNightCycle
