local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local Logger = require(ReplicatedStorage.Shared.Logger)

local ManifestLoader = {}
local SAMPLE_DATA_TIMEOUT_SECONDS = 5
local normalizeChunkRefs

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
    local clonedChunkRefs = {}
    for _, chunkRef in ipairs(chunkRefs or {}) do
        table.insert(clonedChunkRefs, cloneChunkRef(chunkRef))
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

local function chunkRefsNeedShardRebuild(chunkRefs)
    if type(chunkRefs) ~= "table" or #chunkRefs == 0 then
        return true
    end

    for _, chunkRef in ipairs(chunkRefs) do
        if type(chunkRef.shards) ~= "table" or #chunkRef.shards == 0 then
            return true
        end
    end

    return false
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

            local isArray = #value > 0
            if isArray then
                for _, item in ipairs(value) do
                    table.insert(target, item)
                end
            else
                for nestedKey, nestedValue in pairs(value) do
                    target[nestedKey] = nestedValue
                end
            end
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
    local sampleData = ServerStorage:FindFirstChild("SampleData")
    if sampleData then
        return sampleData
    end

    sampleData = ServerStorage:WaitForChild("SampleData", timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if sampleData then
        return sampleData
    end

    error("ServerStorage.SampleData was not provisioned into the live DataModel")
end

local function resolveSampleModule(name, timeoutSeconds)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    local module = sampleData:FindFirstChild(name)
    if module then
        return module
    end

    module = sampleData:WaitForChild(name, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if module then
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
        error(("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(shardFolderName))
    end

    local chunkRefs = normalizeChunkRefs(index, shardFolder, timeoutSeconds)
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

local function buildChunkRefsFromShards(index, shardFolder, timeoutSeconds, seedChunkRefsById)
    local chunkRefsById = {}
    local chunkOrder = {}

    for _, shardName in ipairs(index.shards or {}) do
        local shardModule = shardFolder:FindFirstChild(shardName)
            or shardFolder:WaitForChild(shardName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        if not shardModule then
            error(("%s.%s was not provisioned into the live DataModel"):format(shardFolder:GetFullName(), shardName))
        end

        local shardData = require(shardModule)
        for _, chunk in ipairs(shardData.chunks or {}) do
            local chunkRef = chunkRefsById[chunk.id]
            if not chunkRef then
                local seedChunkRef = seedChunkRefsById and seedChunkRefsById[chunk.id]
                chunkRef = {
                    id = chunk.id,
                    originStuds = chunk.originStuds or (seedChunkRef and seedChunkRef.originStuds and table.clone(
                        seedChunkRef.originStuds
                    )) or { x = 0, y = 0, z = 0 },
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

    local chunkRefs = {}
    for _, chunkId in ipairs(chunkOrder) do
        table.insert(chunkRefs, chunkRefsById[chunkId])
    end
    return chunkRefs
end

function normalizeChunkRefs(index, shardFolder, timeoutSeconds)
    local chunkRefs = index.chunkRefs
    if chunkRefsNeedShardRebuild(chunkRefs) then
        return buildChunkRefsFromShards(index, shardFolder, timeoutSeconds, buildChunkRefSeedMap(chunkRefs))
    end

    return cloneChunkRefs(chunkRefs)
end

function ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds, options)
    local freshRequire = type(options) == "table" and options.freshRequire == true
    local index = requireModule(indexModule, freshRequire)
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

    local chunkRefById = {}
    for _, chunkRef in ipairs(chunkRefs) do
        chunkRefById[chunkRef.id] = chunkRef
    end

    local function resolveShardModule(shardName)
        local shardModule = shardFolder:FindFirstChild(shardName)
            or shardFolder:WaitForChild(shardName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
        if not shardModule then
            error(("%s.%s was not provisioned into the live DataModel"):format(shardFolder:GetFullName(), shardName))
        end
        return shardModule
    end

    local function loadShardData(shardName)
        local cached = shardCache[shardName]
        if cached ~= nil then
            return cached
        end

        local shardModule = resolveShardModule(shardName)

        cached = requireModule(shardModule, freshRequire)
        shardCache[shardName] = cached
        return cached
    end

    local handle = {
        schemaVersion = index.schemaVersion,
        meta = index.meta,
        shardFolder = index.shardFolder,
        chunkRefs = chunkRefs,
    }

    function handle:GetChunk(chunkId)
        local cached = chunkCache[chunkId]
        if cached ~= nil then
            return cached
        end

        local chunkRef = chunkRefById[chunkId]
        if not chunkRef then
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local chunksById = {}
        local chunkOrder = {}
        for _, shardName in ipairs(chunkRef.shards or {}) do
            local shardData = loadShardData(shardName)
            for _, chunk in ipairs(shardData.chunks or {}) do
                if chunk.id == chunkId then
                    mergeChunkFragment(chunksById, chunkOrder, chunk)
                end
            end
        end

        local validated = finalizeManifest(index, chunksById, chunkOrder, { chunkRef })
        local chunk = validated.chunks[1]
        if not chunk then
            error(("Failed to materialize chunk id: %s"):format(tostring(chunkId)))
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
            error(("Unknown chunk id: %s"):format(tostring(chunkId)))
        end

        local shardFingerprints = {}
        for _, shardName in ipairs(chunkRef.shards or {}) do
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
        local chunks = {}
        for _, chunkId in ipairs(chunkIds or {}) do
            table.insert(chunks, self:GetChunk(chunkId))
        end
        return chunks
    end

    function handle:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        if not loadRadius then
            local chunkIds = {}
            for _, chunkRef in ipairs(self.chunkRefs) do
                table.insert(chunkIds, chunkRef.id)
            end
            return chunkIds
        end

        local centerX = loadCenter and loadCenter.X or 0
        local centerZ = loadCenter and loadCenter.Z or 0
        local chunkSize = self.meta and self.meta.chunkSizeStuds or 256
        local loadRadiusSq = loadRadius * loadRadius
        local chunkIds = {}
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
        local chunkIds = {}
        for _, chunkRef in ipairs(self.chunkRefs) do
            table.insert(chunkIds, chunkRef.id)
        end

        local manifest = newManifest(index, self.chunkRefs)
        manifest.chunks = self:LoadChunks(chunkIds)
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
    local indexModule = resolveSampleModule(indexName, timeoutSeconds)
    local sampleData = resolveSampleDataFolder(timeoutSeconds)
    local index = require(indexModule)
    local shardFolderName = index.shardFolder or (indexModule.Name .. "Chunks")
    local shardFolder = sampleData:FindFirstChild(shardFolderName)
        or sampleData:WaitForChild(shardFolderName, timeoutSeconds or SAMPLE_DATA_TIMEOUT_SECONDS)
    if not shardFolder then
        error(("ServerStorage.SampleData.%s was not provisioned into the live DataModel"):format(shardFolderName))
    end

    return ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, timeoutSeconds, options)
end

function ManifestLoader.FreezeHandleForChunkIds(handle, chunkIds)
    local frozenChunkIds = {}
    local frozenChunkIdSet = {}
    for _, chunkId in ipairs(chunkIds or {}) do
        if not frozenChunkIdSet[chunkId] then
            frozenChunkIdSet[chunkId] = true
            table.insert(frozenChunkIds, chunkId)
        end
    end

    local frozenChunkRefs = {}
    local frozenChunkRefById = {}
    for _, chunkRef in ipairs(handle.chunkRefs or {}) do
        if frozenChunkIdSet[chunkRef.id] then
            local frozenRef = cloneChunkRef(chunkRef)
            frozenChunkRefById[chunkRef.id] = frozenRef
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
        local chunks = {}
        for _, chunkId in ipairs(loadChunkIds or {}) do
            table.insert(chunks, self:GetChunk(chunkId))
        end
        return chunks
    end

    function frozenHandle:GetChunkIdsWithinRadius(loadCenter, loadRadius)
        if not loadRadius then
            local ids = {}
            for _, chunkRef in ipairs(self.chunkRefs) do
                table.insert(ids, chunkRef.id)
            end
            return ids
        end

        local centerX = loadCenter and loadCenter.X or 0
        local centerZ = loadCenter and loadCenter.Z or 0
        local chunkSize = self.meta and self.meta.chunkSizeStuds or 256
        local loadRadiusSq = loadRadius * loadRadius
        local ids = {}
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
