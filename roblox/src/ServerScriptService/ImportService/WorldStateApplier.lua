local gameLighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldStateApplier = {}
local WorldStateConfig = require(ReplicatedStorage.Shared.WorldStateConfig)

local function resolveConfigValue(config, key)
    if type(config) == "table" and config[key] ~= nil then
        return config[key]
    end
    return WorldStateConfig[key]
end

local function ensureAtmosphere()
    local atmosphere = gameLighting:FindFirstChildOfClass("Atmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Parent = gameLighting
    end

    atmosphere.Density = 0.3
    atmosphere.Offset = 0.25
    atmosphere.Glare = 0
    atmosphere.Haze = 1
    atmosphere.Color = Color3.fromRGB(199, 210, 225)
    atmosphere.Decay = Color3.fromRGB(106, 112, 125)
end

local function ensureBloom()
    local bloom = gameLighting:FindFirstChildOfClass("BloomEffect")
    if not bloom then
        bloom = Instance.new("BloomEffect")
        bloom.Parent = gameLighting
    end

    bloom.Intensity = 0.5
    bloom.Size = 24
    bloom.Threshold = 2
end

local function ensureColorCorrection()
    local colorCorrection = gameLighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if not colorCorrection then
        colorCorrection = Instance.new("ColorCorrectionEffect")
        colorCorrection.Parent = gameLighting
    end

    colorCorrection.Brightness = 0.02
    colorCorrection.Contrast = 0.05
    colorCorrection.Saturation = 0.1
    colorCorrection.TintColor = Color3.fromRGB(255, 248, 240)
end

local function ensureSunRays()
    local sunRays = gameLighting:FindFirstChildOfClass("SunRaysEffect")
    if not sunRays then
        sunRays = Instance.new("SunRaysEffect")
        sunRays.Parent = gameLighting
    end

    sunRays.Intensity = 0.15
    sunRays.Spread = 0.8
end

local function applyAtmosphere()
    ensureAtmosphere()

    gameLighting.Brightness = 2
    gameLighting.EnvironmentDiffuseScale = 1
    gameLighting.EnvironmentSpecularScale = 1
    gameLighting.GlobalShadows = true
    gameLighting.ShadowSoftness = 0.2

    ensureBloom()
    ensureColorCorrection()
    ensureSunRays()
end

function WorldStateApplier.Apply(manifest, config, options)
    local resolvedOptions = options or {}

    if resolveConfigValue(config, "EnableAtmosphere") ~= false then
        applyAtmosphere()
    end

    if manifest and manifest.meta and manifest.meta.bbox then
        local bbox = manifest.meta.bbox
        local latitude = (bbox.minLat + bbox.maxLat) / 2
        local longitude = (bbox.minLon + bbox.maxLon) / 2
        local datetime = resolveConfigValue(config, "DateTime") or "auto"
        local dayNightCycle = require(script.Parent.DayNightCycle)
        dayNightCycle.Configure(latitude, longitude, datetime)

        if resolveConfigValue(config, "EnableDayNightCycle") ~= false then
            dayNightCycle.Start(resolveConfigValue(config, "DayNightSpeed"))
        end
    end

    if resolvedOptions.startMinimap == true and resolveConfigValue(config, "EnableMinimap") ~= false then
        local minimapService = require(script.Parent.MinimapService)
        minimapService.Start({
            worldRootName = resolvedOptions.worldRootName,
        })
    end

    if resolvedOptions.hideLoadingScreen == true then
        local loadingScreen = require(script.Parent.LoadingScreen)
        loadingScreen.Hide()
    end
end

return WorldStateApplier
