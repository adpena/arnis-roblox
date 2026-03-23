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
local RunService = game:GetService("RunService")

local AustinSpawn = require(script.Parent.ImportService.AustinSpawn)
local RunAustin = require(script.Parent.ImportService.RunAustin)
local StreamingService = require(script.Parent.ImportService.StreamingService)
local SubplanRollout = require(script.Parent.ImportService.SubplanRollout)
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)

if not RunService:IsStudio() then
    warn("[BootstrapAustin] Refusing to auto-import Austin outside Studio.")
    return
end

Players.CharacterAutoLoads = false

local importReady = false
local spawnCFrame
local holdingPad

local WALKABLE_WORLD_GROUPS = table.freeze({
    Terrain = true,
    Roads = true,
    Landuse = true,
    Rails = true,
})

local function isWalkableWorldDescendant(hitInstance, worldRoot)
    if not hitInstance or not worldRoot then
        return false
    end
    if not hitInstance:IsDescendantOf(worldRoot) then
        return false
    end

    local node = hitInstance
    while node and node.Parent and node.Parent ~= worldRoot do
        node = node.Parent
    end

    return node ~= nil and WALKABLE_WORLD_GROUPS[node.Name] == true
end

local function isValidGroundHit(hitInstance, worldRoot, loadingPad, spawn)
    if not hitInstance then
        return false
    end
    if loadingPad and hitInstance:IsDescendantOf(loadingPad) then
        return false
    end
    if spawn and hitInstance:IsDescendantOf(spawn) then
        return false
    end
    if hitInstance == Workspace.Terrain then
        return true
    end
    if isWalkableWorldDescendant(hitInstance, worldRoot) then
        return true
    end
    return false
end

local function findGroundYNear(worldRoot, point, loadingPad, spawn)
    local ignore = {}
    if loadingPad then
        table.insert(ignore, loadingPad)
    end
    if spawn then
        table.insert(ignore, spawn)
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore

    local rayOrigin = Vector3.new(point.X, point.Y + 2000, point.Z)
    local rayDirection = Vector3.new(0, -4000, 0)

    for _ = 1, 8 do
        local hit = Workspace:Raycast(rayOrigin, rayDirection, params)
        if not hit then
            break
        end
        if isValidGroundHit(hit.Instance, worldRoot, loadingPad, spawn) then
            return hit.Position.Y + 5
        end
        table.insert(ignore, hit.Instance)
        params.FilterDescendantsInstances = ignore
    end

    warn(
        string.format(
            "[BootstrapAustin] No valid ground hit near spawn anchor (x=%.1f, y=%.1f, z=%.1f); falling back to manifest Y",
            point.X,
            point.Y,
            point.Z
        )
    )
    return point.Y + 5
end

local function moveCharacterToSpawn(character)
    local root = character:FindFirstChild("HumanoidRootPart")
        or character:WaitForChild("HumanoidRootPart", 10)
    if root and spawnCFrame then
        character:PivotTo(spawnCFrame)
    end
end

local function removeCharacterUntilImportReady(player, character)
    if importReady then
        return
    end

    task.defer(function()
        if player.Character == character and character.Parent then
            character:Destroy()
        end
    end)
end

local function onPlayer(player)
    player.CharacterAdded:Connect(function(character)
        if importReady and spawnCFrame then
            task.defer(function()
                moveCharacterToSpawn(character)
            end)
        else
            removeCharacterUntilImportReady(player, character)
        end
    end)

    if player.Character and not importReady then
        removeCharacterUntilImportReady(player, player.Character)
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

holdingPad = Instance.new("Part")
holdingPad.Name = "AustinLoadingPad"
holdingPad.Anchored = true
holdingPad.CanCollide = false
holdingPad.Transparency = 1
holdingPad.Size = Vector3.new(64, 1, 64)
holdingPad.CFrame = CFrame.new(0, 300, 0)
holdingPad.Parent = Workspace

local result = RunAustin.run()
if result == nil then
    warn("[BootstrapAustin] Austin manifest unavailable; skipping bootstrap.")
    if holdingPad then
        holdingPad:Destroy()
    end
    Players.CharacterAutoLoads = true
    for _, player in ipairs(Players:GetPlayers()) do
        if not player.Character then
            player:LoadCharacter()
        end
    end
    return
end

local manifest = result.manifest
local manifestSource = result.manifestSource or manifest
local worldRoot = Workspace:FindFirstChild("GeneratedWorld_Austin")

print("[BootstrapAustin] Done.")

local anchor = AustinSpawn.resolveAnchor(manifestSource, RunAustin.LOAD_RADIUS, result.focusPoint)
local spawnPoint = result.spawnPoint or anchor.spawnPoint
local spawn = Instance.new("SpawnLocation")
spawn.Name = "CongressAveSpawn"
spawn.Size = Vector3.new(6, 1, 6)
spawn.Anchored = true
spawn.Neutral = true
spawn.Material = Enum.Material.Concrete
spawn.BrickColor = BrickColor.new("Medium stone grey")
spawn.Parent = Workspace

for _, player in ipairs(Players:GetPlayers()) do
    player.RespawnLocation = spawn
end
Players.PlayerAdded:Connect(function(player)
    player.RespawnLocation = spawn
end)

local spawnY = findGroundYNear(worldRoot, spawnPoint, holdingPad, spawn)
local preferredLookTarget = result.lookTarget or anchor.lookTarget
local lookTarget = Vector3.new(preferredLookTarget.X, spawnY, preferredLookTarget.Z)
if (lookTarget - Vector3.new(spawnPoint.X, spawnY, spawnPoint.Z)).Magnitude < 1 then
    lookTarget = Vector3.new(spawnPoint.X, spawnY, spawnPoint.Z - 1)
end
spawnCFrame = CFrame.lookAt(Vector3.new(spawnPoint.X, spawnY, spawnPoint.Z), lookTarget)
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

if WorldConfig.StreamingEnabled then
    local rolloutDescription = SubplanRollout.Describe(WorldConfig)
    print(
        ("[BootstrapAustin] Subplan rollout enabled=%s mode=%s layers=%d chunks=%d"):format(
            tostring(rolloutDescription.enabled),
            tostring(rolloutDescription.mode),
            rolloutDescription.allowedLayerCount,
            rolloutDescription.allowlistedChunkCount
        )
    )
    StreamingService.Start(manifestSource, {
        worldRootName = "GeneratedWorld_Austin",
        config = WorldConfig,
        nonBlocking = true,
        frameBudgetSeconds = WorldConfig.StreamingImportFrameBudgetSeconds,
        preferredLookVector = lookTarget - Vector3.new(spawnPoint.X, spawnY, spawnPoint.Z),
    })
    StreamingService.Update(spawnPoint)
    print("[BootstrapAustin] StreamingService started.")
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
