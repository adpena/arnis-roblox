local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local Logger = require(ReplicatedStorage.Shared.Logger)

local ManifestLoader = {}
local SAMPLE_DATA_TIMEOUT_SECONDS = 5
local normalizeChunkRefs
local buildChunkRefsFromShards

local function cloneArray(values)
    if type(values) ~= "table" then
        return values
    end

    local copy = {}
    for index, value in ipairs(values) do
        if type(value) == "table" then
            copy[index] = table.clone(value)
        else
            copy[index] = value
        end
    end
    return copy
end

local function cloneChunkRef(chunkRef)
    local cloned = {
        id = chunkRef.id,
        originStuds = chunkRef.originStuds and table.clone(chunkRef.originStuds) or nil,
    }

    if type(chunkRef.shards) == "table" then
        cloned.shards = cloneArray(chunkRef.shards)
    end

    if chunkRef.featureCount ~= nil then
        cloned.featureCount = chunkRef.featureCount
    end

    if chunkRef.streamingCost ~= nil then
        cloned.streamingCost = chunkRef.streamingCost
    end

    if chunkRef.partitionVersion ~= nil then
        cloned.partitionVersion = chunkRef.partitionVersion
    end

    if type(chunkRef.subplans) == "table" then
        cloned.subplans = cloneArray(chunkRef.subplans)
    end

    return cloned
end

local function cloneChunkRefs(chunkRefs)
    local sourceChunkRefs = chunkRefs or {}
    local clonedChunkRefs = table.create(#sourceChunkRefs)
    for index, chunkRef in ipairs(sourceChunkRefs) do
        clonedChunkRefs[index] = cloneChunkRef(chunkRef)
    end
    return clonedChunkRefs
end

local function buildChunkRefSeedMap(chunkRefs)
    local chunkRefsById = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        chunkRefsById[chunkRef.id] = chunkRef
    end
    return chunkRefsById
end

local function hasChunkRefs(chunkRefs)
    return type(chunkRefs) == "table" and #chunkRefs > 0
end

local function requireModule(module, freshRequire)
    if not freshRequire then
        return require(module)
    end

    if not module:IsA("ModuleScript") then
        return require(module)
    end

    local clone = module:Clone()
    clone.Name = module.Name .. "_Fresh"
    clone.Parent = module.Parent

    local ok, result = pcall(require, clone)
    clone:Destroy()
    if not ok then
        error(result)
    end
    return result
end

local function newManifest(index, chunkRefs)
    local manifest = {
        schemaVersion = index.schemaVersion,
        meta = index.meta,
        chunks = {},
    }

    if type(chunkRefs) == "table" and #chunkRefs > 0 then
        manifest.chunkRefs = cloneChunkRefs(chunkRefs)
    end

    return manifest
end

local function mergeTableValue(target, value)
    local isArray = #value > 0
    if isArray then
        for _, item in ipairs(value) do
            table.insert(target, item)
        end
        return
    end

    for nestedKey, nestedValue in pairs(value) do
        if type(nestedValue) == "table" then
            local nestedTarget = target[nestedKey]
            if type(nestedTarget) ~= "table" then
                nestedTarget = {}
                target[nestedKey] = nestedTarget
            end
            mergeTableValue(nestedTarget, nestedValue)
        elseif target[nestedKey] == nil then
            target[nestedKey] = nestedValue
        end
    end
end

local function mergeChunkFragment(chunksById, chunkOrder, chunk)
    local existing = chunksById[chunk.id]
    if not existing then
        existing = {}
        chunksById[chunk.id] = existing
        table.insert(chunkOrder, chunk.id)
    end

    for key, value in pairs(chunk) do
        if type(value) == "table" then
            local target = existing[key]
            if target == nil then
                target = {}
                existing[key] = target
            end

            mergeTableValue(target, value)
        elseif existing[key] == nil then
            existing[key] = value
        end
    end
end

local function finalizeManifest(index, chunksById, chunkOrder, chunkRefs)
    local manifest = newManifest(index, chunkRefs)
    for _, chunkId in ipairs(chunkOrder) do
        table.insert(manifest.chunks, chunksById[chunkId])
    end

    return ChunkSchema.validateManifest(manifest)
end

local function resolveSampleDataFolder(timeoutSeconds)
    print("[ManifestLoader] Resolving ServerStorage.SampleData")
    local sampleData = ServerStorage:FindFirstChild("SampleData")
    if sampleData then
        print("[ManifestLoader] Resolved ServerStorage.SampleData via FindFirstChild")
        return sampleData
    end

    sampleData =
        ServerStorage:WaitForChild("SampleData", timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if sampleData then
        print("[ManifestLoader] Resolved ServerStorage.SampleData via WaitForChild")
        return sampleData
    end

    error("ServerStorage.SampleData was not provisioned into the live DataModel")
end

local function resolveSampleModule(name, timeoutSeconds)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    print(("[ManifestLoader] Resolving sample module %s"):format(name))
    local module = sampleData:FindFirstChild(name)
    if module then
        print(("[ManifestLoader] Resolved sample module %s via FindFirstChild"):format(name))
        return module
    end

    module = sampleData:WaitForChild(name, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if module then
        print(("[ManifestLoader] Resolved sample module %s via WaitForChild"):format(name))
        return module
    end

    error(("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(name))
end

local function loadShardedManifest(indexModule, timeoutSeconds)
    local index = require(indexModule)
    if type(index) ~= "table" then
        error("Sharded manifest index must return a table")
    end

    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    local shardFolderName = index.shardFolder or (indexModule.Name .. "Chunks")
    local shardFolder = sampleData:FindFirstChild(shardFolderName)
        or sampleData:WaitForChild(shardFolderName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if not shardFolder then
        error(
            ("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(
                shardFolderName
            )
        )
    end

    local chunkRefs = buildChunkRefsFromShards(
        index,
        shardFolder,
        timeoutSeconds,
        buildChunkRefSeedMap(index.chunkRefs)
    )
    local chunksById = {}
    local chunkOrder = {}

    for _, shardName in ipairs(index.shards or {}) do
        local shardModule = shardFolder:FindFirstChild(shardName)
            or shardFolder:WaitForChild(shardName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        if not shardModule then
            error(
                ("ServerStorage.SampleData.%s.%s was not provisioned into the live DataModel"):format(
                    shardFolderName,
                    shardName
                )
            )
        end

        local shardData = require(shardModule)
        for _, chunk in ipairs(shardData.chunks or {}) do
            mergeChunkFragment(chunksById, chunkOrder, chunk)
        end
    end

    return finalizeManifest(index, chunksById, chunkOrder, chunkRefs)
end

function buildChunkRefsFromShards(
    index,
    shardFolder,
    timeoutSeconds,
    seedChunkRefsById,
    shardDataLoader
)
    local chunkRefsById = {}
    local chunkOrder = {}

    for _, shardName in ipairs(index.shards or {}) do
        local shardData
        if type(shardDataLoader) == "function" then
            shardData = shardDataLoader(shardName)
        else
            local shardModule = shardFolder:FindFirstChild(shardName)
                or shardFolder:WaitForChild(
                    shardName,
                    timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS
                )
            if not shardModule then
                error(
                    ("%s.%s was not provisioned into the live DataModel"):format(
                        shardFolder:GetFullName(),
                        shardName
                    )
                )
            end

            shardData = require(shardModule)
        end
        for _, chunk in ipairs(shardData.chunks or {}) do
            local chunkRef = chunkRefsById[chunk.id]
            if not chunkRef then
                local seedChunkRef = seedChunkRefsById and seedChunkRefsById[chunk.id]
                chunkRef = {
                    id = chunk.id,
                    originStuds = chunk.originStuds
                        or (seedChunkRef and seedChunkRef.originStuds and table.clone(
                            seedChunkRef.originStuds
                        ))
                        or { x = 0, y = 0, z = 0 },
                    shards = {},
                }
                if seedChunkRef then
                    if seedChunkRef.featureCount ~= nil then
                        chunkRef.featureCount = seedChunkRef.featureCount
                    end
                    if seedChunkRef.streamingCost ~= nil then
                        chunkRef.streamingCost = seedChunkRef.streamingCost
                    end
                    if seedChunkRef.partitionVersion ~= nil then
                        chunkRef.partitionVersion = seedChunkRef.partitionVersion
                    end
                    if type(seedChunkRef.subplans) == "table" then
                        chunkRef.subplans = cloneArray(seedChunkRef.subplans)
                    end
                end
                chunkRefsById[chunk.id] = chunkRef
                table.insert(chunkOrder, chunk.id)
            end
            table.insert(chunkRef.shards, shardName)
        end
    end

    local chunkRefs = table.create(#chunkOrder)
    for arrayIndex, chunkId in ipairs(chunkOrder) do
        chunkRefs[arrayIndex] = chunkRefsById[chunkId]
    end
    return chunkRefs
end

function normalizeChunkRefs(index, shardFolder, timeoutSeconds)
    if hasChunkRefs(index.chunkRefs) then
        return cloneChunkRefs(index.chunkRefs)
    end

    return buildChunkRefsFromShards(
        index,
        shardFolder,
        timeoutSeconds,
        buildChunkRefSeedMap(index.chunkRefs)
    )
end

function ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds, options)
    local freshRequire = type(options) == "table" and options.freshRequire == true
    print(("[ManifestLoader] Requiring sharded index %s"):format(indexModule:GetFullName()))
    local index = requireModule(indexModule, freshRequire)
    print(("[ManifestLoader] Required sharded index %s"):format(indexModule.Name))
    if type(index) ~= "table" then
        error("Sharded manifest index must return a table")
    end
    if not shardFolder then
        error("Sharded manifest folder is required")
    end

    local shardCache = {}
    local chunkCache = {}
    local chunkFingerprintCache = {}
    local chunkRefs = normalizeChunkRefs(index, shardFolder, timeoutSeconds)
    ChunkSchema.validateChunkRefs(chunkRefs)
    print(
        ("[ManifestLoader] Prepared handle for %s with %d chunkRefs"):format(
            indexModule.Name,
            #chunkRefs
        )
    )
    local canonicalShardCacheByChunkId = {}
    local chunkIdsByShardName = {}

    local chunkRefById = {}
    for _, chunkRef in ipairs(chunkRefs) do
        chunkRefById[chunkRef.id] = chunkRef
    end
    local canonicalChunkRefs = nil
    local handle

    local function resolveShardModule(shardName, required)
        local shardModule = shardFolder:FindFirstChild(shardName)
        if shardModule == nil and required ~= false then
            shardModule =
                shardFolder:WaitForChild(shardName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        end
        if shardModule == nil and required ~= false then
            error(
                ("%s.%s was not provisioned into the live DataModel"):format(
                    shardFolder:GetFullName(),
                    shardName
                )
            )
        end
        return shardModule
    end

    local function loadShardData(shardName, required)
        local cached = shardCache[shardName]
        if cached ~= nil then
            return cached
        end

        local shardModule = resolveShardModule(shardName, required)
        if shardModule == nil then
            return nil
        end

        cached = requireModule(shardModule, freshRequire)
        shardCache[shardName] = cached
        return cached
    end

    local function shardContainsChunk(shardName, chunkId, required)
        local chunkIds = chunkIdsByShardName[shardName]
        if chunkIds == nil then
            chunkIds = {}
            local shardData = loadShardData(shardName, required)
            if shardData ~= nil then
                for _, chunk in ipairs(shardData.chunks or {}) do
                    chunkIds[chunk.id] = true
                end
            end
            chunkIdsByShardName[shardName] = chunkIds
        end

        return chunkIds[chunkId] == true
    end

    local function resolveCanonicalShardsForChunk(chunkId)
        local cached = canonicalShardCacheByChunkId[chunkId]
        if cached ~= nil then
            return cached
        end

        local chunkRef = chunkRefById[chunkId]
        if not chunkRef then
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local declaredChunkShards = chunkRef.shards or {}
        local declaredIndexShards = index.shards or {}
        local canonicalShards = table.create(#declaredChunkShards + #declaredIndexShards)
        local seenShardNames = {}

        for _, shardName in ipairs(declaredChunkShards) do
            if not seenShardNames[shardName] and shardContainsChunk(shardName, chunkId, false) then
                seenShardNames[shardName] = true
                table.insert(canonicalShards, shardName)
            end
        end

        for _, shardName in ipairs(declaredIndexShards) do
            if not seenShardNames[shardName] and shardContainsChunk(shardName, chunkId, true) then
                seenShardNames[shardName] = true
                table.insert(canonicalShards, shardName)
            end
        end

        if #canonicalShards == 0 then
            error(("Failed to resolve canonical shards for chunk id: %s"):format(tostring(chunkId)))
        end

        chunkRef.shards = cloneArray(canonicalShards)
        canonicalShardCacheByChunkId[chunkId] = chunkRef.shards
        return chunkRef.shards
    end

    local function materializeChunkFromShardNames(chunkId, chunkRef, shardNames, required)
        if type(shardNames) ~= "table" or #shardNames == 0 then
            return nil, nil
        end

        local chunksById = {}
        local chunkOrder = {}
        local resolvedShardNames = {}

        for _, shardName in ipairs(shardNames) do
            local shardData = loadShardData(shardName, required)
            if shardData ~= nil then
                local foundChunk = false
                for _, chunk in ipairs(shardData.chunks or {}) do
                    if chunk.id == chunkId then
                        mergeChunkFragment(chunksById, chunkOrder, chunk)
                        foundChunk = true
                    end
                end
                if foundChunk then
                    table.insert(resolvedShardNames, shardName)
                end
            end
        end

        if #chunkOrder == 0 then
            return nil, nil
        end

        local validated = finalizeManifest(index, chunksById, chunkOrder, { chunkRef })
        return validated.chunks[1], resolvedShardNames
    end

    local function resolveCanonicalChunkRefs()
        if canonicalChunkRefs ~= nil then
            return canonicalChunkRefs
        end

        canonicalChunkRefs = buildChunkRefsFromShards(
            index,
            shardFolder,
            timeoutSeconds,
            buildChunkRefSeedMap(chunkRefs),
            loadShardData
        )
        chunkRefs = canonicalChunkRefs
        chunkRefById = {}
        for _, chunkRef in ipairs(canonicalChunkRefs) do
            chunkRefById[chunkRef.id] = chunkRef
        end
        handle.chunkRefs = canonicalChunkRefs
        return canonicalChunkRefs
    end

    handle = {
        schemaVersion = index.schemaVersion,
        meta = index.meta,
        shardFolder = index.shardFolder,
        chunkRefs = chunkRefs,
    }

    function handle:ResolveChunkRef(chunkId)
        if chunkRefById[chunkId] == nil then
            resolveCanonicalChunkRefs()
        end
        return chunkRefById[chunkId]
    end

    function handle:GetChunk(chunkId)
        local cached = chunkCache[chunkId]
        if cached ~= nil then
            return cached
        end

        local chunkRef = chunkRefById[chunkId]
        if not chunkRef then
            chunkRef = self:ResolveChunkRef(chunkId)
        end
        if not chunkRef then
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local chunk = nil
        local resolvedShardNames = nil

        if type(chunkRef.shards) == "table" and #chunkRef.shards > 0 then
            chunk, resolvedShardNames =
                materializeChunkFromShardNames(chunkId, chunkRef, chunkRef.shards, false)
        end

        if chunk == nil then
            local canonicalShards = resolveCanonicalShardsForChunk(chunkId)
            chunk, resolvedShardNames =
                materializeChunkFromShardNames(chunkId, chunkRef, canonicalShards, true)
        end

        if not chunk then
            error(("Failed to materialize chunk id: %s"):format(tostring(chunkId)))
        end

        if resolvedShardNames and #resolvedShardNames > 0 then
            chunkRef.shards = cloneArray(resolvedShardNames)
            canonicalShardCacheByChunkId[chunkId] = chunkRef.shards
        end

        chunkCache[chunkId] = chunk
        return chunk
    end

    function handle:GetChunkFingerprint(chunkId)
        local cached = chunkFingerprintCache[chunkId]
        if cached ~= nil then
            return cached
        end

        local chunkRef = chunkRefById[chunkId]
        if not chunkRef then
            chunkRef = self:ResolveChunkRef(chunkId)
        end
        if not chunkRef then
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local shardNames = canonicalShardCacheByChunkId[chunkId]
        if shardNames == nil then
            shardNames = chunkRef.shards
        end
        if type(shardNames) ~= "table" or #shardNames == 0 then
            shardNames = resolveCanonicalShardsForChunk(chunkId)
        end
        local shardFingerprints = table.create(#shardNames)

        for _, shardName in ipairs(shardNames) do
            local shardModule = resolveShardModule(shardName)
            local shardFingerprint = shardModule:GetAttribute("VertigoSyncSha256")
            if type(shardFingerprint) ~= "string" or shardFingerprint == "" then
                local sourceOk, sourceOrErr = pcall(function()
                    return shardModule.Source
                end)
                if sourceOk and type(sourceOrErr) == "string" then
                    shardFingerprint = ("len:%d"):format(#sourceOrErr)
                else
                    shardFingerprint = "module:" .. shardModule.Name
                end
            end
            table.insert(shardFingerprints, ("%s:%s"):format(shardName, shardFingerprint))
        end

        cached = table.concat(shardFingerprints, "|")
        chunkFingerprintCache[chunkId] = cached
        return cached
    end

    function handle:LoadChunks(chunkIds)
        local loadChunkIds = chunkIds or {}
        local chunks = table.create(#loadChunkIds)
        for arrayIndex, chunkId in ipairs(loadChunkIds) do
            chunks[arrayIndex] = self:GetChunk(chunkId)
        end
        return chunks
    end

    function handle:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        if not loadRadius then
            local resolvedChunkRefs = resolveCanonicalChunkRefs()
            local chunkIds = table.create(#resolvedChunkRefs)
            for arrayIndex, chunkRef in ipairs(resolvedChunkRefs) do
                chunkIds[arrayIndex] = chunkRef.id
            end
            return chunkIds
        end

        local centerX = loadCenter and loadCenter.X or 0
        local centerZ = loadCenter and loadCenter.Z or 0
        local chunkSize = self.meta and self.meta.chunkSizeStuds or 256
        local loadRadiusSq = loadRadius * loadRadius
        local chunkIds = table.create(#self.chunkRefs)
        for _, chunkRef in ipairs(self.chunkRefs) do
            local origin = chunkRef.originStuds or { x = 0, z = 0 }
            local chunkCenterX = origin.x + chunkSize * 0.5
            local chunkCenterZ = origin.z + chunkSize * 0.5
            local dx = chunkCenterX - centerX
            local dz = chunkCenterZ - centerZ
            if dx * dx + dz * dz <= loadRadiusSq then
                table.insert(chunkIds, chunkRef.id)
            end
        end
        return chunkIds
    end

    function handle:LoadChunksWithinRadius(loadCenter, loadRadius)
        local chunkIds = self:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        return self:LoadChunks(chunkIds)
    end

    function handle:MaterializeManifest()
        local resolvedChunkRefs = resolveCanonicalChunkRefs()
        local chunkIds = table.create(#resolvedChunkRefs)
        for arrayIndex, chunkRef in ipairs(resolvedChunkRefs) do
            chunkIds[arrayIndex] = chunkRef.id
        end

        local chunks = self:LoadChunks(chunkIds)
        local manifest = newManifest(index, resolvedChunkRefs)
        manifest.chunks = chunks
        return ChunkSchema.validateManifest(manifest)
    end

    return handle
end

function ManifestLoader.LoadFromShardedModuleIndex(indexModule, shardFolder, timeoutSeconds)
    local handle = ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds)
    return handle:MaterializeManifest()
end

function ManifestLoader.LoadFromModule(module)
    if not module:IsA("ModuleScript") then
        error("Manifest must be a ModuleScript")
    end

    local manifest = require(module)
    return ChunkSchema.validateManifest(manifest)
end

function ManifestLoader.LoadSample()
    return ManifestLoader.LoadNamedSample("SampleManifest")
end

function ManifestLoader.LoadNamedSample(name, timeoutSeconds)
    local module = resolveSampleModule(name, timeoutSeconds)
    local manifest = require(module)
    return ChunkSchema.validateManifest(manifest)
end

function ManifestLoader.LoadNamedShardedSample(indexName, timeoutSeconds)
    local indexModule = resolveSampleModule(indexName, timeoutSeconds)
    return loadShardedManifest(indexModule, timeoutSeconds)
end

function ManifestLoader.LoadNamedShardedSampleHandle(indexName, timeoutSeconds, options)
    print(("[ManifestLoader] Loading named sharded sample handle %s"):format(indexName))
    local indexModule = resolveSampleModule(indexName, timeoutSeconds)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    print(("[ManifestLoader] Requiring named sharded sample index %s"):format(indexName))
    local index = require(indexModule)
    print(("[ManifestLoader] Required named sharded sample index %s"):format(indexName))
    local shardFolderName = index.shardFolder or (indexModule.Name .. "Chunks")
    local shardFolder = sampleData:FindFirstChild(shardFolderName)
        or sampleData:WaitForChild(shardFolderName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if not shardFolder then
        error(
            ("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(
                shardFolderName
            )
        )
    end
    print(("[ManifestLoader] Resolved shard folder %s for %s"):format(shardFolderName, indexName))

    return ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds, options)
end

function ManifestLoader.FreezeHandleForChunkIds(handle, chunkIds)
    local sourceChunkIds = chunkIds or {}
    local frozenChunkIds = table.create(#sourceChunkIds)
    local frozenChunkIdSet = {}
    for _, chunkId in ipairs(sourceChunkIds) do
        if not frozenChunkIdSet[chunkId] then
            frozenChunkIdSet[chunkId] = true
            table.insert(frozenChunkIds, chunkId)
        end
    end

    local frozenChunkRefs = table.create(#frozenChunkIds)
    local frozenChunkRefById = {}
    for _, chunkId in ipairs(frozenChunkIds) do
        local resolvedChunkRef = nil
        if type(handle.ResolveChunkRef) == "function" then
            resolvedChunkRef = handle:ResolveChunkRef(chunkId)
        else
            for _, chunkRef in ipairs(handle.chunkRefs or {}) do
                if chunkRef.id == chunkId then
                    resolvedChunkRef = chunkRef
                    break
                end
            end
        end
        if resolvedChunkRef ~= nil then
            local frozenRef = cloneChunkRef(resolvedChunkRef)
            frozenChunkRefById[chunkId] = frozenRef
            table.insert(frozenChunkRefs, frozenRef)
        end
    end

    local frozenChunks = {}
    local frozenFingerprints = {}
    for _, chunkId in ipairs(frozenChunkIds) do
        frozenChunks[chunkId] = handle:GetChunk(chunkId)
        frozenFingerprints[chunkId] = handle:GetChunkFingerprint(chunkId)
    end

    local frozenHandle = {
        schemaVersion = handle.schemaVersion,
        meta = handle.meta,
        chunkRefs = frozenChunkRefs,
    }

    function frozenHandle:GetChunk(chunkId)
        local chunk = frozenChunks[chunkId]
        if chunk == nil then
            error(("Unknown frozen chunk id: %s"):format(tostring(chunkId)))
        end
        return chunk
    end

    function frozenHandle:GetChunkFingerprint(chunkId)
        local fingerprint = frozenFingerprints[chunkId]
        if fingerprint == nil then
            error(("Unknown frozen chunk id: %s"):format(tostring(chunkId)))
        end
        return fingerprint
    end

    function frozenHandle:LoadChunks(loadChunkIds)
        local requestedChunkIds = loadChunkIds or {}
        local chunks = table.create(#requestedChunkIds)
        for index, chunkId in ipairs(requestedChunkIds) do
            chunks[index] = self:GetChunk(chunkId)
        end
        return chunks
    end

    function frozenHandle:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        if not loadRadius then
            local ids = table.create(#self.chunkRefs)
            for index, chunkRef in ipairs(self.chunkRefs) do
                ids[index] = chunkRef.id
            end
            return ids
        end

        local centerX = loadCenter and loadCenter.X or 0
        local centerZ = loadCenter and loadCenter.Z or 0
        local chunkSize = self.meta and self.meta.chunkSizeStuds or 256
        local loadRadiusSq = loadRadius * loadRadius
        local ids = table.create(#self.chunkRefs)
        for _, chunkRef in ipairs(self.chunkRefs) do
            local origin = chunkRef.originStuds or { x = 0, z = 0 }
            local chunkCenterX = origin.x + chunkSize * 0.5
            local chunkCenterZ = origin.z + chunkSize * 0.5
            local dx = chunkCenterX - centerX
            local dz = chunkCenterZ - centerZ
            if dx * dx + dz * dz <= loadRadiusSq then
                table.insert(ids, chunkRef.id)
            end
        end
        return ids
    end

    function frozenHandle:LoadChunksWithinRadius(loadCenter, loadRadius)
        return self:LoadChunks(self:GetChunkIdsWithinRadius(loadCenter, loadRadius))
    end

    function frozenHandle:MaterializeManifest()
        local manifest = newManifest({
            schemaVersion = self.schemaVersion,
            meta = self.meta,
        }, self.chunkRefs)
        manifest.chunks = self:LoadChunks(frozenChunkIds)
        return ChunkSchema.validateManifest(manifest)
    end

    return frozenHandle
end

function ManifestLoader.RequireNamedSample(name, timeoutSeconds)
    local module = resolveSampleModule(name, timeoutSeconds)
    return require(module)
end

function ManifestLoader.LoadFromFile(_path)
    -- In Studio, we might use a plugin to read files,
    -- but for runtime scripts we rely on pre-loaded ModuleScripts.
    Logger.warn("LoadFromFile not implemented for runtime - use LoadFromModule")
    return nil
end

return ManifestLoader
