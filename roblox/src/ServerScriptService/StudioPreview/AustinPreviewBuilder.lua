local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImportService = require(script.Parent.Parent.ImportService)
local AustinSpawn = require(script.Parent.Parent.ImportService.AustinSpawn)
local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
local SubplanRollout = require(script.Parent.Parent.ImportService.SubplanRollout)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
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
AustinPreviewBuilder.SLOW_CHUNK_LOG_THRESHOLD_MS = 150
AustinPreviewBuilder.FULL_MANIFEST_INDEX_NAME = "AustinManifestIndex"
AustinPreviewBuilder.FALLBACK_PREVIEW_INDEX_NAME = "AustinPreviewManifestIndex"
AustinPreviewBuilder.FALLBACK_PREVIEW_CHUNKS_NAME = "AustinPreviewManifestChunks"
AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR = "VertigoSyncTimeTravelEpoch"
AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR = "VertigoSyncPreviewInvalidationEpoch"

local previewPerfState = {}
local previewPerfLastFlushAt = 0
local cachedFullManifestHandle = nil
local cachedFullManifestHash = nil
local observedChunkCostById = {}
local semanticFingerprintCacheByHandle = setmetatable({}, { __mode = "k" })
local getPreviewRoot
local deferredPreviewInvalidationEpoch = nil

local function getPreviewSubplanRollout()
    return SubplanRollout.Describe(DefaultWorldConfig)
end

local function sortPendingSubplans(pending)
    if #pending <= 1 then
        return pending
    end

    local decorated = table.create(#pending)
    for index, subplan in ipairs(pending) do
        decorated[index] = {
            subplan = subplan,
            sourceOrder = index,
        }
    end

    table.sort(decorated, function(left, right)
        local leftRank = ChunkPriority.GetCanonicalLayerRank(left.subplan)
        local rightRank = ChunkPriority.GetCanonicalLayerRank(right.subplan)
        if leftRank ~= rightRank then
            return leftRank < rightRank
        end
        return left.sourceOrder < right.sourceOrder
    end)

    for index, entry in ipairs(decorated) do
        pending[index] = entry.subplan
    end

    return pending
end

local function getPendingPreviewSubplans(chunkRef, options)
    local allowedSubplans = SubplanRollout.GetFullySchedulableSubplans(chunkRef, DefaultWorldConfig)
    if allowedSubplans == nil then
        return nil
    end

    if type(options) == "table" and options.forceAll == true then
        return sortPendingSubplans(table.clone(allowedSubplans))
    end

    local state = ImportService.GetSubplanState(chunkRef.id)
    local pending = {}
    for _, subplan in ipairs(allowedSubplans) do
        local layer = if type(subplan) == "table" then subplan.layer or subplan.id else nil
        if type(layer) == "string" and not state.importedLayers[layer] then
            pending[#pending + 1] = subplan
        end
    end

    return sortPendingSubplans(pending)
end

local function appendSemanticFingerprintValue(buffer, value)
    local valueType = type(value)
    if valueType == "table" then
        local arrayLength = #value
        if arrayLength > 0 then
            buffer[#buffer + 1] = "["
            for index = 1, arrayLength do
                if index > 1 then
                    buffer[#buffer + 1] = ","
                end
                appendSemanticFingerprintValue(buffer, value[index])
            end
            buffer[#buffer + 1] = "]"
            return
        end

        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(left, right)
            local leftType = type(left)
            local rightType = type(right)
            if leftType ~= rightType then
                return leftType < rightType
            end
            if leftType == "number" or leftType == "string" then
                return left < right
            end
            return tostring(left) < tostring(right)
        end)

        buffer[#buffer + 1] = "{"
        for index, key in ipairs(keys) do
            if index > 1 then
                buffer[#buffer + 1] = ","
            end
            buffer[#buffer + 1] = tostring(key)
            buffer[#buffer + 1] = "="
            appendSemanticFingerprintValue(buffer, value[key])
        end
        buffer[#buffer + 1] = "}"
        return
    end

    if valueType == "number" then
        buffer[#buffer + 1] = string.format("%.17g", value)
    elseif valueType == "string" then
        buffer[#buffer + 1] = value
    elseif valueType == "boolean" then
        buffer[#buffer + 1] = if value then "true" else "false"
    elseif value == nil then
        buffer[#buffer + 1] = "nil"
    else
        buffer[#buffer + 1] = tostring(value)
    end
end

local function getSemanticChunkFingerprint(manifestSource, chunkId)
    local cacheByChunkId = semanticFingerprintCacheByHandle[manifestSource]
    if cacheByChunkId == nil then
        cacheByChunkId = {}
        semanticFingerprintCacheByHandle[manifestSource] = cacheByChunkId
    end

    local cached = cacheByChunkId[chunkId]
    if cached ~= nil then
        return cached
    end

    local chunk = manifestSource:GetChunk(chunkId)
    local buffer = {}
    appendSemanticFingerprintValue(buffer, chunk)
    cached = table.concat(buffer)
    cacheByChunkId[chunkId] = cached
    return cached
end

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

local function shouldCancelBuild(buildToken)
    local worldRoot = getPreviewRoot()
    if
        not worldRoot
        or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
    then
        return true
    end
    return false
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
            return ManifestLoader.LoadNamedShardedSampleHandle(
                AustinPreviewBuilder.FULL_MANIFEST_INDEX_NAME,
                nil,
                {
                    freshRequire = timeTravelActive,
                }
            )
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
    local fieldCount = 0
    if type(fields) == "table" then
        for _ in pairs(fields) do
            fieldCount += 1
        end
    end
    local parts = table.create(fieldCount)
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

local function measureMs(timings, key, fn)
    local startedAt = os.clock()
    local result = fn()
    timings[key] = (os.clock() - startedAt) * 1000
    return result
end

local function recordSlowChunkSample(phaseName, sample)
    if type(sample) ~= "table" then
        return
    end
    local totalMs = tonumber(sample.totalMs) or 0
    local chunkId = sample.chunkId
    if type(chunkId) == "string" and chunkId ~= "" and totalMs > 0 then
        local previous = observedChunkCostById[chunkId]
        if previous == nil then
            observedChunkCostById[chunkId] = totalMs
        else
            observedChunkCostById[chunkId] = previous * 0.7 + totalMs * 0.3
        end
    end
    if totalMs < AustinPreviewBuilder.SLOW_CHUNK_LOG_THRESHOLD_MS then
        return
    end

    updatePreviewPerf({
        SlowChunkId = sample.chunkId,
        SlowChunkPhase = phaseName,
        SlowChunkMs = math.floor(totalMs + 0.5),
        SlowChunkRoadsMs = math.floor((tonumber(sample.roadsMs) or 0) + 0.5),
        SlowChunkRoadSurfacesMs = math.floor((tonumber(sample.roadsSurfaceMs) or 0) + 0.5),
        SlowChunkRoadDecorationsMs = math.floor((tonumber(sample.roadsDecorationMs) or 0) + 0.5),
        SlowChunkRoadSurfaceAccumulators = tonumber(sample.roadSurfaceAccumulatorCount) or 0,
        SlowChunkRoadSurfaceMeshes = tonumber(sample.roadSurfaceMeshPartCount) or 0,
        SlowChunkRoadSurfaceSegments = tonumber(sample.roadSurfaceSegmentCount) or 0,
        SlowChunkRoadSurfaceRoads = tonumber(sample.roadSurfaceRoadCount) or 0,
        SlowChunkRoadSurfaceVertices = tonumber(sample.roadSurfaceVertexCount) or 0,
        SlowChunkRoadSurfaceTriangles = tonumber(sample.roadSurfaceTriangleCount) or 0,
        SlowChunkRoadSurfaceMeshCreateMs = math.floor(
            (tonumber(sample.roadSurfaceMeshCreateMs) or 0) + 0.5
        ),
        SlowChunkRoadImprintMs = math.floor((tonumber(sample.roadImprintMs) or 0) + 0.5),
        SlowChunkBuildingsMs = math.floor((tonumber(sample.buildingsMs) or 0) + 0.5),
        SlowChunkBuildingMeshes = tonumber(sample.buildingMeshPartCount) or 0,
        SlowChunkBuildingRoofMeshes = tonumber(sample.buildingRoofMeshPartCount) or 0,
        SlowChunkBuildingVertices = tonumber(sample.buildingMeshVertexCount) or 0,
        SlowChunkBuildingTriangles = tonumber(sample.buildingMeshTriangleCount) or 0,
        SlowChunkBuildingMeshCreateMs = math.floor(
            (tonumber(sample.buildingMeshCreateMs) or 0) + 0.5
        ),
        SlowChunkTerrainMs = math.floor((tonumber(sample.terrainMs) or 0) + 0.5),
        SlowChunkLanduseMs = math.floor((tonumber(sample.landuseMs) or 0) + 0.5),
        SlowChunkLandusePlanMs = math.floor((tonumber(sample.landusePlanMs) or 0) + 0.5),
        SlowChunkLanduseExecuteMs = math.floor((tonumber(sample.landuseExecuteMs) or 0) + 0.5),
        SlowChunkLanduseTerrainFillMs = math.floor(
            (tonumber(sample.landuseTerrainFillMs) or 0) + 0.5
        ),
        SlowChunkLanduseDetailMs = math.floor((tonumber(sample.landuseDetailMs) or 0) + 0.5),
        SlowChunkLanduseCells = tonumber(sample.landuseCellCount) or 0,
        SlowChunkLanduseRects = tonumber(sample.landuseRectCount) or 0,
        SlowChunkLanduseDetailInstances = tonumber(sample.landuseDetailInstanceCount) or 0,
        SlowChunkPropsMs = math.floor((tonumber(sample.propsMs) or 0) + 0.5),
        SlowChunkPropFeatureCount = tonumber(sample.propFeatureCount) or 0,
        SlowChunkPropKindCount = tonumber(sample.propKindCount) or 0,
        SlowChunkPropTopKind1Count = tonumber(sample.propTopKind1Count) or 0,
        SlowChunkPropTopKind1Ms = math.floor((tonumber(sample.propTopKind1Ms) or 0) + 0.5),
        SlowChunkPropTopKind2Count = tonumber(sample.propTopKind2Count) or 0,
        SlowChunkPropTopKind2Ms = math.floor((tonumber(sample.propTopKind2Ms) or 0) + 0.5),
        SlowChunkPropTopKind3Count = tonumber(sample.propTopKind3Count) or 0,
        SlowChunkPropTopKind3Ms = math.floor((tonumber(sample.propTopKind3Ms) or 0) + 0.5),
        SlowChunkAmbientMs = math.floor((tonumber(sample.ambientMs) or 0) + 0.5),
        SlowChunkArtifacts = tonumber(sample.artifactCount) or 0,
    }, false)

    logPreview("slow chunk", {
        phase = phaseName,
        chunkId = sample.chunkId,
        totalMs = math.floor(totalMs + 0.5),
        terrainMs = math.floor((tonumber(sample.terrainMs) or 0) + 0.5),
        landuseMs = math.floor((tonumber(sample.landuseMs) or 0) + 0.5),
        landusePlanMs = math.floor((tonumber(sample.landusePlanMs) or 0) + 0.5),
        landuseExecuteMs = math.floor((tonumber(sample.landuseExecuteMs) or 0) + 0.5),
        landuseTerrainFillMs = math.floor((tonumber(sample.landuseTerrainFillMs) or 0) + 0.5),
        landuseDetailMs = math.floor((tonumber(sample.landuseDetailMs) or 0) + 0.5),
        landuseCellCount = tonumber(sample.landuseCellCount) or 0,
        landuseRectCount = tonumber(sample.landuseRectCount) or 0,
        landuseDetailInstanceCount = tonumber(sample.landuseDetailInstanceCount) or 0,
        roadsMs = math.floor((tonumber(sample.roadsMs) or 0) + 0.5),
        roadsSurfaceMs = math.floor((tonumber(sample.roadsSurfaceMs) or 0) + 0.5),
        roadsDecorationMs = math.floor((tonumber(sample.roadsDecorationMs) or 0) + 0.5),
        roadSurfaceAccumulatorCount = tonumber(sample.roadSurfaceAccumulatorCount) or 0,
        roadSurfaceMeshPartCount = tonumber(sample.roadSurfaceMeshPartCount) or 0,
        roadSurfaceSegmentCount = tonumber(sample.roadSurfaceSegmentCount) or 0,
        roadSurfaceRoadCount = tonumber(sample.roadSurfaceRoadCount) or 0,
        roadSurfaceVertexCount = tonumber(sample.roadSurfaceVertexCount) or 0,
        roadSurfaceTriangleCount = tonumber(sample.roadSurfaceTriangleCount) or 0,
        roadSurfaceMeshCreateMs = math.floor((tonumber(sample.roadSurfaceMeshCreateMs) or 0) + 0.5),
        roadImprintMs = math.floor((tonumber(sample.roadImprintMs) or 0) + 0.5),
        barriersMs = math.floor((tonumber(sample.barriersMs) or 0) + 0.5),
        buildingsMs = math.floor((tonumber(sample.buildingsMs) or 0) + 0.5),
        buildingMeshPartCount = tonumber(sample.buildingMeshPartCount) or 0,
        buildingRoofMeshPartCount = tonumber(sample.buildingRoofMeshPartCount) or 0,
        buildingMeshVertexCount = tonumber(sample.buildingMeshVertexCount) or 0,
        buildingMeshTriangleCount = tonumber(sample.buildingMeshTriangleCount) or 0,
        buildingMeshCreateMs = math.floor((tonumber(sample.buildingMeshCreateMs) or 0) + 0.5),
        waterMs = math.floor((tonumber(sample.waterMs) or 0) + 0.5),
        propsMs = math.floor((tonumber(sample.propsMs) or 0) + 0.5),
        propFeatureCount = tonumber(sample.propFeatureCount) or 0,
        propKindCount = tonumber(sample.propKindCount) or 0,
        propTopKind1 = sample.propTopKind1,
        propTopKind1Count = tonumber(sample.propTopKind1Count) or 0,
        propTopKind1Ms = math.floor((tonumber(sample.propTopKind1Ms) or 0) + 0.5),
        propTopKind2 = sample.propTopKind2,
        propTopKind2Count = tonumber(sample.propTopKind2Count) or 0,
        propTopKind2Ms = math.floor((tonumber(sample.propTopKind2Ms) or 0) + 0.5),
        propTopKind3 = sample.propTopKind3,
        propTopKind3Count = tonumber(sample.propTopKind3Count) or 0,
        propTopKind3Ms = math.floor((tonumber(sample.propTopKind3Ms) or 0) + 0.5),
        ambientMs = math.floor((tonumber(sample.ambientMs) or 0) + 0.5),
        artifactCount = tonumber(sample.artifactCount) or 0,
    })
end

function getPreviewRoot()
    return Workspace:FindFirstChild(AustinPreviewBuilder.WORLD_ROOT_NAME)
end

Workspace:GetAttributeChangedSignal(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR):Connect(function()
    if not isTimeTravelHardPauseActive() then
        return
    end

    local worldRoot = getPreviewRoot()
    if not worldRoot then
        return
    end

    local currentTimeTravelEpoch =
        Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR)
    worldRoot:SetAttribute("VertigoPreviewDeferredTimeTravelEpoch", currentTimeTravelEpoch)
    if Workspace:GetAttribute(AustinPreviewBuilder.PERF_PREFIX .. "SyncActive") == true then
        logPreview("time-travel epoch deferred", {
            buildToken = worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR),
            deferredEpoch = currentTimeTravelEpoch,
        })
    end
end)

Workspace:GetAttributeChangedSignal(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
    :Connect(function()
        local worldRoot = getPreviewRoot()
        deferredPreviewInvalidationEpoch =
            Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
        if not worldRoot then
            return
        end

        worldRoot:SetAttribute(
            "VertigoPreviewDeferredInvalidationEpoch",
            deferredPreviewInvalidationEpoch
        )
        if Workspace:GetAttribute(AustinPreviewBuilder.PERF_PREFIX .. "SyncActive") == true then
            logPreview("preview invalidation deferred", {
                buildToken = worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR),
                deferredEpoch = deferredPreviewInvalidationEpoch,
            })
        end
    end)

local function ensurePreviewRoot()
    local worldRoot = getPreviewRoot()
    if not worldRoot then
        worldRoot = Instance.new("Folder")
        worldRoot.Name = AustinPreviewBuilder.WORLD_ROOT_NAME
        worldRoot.Parent = Workspace
    end
    worldRoot:SetAttribute(
        "VertigoPreviewDeferredInvalidationEpoch",
        deferredPreviewInvalidationEpoch
    )

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
    focusPoint = focusPoint
        or AustinSpawn.resolveAnchor(manifestSource, AustinPreviewBuilder.LOAD_RADIUS).focusPoint
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

    local children = worldRoot:GetChildren()
    local chunkIds = table.create(#children)
    for _, child in ipairs(children) do
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

local function buildChunkRefById(manifestSource)
    local chunkRefById = {}
    for _, chunkRef in ipairs(manifestSource.chunkRefs or {}) do
        chunkRefById[chunkRef.id] = chunkRef
    end
    return chunkRefById
end

local function appendPreviewWorkItems(workItems, chunkRef, chunk, expectedFingerprint)
    local pendingSubplans = if chunkRef then getPendingPreviewSubplans(chunkRef) else nil
    if pendingSubplans == nil or #pendingSubplans == 0 then
        workItems[#workItems + 1] = {
            kind = "chunk",
            chunkId = chunk.id,
            chunkRef = chunkRef,
            chunk = chunk,
            originStuds = chunk.originStuds,
            expectedFingerprint = expectedFingerprint,
        }
        return false
    end

    for _, subplan in ipairs(pendingSubplans) do
        workItems[#workItems + 1] = {
            kind = "subplan",
            chunkId = chunk.id,
            chunkRef = chunkRef,
            chunk = chunk,
            originStuds = chunk.originStuds,
            subplan = subplan,
            expectedFingerprint = expectedFingerprint,
        }
    end
    return true
end

local function reconcilePreviewChunkState(
    chunkId,
    existingChunkFolder,
    existingFingerprint,
    expectedFingerprint
)
    if type(chunkId) ~= "string" or chunkId == "" then
        return
    end

    if existingChunkFolder == nil or existingFingerprint ~= expectedFingerprint then
        ImportService.ResetSubplanState(chunkId)
    end
end

local function splitChunkIdsByRadius(chunkIds, distanceByChunkId, radius)
    local foreground = table.create(#chunkIds)
    local background = table.create(#chunkIds)
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

local function syncChunkBatch(
    manifestSource,
    worldRoot,
    buildToken,
    chunkIds,
    counters,
    phaseName,
    chunkRefById,
    focusPoint,
    lookTarget
)
    local sliceStart = os.clock()
    local buildEpoch = Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
    local workItems = {}
    local remainingWorkItemsByChunkId = {}

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
                currentEpoch = Workspace:GetAttribute(
                    AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR
                ),
            })
            updatePreviewPerf({
                SyncActive = false,
                SyncState = "cancelled",
                SyncPhase = phaseName,
            }, true)
            return false
        end

        local expectedFingerprint = getSemanticChunkFingerprint(manifestSource, chunkId)
        local existingChunkFolder = getPreviewChunkFolder(worldRoot, chunkId)
        local existingFingerprint = existingChunkFolder
            and existingChunkFolder:GetAttribute(AustinPreviewBuilder.CHUNK_FINGERPRINT_ATTR)
        local chunkRef = if type(chunkRefById) == "table" then chunkRefById[chunkId] else nil
        local forceAllSubplans = existingChunkFolder == nil
            or existingFingerprint ~= expectedFingerprint
        reconcilePreviewChunkState(
            chunkId,
            existingChunkFolder,
            existingFingerprint,
            expectedFingerprint
        )
        local pendingSubplans = if chunkRef
            then getPendingPreviewSubplans(chunkRef, {
                forceAll = forceAllSubplans,
            })
            else nil
        local needsImport = existingFingerprint ~= expectedFingerprint
            or (pendingSubplans ~= nil and #pendingSubplans > 0)

        if needsImport then
            local chunk = manifestSource:GetChunk(chunkId)
            local workItemStart = #workItems + 1
            appendPreviewWorkItems(workItems, chunkRef, chunk, expectedFingerprint)
            remainingWorkItemsByChunkId[chunkId] = #workItems - workItemStart + 1
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
            if
                not worldRoot
                or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
            then
                logPreview("sync cancelled", {
                    reason = "yield-state-changed",
                    phase = phaseName,
                    buildToken = buildToken,
                    buildEpoch = buildEpoch,
                    currentEpoch = Workspace:GetAttribute(
                        AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR
                    ),
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

    if #workItems > 1 then
        local chunkSize = manifestSource.meta and manifestSource.meta.chunkSizeStuds or 256
        local forwardVector = if typeof(lookTarget) == "Vector3"
                and typeof(focusPoint) == "Vector3"
            then lookTarget - focusPoint
            else nil
        ChunkPriority.SortWorkItems(
            workItems,
            focusPoint,
            chunkSize,
            forwardVector,
            observedChunkCostById
        )
    end

    for _, workItem in ipairs(workItems) do
        local chunkFolder = nil
        local importStartedAt = os.clock()
        if workItem.kind == "subplan" then
            chunkFolder = ImportService.ImportChunkSubplan(workItem.chunk, workItem.subplan, {
                worldRootName = AustinPreviewBuilder.WORLD_ROOT_NAME,
                registrationChunk = workItem.chunkRef or workItem.chunk,
                meshCollisionPolicy = "visual_only",
                nonBlocking = true,
                frameBudgetSeconds = AustinPreviewBuilder.FRAME_BUDGET_SECONDS,
                shouldCancel = function()
                    return shouldCancelBuild(buildToken)
                end,
                onChunkProfile = function(profile)
                    recordSlowChunkSample(phaseName, profile)
                end,
            })
        else
            chunkFolder = ImportService.ImportChunk(workItem.chunk, {
                worldRootName = AustinPreviewBuilder.WORLD_ROOT_NAME,
                meshCollisionPolicy = "visual_only",
                nonBlocking = true,
                frameBudgetSeconds = AustinPreviewBuilder.FRAME_BUDGET_SECONDS,
                shouldCancel = function()
                    return shouldCancelBuild(buildToken)
                end,
                onChunkProfile = function(profile)
                    recordSlowChunkSample(phaseName, profile)
                end,
            })
        end

        if chunkFolder == nil then
            logPreview("sync cancelled", {
                reason = "chunk-import-cancelled",
                phase = phaseName,
                chunkId = workItem.chunkId,
                buildToken = buildToken,
                buildEpoch = buildEpoch,
                currentEpoch = Workspace:GetAttribute(
                    AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR
                ),
            })
            updatePreviewPerf({
                SyncActive = false,
                SyncState = "cancelled",
                SyncPhase = phaseName,
            }, true)
            return false
        end

        local elapsedMs = (os.clock() - importStartedAt) * 1000
        local previous = observedChunkCostById[workItem.chunkId]
        if previous == nil then
            observedChunkCostById[workItem.chunkId] = elapsedMs
        else
            observedChunkCostById[workItem.chunkId] = previous * 0.7 + elapsedMs * 0.3
        end

        remainingWorkItemsByChunkId[workItem.chunkId] = (
            remainingWorkItemsByChunkId[workItem.chunkId] or 1
        ) - 1
        if remainingWorkItemsByChunkId[workItem.chunkId] <= 0 then
            chunkFolder:SetAttribute(
                AustinPreviewBuilder.CHUNK_FINGERPRINT_ATTR,
                workItem.expectedFingerprint
            )
            counters.imported += 1
        end

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
        then
            logPreview("sync cancelled", {
                reason = "post-import-state-changed",
                phase = phaseName,
                chunkId = workItem.chunkId,
                buildToken = buildToken,
                buildEpoch = buildEpoch,
                currentEpoch = Workspace:GetAttribute(
                    AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR
                ),
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

    return true
end

local function syncPreviewChunks(
    manifestSource,
    focusPoint,
    buildToken,
    timings,
    desiredChunkIds,
    lookTarget
)
    timings = timings or {}
    local syncStartedAt = os.clock()
    local previewSubplanRollout = getPreviewSubplanRollout()
    if not desiredChunkIds then
        desiredChunkIds = measureMs(timings, "radiusMs", function()
            return manifestSource:GetChunkIdsWithinRadius(
                focusPoint,
                AustinPreviewBuilder.LOAD_RADIUS
            )
        end)
    end
    local distanceByChunkId = measureMs(timings, "distanceMs", function()
        return getChunkDistanceSqMap(manifestSource, focusPoint)
    end)
    local chunkRefById = buildChunkRefById(manifestSource)
    measureMs(timings, "sortMs", function()
        local chunkSize = manifestSource.meta and manifestSource.meta.chunkSizeStuds or 256
        local forwardVector = if typeof(lookTarget) == "Vector3"
            then lookTarget - focusPoint
            else nil
        ChunkPriority.SortChunkIdsByPriority(
            desiredChunkIds,
            chunkRefById,
            focusPoint,
            chunkSize,
            forwardVector,
            observedChunkCostById
        )
    end)
    local splitStartedAt = os.clock()
    local foregroundChunkIds, backgroundChunkIds = splitChunkIdsByRadius(
        desiredChunkIds,
        distanceByChunkId,
        AustinPreviewBuilder.FOREGROUND_LOAD_RADIUS
    )
    timings.splitMs = (os.clock() - splitStartedAt) * 1000
    local startupChunkIds =
        table.create(math.min(#foregroundChunkIds, AustinPreviewBuilder.STARTUP_CHUNK_COUNT))
    local deferredForegroundChunkIds =
        table.create(math.max(#foregroundChunkIds - AustinPreviewBuilder.STARTUP_CHUNK_COUNT, 0))
    local desiredChunkSet = {}
    local chunkIdsToUnload = {}
    local counters = {
        unloaded = 0,
        imported = 0,
        skipped = 0,
        yields = 0,
    }

    updatePreviewPerf({
        SyncActive = true,
        SyncState = "running",
        SubplanRolloutEnabled = previewSubplanRollout.enabled,
        SubplanRolloutMode = previewSubplanRollout.mode,
        SubplanRolloutAllowedLayerCount = previewSubplanRollout.allowedLayerCount,
        SubplanRolloutAllowlistedChunkCount = previewSubplanRollout.allowlistedChunkCount,
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
    local buildEpoch = Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
    if
        not worldRoot
        or worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
    then
        updatePreviewPerf({
            SyncActive = false,
            SyncState = "cancelled",
        }, true)
        return {}
    end

    local unloadSweepStartedAt = os.clock()
    for _, loadedChunkId in ipairs(listPreviewChunkIds(worldRoot)) do
        if worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken then
            timings.unloadSweepMs = (os.clock() - unloadSweepStartedAt) * 1000
            updatePreviewPerf({
                SyncActive = false,
                SyncState = "cancelled",
            }, true)
            return desiredChunkIds
        end
        if not desiredChunkSet[loadedChunkId] then
            chunkIdsToUnload[#chunkIdsToUnload + 1] = loadedChunkId
        end
    end
    timings.unloadSweepMs = (os.clock() - unloadSweepStartedAt) * 1000

    local startupOk = measureMs(timings, "startupMs", function()
        return syncChunkBatch(
            manifestSource,
            worldRoot,
            buildToken,
            startupChunkIds,
            counters,
            "startup",
            chunkRefById,
            focusPoint,
            lookTarget
        )
    end)
    if not startupOk then
        return desiredChunkIds
    end

    if #chunkIdsToUnload > 0 then
        local pruneStartedAt = os.clock()
        for _, loadedChunkId in ipairs(chunkIdsToUnload) do
            if worldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken then
                timings.pruneMs = (os.clock() - pruneStartedAt) * 1000
                updatePreviewPerf({
                    SyncActive = false,
                    SyncState = "cancelled",
                }, true)
                return desiredChunkIds
            end

            ChunkLoader.UnloadChunk(loadedChunkId)
            ImportService.ResetSubplanState(loadedChunkId)
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
            then
                timings.pruneMs = (os.clock() - pruneStartedAt) * 1000
                updatePreviewPerf({
                    SyncActive = false,
                    SyncState = "cancelled",
                }, true)
                return desiredChunkIds
            end
        end
        timings.pruneMs = (os.clock() - pruneStartedAt) * 1000
    end

    if #deferredForegroundChunkIds > 0 then
        updatePreviewPerf({
            SyncPhase = "foreground",
            SyncPhaseTargetChunks = #deferredForegroundChunkIds,
        }, true)
        local foregroundOk = measureMs(timings, "foregroundMs", function()
            return syncChunkBatch(
                manifestSource,
                worldRoot,
                buildToken,
                deferredForegroundChunkIds,
                counters,
                "foreground",
                chunkRefById,
                focusPoint,
                lookTarget
            )
        end)
        if not foregroundOk then
            return desiredChunkIds
        end
    end

    if #backgroundChunkIds > 0 then
        updatePreviewPerf({
            SyncPhase = "background",
            SyncPhaseTargetChunks = #backgroundChunkIds,
        }, true)
    end
    local backgroundOk = measureMs(timings, "backgroundMs", function()
        return syncChunkBatch(
            manifestSource,
            worldRoot,
            buildToken,
            backgroundChunkIds,
            counters,
            "background",
            chunkRefById,
            focusPoint,
            lookTarget
        )
    end)
    if not backgroundOk then
        return desiredChunkIds
    end

    local syncElapsedMs = (os.clock() - syncStartedAt) * 1000
    local currentInvalidationEpoch =
        Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
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

    logPreview("sync timing", {
        backgroundMs = math.floor((timings.backgroundMs or 0) + 0.5),
        distanceMs = math.floor((timings.distanceMs or 0) + 0.5),
        foregroundMs = math.floor((timings.foregroundMs or 0) + 0.5),
        loadManifestMs = math.floor((timings.manifestLoadMs or 0) + 0.5),
        anchorMs = math.floor((timings.anchorMs or 0) + 0.5),
        radiusMs = math.floor((timings.radiusMs or 0) + 0.5),
        sortMs = math.floor((timings.sortMs or 0) + 0.5),
        splitMs = math.floor((timings.splitMs or 0) + 0.5),
        startupMs = math.floor((timings.startupMs or 0) + 0.5),
        totalMs = math.floor(syncElapsedMs + 0.5),
        unloadSweepMs = math.floor((timings.unloadSweepMs or 0) + 0.5),
        imported = counters.imported,
        skipped = counters.skipped,
        unloaded = counters.unloaded,
        yields = counters.yields,
        targetChunks = #desiredChunkIds,
    })

    logPreview("sync complete", {
        buildToken = buildToken,
        buildEpoch = buildEpoch,
        currentEpoch = currentInvalidationEpoch,
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
    cachedFullManifestHandle = nil
    cachedFullManifestHash = nil
    deferredPreviewInvalidationEpoch = nil
    table.clear(observedChunkCostById)
    table.clear(semanticFingerprintCacheByHandle)
    ImportService.ResetSubplanState()

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
    local buildEpoch = Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
    worldRoot:SetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR, buildToken)
    worldRoot:SetAttribute("VertigoPreviewBuildEpoch", buildEpoch)
    worldRoot:SetAttribute("VertigoPreviewHardPause", hardPause)
    worldRoot:SetAttribute("VertigoPreviewDeferredInvalidationEpoch", nil)
    worldRoot:SetAttribute("VertigoPreviewDeferredTimeTravelEpoch", nil)
    if deferredPreviewInvalidationEpoch == buildEpoch then
        deferredPreviewInvalidationEpoch = nil
    end
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
        then
            return
        end

        local buildTimings = {}
        local manifestSource = measureMs(buildTimings, "manifestLoadMs", function()
            return loadManifestSource()
        end)
        liveWorldRoot = getPreviewRoot()
        if
            not liveWorldRoot
            or liveWorldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
        then
            return
        end

        local anchor = measureMs(buildTimings, "anchorMs", function()
            return AustinSpawn.resolveAnchor(manifestSource, AustinPreviewBuilder.LOAD_RADIUS)
        end)
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
        local previewChunkIds = measureMs(buildTimings, "radiusMs", function()
            return manifestSource:GetChunkIdsWithinRadius(
                focusPoint,
                AustinPreviewBuilder.LOAD_RADIUS
            )
        end)
        if hardPause then
            manifestSource = ManifestLoader.FreezeHandleForChunkIds(manifestSource, previewChunkIds)
        end

        liveWorldRoot = getPreviewRoot()
        if
            not liveWorldRoot
            or liveWorldRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) ~= buildToken
        then
            return
        end

        addPreviewBeacon(liveWorldRoot, manifestSource, previewChunkIds, focusPoint)
        syncPreviewChunks(
            manifestSource,
            focusPoint,
            buildToken,
            buildTimings,
            previewChunkIds,
            anchor.lookTarget
        )

        local latestRoot = getPreviewRoot()
        local currentEpoch =
            Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
        if
            latestRoot
            and latestRoot:GetAttribute(AustinPreviewBuilder.BUILD_TOKEN_ATTR) == buildToken
            and currentEpoch ~= buildEpoch
        then
            latestRoot:SetAttribute("VertigoPreviewDeferredInvalidationEpoch", currentEpoch)
            logPreview("rebuild deferred preview invalidation", {
                buildToken = buildToken,
                buildEpoch = buildEpoch,
                currentEpoch = currentEpoch,
            })
            task.defer(AustinPreviewBuilder.Build)
        end
    end)

    return { worldRoot }
end

return AustinPreviewBuilder
