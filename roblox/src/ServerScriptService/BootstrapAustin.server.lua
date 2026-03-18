--[[
  BootstrapAustin.server.lua
  Automatically imports the Austin, TX manifest when the game starts.
  This runs on Play (server-side) so you can open Studio, hit Play, and see Austin.

  To disable: set ENABLED = false below.
--]]

local ENABLED = true

if not ENABLED then
    return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local AustinSpawn = require(script.Parent.ImportService.AustinSpawn)
local RunAustin = require(script.Parent.ImportService.RunAustin)

local importReady = false
local spawnCFrame

Players.CharacterAutoLoads = false

local holdingPad = Instance.new("Part")
holdingPad.Name = "AustinLoadingPad"
holdingPad.Anchored = true
holdingPad.CanCollide = true
holdingPad.Transparency = 1
holdingPad.Size = Vector3.new(64, 1, 64)
holdingPad.CFrame = CFrame.new(0, 300, 0)
holdingPad.Parent = Workspace

local function moveCharacterToSpawn(character)
    local root = character:FindFirstChild("HumanoidRootPart")
        or character:WaitForChild("HumanoidRootPart", 10)
    if root and spawnCFrame then
        character:PivotTo(spawnCFrame)
    end
end

local function onPlayer(player)
    player.CharacterAdded:Connect(function(character)
        if importReady and spawnCFrame then
            task.defer(function()
                moveCharacterToSpawn(character)
            end)
        elseif holdingPad then
            task.defer(function()
                local root = character:FindFirstChild("HumanoidRootPart")
                    or character:WaitForChild("HumanoidRootPart", 10)
                if root and holdingPad then
                    character:PivotTo(holdingPad.CFrame + Vector3.new(0, 5, 0))
                end
            end)
        end
    end)

    if player.Character and holdingPad then
        task.defer(function()
            local root = player.Character:FindFirstChild("HumanoidRootPart")
                or player.Character:WaitForChild("HumanoidRootPart", 10)
            if root and holdingPad then
                player.Character:PivotTo(holdingPad.CFrame + Vector3.new(0, 5, 0))
            end
        end)
    end

    if importReady and not player.Character then
        player:LoadCharacter()
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)

print("[BootstrapAustin] Starting Austin, TX import...")

-- Note: StreamingEnabled and Terrain.SmoothingEnabled must be configured
-- in Studio settings (File > Game Settings > Streaming) — not scriptable.

local manifest = RunAustin.run()
print("[BootstrapAustin] Done.")

local spawnPoint = AustinSpawn.findSpawnPoint(manifest, RunAustin.LOAD_RADIUS)
local spawn = Instance.new("SpawnLocation")
spawn.Name = "CongressAveSpawn"
spawn.Size = Vector3.new(6, 1, 6)
spawn.Anchored = true
spawn.Neutral = true
spawn.Material = Enum.Material.Concrete
spawn.BrickColor = BrickColor.new("Medium stone grey")
spawn.Parent = Workspace

local rayOrigin = Vector3.new(spawnPoint.X, spawnPoint.Y + 2000, spawnPoint.Z)
local ray = Workspace:Raycast(rayOrigin, Vector3.new(0, -4000, 0))
local spawnY = ray and (ray.Position.Y + 5) or (spawnPoint.Y + 5)
spawnCFrame = CFrame.new(spawnPoint.X, spawnY, spawnPoint.Z)
spawn.CFrame = spawnCFrame

importReady = true
Players.CharacterAutoLoads = true

for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then
        moveCharacterToSpawn(player.Character)
    else
        player:LoadCharacter()
    end
end

holdingPad:Destroy()

Lighting.Ambient = Color3.fromRGB(120, 100, 80) -- warm Texas ambient
Lighting.Brightness = 3.5
Lighting.ColorShift_Bottom = Color3.fromRGB(255, 200, 120)
Lighting.ColorShift_Top = Color3.fromRGB(180, 220, 255)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.8
Lighting.ExposureCompensation = 0.3
Lighting.GeographicLatitude = 30.265 -- Austin, TX
Lighting.TimeOfDay = "16:30:00" -- late afternoon golden hour
Lighting.ShadowSoftness = 0.3
Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 180)

-- Atmosphere
local atmo = Instance.new("Atmosphere")
atmo.Density = 0.35
atmo.Offset = 0.2
atmo.Color = Color3.fromRGB(255, 220, 170) -- warm Texas haze
atmo.Decay = Color3.fromRGB(100, 80, 60)
atmo.Glare = 0.4
atmo.Haze = 1.8
atmo.Parent = Lighting

-- Bloom post-processing
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.4
bloom.Size = 24
bloom.Threshold = 0.95
bloom.Parent = Lighting

-- Sun rays
local sunRays = Instance.new("SunRaysEffect")
sunRays.Intensity = 0.08
sunRays.Spread = 0.5
sunRays.Parent = Lighting

-- Color correction for cinematic look
local cc = Instance.new("ColorCorrectionEffect")
cc.Brightness = 0.02
cc.Contrast = 0.08
cc.Saturation = 0.15
cc.TintColor = Color3.fromRGB(255, 248, 235)
cc.Parent = Lighting

print("[BootstrapAustin] Spawn and atmosphere configured.")
