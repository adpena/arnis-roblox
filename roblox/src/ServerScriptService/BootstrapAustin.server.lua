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
local MinimapService = require(script.Parent.ImportService.MinimapService)
local RunAustin = require(script.Parent.ImportService.RunAustin)
local StreamingService = require(script.Parent.ImportService.StreamingService)
local SubplanRollout = require(script.Parent.ImportService.SubplanRollout)
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.WorldConfig)
local StreamingRuntimeConfig = require(game:GetService("ReplicatedStorage").Shared.StreamingRuntimeConfig)

local BOOTSTRAP_STATE_ATTR = "ArnisAustinBootstrapState"
local BOOTSTRAP_STATE_ORDER_ATTR = "ArnisAustinBootstrapStateOrder"
local BOOTSTRAP_FAILURE_ATTR = "ArnisAustinBootstrapFailure"
local BOOTSTRAP_DUPLICATE_COUNT_ATTR = "ArnisAustinBootstrapDuplicateCount"
local BOOTSTRAP_ENTRY_COUNT_ATTR = "ArnisAustinBootstrapEntryCount"
local BOOTSTRAP_LAST_SCRIPT_PATH_ATTR = "ArnisAustinBootstrapLastScriptPath"
local BOOTSTRAP_STATES = table.freeze({
    loading_manifest = 1,
    importing_startup = 2,
    world_ready = 3,
    streaming_ready = 4,
    minimap_ready = 5,
    gameplay_ready = 6,
    failed = 7,
})

if not RunService:IsStudio() then
    warn("[BootstrapAustin] Refusing to auto-import Austin outside Studio.")
    return
end

local function setBootstrapState(state, failureMessage)
    local stateOrder = BOOTSTRAP_STATES[state]
    if stateOrder == nil then
        error(("[BootstrapAustin] Unknown bootstrap state %s"):format(tostring(state)), 0)
    end

    local currentState = Workspace:GetAttribute(BOOTSTRAP_STATE_ATTR)
    local currentOrder = Workspace:GetAttribute(BOOTSTRAP_STATE_ORDER_ATTR) or 0
    if state ~= "failed" and type(currentOrder) == "number" and currentOrder > stateOrder then
        error(
            ("[BootstrapAustin] Invalid bootstrap transition %s -> %s"):format(tostring(currentState), state),
            0
        )
    end

    Workspace:SetAttribute(BOOTSTRAP_STATE_ATTR, state)
    Workspace:SetAttribute(BOOTSTRAP_STATE_ORDER_ATTR, stateOrder)
    Workspace:SetAttribute(BOOTSTRAP_FAILURE_ATTR, failureMessage or "")
    print(("[BootstrapAustin] state=%s"):format(state))
end

local entryCount = (Workspace:GetAttribute(BOOTSTRAP_ENTRY_COUNT_ATTR) or 0) + 1
Workspace:SetAttribute(BOOTSTRAP_ENTRY_COUNT_ATTR, entryCount)
Workspace:SetAttribute(BOOTSTRAP_LAST_SCRIPT_PATH_ATTR, script:GetFullName())

local existingBootstrapState = Workspace:GetAttribute(BOOTSTRAP_STATE_ATTR)
if type(existingBootstrapState) == "string" and existingBootstrapState ~= "" then
    local duplicateCount = (Workspace:GetAttribute(BOOTSTRAP_DUPLICATE_COUNT_ATTR) or 0) + 1
    Workspace:SetAttribute(BOOTSTRAP_DUPLICATE_COUNT_ATTR, duplicateCount)
    setBootstrapState("failed", "duplicate bootstrap entry")
    error(
        ("[BootstrapAustin] Duplicate bootstrap entry detected. state=%s entries=%d script=%s"):format(
            existingBootstrapState,
            entryCount,
            script:GetFullName()
        ),
        0
    )
end

Workspace:SetAttribute(BOOTSTRAP_DUPLICATE_COUNT_ATTR, 0)
Workspace:SetAttribute(BOOTSTRAP_STATE_ORDER_ATTR, 0)
Workspace:SetAttribute(BOOTSTRAP_FAILURE_ATTR, "")

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
    local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
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

local function configureLighting()
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

    local atmo = Instance.new("Atmosphere")
    atmo.Density = 0.35
    atmo.Offset = 0.2
    atmo.Color = Color3.fromRGB(255, 220, 170) -- warm Texas haze
    atmo.Decay = Color3.fromRGB(100, 80, 60)
    atmo.Glare = 0.4
    atmo.Haze = 1.8
    atmo.Parent = Lighting

    local bloom = Instance.new("BloomEffect")
    bloom.Intensity = 0.4
    bloom.Size = 24
    bloom.Threshold = 0.95
    bloom.Parent = Lighting

    local sunRays = Instance.new("SunRaysEffect")
    sunRays.Intensity = 0.08
    sunRays.Spread = 0.5
    sunRays.Parent = Lighting

    local cc = Instance.new("ColorCorrectionEffect")
    cc.Brightness = 0.02
    cc.Contrast = 0.08
    cc.Saturation = 0.15
    cc.TintColor = Color3.fromRGB(255, 248, 235)
    cc.Parent = Lighting
end

local function destroyHoldingPad()
    if holdingPad then
        holdingPad:Destroy()
        holdingPad = nil
    end
end

local function restoreCharacterLoading()
    Players.CharacterAutoLoads = true
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            moveCharacterToSpawn(player.Character)
        else
            player:LoadCharacter()
        end
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    onPlayer(player)
end
Players.PlayerAdded:Connect(onPlayer)

local function runBootstrap()
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

    local runtimeWorldConfig = StreamingRuntimeConfig.Resolve(WorldConfig)
    local startupImportConfig = table.clone(runtimeWorldConfig)
    startupImportConfig.EnableMinimap = false

    local result = RunAustin.run({
        onBootstrapState = setBootstrapState,
        importConfig = startupImportConfig,
    })
    if result == nil then
        error("[BootstrapAustin] Austin manifest unavailable; skipping bootstrap.", 0)
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

    setBootstrapState("world_ready")

    if runtimeWorldConfig.StreamingEnabled then
        local rolloutDescription = SubplanRollout.Describe(runtimeWorldConfig)
        print(
            ("[BootstrapAustin] Streaming profile=%s rollout enabled=%s mode=%s layers=%d chunks=%d"):format(
                tostring(runtimeWorldConfig.StreamingProfile),
                tostring(rolloutDescription.enabled),
                tostring(rolloutDescription.mode),
                rolloutDescription.allowedLayerCount,
                rolloutDescription.allowlistedChunkCount
            )
        )
        StreamingService.Start(manifestSource, {
            worldRootName = "GeneratedWorld_Austin",
            config = runtimeWorldConfig,
            nonBlocking = true,
            frameBudgetSeconds = runtimeWorldConfig.StreamingImportFrameBudgetSeconds,
            preferredLookVector = lookTarget - Vector3.new(spawnPoint.X, spawnY, spawnPoint.Z),
        })
        StreamingService.Update(spawnPoint)
        print("[BootstrapAustin] StreamingService started.")
    end

    setBootstrapState("streaming_ready")

    if runtimeWorldConfig.EnableMinimap ~= false then
        MinimapService.Start()
    end

    setBootstrapState("minimap_ready")

    destroyHoldingPad()
    configureLighting()

    importReady = true
    Players.CharacterAutoLoads = true
    restoreCharacterLoading()
    setBootstrapState("gameplay_ready")

    print("[BootstrapAustin] Spawn and atmosphere configured.")
end

local ok, bootstrapErr = xpcall(runBootstrap, function(runtimeError)
    return tostring(runtimeError)
end)

if not ok then
    setBootstrapState("failed", tostring(bootstrapErr))
    destroyHoldingPad()
    restoreCharacterLoading()
    warn(tostring(bootstrapErr))
end
