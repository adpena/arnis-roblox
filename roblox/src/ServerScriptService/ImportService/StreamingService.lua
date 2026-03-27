local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ImportService = require(script.Parent)
local ChunkLoader = require(script.Parent.ChunkLoader)
local ChunkPriority = require(script.Parent.ChunkPriority)
local ImportSignatures = require(script.Parent.ImportSignatures)
local MemoryGuardrail = require(script.Parent.MemoryGuardrail)
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
local streamingMemoryGuardrail = nil
local streamingResidentEstimatedCostById = {}
local streamingUpdateInProgress = false

local MEMORY_GUARDRAIL_ATTR_PREFIX = "ArnisStreamingMemoryGuardrail"
local HOST_PROBE_AVAILABLE_ATTR = "ArnisStreamingHostProbeAvailableBytes"
local HOST_PROBE_PRESSURE_ATTR = "ArnisStreamingHostProbePressureLevel"
local DEFAULT_WORLD_ROOT_NAME = "GeneratedWorld"

local function normalizePositiveNumber(value)
    if type(value) ~= "number" then
        return nil
    end
    if value <= 0 then
        return nil
    end
    return value
end

local function normalizeNonNegativeNumber(value)
    if type(value) ~= "number" or value < 0 then
        return 0
    end
    return value
end

local function setMemoryGuardrailTelemetry(snapshot, deferredAdmissions, residentCost, inFlightCost)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "Enabled", snapshot.enabled)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "State", snapshot.state)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "BudgetBytes", snapshot.budgetBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "ResidentEstimatedCost", residentCost)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "InFlightEstimatedCost", inFlightCost)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "ProjectedUsageBytes", snapshot.projectedUsageBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "ResumeThresholdBytes", snapshot.resumeThresholdBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostProbeEnabled", snapshot.hostProbe.enabled)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostAvailableBytes", snapshot.hostProbe.availableBytes)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostPressureLevel", snapshot.hostProbe.pressureLevel)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "HostCritical", snapshot.hostProbe.critical)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "DeferredAdmissions", deferredAdmissions)
    Workspace:SetAttribute(MEMORY_GUARDRAIL_ATTR_PREFIX .. "LastPauseReason", snapshot.pauseReason)
end

local function clearMemoryGuardrailTelemetry()
    setMemoryGuardrailTelemetry({
        enabled = false,
        state = "active",
        budgetBytes = 0,
        projectedUsageBytes = 0,
        resumeThresholdBytes = 0,
        residentBytes = 0,
        inFlightBytes = 0,
        pauseReason = nil,
        hostProbe = {
            enabled = false,
            availableBytes = nil,
            pressureLevel = nil,
            critical = false,
        },
    }, 0, 0, 0)
end

local function resetStreamingResidencyTelemetry()
    Workspace:SetAttribute("ArnisStreamingLoadedChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingDesiredChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingCandidateChunkCount", 0)
    Workspace:SetAttribute("ArnisStreamingProcessedWorkItems", 0)
    Workspace:SetAttribute("ArnisStreamingLastFocalX", 0)
    Workspace:SetAttribute("ArnisStreamingLastFocalZ", 0)
end

local function updateStreamingResidencyTelemetry(
    playerPos,
    candidateChunkEntries,
    desiredChunkCount,
    processedWorkItems
)
    local focalX = 0
    local focalZ = 0
    if typeof(playerPos) == "Vector3" then
        focalX = playerPos.X
        focalZ = playerPos.Z
    end

    Workspace:SetAttribute(
        "ArnisStreamingLoadedChunkCount",
        #ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)
    )
    Workspace:SetAttribute("ArnisStreamingCandidateChunkCount", #candidateChunkEntries)
    Workspace:SetAttribute("ArnisStreamingDesiredChunkCount", desiredChunkCount)
    Workspace:SetAttribute("ArnisStreamingProcessedWorkItems", processedWorkItems)
    Workspace:SetAttribute("ArnisStreamingLastFocalX", focalX)
    Workspace:SetAttribute("ArnisStreamingLastFocalZ", focalZ)
end

local function observeHostProbeSample()
    if not streamingMemoryGuardrail then
        return
    end

    local guardrailConfig = streamingMemoryGuardrail:GetConfig()
    local hostProbeConfig = guardrailConfig and guardrailConfig.HostProbe or nil
    if type(hostProbeConfig) ~= "table" or hostProbeConfig.Enabled ~= true then
        streamingMemoryGuardrail:ObserveHostProbe(nil)
        return
    end

    streamingMemoryGuardrail:ObserveHostProbe({
        availableBytes = Workspace:GetAttribute(HOST_PROBE_AVAILABLE_ATTR),
        pressureLevel = Workspace:GetAttribute(HOST_PROBE_PRESSURE_ATTR),
    })
end

local function sumEstimatedCosts(costById)
    local total = 0
    for _, cost in pairs(costById) do
        total += cost
    end
    return total
end

local function getEstimatedWorkItemCost(workItem)
    local subplan = workItem.subplan
    local chunkRef = workItem.chunkEntry and workItem.chunkEntry.ref or nil

    local function deriveChunkLevelSubplanCost(chunkCost)
        if type(subplan) ~= "table" or type(chunkRef) ~= "table" then
            return nil
        end

        local siblingSubplans = chunkRef.subplans
        if type(siblingSubplans) ~= "table" or #siblingSubplans == 0 then
            return nil
        end

        local totalFeatureCount = 0
        local targetFeatureCount = nil
        for _, candidate in ipairs(siblingSubplans) do
            if type(candidate) == "table" then
                local candidateFeatureCount = normalizeNonNegativeNumber(candidate.featureCount)
                totalFeatureCount += candidateFeatureCount
                if candidate == subplan or candidate.id == subplan.id then
                    targetFeatureCount = candidateFeatureCount
                end
            end
        end

        if totalFeatureCount > 0 and targetFeatureCount ~= nil then
            return chunkCost * (targetFeatureCount / totalFeatureCount)
        end

        return chunkCost / #siblingSubplans
    end

    if type(subplan) == "table" and type(subplan.estimatedMemoryCost) == "number" then
        return normalizeNonNegativeNumber(subplan.estimatedMemoryCost)
    end

    if type(chunkRef) == "table" and type(chunkRef.estimatedMemoryCost) == "number" then
        local chunkEstimatedCost = normalizeNonNegativeNumber(chunkRef.estimatedMemoryCost)
        return if type(subplan) == "table"
            then deriveChunkLevelSubplanCost(chunkEstimatedCost) or chunkEstimatedCost
            else chunkEstimatedCost
    end

    if type(subplan) == "table" and type(subplan.streamingCost) == "number" then
        return normalizeNonNegativeNumber(subplan.streamingCost)
    end

    if type(chunkRef) == "table" and type(chunkRef.streamingCost) == "number" then
        local chunkStreamingCost = normalizeNonNegativeNumber(chunkRef.streamingCost)
        return if type(subplan) == "table"
            then deriveChunkLevelSubplanCost(chunkStreamingCost) or chunkStreamingCost
            else chunkStreamingCost
    end

    return 0
end

local function getEstimatedChunkOrSubplanCost(chunkRef, subplan)
    return getEstimatedWorkItemCost({
        chunkEntry = {
            ref = chunkRef,
        },
        subplan = subplan,
    })
end

local function getResidentCostKey(workItem)
    local chunkId = workItem.chunkId
    local subplanId = type(workItem.subplan) == "table" and workItem.subplan.id or nil
    return ChunkPriority.GetObservedCostKey(chunkId, subplanId) or chunkId
end

local function getCompletedSubplanWorkId(chunkId, subplan)
    if type(chunkId) ~= "string" or chunkId == "" or type(subplan) ~= "table" then
        return nil
    end

    local subplanId = subplan.id
    if type(subplanId) ~= "string" or subplanId == "" then
        subplanId = subplan.layer
    end
    if type(subplanId) ~= "string" or subplanId == "" then
        return nil
    end

    return ("%s:%s"):format(chunkId, subplanId)
end

local function clearResidentEstimatedCostForChunk(chunkId)
    local prefix = chunkId .. "::"
    local toRemove = {}
    for residentKey, _ in pairs(streamingResidentEstimatedCostById) do
        if residentKey == chunkId or string.sub(residentKey, 1, #prefix) == prefix then
            toRemove[#toRemove + 1] = residentKey
        end
    end

    for _, residentKey in ipairs(toRemove) do
        streamingResidentEstimatedCostById[residentKey] = nil
    end
end

local function clearResidentEstimatedCost(workItem)
    local residentKey = getResidentCostKey(workItem)
    if residentKey == workItem.chunkId then
        clearResidentEstimatedCostForChunk(workItem.chunkId)
        return
    end
    streamingResidentEstimatedCostById[residentKey] = nil
end

local function recordResidentEstimatedCost(workItem, cost)
    local residentKey = getResidentCostKey(workItem)
    if residentKey == workItem.chunkId then
        clearResidentEstimatedCostForChunk(workItem.chunkId)
    end
    streamingResidentEstimatedCostById[residentKey] = cost
end

local function getResidentEstimatedCostToReplace(workItem)
    local residentKey = getResidentCostKey(workItem)
    if residentKey == workItem.chunkId then
        local total = 0
        local prefix = workItem.chunkId .. "::"
        for existingKey, cost in pairs(streamingResidentEstimatedCostById) do
            if existingKey == workItem.chunkId or string.sub(existingKey, 1, #prefix) == prefix then
                total += cost
            end
        end
        return total
    end

    return streamingResidentEstimatedCostById[residentKey] or 0
end

local function getEffectiveGuardrailResidentCost(config)
    if not streamingMemoryGuardrail or config.CountResidentChunkCost == false then
        return 0
    end
    return sumEstimatedCosts(streamingResidentEstimatedCostById)
end

local function getEffectiveGuardrailInFlightCost(config)
    if not streamingMemoryGuardrail or config.CountInFlightCost == false then
        return 0
    end
    return streamingMemoryGuardrail:GetCounters().inFlightBytes
end

local function chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName)
    local resolvedWorldRootName = if type(worldRootName) == "string" and worldRootName ~= ""
        then worldRootName
        else DEFAULT_WORLD_ROOT_NAME

    local folder = chunkEntry and chunkEntry.folder
    local parent = folder and folder.Parent
    local expectedWorldRoot = Workspace:FindFirstChild(resolvedWorldRootName)
    return parent ~= nil and expectedWorldRoot ~= nil and parent == expectedWorldRoot
end

local function isChunkLoadedInWorldRoot(chunkId, worldRootName)
    local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
    return chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName)
end

local function pruneStaleResidentEstimatedCosts(worldRootName)
    local staleChunkIds = {}
    local seenChunkIds = {}
    for residentKey in pairs(streamingResidentEstimatedCostById) do
        local chunkId = string.match(residentKey, "^(.-)::") or residentKey
        if not seenChunkIds[chunkId] then
            seenChunkIds[chunkId] = true
            if not isChunkLoadedInWorldRoot(chunkId, worldRootName) then
                staleChunkIds[#staleChunkIds + 1] = chunkId
            end
        end
    end

    for _, chunkId in ipairs(staleChunkIds) do
        clearResidentEstimatedCostForChunk(chunkId)
        loadedChunkLods[chunkId] = nil
        ImportService.ResetSubplanState(chunkId, worldRootName)
    end
end

local function reconcileLoadedChunksForStart(chunkRefs, worldRootName)
    local chunkRefById = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        if type(chunkRef) == "table" and type(chunkRef.id) == "string" and chunkRef.id ~= "" then
            chunkRefById[chunkRef.id] = chunkRef
        end
    end

    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        if chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName) then
            local chunkRef = chunkRefById[chunkId]
            local chunkSignature = if type(chunkRef) == "table"
                then ImportSignatures.GetChunkSignature(chunkRef)
                else ""
            if chunkRef == nil or chunkEntry.chunkSignature ~= chunkSignature then
                ChunkLoader.UnloadChunk(chunkId, nil, worldRootName)
                ImportService.ResetSubplanState(chunkId, worldRootName)
                clearResidentEstimatedCostForChunk(chunkId)
            end
        end
    end

    for chunkId in pairs(chunkRefById) do
        if not isChunkLoadedInWorldRoot(chunkId, worldRootName) then
            ImportService.ResetSubplanState(chunkId, worldRootName)
        end
    end
end

local function seedLoadedChunkLods(chunkOptionsByLod, worldRootName)
    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        if chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName) then
            if chunkEntry.configSignature == chunkOptionsByLod[LOD_LOW].configSignature then
                loadedChunkLods[chunkId] = LOD_LOW
            else
                loadedChunkLods[chunkId] = LOD_HIGH
            end
        end
    end
end

local function seedResidentEstimatedCosts(chunkRefs, config, worldRootName)
    if not streamingMemoryGuardrail then
        return
    end

    local chunkRefsById = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        if type(chunkRef) == "table" and type(chunkRef.id) == "string" and chunkRef.id ~= "" then
            chunkRefsById[chunkRef.id] = chunkRef
        end
    end

    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
        if chunkEntry ~= nil and chunkEntryBelongsToWorldRoot(chunkEntry, worldRootName) then
            local chunkRef = chunkRefsById[chunkId]
            if chunkRef ~= nil then
                local allowedSubplans = SubplanRollout.GetFullySchedulableSubplans(chunkRef, config)
                if allowedSubplans == nil then
                    recordResidentEstimatedCost({
                        chunkId = chunkId,
                        chunkEntry = {
                            ref = chunkRef,
                        },
                    }, getEstimatedChunkOrSubplanCost(chunkRef, nil))
                else
                    local state = ImportService.GetSubplanState(chunkId, worldRootName)
                    local completedWorkItems = state.completedWorkItems or {}
                    local seededSubplan = false
                    for _, subplan in ipairs(allowedSubplans) do
                        local completedWorkId = getCompletedSubplanWorkId(chunkId, subplan)
                        if type(completedWorkId) == "string" and completedWorkItems[completedWorkId] then
                            recordResidentEstimatedCost({
                                chunkId = chunkId,
                                chunkEntry = {
                                    ref = chunkRef,
                                },
                                subplan = subplan,
                            }, getEstimatedChunkOrSubplanCost(chunkRef, subplan))
                            seededSubplan = true
                        end
                    end

                    if not seededSubplan then
                        recordResidentEstimatedCost({
                            chunkId = chunkId,
                            chunkEntry = {
                                ref = chunkRef,
                            },
                        }, getEstimatedChunkOrSubplanCost(chunkRef, nil))
                    end
                end
            end
        end
    end
end

local function refreshMemoryGuardrailTelemetry(config, deferredAdmissions, projectedUsage)
    if not streamingMemoryGuardrail then
        clearMemoryGuardrailTelemetry()
        return
    end

    local residentCost = getEffectiveGuardrailResidentCost(config)
    local inFlightCost = getEffectiveGuardrailInFlightCost(config)
    streamingMemoryGuardrail:SetResidentBytes(residentCost)
    streamingMemoryGuardrail:SetProjectedUsageBytes(
        if type(projectedUsage) == "number"
            then normalizeNonNegativeNumber(projectedUsage)
            else residentCost + inFlightCost
    )

    local snapshot = streamingMemoryGuardrail:Snapshot()
    if
        snapshot.pauseOrigin ~= "manual"
        and streamingMemoryGuardrail:IsPaused()
        and streamingMemoryGuardrail:CanResume()
    then
        streamingMemoryGuardrail:Resume()
        streamingMemoryGuardrail:SetProjectedUsageBytes(
            if type(projectedUsage) == "number"
                then normalizeNonNegativeNumber(projectedUsage)
                else residentCost + inFlightCost
        )
        snapshot = streamingMemoryGuardrail:Snapshot()
    end

    setMemoryGuardrailTelemetry(snapshot, normalizeNonNegativeNumber(deferredAdmissions), residentCost, inFlightCost)
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

    local state = ImportService.GetSubplanState(chunkRef.id, streamingOptions.worldRootName)
    local completedWorkItems = state.completedWorkItems or {}
    local pending = {}
    for _, subplan in ipairs(allowedSubplans) do
        local completedWorkId = getCompletedSubplanWorkId(chunkRef.id, subplan)
        if type(completedWorkId) == "string" and not completedWorkItems[completedWorkId] then
            pending[#pending + 1] = subplan
        end
    end
    return pending
end

local function queuePendingSubplans(workItems, chunkEntry, chunkOptions, targetLod)
    local pendingSubplans = getPendingSubplans(chunkEntry.ref, chunkOptions.config)
    if pendingSubplans == nil or #pendingSubplans == 0 then
        return false
    end

    for _, subplan in ipairs(pendingSubplans) do
        workItems[#workItems + 1] = {
            chunkEntry = chunkEntry,
            chunkOptions = chunkOptions,
            chunkId = chunkEntry.ref.id,
            originStuds = chunkEntry.ref.originStuds,
            subplan = subplan,
            targetLod = targetLod,
        }
    end
    return true
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
            configSignature = ImportSignatures.GetConfigSignature(getLodConfig(LOD_HIGH, baseConfig)),
            layerSignatures = ImportSignatures.GetLayerSignatures(getLodConfig(LOD_HIGH, baseConfig)),
        },
        [LOD_LOW] = {
            worldRootName = options.worldRootName,
            frameBudgetSeconds = frameBudgetSeconds,
            nonBlocking = nonBlocking,
            shouldCancel = options.shouldCancel,
            config = getLodConfig(LOD_LOW, baseConfig),
            configSignature = ImportSignatures.GetConfigSignature(getLodConfig(LOD_LOW, baseConfig)),
            layerSignatures = ImportSignatures.GetLayerSignatures(getLodConfig(LOD_LOW, baseConfig)),
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

    for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)) do
        local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, streamingOptions.worldRootName)
        updateChunkEntryLodGroups(chunkEntry, camPos, highDetailRadius, interiorRadius)
    end
end

function StreamingService.Start(manifest, options)
    if heartbeatConn then
        StreamingService.Stop()
    end

    local worldRootName = if type(options) == "table" then options.worldRootName else nil
    if type(worldRootName) ~= "string" or worldRootName == "" then
        worldRootName = DEFAULT_WORLD_ROOT_NAME
    end

    if #ChunkLoader.ListLoadedChunks(worldRootName) == 0 then
        ImportService.ResetSubplanState(nil, worldRootName)
    end

    streamingManifest = manifest
    streamingChunkRefs = manifest and (manifest.chunkRefs or manifest.chunks) or nil
    streamingOptions = table.clone(options or {})
    streamingOptions.worldRootName = worldRootName
    local config = streamingOptions.config or DefaultWorldConfig
    reconcileLoadedChunksForStart(streamingChunkRefs, streamingOptions.worldRootName)
    streamingSubplanRollout = SubplanRollout.Describe(config)
    streamingPreferredForward = if typeof(streamingOptions.preferredLookVector) == "Vector3"
        then streamingOptions.preferredLookVector
        else nil
    streamingLastFocalPoint = nil
    -- Fresh starts should not inherit stale heartbeat cadence from prior runs.
    -- Tests and harnesses explicitly drive the first Update() when they need it.
    lastUpdate = os.clock()
    streamingChunkOptionsByLod = buildChunkOptionsByLod(streamingOptions, config)
    streamingChunkIndex = buildChunkSpatialIndex(streamingChunkRefs, config)
    seedLoadedChunkLods(streamingChunkOptionsByLod, streamingOptions.worldRootName)
    streamingMemoryGuardrail = MemoryGuardrail.New(MemoryGuardrail.ResolveConfig(config.MemoryGuardrails))
    table.clear(streamingResidentEstimatedCostById)
    seedResidentEstimatedCosts(streamingChunkRefs, config, streamingOptions.worldRootName)

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
    refreshMemoryGuardrailTelemetry(streamingMemoryGuardrail:GetConfig(), 0)
    resetStreamingResidencyTelemetry()
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
    streamingManifest = nil
    streamingChunkRefs = nil
    streamingChunkIndex = nil
    streamingOptions = nil
    streamingChunkOptionsByLod = nil
    streamingLastFocalPoint = nil
    streamingPreferredForward = nil
    streamingSubplanRollout = nil
    streamingMemoryGuardrail = nil
    table.clear(observedChunkImportMsById)
    table.clear(streamingResidentEstimatedCostById)
    loadedChunkLods = {}
    streamingUpdateInProgress = false
    lastUpdate = 0
    lastLODUpdate = 0
    clearMemoryGuardrailTelemetry()
    resetStreamingResidencyTelemetry()
end

function StreamingService.Update(focalPoint)
    if streamingUpdateInProgress then
        return
    end

    streamingUpdateInProgress = true
    local ok, err = xpcall(function()
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
        pruneStaleResidentEstimatedCosts(streamingOptions.worldRootName)
        observeHostProbeSample()
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

            if targetLod then
                local chunkOptions = streamingChunkOptionsByLod[targetLod]
                local currentEntry = ChunkLoader.GetChunkEntry(chunkRef.id, streamingOptions.worldRootName)
                if currentEntry then
                    local changedLayers =
                        computeChangedLayers(currentEntry.layerSignatures, chunkOptions.layerSignatures)
                    if not changedLayers and currentEntry.configSignature == chunkOptions.configSignature then
                        loadedChunkLods[chunkRef.id] = targetLod
                        desiredChunkIds[chunkRef.id] = true
                        queuePendingSubplans(importWorkItems, chunkEntry, chunkOptions, targetLod)
                        continue
                    end
                    if not changedLayers then
                        if not queuePendingSubplans(importWorkItems, chunkEntry, chunkOptions, targetLod) then
                            loadedChunkLods[chunkRef.id] = targetLod
                        end
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
                local currentEntry = ChunkLoader.GetChunkEntry(chunkRef.id, streamingOptions.worldRootName)
                if currentLod == nil and currentEntry == nil then
                    continue
                end
                -- Unload
                ChunkLoader.UnloadChunk(chunkRef.id, nil, streamingOptions.worldRootName)
                ImportService.ResetSubplanState(chunkRef.id, streamingOptions.worldRootName)
                clearResidentEstimatedCostForChunk(chunkRef.id)
                loadedChunkLods[chunkRef.id] = nil
            end
        end

        local desiredChunkCount = 0
        for _, _ in pairs(desiredChunkIds) do
            desiredChunkCount += 1
        end

        ChunkPriority.SortWorkItems(
            importWorkItems,
            playerPos,
            chunkSizeStuds,
            forwardVector,
            observedChunkImportMsById
        )

        local maxWorkItemsPerUpdate = config.StreamingMaxWorkItemsPerUpdate
        if type(maxWorkItemsPerUpdate) ~= "number" or maxWorkItemsPerUpdate < 1 then
            maxWorkItemsPerUpdate = #importWorkItems
        else
            maxWorkItemsPerUpdate = math.max(1, math.floor(maxWorkItemsPerUpdate))
        end

        local processedWorkItems = 0
        local deferredAdmissions = 0
        local deferredProjectedUsage = nil
        local memoryGuardrailConfig = if streamingMemoryGuardrail
            then streamingMemoryGuardrail:GetConfig()
            else MemoryGuardrail.ResolveConfig(nil)
        updateStreamingResidencyTelemetry(playerPos, candidateChunkEntries, desiredChunkCount, processedWorkItems)
        refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
        for workItemIndex, workItem in ipairs(importWorkItems) do
            if processedWorkItems >= maxWorkItemsPerUpdate then
                break
            end

            local workItemCost = getEstimatedWorkItemCost(workItem)
            local residentCostToReplace = if memoryGuardrailConfig.CountResidentChunkCost == false
                then 0
                else getResidentEstimatedCostToReplace(workItem)
            local effectiveWorkItemCost = if memoryGuardrailConfig.CountInFlightCost == false then 0 else workItemCost
            local projectedUsage = (getEffectiveGuardrailResidentCost(memoryGuardrailConfig) - residentCostToReplace)
                + getEffectiveGuardrailInFlightCost(memoryGuardrailConfig)
                + effectiveWorkItemCost
            refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, projectedUsage)
            if streamingMemoryGuardrail and streamingMemoryGuardrail:IsPaused() then
                deferredAdmissions = math.max(1, maxWorkItemsPerUpdate - processedWorkItems)
                if #importWorkItems >= workItemIndex then
                    deferredAdmissions = math.min(deferredAdmissions, #importWorkItems - workItemIndex + 1)
                end
                deferredProjectedUsage = projectedUsage
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, projectedUsage)
                break
            end

            local chunkEntry = workItem.chunkEntry
            local chunkRef = chunkEntry.ref
            local chunk = getMaterializedChunk(chunkEntry)
            local importStartedAt = os.clock()
            if streamingMemoryGuardrail then
                streamingMemoryGuardrail:AdmitInFlightBytes(workItemCost)
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, projectedUsage)
            end
            local importOk, importResult = xpcall(function()
                if workItem.subplan then
                    local subplanOptions = table.clone(workItem.chunkOptions)
                    subplanOptions.registrationChunk = chunkRef
                    subplanOptions.chunkSignature = ImportSignatures.GetChunkSignature(chunkRef)
                    return ImportService.ImportChunkSubplan(chunk, workItem.subplan, subplanOptions)
                else
                    local importOptions = table.clone(workItem.chunkOptions)
                    importOptions.chunkSignature = ImportSignatures.GetChunkSignature(chunkRef)
                    return ImportService.ImportChunk(chunk, importOptions)
                end
            end, debug.traceback)
            if streamingMemoryGuardrail then
                streamingMemoryGuardrail:CompleteInFlightBytes(workItemCost)
            end
            if not importOk then
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
                error(importResult, 0)
            end
            if importResult == nil then
                ImportService.RollbackCancelledImport(chunk, {
                    config = workItem.chunkOptions.config,
                    configSignature = workItem.chunkOptions.configSignature,
                    layerSignatures = workItem.chunkOptions.layerSignatures,
                    layers = workItem.chunkOptions.layers,
                    subplan = workItem.subplan,
                    worldRootName = workItem.chunkOptions.worldRootName,
                })
                clearResidentEstimatedCost(workItem)
                loadedChunkLods[chunkRef.id] = nil
                refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
                break
            end
            recordResidentEstimatedCost(workItem, workItemCost)
            refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions)
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
                ChunkLoader.UnloadChunk(chunkId, nil, streamingOptions.worldRootName)
                ImportService.ResetSubplanState(chunkId, streamingOptions.worldRootName)
                clearResidentEstimatedCostForChunk(chunkId)
                loadedChunkLods[chunkId] = nil
            end
        end

        refreshMemoryGuardrailTelemetry(memoryGuardrailConfig, deferredAdmissions, deferredProjectedUsage)
        updateStreamingResidencyTelemetry(playerPos, candidateChunkEntries, desiredChunkCount, processedWorkItems)

        for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)) do
            local chunkEntry = ChunkLoader.GetChunkEntry(chunkId, streamingOptions.worldRootName)
            updateChunkEntryLodGroups(chunkEntry, playerPos, highRadius, interiorRadius)
        end

        streamingLastFocalPoint = playerPos
    end, debug.traceback)
    streamingUpdateInProgress = false
    if not ok then
        error(err, 0)
    end
end

return StreamingService
