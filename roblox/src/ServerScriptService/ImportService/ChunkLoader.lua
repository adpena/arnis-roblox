local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local TerrainBuilder = require(script.Parent.Builders.TerrainBuilder)
local PropBuilder = require(script.Parent.Builders.PropBuilder)
local Profiler = require(script.Parent.Profiler)

local ChunkLoader = {}

local registry = {}
local DEFAULT_WORLD_ROOT_NAME = "GeneratedWorld"

local function resolveWorldRootName(worldRootName, folder)
    if type(worldRootName) == "string" and worldRootName ~= "" then
        return worldRootName
    end

    local parent = folder and folder.Parent
    if parent ~= nil then
        return parent.Name
    end

    return DEFAULT_WORLD_ROOT_NAME
end

local function getRegistryKey(chunkId, worldRootName, folder)
    return ("%s::%s"):format(resolveWorldRootName(worldRootName, folder), chunkId)
end

local function hasExplicitWorldRootName(worldRootName)
    return type(worldRootName) == "string" and worldRootName ~= ""
end

local function isEntryFolderAttached(entry)
    local folder = entry and entry.folder
    if folder == nil then
        return false
    end

    local parent = folder.Parent
    if parent == nil then
        return false
    end

    local expectedWorldRoot = Workspace:FindFirstChild(entry.worldRootName)
    return folder.Name == entry.chunkId and expectedWorldRoot ~= nil and parent == expectedWorldRoot
end

local function getValidatedEntryForKey(registryKey)
    local entry = registry[registryKey]
    if entry ~= nil and not isEntryFolderAttached(entry) then
        registry[registryKey] = nil
        return nil
    end
    return entry
end

local function getValidatedEntry(chunkId, worldRootName)
    if hasExplicitWorldRootName(worldRootName) then
        return getValidatedEntryForKey(getRegistryKey(chunkId, worldRootName))
    end

    local defaultEntry = getValidatedEntryForKey(getRegistryKey(chunkId, DEFAULT_WORLD_ROOT_NAME))
    if defaultEntry ~= nil then
        return defaultEntry
    end

    local registryKeys = {}
    for registryKey, entry in pairs(registry) do
        if entry ~= nil and entry.chunkId == chunkId then
            registryKeys[#registryKeys + 1] = registryKey
        end
    end
    table.sort(registryKeys)

    for _, registryKey in ipairs(registryKeys) do
        local entry = getValidatedEntryForKey(registryKey)
        if entry ~= nil then
            return entry
        end
    end

    return nil
end

local function clearChildren(folder)
    folder:SetAttribute("ArnisMinimapChunkJson", nil)
    folder:SetAttribute("ArnisMinimapChunkId", nil)
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

function ChunkLoader.RegisterChunk(chunkId, folder, chunk, metadata)
    local collected = collectChunkMetadata(folder)
    local worldRootName = resolveWorldRootName(metadata and metadata.worldRootName, folder)
    registry[getRegistryKey(chunkId, worldRootName, folder)] = {
        chunkId = chunkId,
        worldRootName = worldRootName,
        folder = folder,
        chunk = chunk,
        planKey = metadata and metadata.planKey or nil,
        configSignature = metadata and metadata.configSignature or nil,
        chunkSignature = metadata and metadata.chunkSignature or nil,
        layerSignatures = metadata and metadata.layerSignatures or nil,
        lodGroups = collected.lodGroups,
        reactives = collected.reactives,
    }
end

function ChunkLoader.RefreshChunkMetadata(chunkId, worldRootName)
    local entry = getValidatedEntry(chunkId, worldRootName)
    if not entry then
        return nil
    end

    local collected = collectChunkMetadata(entry.folder)
    entry.lodGroups = collected.lodGroups
    entry.reactives = collected.reactives
    return entry
end

function ChunkLoader.GetChunkFolder(chunkId, worldRootName)
    local entry = getValidatedEntry(chunkId, worldRootName)
    return entry and entry.folder
end

function ChunkLoader.GetChunkEntry(chunkId, worldRootName)
    return getValidatedEntry(chunkId, worldRootName)
end

function ChunkLoader.UnloadChunk(chunkId, preserveFolder, worldRootName)
    local registryKeys = {}
    if hasExplicitWorldRootName(worldRootName) then
        registryKeys[1] = getRegistryKey(chunkId, worldRootName)
    else
        local defaultRegistryKey = getRegistryKey(chunkId, DEFAULT_WORLD_ROOT_NAME)
        if getValidatedEntryForKey(defaultRegistryKey) ~= nil then
            registryKeys[1] = defaultRegistryKey
        else
            local explicitRegistryKeys = {}
            for registryKey, entry in pairs(registry) do
                if entry ~= nil and entry.chunkId == chunkId then
                    explicitRegistryKeys[#explicitRegistryKeys + 1] = registryKey
                end
            end
            table.sort(explicitRegistryKeys)
            for _, registryKey in ipairs(explicitRegistryKeys) do
                if getValidatedEntryForKey(registryKey) ~= nil then
                    registryKeys[1] = registryKey
                    break
                end
            end
        end
    end

    for _, registryKey in ipairs(registryKeys) do
        local entry = registry[registryKey]
        if entry then
            local profile = Profiler.begin("UnloadChunk")

            if entry.folder then
                entry.folder:SetAttribute("ArnisMinimapChunkJson", nil)
                entry.folder:SetAttribute("ArnisMinimapChunkId", nil)
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

            registry[registryKey] = nil

            Profiler.finish(profile, {
                chunkId = chunkId,
                worldRootName = entry.worldRootName,
            })
        end
    end
end

function ChunkLoader.ListLoadedChunks(worldRootName)
    local result = {}
    local resolvedWorldRootName = if hasExplicitWorldRootName(worldRootName)
        then resolveWorldRootName(worldRootName)
        else nil
    local seenChunkIds = {}
    local defaultChunkIds = {}

    local keys = {}
    for registryKey in pairs(registry) do
        keys[#keys + 1] = registryKey
    end
    table.sort(keys)

    if resolvedWorldRootName == nil then
        for _, registryKey in ipairs(keys) do
            local entry = getValidatedEntryForKey(registryKey)
            if entry ~= nil and entry.worldRootName == DEFAULT_WORLD_ROOT_NAME and not seenChunkIds[entry.chunkId] then
                defaultChunkIds[entry.chunkId] = true
                seenChunkIds[entry.chunkId] = true
                table.insert(result, entry.chunkId)
            end
        end

        for _, registryKey in ipairs(keys) do
            local entry = getValidatedEntryForKey(registryKey)
            if entry ~= nil and not seenChunkIds[entry.chunkId] then
                seenChunkIds[entry.chunkId] = true
                table.insert(result, entry.chunkId)
            end
        end
    else
        for _, registryKey in ipairs(keys) do
            local entry = getValidatedEntryForKey(registryKey)
            if entry ~= nil and entry.worldRootName == resolvedWorldRootName and not seenChunkIds[entry.chunkId] then
                seenChunkIds[entry.chunkId] = true
                table.insert(result, entry.chunkId)
            end
        end
    end

    table.sort(result)
    return result
end

function ChunkLoader.Clear(worldRootName)
    if type(worldRootName) == "string" and worldRootName ~= "" then
        for _, chunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
            ChunkLoader.UnloadChunk(chunkId, nil, worldRootName)
        end
        return
    end

    local keys = {}
    for registryKey in pairs(registry) do
        keys[#keys + 1] = registryKey
    end
    for _, registryKey in ipairs(keys) do
        local entry = registry[registryKey]
        if entry ~= nil then
            ChunkLoader.UnloadChunk(entry.chunkId, nil, entry.worldRootName)
        end
    end
end

return ChunkLoader
