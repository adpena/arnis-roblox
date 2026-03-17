local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local Logger = require(ReplicatedStorage.Shared.Logger)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local Profiler = require(script.Profiler)
local ChunkLoader = require(script.ChunkLoader)
local TerrainBuilder = require(script.Builders.TerrainBuilder)
local RoadBuilder = require(script.Builders.RoadBuilder)
local RailBuilder = require(script.Builders.RailBuilder)
local BuildingBuilder = require(script.Builders.BuildingBuilder)
local WaterBuilder = require(script.Builders.WaterBuilder)
local PropBuilder = require(script.Builders.PropBuilder)
local RoomBuilder = require(script.Builders.RoomBuilder)

local ImportService = {}

local DEFAULT_WORLD_ROOT_NAME = "GeneratedWorld"

local function getWorldRoot(rootName)
    local worldRoot = Workspace:FindFirstChild(rootName)
    if not worldRoot then
        worldRoot = Instance.new("Folder")
        worldRoot.Name = rootName
        worldRoot.Parent = Workspace
    end

    return worldRoot
end

local function clearChildren(container)
    for _, child in ipairs(container:GetChildren()) do
        child:Destroy()
    end
end

local function ensureChunkFolder(worldRoot, chunkId)
    local chunkFolder = worldRoot:FindFirstChild(chunkId)
    if not chunkFolder then
        chunkFolder = Instance.new("Folder")
        chunkFolder.Name = chunkId
        chunkFolder.Parent = worldRoot
    else
        clearChildren(chunkFolder)
    end

    return chunkFolder
end

function ImportService.ImportChunk(chunk, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    local profile = Profiler.begin("ImportChunk")
    
    -- Authoritative overwrite: ensure any existing version of this chunk is unloaded first.
    ChunkLoader.UnloadChunk(chunk.id)

    local worldRootName = options.worldRootName or DEFAULT_WORLD_ROOT_NAME
    local worldRoot = getWorldRoot(worldRootName)
    local chunkFolder = ensureChunkFolder(worldRoot, chunk.id)

    local terrainFolder = Instance.new("Folder")
    terrainFolder.Name = "Terrain"
    terrainFolder.Parent = chunkFolder

    local roadsFolder = Instance.new("Folder")
    roadsFolder.Name = "Roads"
    roadsFolder.Parent = chunkFolder

    local railsFolder = Instance.new("Folder")
    railsFolder.Name = "Rails"
    railsFolder.Parent = chunkFolder

    local buildingsFolder = Instance.new("Folder")
    buildingsFolder.Name = "Buildings"
    buildingsFolder.Parent = chunkFolder

    local waterFolder = Instance.new("Folder")
    waterFolder.Name = "Water"
    waterFolder.Parent = chunkFolder

    local propsFolder = Instance.new("Folder")
    propsFolder.Name = "Props"
    propsFolder.Parent = chunkFolder

    if chunk.terrain and config.TerrainMode ~= "none" then
        local p = Profiler.begin("BuildTerrain")
        TerrainBuilder.Build(terrainFolder, chunk)
        Profiler.finish(p)
    end

    if config.RoadMode ~= "none" then
        local pRoads = Profiler.begin("BuildRoads")
        if config.RoadMode == "mesh" then
            RoadBuilder.BuildAll(roadsFolder, chunk.roads, chunk.originStuds)
            RailBuilder.BuildAll(railsFolder, chunk.rails, chunk.originStuds)
        else
            for _, road in ipairs(chunk.roads or {}) do
                RoadBuilder.FallbackBuild(roadsFolder, road, chunk.originStuds)
            end
            for _, rail in ipairs(chunk.rails or {}) do
                RailBuilder.FallbackBuild(railsFolder, rail, chunk.originStuds)
            end
        end
        Profiler.finish(pRoads)
    end

    if config.BuildingMode ~= "none" then
        local pBldgs = Profiler.begin("BuildBuildings")
        if config.BuildingMode == "shellMesh" then
            BuildingBuilder.BuildAll(buildingsFolder, chunk.buildings, chunk.originStuds)
            -- Build interiors (merged by material across chunk)
            RoomBuilder.BuildAll(buildingsFolder, chunk.buildings, chunk.originStuds)
        elseif config.BuildingMode == "shellParts" then
            for _, building in ipairs(chunk.buildings or {}) do
                BuildingBuilder.PartBuild(buildingsFolder, building, chunk.originStuds)
            end
        else
            for _, building in ipairs(chunk.buildings or {}) do
                BuildingBuilder.FallbackBuild(buildingsFolder, building, chunk.originStuds)
            end
        end

        Profiler.finish(pBldgs)
    end

    if config.WaterMode ~= "none" then
        local pWater = Profiler.begin("BuildWater")
        if config.WaterMode == "mesh" then
            WaterBuilder.BuildAll(waterFolder, chunk.water, chunk.originStuds)
        else
            for _, water in ipairs(chunk.water or {}) do
                WaterBuilder.FallbackBuild(waterFolder, water, chunk.originStuds)
            end
        end
        Profiler.finish(pWater)
    end

    local pProps = Profiler.begin("BuildProps")
    for _, prop in ipairs(chunk.props or {}) do
        PropBuilder.Build(propsFolder, prop, chunk.originStuds)
    end
    Profiler.finish(pProps)

    ChunkLoader.RegisterChunk(chunk.id, chunkFolder, chunk)

    Profiler.finish(profile, { 
        chunkId = chunk.id,
        instanceCount = #chunkFolder:GetDescendants()
    })

    return chunkFolder
end

function ImportService.ImportManifest(manifest, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    Profiler.clear()
    local profile = Profiler.begin("ImportManifest")
    local validated = ChunkSchema.validateManifest(manifest)
    local worldRootName = options.worldRootName or DEFAULT_WORLD_ROOT_NAME
    local worldRoot = getWorldRoot(worldRootName)

    if options.clearFirst then
        ChunkLoader.Clear() -- This now handles folder destruction and prop releasing
        clearChildren(worldRoot)
    elseif options.sync then
        -- Sync mode: remove any loaded chunks that are NOT in this manifest
        local manifestChunkIds = {}
        for _, chunk in ipairs(validated.chunks) do
            manifestChunkIds[chunk.id] = true
        end

        for _, loadedChunkId in ipairs(ChunkLoader.ListLoadedChunks()) do
            if not manifestChunkIds[loadedChunkId] then
                ChunkLoader.UnloadChunk(loadedChunkId)
            end
        end
    end

    local stats = {
        chunksImported = 0,
        roadsImported = 0,
        railsImported = 0,
        buildingsImported = 0,
        waterImported = 0,
        propsImported = 0,
    }

    for _, chunk in ipairs(validated.chunks) do
        local chunkOptions = table.clone(options)
        chunkOptions.config = config
        ImportService.ImportChunk(chunk, chunkOptions)
        
        stats.chunksImported += 1
        stats.roadsImported += #(chunk.roads or {})
        stats.railsImported += #(chunk.rails or {})
        stats.buildingsImported += #(chunk.buildings or {})
        stats.waterImported += #(chunk.water or {})
        stats.propsImported += #(chunk.props or {})
    end

    Profiler.finish(profile, {
        worldRoot = worldRoot:GetFullName(),
        chunksImported = stats.chunksImported,
        totalInstances = #worldRoot:GetDescendants()
    })

    Logger.info(
        "Imported manifest",
        validated.meta.worldName,
        "chunks=" .. stats.chunksImported,
        "roads=" .. stats.roadsImported,
        "rails=" .. stats.railsImported,
        "buildings=" .. stats.buildingsImported
    )

    if options.printReport then
        Profiler.printReport()
    end

    return stats
end

return ImportService
