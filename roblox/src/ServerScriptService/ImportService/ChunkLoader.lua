local CollectionService = game:GetService("CollectionService")

local TerrainBuilder = require(script.Parent.Builders.TerrainBuilder)
local PropBuilder = require(script.Parent.Builders.PropBuilder)
local Profiler = require(script.Parent.Profiler)

local ChunkLoader = {}

local registry = {}

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
            elseif
                kind == "interior" and CollectionService:HasTag(descendant, "LOD_InteriorGroup")
            then
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
    registry[chunkId] = {
        folder = folder,
        chunk = chunk,
        planKey = metadata and metadata.planKey or nil,
        configSignature = metadata and metadata.configSignature or nil,
        layerSignatures = metadata and metadata.layerSignatures or nil,
        lodGroups = collected.lodGroups,
        reactives = collected.reactives,
    }
end

function ChunkLoader.RefreshChunkMetadata(chunkId)
    local entry = registry[chunkId]
    if not entry then
        return nil
    end

    local collected = collectChunkMetadata(entry.folder)
    entry.lodGroups = collected.lodGroups
    entry.reactives = collected.reactives
    return entry
end

function ChunkLoader.GetChunkFolder(chunkId)
    local entry = registry[chunkId]
    return entry and entry.folder
end

function ChunkLoader.GetChunkEntry(chunkId)
    return registry[chunkId]
end

function ChunkLoader.UnloadChunk(chunkId, preserveFolder)
    local entry = registry[chunkId]
    if entry then
        local profile = Profiler.begin("UnloadChunk")

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

        registry[chunkId] = nil

        Profiler.finish(profile, { chunkId = chunkId })
    end
end

function ChunkLoader.ListLoadedChunks()
    local result = {}

    for chunkId, _ in pairs(registry) do
        table.insert(result, chunkId)
    end

    table.sort(result)
    return result
end

function ChunkLoader.Clear()
    for chunkId, _ in pairs(registry) do
        ChunkLoader.UnloadChunk(chunkId)
    end
end

return ChunkLoader
