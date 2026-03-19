local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ImportService = require(script.Parent)
local ChunkLoader = require(script.Parent.ChunkLoader)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Logger = require(ReplicatedStorage.Shared.Logger)

local StreamingService = {}

local streamingManifest = nil
local streamingChunkRefs = nil
local streamingOptions = nil
local streamingChunkIndex = nil
local heartbeatConn = nil
local lastUpdate = 0
local UPDATE_INTERVAL = 1.0 -- seconds between distance checks
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

    local config = table.clone(baseConfig)
    if level == LOD_LOW then
        -- Low LOD: keep terrain and roads, hide buildings/water/props
        config.BuildingMode = "none"
        config.WaterMode = "none"
        -- config.RoadMode = "mesh" -- Keep roads for macro shape
    end

    cachedByLevel[level] = config
    return config
end

local function buildChunkOptionsByLod(options, baseConfig)
    return {
        [LOD_HIGH] = {
            worldRootName = options.worldRootName,
            frameBudgetSeconds = options.frameBudgetSeconds,
            nonBlocking = options.nonBlocking,
            shouldCancel = options.shouldCancel,
            config = getLodConfig(LOD_HIGH, baseConfig),
            configSignature = getConfigSignature(getLodConfig(LOD_HIGH, baseConfig)),
            layerSignatures = getLayerSignatures(getLodConfig(LOD_HIGH, baseConfig)),
        },
        [LOD_LOW] = {
            worldRootName = options.worldRootName,
            frameBudgetSeconds = options.frameBudgetSeconds,
            nonBlocking = options.nonBlocking,
            shouldCancel = options.shouldCancel,
            config = getLodConfig(LOD_LOW, baseConfig),
            configSignature = getConfigSignature(getLodConfig(LOD_LOW, baseConfig)),
            layerSignatures = getLayerSignatures(getLodConfig(LOD_LOW, baseConfig)),
        },
    }
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

    -- LOD_Detail: windows, street lights, oneway arrows, building name labels.
    for _, instance in ipairs(CollectionService:GetTagged("LOD_Detail")) do
        -- Guard: only toggle parts that are in the workspace and currently rendered.
        -- BillboardGui tagged instances are toggled via Enabled, not Transparency.
        if instance:IsA("BasePart") then
            local dist = (instance.Position - camPos).Magnitude
            if dist > highDetailRadius then
                instance.Transparency = 1
            else
                instance.Transparency = instance:GetAttribute("BaseTransparency") or 0
            end
        elseif instance:IsA("BillboardGui") then
            local adornee = instance.Adornee or instance.Parent
            if adornee and adornee:IsA("BasePart") then
                local dist = (adornee.Position - camPos).Magnitude
                instance.Enabled = dist <= highDetailRadius
            end
        end
    end

    -- LOD_Interior: room floors, walls, ceilings.
    for _, instance in ipairs(CollectionService:GetTagged("LOD_Interior")) do
        if instance:IsA("BasePart") then
            local dist = (instance.Position - camPos).Magnitude
            if dist > interiorRadius then
                instance.Transparency = 1
            else
                instance.Transparency = instance:GetAttribute("BaseTransparency") or 0
            end
        end
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
    streamingChunkOptionsByLod = buildChunkOptionsByLod(streamingOptions, config)
    streamingChunkIndex = buildChunkSpatialIndex(streamingChunkRefs, config)

    if not config.StreamingEnabled then
        Logger.warn("StreamingService.Start called but StreamingEnabled is false in config")
        return
    end

    Logger.info("StreamingService started for world:", manifest.meta.worldName)

    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        local now = os.clock()
        if now - lastUpdate >= UPDATE_INTERVAL then
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

    local targetRadiusSq = targetRadius * targetRadius
    local highRadiusSq = highRadius * highRadius
    local highExitRadius = getExitRadius(highRadius, targetRadius)
    local targetExitRadius = getExitRadius(targetRadius, nil)
    local highExitRadiusSq = highExitRadius * highExitRadius
    local targetExitRadiusSq = targetExitRadius * targetExitRadius

    local desiredChunkIds = {}
    for _, chunkEntry in ipairs(getCandidateChunkRefs(streamingChunkIndex, playerPos, targetExitRadius)) do
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
                local currentEntry = ChunkLoader.GetChunkEntry(chunkRef.id)
                if currentEntry and currentEntry.configSignature == chunkOptions.configSignature then
                    loadedChunkLods[chunkRef.id] = targetLod
                    continue
                end

                if currentEntry then
                    local changedLayers =
                        computeChangedLayers(currentEntry.layerSignatures, chunkOptions.layerSignatures)
                    if not changedLayers then
                        loadedChunkLods[chunkRef.id] = targetLod
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

                local chunk = getMaterializedChunk(chunkEntry)
                ImportService.ImportChunk(chunk, chunkOptions)
                loadedChunkLods[chunkRef.id] = targetLod
                desiredChunkIds[chunkRef.id] = true
            else
                -- Unload
                ChunkLoader.UnloadChunk(chunkRef.id)
                loadedChunkLods[chunkRef.id] = nil
            end
        elseif targetLod then
            desiredChunkIds[chunkRef.id] = true
        end
    end

    for chunkId, _ in pairs(loadedChunkLods) do
        if not desiredChunkIds[chunkId] then
            ChunkLoader.UnloadChunk(chunkId)
            loadedChunkLods[chunkId] = nil
        end
    end
end

return StreamingService
