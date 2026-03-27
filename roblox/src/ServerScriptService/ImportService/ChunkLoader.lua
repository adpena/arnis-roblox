local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local TerrainBuilder = require(script.Parent.Builders.TerrainBuilder)
local PropBuilder = require(script.Parent.Builders.PropBuilder)
local Profiler = require(script.Parent.Profiler)

local ChunkLoader = {}

local registryByWorldRootName = {}

local function clearChildren(folder)
    for _, child in ipairs(folder:GetChildren()) do
        child:Destroy()
    end
end

local function collectLodGroups(folder)
    local groups = {
        detail = {},
        interior = {},
    }
    if not folder then
        return groups
    end

    for _, descendant in ipairs(folder:GetDescendants()) do
        if descendant:IsA("Folder") then
            local kind = descendant:GetAttribute("ArnisLodGroupKind")
            if kind == "detail" and CollectionService:HasTag(descendant, "LOD_DetailGroup") then
                groups.detail[#groups.detail + 1] = descendant
            elseif kind == "interior" and CollectionService:HasTag(descendant, "LOD_InteriorGroup") then
                groups.interior[#groups.interior + 1] = descendant
            end
        end
    end

    return groups
end

local function collectReactives(groups)
    local reactives = {
        streetLights = {},
        nightWindows = {},
    }

    for _, group in ipairs(groups.detail) do
        for _, descendant in ipairs(group:GetDescendants()) do
            if descendant:IsA("BasePart") then
                if CollectionService:HasTag(descendant, "StreetLight") then
                    reactives.streetLights[#reactives.streetLights + 1] = descendant
                end
                if
                    descendant.Material == Enum.Material.Glass
                    and descendant:GetAttribute("BaseTransparency") ~= nil
                then
                    reactives.nightWindows[#reactives.nightWindows + 1] = descendant
                end
            end
        end
    end

    return reactives
end

local function collectChunkMetadata(folder)
    local lodGroups = collectLodGroups(folder)
    return {
        lodGroups = lodGroups,
        reactives = collectReactives(lodGroups),
    }
end

local function resolveWorldRootName(folder, metadata)
    if type(metadata) == "table" and type(metadata.worldRootName) == "string" and metadata.worldRootName ~= "" then
        return metadata.worldRootName
    end

    if folder and folder.Parent then
        if folder.Parent == Workspace then
            return folder.Name
        end
        return folder.Parent.Name
    end

    return "__global__"
end

local function getRegistryBucket(worldRootName, createIfMissing)
    local bucket = registryByWorldRootName[worldRootName]
    if bucket == nil and createIfMissing then
        bucket = {}
        registryByWorldRootName[worldRootName] = bucket
    end
    return bucket
end

local function clearEmptyBucket(worldRootName)
    local bucket = registryByWorldRootName[worldRootName]
    if bucket == nil then
        return
    end
    if next(bucket) == nil then
        registryByWorldRootName[worldRootName] = nil
    end
end

local function disconnectDestroyConn(entry)
    if entry and entry.destroyConn then
        entry.destroyConn:Disconnect()
        entry.destroyConn = nil
    end
end

local function removeEntry(worldRootName, chunkId)
    local bucket = registryByWorldRootName[worldRootName]
    if bucket == nil then
        return
    end
    local entry = bucket[chunkId]
    if entry == nil then
        return
    end
    disconnectDestroyConn(entry)
    bucket[chunkId] = nil
    clearEmptyBucket(worldRootName)
end

local function getScopedEntry(chunkId, worldRootName)
    local bucket = registryByWorldRootName[worldRootName]
    return bucket and bucket[chunkId] or nil
end

local function listScopedChunks(worldRootName)
    local result = {}
    local bucket = registryByWorldRootName[worldRootName]
    if bucket == nil then
        return result
    end
    for chunkId in pairs(bucket) do
        result[#result + 1] = chunkId
    end
    table.sort(result)
    return result
end

local function unloadScopedEntry(chunkId, worldRootName, preserveFolder)
    local entry = getScopedEntry(chunkId, worldRootName)
    if not entry then
        return
    end

    local profile = Profiler.begin("UnloadChunk")

    disconnectDestroyConn(entry)

    if entry.folder then
        local propsFolder = entry.folder:FindFirstChild("Props")
        if propsFolder then
            PropBuilder.ReleaseAll(propsFolder)
        end
        if preserveFolder then
            clearChildren(entry.folder)
        else
            entry.folder:Destroy()
        end
    end

    if entry.chunk and entry.chunk.terrain then
        TerrainBuilder.Clear(entry.chunk)
    end

    local bucket = registryByWorldRootName[worldRootName]
    if bucket then
        bucket[chunkId] = nil
        clearEmptyBucket(worldRootName)
    end

    Profiler.finish(profile, {
        chunkId = chunkId,
        worldRootName = worldRootName,
    })
end

function ChunkLoader.RegisterChunk(chunkId, folder, chunk, metadata)
    local worldRootName = resolveWorldRootName(folder, metadata)
    local collected = collectChunkMetadata(folder)
    local bucket = getRegistryBucket(worldRootName, true)
    removeEntry(worldRootName, chunkId)
    local entry = {
        folder = folder,
        chunk = chunk,
        worldRootName = worldRootName,
        planKey = metadata and metadata.planKey or nil,
        configSignature = metadata and metadata.configSignature or nil,
        layerSignatures = metadata and metadata.layerSignatures or nil,
        lodGroups = collected.lodGroups,
        reactives = collected.reactives,
    }
    if folder and folder.Destroying then
        entry.destroyConn = folder.Destroying:Connect(function()
            removeEntry(worldRootName, chunkId)
        end)
    end
    bucket[chunkId] = entry
end

function ChunkLoader.RefreshChunkMetadata(chunkId, worldRootName)
    local entry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
    if not entry then
        return nil
    end

    local collected = collectChunkMetadata(entry.folder)
    entry.lodGroups = collected.lodGroups
    entry.reactives = collected.reactives
    return entry
end

function ChunkLoader.GetChunkFolder(chunkId, worldRootName)
    local entry = ChunkLoader.GetChunkEntry(chunkId, worldRootName)
    return entry and entry.folder
end

function ChunkLoader.GetChunkEntry(chunkId, worldRootName)
    if type(worldRootName) == "string" and worldRootName ~= "" then
        return getScopedEntry(chunkId, worldRootName)
    end

    for _, bucket in pairs(registryByWorldRootName) do
        local entry = bucket[chunkId]
        if entry then
            return entry
        end
    end
    return nil
end

function ChunkLoader.UnloadChunk(chunkId, preserveFolder, worldRootName)
    if type(worldRootName) == "string" and worldRootName ~= "" then
        unloadScopedEntry(chunkId, worldRootName, preserveFolder)
        return
    end

    local scopedWorldRootNames = {}
    for existingWorldRootName, bucket in pairs(registryByWorldRootName) do
        if bucket[chunkId] ~= nil then
            scopedWorldRootNames[#scopedWorldRootNames + 1] = existingWorldRootName
        end
    end
    table.sort(scopedWorldRootNames)
    for _, scopedWorldRootName in ipairs(scopedWorldRootNames) do
        unloadScopedEntry(chunkId, scopedWorldRootName, preserveFolder)
    end
end

function ChunkLoader.ListLoadedChunks(worldRootName)
    if type(worldRootName) == "string" and worldRootName ~= "" then
        return listScopedChunks(worldRootName)
    end

    local result = {}
    local seen = {}
    for _, bucket in pairs(registryByWorldRootName) do
        for chunkId in pairs(bucket) do
            if not seen[chunkId] then
                seen[chunkId] = true
                table.insert(result, chunkId)
            end
        end
    end

    table.sort(result)
    return result
end

function ChunkLoader.Clear(worldRootName)
    if type(worldRootName) == "string" and worldRootName ~= "" then
        for _, chunkId in ipairs(listScopedChunks(worldRootName)) do
            ChunkLoader.UnloadChunk(chunkId, nil, worldRootName)
        end
        return
    end

    local worldRootNames = {}
    for existingWorldRootName in pairs(registryByWorldRootName) do
        worldRootNames[#worldRootNames + 1] = existingWorldRootName
    end
    table.sort(worldRootNames)
    for _, existingWorldRootName in ipairs(worldRootNames) do
        ChunkLoader.Clear(existingWorldRootName)
    end
end

return ChunkLoader
