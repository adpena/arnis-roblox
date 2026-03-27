local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ImportService = require(script.Parent)
local ChunkLoader = require(script.Parent.ChunkLoader)
local ChunkPriority = require(script.Parent.ChunkPriority)
local SubplanRollout = require(script.Parent.SubplanRollout)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Logger = require(ReplicatedStorage.Shared.Logger)

local StreamingService = {}

local streamingManifest = nil
local streamingChunkRefs = nil
local streamingOptions = nil
local streamingChunkIndex = nil
local heartbeatConn = nil
local lastUpdate = 0
local DEFAULT_UPDATE_INTERVAL = 0.25 -- seconds between distance checks
local HYSTERESIS_RATIO = 0.15

-- LOD detail toggle: runs at a lower frequency to keep per-frame cost cheap.
local LOD_UPDATE_INTERVAL = 2 -- seconds
local lastLODUpdate = 0

local LOD_HIGH = "High"
local LOD_LOW = "Low"
-- Registry of chunkId -> current LOD level
local loadedChunkLods = {}
local lodConfigCache = setmetatable({}, { __mode = "k" })
local streamingChunkOptionsByLod = nil
local streamingLastFocalPoint = nil
local streamingPreferredForward = nil
local observedChunkImportMsById = {}
local streamingSubplanRollout = nil

local function getStreamingWorldRootName()
    local options = streamingOptions or {}
    return options.worldRootName
end

local function normalizePositiveNumber(value)
    if type(value) ~= "number" then
        return nil
    end
    if value <= 0 then
        return nil
    end
    return value
end

local function getChunkCenter(chunkRef, chunkSizeStuds)
    local originData = chunkRef.originStuds or { x = 0, y = 0, z = 0 }
    local halfSize = chunkSizeStuds * 0.5
    return originData.x + halfSize, originData.z + halfSize
end

local function getIndexCoord(value, cellSize)
    return math.floor(value / cellSize)
end

local function buildChunkSpatialIndex(chunkRefs, config)
    local targetRadius = config.StreamingTargetRadius or 2048
    local cellSize = math.max(config.ChunkSizeStuds or 256, targetRadius)
    local buckets = {}

    for _, chunkRef in ipairs(chunkRefs or {}) do
        local centerX, centerZ = getChunkCenter(chunkRef, config.ChunkSizeStuds)
        local chunkEntry = {
            ref = chunkRef,
            centerX = centerX,
            centerZ = centerZ,
            materializedChunk = nil,
        }
        local cellX = getIndexCoord(centerX, cellSize)
        local cellZ = getIndexCoord(centerZ, cellSize)
        local row = buckets[cellX]
        if not row then
            row = {}
            buckets[cellX] = row
        end
        local bucket = row[cellZ]
        if not bucket then
            bucket = {}
            row[cellZ] = bucket
        end
        bucket[#bucket + 1] = chunkEntry
    end

    return {
        cellSize = cellSize,
        buckets = buckets,
    }
end

local function getCandidateChunkRefs(index, playerPos, targetRadius)
    if not index then
        return {}
    end

    local minCellX = getIndexCoord(playerPos.X - targetRadius, index.cellSize)
    local maxCellX = getIndexCoord(playerPos.X + targetRadius, index.cellSize)
    local minCellZ = getIndexCoord(playerPos.Z - targetRadius, index.cellSize)
    local maxCellZ = getIndexCoord(playerPos.Z + targetRadius, index.cellSize)
    local candidates = {}

    for cellX = minCellX, maxCellX do
        local row = index.buckets[cellX]
        if row then
            for cellZ = minCellZ, maxCellZ do
                local bucket = row[cellZ]
                if bucket then
                    for _, chunkEntry in ipairs(bucket) do
                        candidates[#candidates + 1] = chunkEntry
                    end
                end
            end
        end
    end

    return candidates
end

local function getMaterializedChunk(chunkEntry)
    if chunkEntry.materializedChunk then
        return chunkEntry.materializedChunk
    end

    local chunkRef = chunkEntry.ref
    local chunk = if streamingManifest.GetChunk then streamingManifest:GetChunk(chunkRef.id) else chunkRef
    chunkEntry.materializedChunk = chunk
    return chunk
end

local function appendStreamingWorkItems(workItems, chunkEntry, chunkOptions, config, targetLod)
    local chunkRef = chunkEntry.ref
    local allowedSubplans = SubplanRollout.GetFullySchedulableSubplans(chunkRef, config)
    if allowedSubplans == nil then
        workItems[#workItems + 1] = {
            chunkEntry = chunkEntry,
            chunkOptions = chunkOptions,
            chunkId = chunkRef.id,
            originStuds = chunkRef.originStuds,
            targetLod = targetLod,
        }
        return false
    end

    for _, subplan in ipairs(allowedSubplans) do
        workItems[#workItems + 1] = {
            chunkEntry = chunkEntry,
            chunkOptions = chunkOptions,
            chunkId = chunkRef.id,
            originStuds = chunkRef.originStuds,
            subplan = subplan,
            targetLod = targetLod,
        }
    end
    return true
end

local function getPendingSubplans(chunkRef, config)
    local allowedSubplans = SubplanRollout.GetFullySchedulableSubplans(chunkRef, config)
    if allowedSubplans == nil then
        return nil
    end

    local state = ImportService.GetSubplanState(chunkRef.id)
    local pending = {}
    for _, subplan in ipairs(allowedSubplans) do
        local layer = if type(subplan) == "table" then subplan.layer or subplan.id else nil
        if type(layer) == "string" and not state.importedLayers[layer] then
            pending[#pending + 1] = subplan
        end
    end
    return pending
end

local function getConfigSignature(config)
    return table.concat({
        tostring(config.TerrainMode),
        tostring(config.RoadMode),
        tostring(config.BuildingMode),
        tostring(config.WaterMode),
        tostring(config.LanduseMode),
    }, "|")
end

local function getLayerSignatures(config)
    return {
        terrain = tostring(config.TerrainMode),
        roads = table.concat({
            tostring(config.RoadMode),
        }, "|"),
        landuse = tostring(config.LanduseMode),
        barriers = "default",
        buildings = tostring(config.BuildingMode),
        water = tostring(config.WaterMode),
        props = "default",
    }
end

local function computeChangedLayers(currentLayerSignatures, targetLayerSignatures)
    local changed = nil
    for layerName, targetSignature in pairs(targetLayerSignatures) do
        local currentSignature = currentLayerSignatures and currentLayerSignatures[layerName] or nil
        if currentSignature ~= targetSignature then
            if changed == nil then
                changed = {}
            end
            changed[layerName] = true
        end
    end
    return changed
end

local function getExitRadius(enterRadius, maxRadius)
    local expanded = enterRadius * (1 + HYSTERESIS_RATIO)
    if maxRadius ~= nil then
        return math.min(expanded, maxRadius)
    end
    return expanded
end

local function chooseTargetLod(distSq, currentLod, highRadiusSq, highExitRadiusSq, targetRadiusSq, targetExitRadiusSq)
    if currentLod == LOD_HIGH then
        if distSq <= highExitRadiusSq then
            return LOD_HIGH
        end
        if distSq <= targetRadiusSq then
            return LOD_LOW
        end
        return nil
    end

    if currentLod == LOD_LOW then
        if distSq <= highRadiusSq then
            return LOD_HIGH
        end
        if distSq <= targetExitRadiusSq then
            return LOD_LOW
        end
        return nil
    end

    if distSq <= highRadiusSq then
        return LOD_HIGH
    end
    if distSq <= targetRadiusSq then
        return LOD_LOW
    end
    return nil
end

local function getLodConfig(level, baseConfig)
    local cachedByLevel = lodConfigCache[baseConfig]
    if not cachedByLevel then
        cachedByLevel = {}
        lodConfigCache[baseConfig] = cachedByLevel
    end

    local cached = cachedByLevel[level]
    if cached then
        return cached
    end

    -- Low LOD is residency-driven; grouped detail/interior handle visual downgrade
    -- while macro layers remain resident and rebuild-free.
    local config = table.clone(baseConfig)

    cachedByLevel[level] = config
    return config
end

local function buildChunkOptionsByLod(options, baseConfig)
    local frameBudgetSeconds = normalizePositiveNumber(options.frameBudgetSeconds)
        or normalizePositiveNumber(baseConfig.StreamingImportFrameBudgetSeconds)
    local nonBlocking = options.nonBlocking
    if nonBlocking == nil then
        nonBlocking = frameBudgetSeconds ~= nil
    end

    return {
        [LOD_HIGH] = {
            worldRootName = options.worldRootName,
            frameBudgetSeconds = frameBudgetSeconds,
            nonBlocking = nonBlocking,
            shouldCancel = options.shouldCancel,
            config = getLodConfig(LOD_HIGH, baseConfig),
            configSignature = getConfigSignature(getLodConfig(LOD_HIGH, baseConfig)),
            layerSignatures = getLayerSignatures(getLodConfig(LOD_HIGH, baseConfig)),
        },
        [LOD_LOW] = {
            worldRootName = options.worldRootName,
            frameBudgetSeconds = frameBudgetSeconds,
            nonBlocking = nonBlocking,
            shouldCancel = options.shouldCancel,
            config = getLodConfig(LOD_LOW, baseConfig),
            configSignature = getConfigSignature(getLodConfig(LOD_LOW, baseConfig)),
            layerSignatures = getLayerSignatures(getLodConfig(LOD_LOW, baseConfig)),
        },
    }
end

local function setInstanceVisible(instance, visible)
    if instance:IsA("BasePart") then
        instance.Transparency = if visible
            then (instance:GetAttribute("BaseTransparency") or instance:GetAttribute("ArnisBaseTransparency") or 0)
            else 1
    elseif instance:IsA("BillboardGui") then
        instance.Enabled = visible
    end
end

local function setGroupVisible(group, visible)
    if group:GetAttribute("ArnisLodVisible") == visible then
        return
    end

    for _, descendant in ipairs(group:GetDescendants()) do
        setInstanceVisible(descendant, visible)
    end
    group:SetAttribute("ArnisLodVisible", visible)
end

local function updateChunkEntryLodGroups(chunkEntry, camPos, highDetailRadius, interiorRadius)
    if not chunkEntry or not chunkEntry.lodGroups then
        return
    end

    local folder = chunkEntry.folder
    local chunkCenter = nil
    if folder and folder.Parent then
        local chunkPos = folder:GetAttribute("ArnisChunkCenter")
        if typeof(chunkPos) == "Vector3" then
            chunkCenter = chunkPos
        end
    end
    if chunkCenter == nil and chunkEntry.chunk then
        local origin = chunkEntry.chunk.originStuds or { x = 0, y = 0, z = 0 }
        local chunkSize = streamingOptions and streamingOptions.config and streamingOptions.config.ChunkSizeStuds
            or DefaultWorldConfig.ChunkSizeStuds
            or 256
        chunkCenter = Vector3.new(origin.x + chunkSize * 0.5, origin.y or 0, origin.z + chunkSize * 0.5)
    end
    if chunkCenter == nil then
        return
    end

    local detailVisible = (chunkCenter - camPos).Magnitude <= highDetailRadius
    local interiorVisible = (chunkCenter - camPos).Magnitude <= interiorRadius
    for _, group in ipairs(chunkEntry.lodGroups.detail or {}) do
        if group:IsDescendantOf(Workspace) then
            setGroupVisible(group, detailVisible)
        end
    end
    for _, group in ipairs(chunkEntry.lodGroups.interior or {}) do
        if group:IsDescendantOf(Workspace) then
            setGroupVisible(group, interiorVisible)
        end
    end
end

-- Toggle visibility of LOD-tagged detail and interior parts based on camera distance.
-- Runs at LOD_UPDATE_INTERVAL cadence — cheap: iterates CollectionService lists,
-- not the full workspace tree.
local function updateLOD()
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local camPos = camera.CFrame.Position
    local config = streamingOptions and (streamingOptions.config or DefaultWorldConfig) or DefaultWorldConfig
    local highDetailRadius = config.HighDetailRadius or 2048
    local interiorRadius = highDetailRadius * 0.25 -- interiors only very close

    local worldRootName = getStreamingWorldRootName()
    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        updateChunkEntryLodGroups(chunkEntry, camPos, highDetailRadius, interiorRadius)
    end
end

function StreamingService.Start(manifest, options)
    if heartbeatConn then
        StreamingService.Stop()
    end

    streamingManifest = manifest
    streamingChunkRefs = manifest and (manifest.chunkRefs or manifest.chunks) or nil
    streamingOptions = options or {}
    local config = streamingOptions.config or DefaultWorldConfig
    local worldRootName = getStreamingWorldRootName()
    streamingSubplanRollout = SubplanRollout.Describe(config)
    streamingPreferredForward = if typeof(streamingOptions.preferredLookVector) == "Vector3"
        then streamingOptions.preferredLookVector
        else nil
    streamingLastFocalPoint = nil
    streamingChunkOptionsByLod = buildChunkOptionsByLod(streamingOptions, config)
    streamingChunkIndex = buildChunkSpatialIndex(streamingChunkRefs, config)

    if not config.StreamingEnabled then
        Logger.warn("StreamingService.Start called but StreamingEnabled is false in config")
        return
    end

    Workspace:SetAttribute("ArnisStreamingSubplanRolloutEnabled", streamingSubplanRollout.enabled)
    Workspace:SetAttribute("ArnisStreamingSubplanRolloutMode", streamingSubplanRollout.mode)
    Workspace:SetAttribute("ArnisStreamingSubplanRolloutAllowedLayerCount", streamingSubplanRollout.allowedLayerCount)
    Workspace:SetAttribute(
        "ArnisStreamingSubplanRolloutAllowlistedChunkCount",
        streamingSubplanRollout.allowlistedChunkCount
    )
    Logger.info("StreamingService started for world:", manifest.meta.worldName)
    Logger.info(
        "StreamingService subplan rollout:",
        streamingSubplanRollout.mode,
        "enabled=" .. tostring(streamingSubplanRollout.enabled),
        "layers=" .. tostring(streamingSubplanRollout.allowedLayerCount),
        "chunks=" .. tostring(streamingSubplanRollout.allowlistedChunkCount)
    )

    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        local now = os.clock()
        local updateInterval = normalizePositiveNumber(config.StreamingUpdateIntervalSeconds) or DEFAULT_UPDATE_INTERVAL
        if now - lastUpdate >= updateInterval then
            lastUpdate = now
            StreamingService.Update()
        end

        lastLODUpdate = lastLODUpdate + dt
        if lastLODUpdate >= LOD_UPDATE_INTERVAL then
            lastLODUpdate = 0
            updateLOD()
        end
    end)
end

function StreamingService.Stop()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    ImportService.ResetSubplanState()
    streamingManifest = nil
    streamingChunkRefs = nil
    streamingChunkIndex = nil
    streamingOptions = nil
    streamingChunkOptionsByLod = nil
    streamingLastFocalPoint = nil
    streamingPreferredForward = nil
    streamingSubplanRollout = nil
    table.clear(observedChunkImportMsById)
    loadedChunkLods = {}
    lastLODUpdate = 0
end

function StreamingService.Update(focalPoint)
    if not streamingManifest or not streamingChunkRefs then
        return
    end

    local playerPos = focalPoint
    if not playerPos then
        local player = Players:GetPlayers()[1]
        local character = player and player.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if not rootPart then
            return
        end
        playerPos = rootPart.Position
    end

    local config = streamingOptions.config or DefaultWorldConfig
    local targetRadius = config.StreamingTargetRadius or 2048
    local highRadius = config.HighDetailRadius or 1024
    local chunkSizeStuds = config.ChunkSizeStuds or DefaultWorldConfig.ChunkSizeStuds or 256

    local targetRadiusSq = targetRadius * targetRadius
    local highRadiusSq = highRadius * highRadius
    local highExitRadius = getExitRadius(highRadius, targetRadius)
    local targetExitRadius = getExitRadius(targetRadius, nil)
    local highExitRadiusSq = highExitRadius * highExitRadius
    local targetExitRadiusSq = targetExitRadius * targetExitRadius
    local interiorRadius = highRadius * 0.25
    local movementForward = nil
    if typeof(streamingLastFocalPoint) == "Vector3" then
        local delta = playerPos - streamingLastFocalPoint
        if Vector3.new(delta.X, 0, delta.Z).Magnitude >= 1 then
            movementForward = delta
        end
    end
    local forwardVector = movementForward or streamingPreferredForward

    local desiredChunkIds = {}
    local candidateChunkEntries = getCandidateChunkRefs(streamingChunkIndex, playerPos, targetExitRadius)
    local importWorkItems = {}
    ChunkPriority.SortChunkEntriesByPriority(
        candidateChunkEntries,
        playerPos,
        chunkSizeStuds,
        forwardVector,
        observedChunkImportMsById
    )

    for _, chunkEntry in ipairs(candidateChunkEntries) do
        local chunkRef = chunkEntry.ref
        local dx = playerPos.X - chunkEntry.centerX
        local dz = playerPos.Z - chunkEntry.centerZ
        local distSq = dx * dx + dz * dz

        local currentLod = loadedChunkLods[chunkRef.id]
        local targetLod =
            chooseTargetLod(distSq, currentLod, highRadiusSq, highExitRadiusSq, targetRadiusSq, targetExitRadiusSq)

        if targetLod ~= currentLod then
            if targetLod then
                -- Load or Upgrade/Downgrade
                local chunkOptions = streamingChunkOptionsByLod[targetLod]
                local currentEntry = ChunkLoader.GetChunkEntry(chunkRef.id, worldRootName)
                if currentEntry and currentEntry.configSignature == chunkOptions.configSignature then
                    loadedChunkLods[chunkRef.id] = targetLod
                    desiredChunkIds[chunkRef.id] = true
                    continue
                end

                if currentEntry then
                    local changedLayers =
                        computeChangedLayers(currentEntry.layerSignatures, chunkOptions.layerSignatures)
                    if not changedLayers then
                        local pendingSubplans = getPendingSubplans(chunkRef, chunkOptions.config)
                        if pendingSubplans == nil or #pendingSubplans == 0 then
                            loadedChunkLods[chunkRef.id] = targetLod
                            desiredChunkIds[chunkRef.id] = true
                            continue
                        end
                        appendStreamingWorkItems(
                            importWorkItems,
                            chunkEntry,
                            chunkOptions,
                            chunkOptions.config,
                            targetLod
                        )
                        desiredChunkIds[chunkRef.id] = true
                        continue
                    end
                    chunkOptions = {
                        worldRootName = chunkOptions.worldRootName,
                        frameBudgetSeconds = chunkOptions.frameBudgetSeconds,
                        nonBlocking = chunkOptions.nonBlocking,
                        shouldCancel = chunkOptions.shouldCancel,
                        config = chunkOptions.config,
                        configSignature = chunkOptions.configSignature,
                        layerSignatures = chunkOptions.layerSignatures,
                        layers = changedLayers,
                    }
                end

                appendStreamingWorkItems(importWorkItems, chunkEntry, chunkOptions, chunkOptions.config, targetLod)
                desiredChunkIds[chunkRef.id] = true
            else
                -- Unload
                ChunkLoader.UnloadChunk(chunkRef.id, nil, worldRootName)
                ImportService.ResetSubplanState(chunkRef.id)
                loadedChunkLods[chunkRef.id] = nil
            end
        elseif targetLod then
            desiredChunkIds[chunkRef.id] = true
        end
    end

    ChunkPriority.SortWorkItems(importWorkItems, playerPos, chunkSizeStuds, forwardVector, observedChunkImportMsById)

    local maxWorkItemsPerUpdate = config.StreamingMaxWorkItemsPerUpdate
    if type(maxWorkItemsPerUpdate) ~= "number" or maxWorkItemsPerUpdate < 1 then
        maxWorkItemsPerUpdate = #importWorkItems
    else
        maxWorkItemsPerUpdate = math.max(1, math.floor(maxWorkItemsPerUpdate))
    end

    local processedWorkItems = 0
    for _, workItem in ipairs(importWorkItems) do
        if processedWorkItems >= maxWorkItemsPerUpdate then
            break
        end
        local chunkEntry = workItem.chunkEntry
        local chunkRef = chunkEntry.ref
        local chunk = getMaterializedChunk(chunkEntry)
        local importStartedAt = os.clock()
        if workItem.subplan then
            local subplanOptions = table.clone(workItem.chunkOptions)
            subplanOptions.registrationChunk = chunkRef
            ImportService.ImportChunkSubplan(chunk, workItem.subplan, subplanOptions)
        else
            ImportService.ImportChunk(chunk, workItem.chunkOptions)
        end
        local elapsedMs = (os.clock() - importStartedAt) * 1000
        local observedCostKey = ChunkPriority.GetObservedCostKey(
            chunkRef.id,
            type(workItem.subplan) == "table" and workItem.subplan.id or nil
        ) or chunkRef.id
        local previous = observedChunkImportMsById[observedCostKey]
        if previous == nil then
            observedChunkImportMsById[observedCostKey] = elapsedMs
        else
            observedChunkImportMsById[observedCostKey] = previous * 0.7 + elapsedMs * 0.3
        end
        loadedChunkLods[chunkRef.id] = workItem.targetLod or loadedChunkLods[chunkRef.id]
        processedWorkItems += 1
    end

    for chunkId, _ in pairs(loadedChunkLods) do
        if not desiredChunkIds[chunkId] then
            ChunkLoader.UnloadChunk(chunkId, nil, worldRootName)
            ImportService.ResetSubplanState(chunkId)
            loadedChunkLods[chunkId] = nil
        end
    end

    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        updateChunkEntryLodGroups(chunkEntry, playerPos, highRadius, interiorRadius)
    end

    streamingLastFocalPoint = playerPos
end

return StreamingService
