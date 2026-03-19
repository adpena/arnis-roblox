-- AmbientSoundscape.client.lua
-- LocalScript: spatial ambient audio and surface-aware footstep sounds.
-- Volumes adjust every UPDATE_INTERVAL seconds based on the player's surroundings.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- ---------------------------------------------------------------------------
-- 1. Ambient city sounds
-- ---------------------------------------------------------------------------

local AMBIENT_SOUNDS = {
    -- City background hum (always playing, volume varies with density)
    cityHum = {
        id = "rbxassetid://9112858785",
        volume = 0.15,
        looped = true,
    },
    -- Wind (always playing, volume varies with altitude)
    wind = {
        id = "rbxassetid://9113543029",
        volume = 0.0,
        looped = true,
    },
    -- Birds (near parks/trees)
    birds = {
        id = "rbxassetid://9113088613",
        volume = 0.0,
        looped = true,
    },
    -- Water (near rivers/lakes)
    water = {
        id = "rbxassetid://9113586364",
        volume = 0.0,
        looped = true,
    },
}

-- sounds[name] = { instance: Sound, baseVolume: number }
local sounds = {}

local function createSounds()
    for name, config in pairs(AMBIENT_SOUNDS) do
        local sound = Instance.new("Sound")
        sound.Name = "Ambient_" .. name
        sound.SoundId = config.id
        sound.Volume = config.volume
        sound.Looped = config.looped
        sound.RollOffMode = Enum.RollOffMode.Linear
        sound.Parent = SoundService
        sound:Play()
        sounds[name] = { instance = sound, baseVolume = config.volume }
    end
end

-- ---------------------------------------------------------------------------
-- 2. Context-aware volume update
-- ---------------------------------------------------------------------------

local UPDATE_INTERVAL = 0.3

local function updateAmbience()
    local character = player.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local pos = hrp.Position

    -- Smooth volume helper: lerp toward target to prevent audio pops
    local function smoothVol(sound, target)
        sound.instance.Volume = sound.instance.Volume + (target - sound.instance.Volume) * 0.15
    end

    -- Altitude-based wind: louder when high up (e.g. on a rooftop).
    -- 50 studs is approximate street level; ramps up to full at 350 studs.
    local altitude = math.max(0, pos.Y - 50)
    local windVol = math.clamp(altitude / 300, 0, 0.4)
    smoothVol(sounds.wind, windVol)

    -- Near water? Scan water-surface parts tagged by the importer.
    local nearWater = false
    for _, waterPart in ipairs(CollectionService:GetTagged("LOD_Detail")) do
        if waterPart.Name == "RibbonWaterSurface"
            or waterPart.Name == "PolygonWaterSurface"
        then
            -- Use a fast squared-distance check before the sqrt.
            local delta = waterPart.Position - pos
            if delta.X * delta.X + delta.Z * delta.Z < 100 * 100 then
                nearWater = true
                break
            end
        end
    end
    smoothVol(sounds.water, nearWater and 0.2 or 0)

    -- Near nature? Raycast straight down and inspect terrain material.
    local nearNature = false
    local rayResult = workspace:Raycast(pos, Vector3.new(0, -100, 0))
    if rayResult and rayResult.Material then
        if rayResult.Material == Enum.Material.Grass
            or rayResult.Material == Enum.Material.LeafyGrass
        then
            nearNature = true
        end
    end
    smoothVol(sounds.birds, nearNature and 0.12 or 0)

    -- City hum: louder near roads (tagged by the importer), softer in parks.
    local nearRoad = false
    for _, part in ipairs(CollectionService:GetTagged("Road")) do
        local delta = part.Position - pos
        if delta.X * delta.X + delta.Z * delta.Z < 50 * 50 then
            nearRoad = true
            break
        end
    end
    smoothVol(sounds.cityHum, nearRoad and 0.2 or 0.08)
end

-- ---------------------------------------------------------------------------
-- 3. Surface-aware footstep sounds
-- ---------------------------------------------------------------------------

local FOOTSTEP_SOUNDS = {
    [Enum.Material.Asphalt]    = "rbxassetid://9114105209",  -- hard step
    [Enum.Material.Concrete]   = "rbxassetid://9114105209",  -- hard step
    [Enum.Material.Cobblestone] = "rbxassetid://9114105209", -- hard step
    [Enum.Material.Brick]      = "rbxassetid://9114105209",  -- hard step
    [Enum.Material.Grass]      = "rbxassetid://9114077935",  -- soft grass
    [Enum.Material.LeafyGrass] = "rbxassetid://9114077935",  -- soft grass
    [Enum.Material.Sand]       = "rbxassetid://9114077935",  -- soft step
    [Enum.Material.Ground]     = "rbxassetid://9114077935",  -- earth step
    [Enum.Material.WoodPlanks] = "rbxassetid://9114119441",  -- wood creak
    [Enum.Material.Metal]      = "rbxassetid://9114119441",  -- metal clang
}

local FOOTSTEP_DEFAULT = FOOTSTEP_SOUNDS[Enum.Material.Concrete]

local footstepSound = nil       -- Sound instance parented to HumanoidRootPart
local lastFootstepMaterial = nil

local function updateFootsteps()
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return end

    local walking = humanoid.MoveDirection.Magnitude > 0.1
        and humanoid:GetState() == Enum.HumanoidStateType.Running

    if walking then
        -- Raycast down from hip height to find what we're walking on.
        local ray = workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0))
        local material = (ray and ray.Material) or Enum.Material.Concrete

        -- Re-create or retarget the Sound whenever the surface type changes.
        if material ~= lastFootstepMaterial then
            lastFootstepMaterial = material

            local soundId = FOOTSTEP_SOUNDS[material] or FOOTSTEP_DEFAULT

            if not footstepSound then
                footstepSound = Instance.new("Sound")
                footstepSound.Name = "Footstep"
                footstepSound.Looped = true
                footstepSound.Volume = 0.15
                footstepSound.Parent = hrp
            end

            -- Stop before changing SoundId to avoid a brief audio glitch.
            if footstepSound.IsPlaying then
                footstepSound:Stop()
            end
            footstepSound.SoundId = soundId
        end

        if not footstepSound.IsPlaying then
            footstepSound:Play()
        end

        -- Scale playback speed with WalkSpeed so slow-walks feel heavy and
        -- sprints feel snappy. Baseline is 16 studs/s.
        footstepSound.PlaybackSpeed = 0.8 + (humanoid.WalkSpeed / 16) * 0.4

    elseif footstepSound and footstepSound.IsPlaying then
        footstepSound:Stop()
    end
end

-- ---------------------------------------------------------------------------
-- 4. Initialise and run
-- ---------------------------------------------------------------------------

createSounds()

local timer = 0
RunService.Heartbeat:Connect(function(dt)
    -- Ambience update is throttled; footstep update runs every frame for
    -- responsiveness (it is cheap — one raycast per frame at most).
    timer = timer + dt
    if timer >= UPDATE_INTERVAL then
        timer = 0
        updateAmbience()
    end
    updateFootsteps()
end)

-- Destroy per-character Sound when the character is removed (death / reset).
-- The ambient Sounds live in SoundService and persist across respawns.
player.CharacterRemoving:Connect(function()
    if footstepSound then
        footstepSound:Destroy()
        footstepSound = nil
    end
    lastFootstepMaterial = nil
end)
