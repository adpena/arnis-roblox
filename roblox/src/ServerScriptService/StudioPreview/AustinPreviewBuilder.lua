local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImportService = require(script.Parent.Parent.ImportService)
local AustinSpawn = require(script.Parent.Parent.ImportService.AustinSpawn)
local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
local Logger = require(ReplicatedStorage.Shared.Logger)

local AustinPreviewBuilder = {}

AustinPreviewBuilder.WORLD_ROOT_NAME = "GeneratedWorld_AustinPreview"
AustinPreviewBuilder.LOAD_RADIUS = 1024
AustinPreviewBuilder.FOREGROUND_LOAD_RADIUS = 448
AustinPreviewBuilder.STARTUP_CHUNK_COUNT = 2
AustinPreviewBuilder.FRAME_BUDGET_SECONDS = 1 / 240
AustinPreviewBuilder.CHUNK_FINGERPRINT_ATTR = "VertigoPreviewChunkFingerprint"
AustinPreviewBuilder.BUILD_TOKEN_ATTR = "VertigoPreviewBuildToken"
AustinPreviewBuilder.BackgroundBuild = true
AustinPreviewBuilder.PERF_PREFIX = "VertigoPreview"
AustinPreviewBuilder.PERF_FLUSH_SECONDS = 0.25
AustinPreviewBuilder.FULL_MANIFEST_INDEX_NAME = "AustinManifestIndex"
AustinPreviewBuilder.FALLBACK_PREVIEW_INDEX_NAME = "AustinPreviewManifestIndex"
AustinPreviewBuilder.FALLBACK_PREVIEW_CHUNKS_NAME = "AustinPreviewManifestChunks"
AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR = "VertigoSyncTimeTravelEpoch"

local previewPerfState = {}
local previewPerfLastFlushAt = 0
local cachedFullManifestHandle = nil
local cachedFullManifestHash = nil
local getPreviewRoot
local epochCancelNonce = 0

local function setPerfAttribute(name, value)
    Workspace:SetAttribute(AustinPreviewBuilder.PERF_PREFIX .. name, value)
end

local function setAustinAnchorAttributes(focusPoint, spawnPoint)
    if focusPoint then
        Workspace:SetAttribute("VertigoAustinFocusX", math.round(focusPoint.X))
        Workspace:SetAttribute("VertigoAustinFocusY", math.round(focusPoint.Y))
        Workspace:SetAttribute("VertigoAustinFocusZ", math.round(focusPoint.Z))
    end
    if spawnPoint then
        Workspace:SetAttribute("VertigoAustinSpawnX", math.round(spawnPoint.X))
        Workspace:SetAttribute("VertigoAustinSpawnY", math.round(spawnPoint.Y))
        Workspace:SetAttribute("VertigoAustinSpawnZ", math.round(spawnPoint.Z))
    end
end

local function updatePreviewPerf(snapshot, force)
    for key, value in pairs(snapshot) do
        previewPerfState[key] = value
    end

    local now = os.clock()
    if not force and now - previewPerfLastFlushAt < AustinPreviewBuilder.PERF_FLUSH_SECONDS then
        return
    end

    previewPerfLastFlushAt = now
    for key, value in pairs(previewPerfState) do
        setPerfAttribute(key, value)
    end
end

local function isTimeTravelHardPauseActive()
    return Workspace:GetAttribute("VertigoSyncTimeTravelHardPause") == true
end

local function getCurrentSyncHash()
    local hash = Workspace:GetAttribute("VertigoSyncHash")
    if type(hash) == "string" then
        return hash
    end
    return nil
end

local function shouldCancelBuild(buildToken, buildEpoch)
    local worldRoot = getPreviewRoot()
    if not worldRoot or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken then
        return true
    end
    return Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch
end

local function loadManifestSource()
    local timeTravelActive = isTimeTravelHardPauseActive()
    if RunService:IsStudio() then
        if not timeTravelActive then
            local currentHash = getCurrentSyncHash()
            if cachedFullManifestHandle ~= nil and cachedFullManifestHash == currentHash then
                updatePreviewPerf({
                    ManifestSource = "full-cached",
                }, true)
                return cachedFullManifestHandle
            end
        end

        local fullOk, fullManifest = pcall(function()
            return ManifestLoader.LoadNamedShardedSampleHandle(AustinPreviewBuilder.FULL_MANIFEST_INDEX_NAME, nil, {
                freshRequire = timeTravelActive,
            })
        end)
        if fullOk then
            if not timeTravelActive then
                cachedFullManifestHandle = fullManifest
                cachedFullManifestHash = getCurrentSyncHash()
            end
            updatePreviewPerf({
                ManifestSource = if timeTravelActive then "full-frozen" else "full",
            }, true)
            return fullManifest
        end
    end

    updatePreviewPerf({
        ManifestSource = "preview",
    }, true)
    return ManifestLoader.LoadShardedModuleHandle(
        script.Parent[AustinPreviewBuilder.FALLBACK_PREVIEW_INDEX_NAME],
        script.Parent[AustinPreviewBuilder.FALLBACK_PREVIEW_CHUNKS_NAME]
    )
end

local function logPreview(message, fields)
    local parts = {}
    if type(fields) == "table" then
        for key, value in pairs(fields) do
            table.insert(parts, ("%s=%s"):format(tostring(key), tostring(value)))
        end
        table.sort(parts)
    end
    if #parts > 0 then
        Logger.info("[AustinPreviewBuilder]", message, table.concat(parts, " "))
    else
        Logger.info("[AustinPreviewBuilder]", message)
    end
end

function getPreviewRoot()
    return Workspace:FindFirstChild(AustinPreviewBuilder.WORLD_ROOT_NAME)
end

local function cancelActivePreviewBuild(reason)
    local worldRoot = getPreviewRoot()
    if not worldRoot then
        return
    end

    epochCancelNonce += 1
    local buildEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR)
    worldRoot:SetAttribute(
        AustinPreviewBuilder.BUILD_TOKEN_ATTR,
        ("cancel-%s-%d"):format(tostring(buildEpoch), epochCancelNonce)
    )
    worldRoot:SetAttribute("VertigoPreviewBuildEpoch", buildEpoch)
    worldRoot:SetAttribute("VertigoPreviewHardPause", isTimeTravelHardPauseActive())
    updatePreviewPerf({
        SyncActive = false,
        SyncState = "cancelled",
        SyncPhase = reason,
    }, true)
    logPreview("sync cancelled", {
        reason = reason,
        buildEpoch = buildEpoch,
        hardPause = isTimeTravelHardPauseActive(),
    })
end

Workspace:GetAttributeChangedSignal(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR):Connect(function()
    cancelActivePreviewBuild("time-travel-epoch-signal")
end)

local function ensurePreviewRoot()
    local worldRoot = getPreviewRoot()
    if not worldRoot then
        worldRoot = Instance.new("Folder")
        worldRoot.Name = AustinPreviewBuilder.WORLD_ROOT_NAME
        worldRoot.Parent = Workspace
    end

    return worldRoot
end

local function upsertPreviewPart(parent, name, size, color, transparency, cframe)
    local part = parent:FindFirstChild(name)
    if not part then
        part = Instance.new("Part")
        part.Name = name
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Parent = parent
    end

    part.Color = color
    part.Transparency = transparency
    part.Size = size
    part.CFrame = cframe
    return part
end

local function getPreviewBounds(manifestSource, chunkIds)
    local chunkSize = manifestSource.meta and manifestSource.meta.chunkSizeStuds or 256
    local bounds = {
        minX = math.huge,
        maxX = -math.huge,
        minY = math.huge,
        maxY = -math.huge,
        minZ = math.huge,
        maxZ = -math.huge,
    }

    local function includePoint(x, y, z)
        if x < bounds.minX then
            bounds.minX = x
        end
        if x > bounds.maxX then
            bounds.maxX = x
        end
        if y < bounds.minY then
            bounds.minY = y
        end
        if y > bounds.maxY then
            bounds.maxY = y
        end
        if z < bounds.minZ then
            bounds.minZ = z
        end
        if z > bounds.maxZ then
            bounds.maxZ = z
        end
    end

    for _, chunkId in ipairs(chunkIds) do
        local chunk = manifestSource:GetChunk(chunkId)
        if chunk then
            local origin = chunk.originStuds or { x = 0, y = 0, z = 0 }
            local originX = origin.x or 0
            local originY = origin.y or 0
            local originZ = origin.z or 0

            includePoint(originX, originY, originZ)
            includePoint(originX + chunkSize, originY, originZ + chunkSize)

            local terrain = chunk.terrain
            if terrain and terrain.heights then
                for _, height in ipairs(terrain.heights) do
                    local worldY = originY + (height or 0)
                    if worldY < bounds.minY then
                        bounds.minY = worldY
                    end
                    if worldY > bounds.maxY then
                        bounds.maxY = worldY
                    end
                end
            end

            for _, building in ipairs(chunk.buildings or {}) do
                local baseY = originY + (building.baseY or 0)
                local topY = baseY + (building.height or 0)
                if baseY < bounds.minY then
                    bounds.minY = baseY
                end
                if topY > bounds.maxY then
                    bounds.maxY = topY
                end
            end

            for _, prop in ipairs(chunk.props or {}) do
                local position = prop.position
                if position then
                    local propY = originY + (position.y or 0)
                    if propY < bounds.minY then
                        bounds.minY = propY
                    end
                    if propY > bounds.maxY then
                        bounds.maxY = propY
                    end
                end
            end
        end
    end

    if bounds.minX == math.huge then
        return nil
    end

    return bounds
end

local function addPreviewBeacon(parent, manifestSource, chunkIds, focusPoint)
    focusPoint = focusPoint or AustinSpawn.resolveAnchor(manifestSource, AustinPreviewBuilder.LOAD_RADIUS).focusPoint
    local bounds = getPreviewBounds(manifestSource, chunkIds)
    local groundY = bounds and bounds.minY or focusPoint.Y
    local planeInset = 48
    local planeThickness = 1.5

    local markerFolder = parent:FindFirstChild("PreviewFocus")
    if not markerFolder then
        markerFolder = Instance.new("Folder")
        markerFolder.Name = "PreviewFocus"
        markerFolder.Parent = parent
    end

    upsertPreviewPart(
        markerFolder,
        "Pad",
        Vector3.new(16, 0.4, 16),
        Color3.fromRGB(255, 210, 64),
        0.2,
        CFrame.new(focusPoint.X, groundY + 0.2, focusPoint.Z)
    )
    upsertPreviewPart(
        markerFolder,
        "Beacon",
        Vector3.new(1.5, 40, 1.5),
        Color3.fromRGB(255, 240, 160),
        0.15,
        CFrame.new(focusPoint.X, groundY + 20, focusPoint.Z)
    )

    if bounds then
        local sizeX = math.max(32, (bounds.maxX - bounds.minX) + planeInset * 2)
        local sizeZ = math.max(32, (bounds.maxZ - bounds.minZ) + planeInset * 2)
        local centerX = (bounds.minX + bounds.maxX) * 0.5
        local centerZ = (bounds.minZ + bounds.maxZ) * 0.5
        local groundPlane = upsertPreviewPart(
            markerFolder,
            "GroundPlane",
            Vector3.new(sizeX, planeThickness, sizeZ),
            Color3.fromRGB(132, 140, 150),
            0.18,
            CFrame.new(centerX, groundY - planeThickness * 0.5, centerZ)
        )
        groundPlane.Material = Enum.Material.SmoothPlastic
        groundPlane.CanCollide = false
    end

    return markerFolder
end

local function listPreviewChunkIds(worldRoot)
    if not worldRoot then
        return {}
    end

    local chunkIds = {}
    for _, child in ipairs(worldRoot:GetChildren()) do
        if child:IsA("Folder") and child.Name ~= "PreviewFocus" then
            table.insert(chunkIds, child.Name)
        end
    end
    table.sort(chunkIds)
    return chunkIds
end

local function getPreviewChunkFolder(worldRoot, chunkId)
    if not worldRoot then
        return nil
    end

    local chunkFolder = worldRoot:FindFirstChild(chunkId)
    if chunkFolder and chunkFolder:IsA("Folder") then
        return chunkFolder
    end

    return nil
end

local function getChunkDistanceSqMap(manifestSource, focusPoint)
    local distanceByChunkId = {}
    local centerX = focusPoint and focusPoint.X or 0
    local centerZ = focusPoint and focusPoint.Z or 0
    local chunkSize = manifestSource.meta and manifestSource.meta.chunkSizeStuds or 256

    for _, chunkRef in ipairs(manifestSource.chunkRefs or {}) do
        local origin = chunkRef.originStuds or { x = 0, z = 0 }
        local chunkCenterX = origin.x + chunkSize * 0.5
        local chunkCenterZ = origin.z + chunkSize * 0.5
        local dx = chunkCenterX - centerX
        local dz = chunkCenterZ - centerZ
        distanceByChunkId[chunkRef.id] = dx * dx + dz * dz
    end

    return distanceByChunkId
end

local function orderChunkIdsByDistance(chunkIds, distanceByChunkId)
    table.sort(chunkIds, function(a, b)
        local distA = distanceByChunkId[a] or math.huge
        local distB = distanceByChunkId[b] or math.huge
        if distA == distB then
            return a < b
        end
        return distA < distB
    end)
end

local function splitChunkIdsByRadius(chunkIds, distanceByChunkId, radius)
    local foreground = {}
    local background = {}
    local radiusSq = radius * radius

    for _, chunkId in ipairs(chunkIds) do
        local distSq = distanceByChunkId[chunkId] or math.huge
        if distSq <= radiusSq then
            table.insert(foreground, chunkId)
        else
            table.insert(background, chunkId)
        end
    end

    return foreground, background
end

local function syncChunkBatch(manifestSource, worldRoot, buildToken, chunkIds, counters, phaseName)
    local sliceStart = os.clock()
    local buildEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR)

    updatePreviewPerf({
        SyncPhase = phaseName,
        SyncPhaseTargetChunks = #chunkIds,
    }, false)

    for _, chunkId in ipairs(chunkIds) do
        if worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken then
            logPreview("sync cancelled", {
                reason = "build-token-changed",
                phase = phaseName,
                buildToken = buildToken,
                currentToken = worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR),
                buildEpoch = buildEpoch,
                currentEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR),
            })
            updatePreviewPerf({
                SyncActive = false,
                SyncState = "cancelled",
                SyncPhase = phaseName,
            }, true)
            return false
        end
        if Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch then
            logPreview("sync cancelled", {
                reason = "time-travel-epoch-changed",
                phase = phaseName,
                buildToken = buildToken,
                buildEpoch = buildEpoch,
                currentEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR),
            })
            updatePreviewPerf({
                SyncActive = false,
                SyncState = "cancelled",
                SyncPhase = phaseName,
            }, true)
            return false
        end

        local expectedFingerprint = manifestSource:GetChunkFingerprint(chunkId)
        local existingChunkFolder = getPreviewChunkFolder(worldRoot, chunkId)
        local existingFingerprint = existingChunkFolder
            and existingChunkFolder:GetAttribute(AustinPreviewBuilder.CHUNK_FINGERPRINT_ATTR)
        if existingFingerprint ~= expectedFingerprint then
            local chunk = manifestSource:GetChunk(chunkId)
            local chunkFolder = ImportService.ImportChunk(chunk, {
                worldRootName = AustinPreviewBuilder.WORLD_ROOT_NAME,
                nonBlocking = true,
                frameBudgetSeconds = AustinPreviewBuilder.FRAME_BUDGET_SECONDS,
                shouldCancel = function()
                    return shouldCancelBuild(buildToken, buildEpoch)
                end,
            })
            if chunkFolder == nil then
                logPreview("sync cancelled", {
                    reason = "chunk-import-cancelled",
                    phase = phaseName,
                    chunkId = chunkId,
                    buildToken = buildToken,
                    buildEpoch = buildEpoch,
                    currentEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR),
                })
                updatePreviewPerf({
                    SyncActive = false,
                    SyncState = "cancelled",
                    SyncPhase = phaseName,
                }, true)
                return false
            end
            chunkFolder:SetAttribute(AustinPreviewBuilder.CHUNK_FINGERPRINT_ATTR, expectedFingerprint)
            counters.imported += 1
            counters.yields += 1
            updatePreviewPerf({
                SyncLoadedChunks = counters.imported + counters.skipped,
                SyncImportedChunks = counters.imported,
                SyncSkippedChunks = counters.skipped,
                SyncUnloadedChunks = counters.unloaded,
                SyncYieldCount = counters.yields,
                SyncPhase = phaseName,
            }, false)
            task.wait()
            worldRoot = getPreviewRoot()
            if
                not worldRoot
                or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
                or Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch
            then
                logPreview("sync cancelled", {
                    reason = "post-import-state-changed",
                    phase = phaseName,
                    chunkId = chunkId,
                    buildToken = buildToken,
                    buildEpoch = buildEpoch,
                    currentEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR),
                })
                updatePreviewPerf({
                    SyncActive = false,
                    SyncState = "cancelled",
                    SyncPhase = phaseName,
                }, true)
                return false
            end
            sliceStart = os.clock()
        else
            counters.skipped += 1
        end

        if os.clock() - sliceStart >= AustinPreviewBuilder.FRAME_BUDGET_SECONDS then
            counters.yields += 1
            updatePreviewPerf({
                SyncLoadedChunks = counters.imported + counters.skipped,
                SyncImportedChunks = counters.imported,
                SyncSkippedChunks = counters.skipped,
                SyncUnloadedChunks = counters.unloaded,
                SyncYieldCount = counters.yields,
                SyncPhase = phaseName,
            }, false)
            task.wait()
            worldRoot = getPreviewRoot()
            if not worldRoot or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken then
                logPreview("sync cancelled", {
                    reason = "yield-state-changed",
                    phase = phaseName,
                    buildToken = buildToken,
                    buildEpoch = buildEpoch,
                    currentEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR),
                })
                updatePreviewPerf({
                    SyncActive = false,
                    SyncState = "cancelled",
                    SyncPhase = phaseName,
                }, true)
                return false
            end
            sliceStart = os.clock()
        end
    end

    return true
end

local function syncPreviewChunks(manifestSource, focusPoint, buildToken)
    local syncStartedAt = os.clock()
    local desiredChunkIds = manifestSource:GetChunkIdsWithinRadius(focusPoint, AustinPreviewBuilder.LOAD_RADIUS)
    local distanceByChunkId = getChunkDistanceSqMap(manifestSource, focusPoint)
    orderChunkIdsByDistance(desiredChunkIds, distanceByChunkId)
    local foregroundChunkIds, backgroundChunkIds =
        splitChunkIdsByRadius(desiredChunkIds, distanceByChunkId, AustinPreviewBuilder.FOREGROUND_LOAD_RADIUS)
    local startupChunkIds = {}
    local deferredForegroundChunkIds = {}
    local desiredChunkSet = {}
    local counters = {
        unloaded = 0,
        imported = 0,
        skipped = 0,
        yields = 0,
    }

    updatePreviewPerf({
        SyncActive = true,
        SyncState = "running",
        SyncTargetChunks = #desiredChunkIds,
        SyncStartupTargetChunks = 0,
        SyncForegroundTargetChunks = #foregroundChunkIds,
        SyncBackgroundTargetChunks = #backgroundChunkIds,
        SyncPhase = "startup",
        SyncPhaseTargetChunks = 0,
        SyncLoadedChunks = 0,
        SyncImportedChunks = 0,
        SyncSkippedChunks = 0,
        SyncUnloadedChunks = 0,
        SyncYieldCount = 0,
    }, true)

    for _, chunkId in ipairs(desiredChunkIds) do
        desiredChunkSet[chunkId] = true
    end

    for index, chunkId in ipairs(foregroundChunkIds) do
        if index <= AustinPreviewBuilder.STARTUP_CHUNK_COUNT then
            table.insert(startupChunkIds, chunkId)
        else
            table.insert(deferredForegroundChunkIds, chunkId)
        end
    end

    updatePreviewPerf({
        SyncStartupTargetChunks = #startupChunkIds,
        SyncForegroundTargetChunks = #deferredForegroundChunkIds,
        SyncBackgroundTargetChunks = #backgroundChunkIds,
        SyncPhaseTargetChunks = #startupChunkIds,
    }, true)

    local worldRoot = getPreviewRoot()
    local buildEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR)
    if not worldRoot or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken then
        updatePreviewPerf({
            SyncActive = false,
            SyncState = "cancelled",
        }, true)
        return {}
    end

    for _, loadedChunkId in ipairs(listPreviewChunkIds(worldRoot)) do
        if
            worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
            or Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch
        then
            updatePreviewPerf({
                SyncActive = false,
                SyncState = "cancelled",
            }, true)
            return desiredChunkIds
        end
        if not desiredChunkSet[loadedChunkId] then
            ChunkLoader.UnloadChunk(loadedChunkId)
            local orphan = worldRoot and worldRoot:FindFirstChild(loadedChunkId)
            if orphan then
                orphan:Destroy()
            end
            counters.unloaded += 1
            counters.yields += 1
            task.wait()
            worldRoot = getPreviewRoot()
            if
                not worldRoot
                or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
                or Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch
            then
                updatePreviewPerf({
                    SyncActive = false,
                    SyncState = "cancelled",
                }, true)
                return desiredChunkIds
            end
        end
    end

    if not syncChunkBatch(manifestSource, worldRoot, buildToken, startupChunkIds, counters, "startup") then
        return desiredChunkIds
    end

    if #deferredForegroundChunkIds > 0 then
        updatePreviewPerf({
            SyncPhase = "foreground",
            SyncPhaseTargetChunks = #deferredForegroundChunkIds,
        }, true)
        if
            not syncChunkBatch(
                manifestSource,
                worldRoot,
                buildToken,
                deferredForegroundChunkIds,
                counters,
                "foreground"
            )
        then
            return desiredChunkIds
        end
    end

    if #backgroundChunkIds > 0 then
        updatePreviewPerf({
            SyncPhase = "background",
            SyncPhaseTargetChunks = #backgroundChunkIds,
        }, true)
    end
    if not syncChunkBatch(manifestSource, worldRoot, buildToken, backgroundChunkIds, counters, "background") then
        return desiredChunkIds
    end

    local syncElapsedMs = (os.clock() - syncStartedAt) * 1000
    local avgMs = Workspace:GetAttribute(AustinPreviewBuilder.PERF_PREFIX .. "AvgMs") or 0
    local maxMs = Workspace:GetAttribute(AustinPreviewBuilder.PERF_PREFIX .. "MaxMs") or 0
    local samples = Workspace:GetAttribute(AustinPreviewBuilder.PERF_PREFIX .. "Samples") or 0
    samples += 1
    if samples == 1 then
        avgMs = syncElapsedMs
    else
        avgMs = avgMs * 0.85 + syncElapsedMs * 0.15
    end
    if syncElapsedMs > maxMs then
        maxMs = syncElapsedMs
    end

    updatePreviewPerf({
        SyncActive = false,
        SyncState = "idle",
        SyncPhase = "idle",
        SyncLoadedChunks = counters.imported + counters.skipped,
        SyncImportedChunks = counters.imported,
        SyncSkippedChunks = counters.skipped,
        SyncUnloadedChunks = counters.unloaded,
        SyncYieldCount = counters.yields,
        LastMs = syncElapsedMs,
        AvgMs = avgMs,
        MaxMs = maxMs,
        Samples = samples,
    }, true)

    logPreview("sync complete", {
        buildToken = buildToken,
        buildEpoch = buildEpoch,
        hardPause = isTimeTravelHardPauseActive(),
        imported = counters.imported,
        skipped = counters.skipped,
        unloaded = counters.unloaded,
        targetChunks = #desiredChunkIds,
        elapsedMs = math.floor(syncElapsedMs + 0.5),
    })

    return desiredChunkIds
end

function AustinPreviewBuilder.Clear()
    local existing = getPreviewRoot()
    if existing then
        for _, chunkId in ipairs(listPreviewChunkIds(existing)) do
            ChunkLoader.UnloadChunk(chunkId)
        end
        existing:Destroy()
    end
end

function AustinPreviewBuilder.Build()
    local hardPause = isTimeTravelHardPauseActive()

    local worldRoot = ensurePreviewRoot()
    local buildToken = HttpService:GenerateGUID(false)
    local buildEpoch = Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR)
    worldRoot:SetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR, buildToken)
    worldRoot:SetAttribute("VertigoPreviewBuildEpoch", buildEpoch)
    worldRoot:SetAttribute("VertigoPreviewHardPause", hardPause)
    logPreview("build scheduled", {
        buildToken = buildToken,
        buildEpoch = buildEpoch,
        hardPause = hardPause,
        manifestSource = "pending",
        syncHash = Workspace:GetAttribute("VertigoSyncHash"),
    })
    updatePreviewPerf({
        SyncActive = true,
        SyncState = "scheduled",
        SyncTargetChunks = 0,
        SyncStartupTargetChunks = 0,
        SyncForegroundTargetChunks = 0,
        SyncBackgroundTargetChunks = 0,
        SyncPhase = "scheduled",
        SyncPhaseTargetChunks = 0,
        SyncLoadedChunks = 0,
        SyncImportedChunks = 0,
        SyncSkippedChunks = 0,
        SyncUnloadedChunks = 0,
        SyncYieldCount = 0,
    }, true)

    task.spawn(function()
        local liveWorldRoot = getPreviewRoot()
        if
            not liveWorldRoot
            or liveWorldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
            or Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch
        then
            return
        end

        local manifestSource = loadManifestSource()
        liveWorldRoot = getPreviewRoot()
        if
            not liveWorldRoot
            or liveWorldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
            or Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch
        then
            return
        end

        local anchor = AustinSpawn.resolveAnchor(manifestSource, AustinPreviewBuilder.LOAD_RADIUS)
        local focusPoint = anchor.focusPoint
        local spawnPoint = anchor.spawnPoint
        setAustinAnchorAttributes(focusPoint, spawnPoint)
        logPreview("anchor resolved", {
            focusX = math.round(focusPoint.X),
            focusY = math.round(focusPoint.Y),
            focusZ = math.round(focusPoint.Z),
            spawnX = math.round(spawnPoint.X),
            spawnY = math.round(spawnPoint.Y),
            spawnZ = math.round(spawnPoint.Z),
        })
        local previewChunkIds = manifestSource:GetChunkIdsWithinRadius(focusPoint, AustinPreviewBuilder.LOAD_RADIUS)
        if hardPause then
            manifestSource = ManifestLoader.FreezeHandleForChunkIds(manifestSource, previewChunkIds)
        end

        liveWorldRoot = getPreviewRoot()
        if
            not liveWorldRoot
            or liveWorldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
            or Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) ~= buildEpoch
        then
            return
        end

        addPreviewBeacon(liveWorldRoot, manifestSource, previewChunkIds, focusPoint)
        syncPreviewChunks(manifestSource, focusPoint, buildToken)
    end)

    return { worldRoot }
end

return AustinPreviewBuilder
