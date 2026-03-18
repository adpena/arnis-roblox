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
local LanduseBuilder = require(script.Builders.LanduseBuilder)
local BarrierBuilder = require(script.Builders.BarrierBuilder)

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
    -- PERFORMANCE: Capture instance count for delta tracking
    local profile = Profiler.begin("ImportChunk", true)

    -- Authoritative overwrite: ensure any existing version of this chunk is unloaded first.
    -- This prevents duplicate content on re-import.
    ChunkLoader.UnloadChunk(chunk.id)

    local worldRootName = options.worldRootName or DEFAULT_WORLD_ROOT_NAME
    local worldRoot = getWorldRoot(worldRootName)
    local chunkFolder = ensureChunkFolder(worldRoot, chunk.id)

    -- PERFORMANCE: Reuse existing folders if they exist instead of recreating
    local terrainFolder = chunkFolder:FindFirstChild("Terrain")
    if not terrainFolder then
        terrainFolder = Instance.new("Folder")
        terrainFolder.Name = "Terrain"
        terrainFolder.Parent = chunkFolder
    else
        for _, child in ipairs(terrainFolder:GetChildren()) do
            child:Destroy()
        end
    end

    local roadsFolder = chunkFolder:FindFirstChild("Roads")
    if not roadsFolder then
        roadsFolder = Instance.new("Folder")
        roadsFolder.Name = "Roads"
        roadsFolder.Parent = chunkFolder
    else
        for _, child in ipairs(roadsFolder:GetChildren()) do
            child:Destroy()
        end
    end

    local railsFolder = chunkFolder:FindFirstChild("Rails")
    if not railsFolder then
        railsFolder = Instance.new("Folder")
        railsFolder.Name = "Rails"
        railsFolder.Parent = chunkFolder
    else
        for _, child in ipairs(railsFolder:GetChildren()) do
            child:Destroy()
        end
    end

    local buildingsFolder = chunkFolder:FindFirstChild("Buildings")
    if not buildingsFolder then
        buildingsFolder = Instance.new("Folder")
        buildingsFolder.Name = "Buildings"
        buildingsFolder.Parent = chunkFolder
    else
        for _, child in ipairs(buildingsFolder:GetChildren()) do
            child:Destroy()
        end
    end

    local waterFolder = chunkFolder:FindFirstChild("Water")
    if not waterFolder then
        waterFolder = Instance.new("Folder")
        waterFolder.Name = "Water"
        waterFolder.Parent = chunkFolder
    else
        for _, child in ipairs(waterFolder:GetChildren()) do
            child:Destroy()
        end
    end

    local propsFolder = chunkFolder:FindFirstChild("Props")
    if not propsFolder then
        propsFolder = Instance.new("Folder")
        propsFolder.Name = "Props"
        propsFolder.Parent = chunkFolder
    else
        for _, child in ipairs(propsFolder:GetChildren()) do
            child:Destroy()
        end
    end

    local landuseFolder = chunkFolder:FindFirstChild("Landuse")
    if not landuseFolder then
        landuseFolder = Instance.new("Folder")
        landuseFolder.Name = "Landuse"
        landuseFolder.Parent = chunkFolder
    else
        for _, child in ipairs(landuseFolder:GetChildren()) do
            child:Destroy()
        end
    end

    local barriersFolder = chunkFolder:FindFirstChild("Barriers")
    if not barriersFolder then
        barriersFolder = Instance.new("Folder")
        barriersFolder.Name = "Barriers"
        barriersFolder.Parent = chunkFolder
    else
        for _, child in ipairs(barriersFolder:GetChildren()) do
            child:Destroy()
        end
    end

    if chunk.terrain and config.TerrainMode ~= "none" then
        local p = Profiler.begin("BuildTerrain")
        TerrainBuilder.Build(terrainFolder, chunk)
        Profiler.finish(p)
    end

    -- Landuse fills go BEFORE roads so roads paint over them
    if chunk.landuse and #chunk.landuse > 0 then
        local pLanduse = Profiler.begin("BuildLanduse")
        LanduseBuilder.BuildAll(chunk.landuse, chunk.originStuds, landuseFolder, chunk)
        Profiler.finish(pLanduse)
    end

    if config.RoadMode ~= "none" then
        local pRoads = Profiler.begin("BuildRoads")
        if config.RoadMode == "mesh" then
            RoadBuilder.BuildAll(roadsFolder, chunk.roads, chunk.originStuds, chunk)
            RailBuilder.BuildAll(railsFolder, chunk.rails, chunk.originStuds)
        else
            for _, road in ipairs(chunk.roads or {}) do
                RoadBuilder.FallbackBuild(roadsFolder, road, chunk.originStuds, chunk)
            end
            for _, rail in ipairs(chunk.rails or {}) do
                RailBuilder.FallbackBuild(railsFolder, rail, chunk.originStuds)
            end
        end
        Profiler.finish(pRoads)
    end

    local pBarriers = Profiler.begin("BuildBarriers")
    BarrierBuilder.BuildAll(chunk, barriersFolder)
    Profiler.finish(pBarriers)

    if config.BuildingMode ~= "none" then
        local pBldgs = Profiler.begin("BuildBuildings")
        if config.BuildingMode == "shellMesh" then
            BuildingBuilder.BuildAll(buildingsFolder, chunk.buildings, chunk.originStuds, chunk)
            -- Build interiors (merged by material across chunk)
            RoomBuilder.BuildAll(buildingsFolder, chunk.buildings, chunk.originStuds)
        elseif config.BuildingMode == "shellParts" then
            for _, building in ipairs(chunk.buildings or {}) do
                BuildingBuilder.PartBuild(buildingsFolder, building, chunk.originStuds, chunk)
            end
        else
            for _, building in ipairs(chunk.buildings or {}) do
                BuildingBuilder.FallbackBuild(buildingsFolder, building, chunk.originStuds, chunk)
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
        PropBuilder.Build(propsFolder, prop, chunk.originStuds, chunk)
    end
    Profiler.finish(pProps)

    ChunkLoader.RegisterChunk(chunk.id, chunkFolder, chunk)

    Profiler.finish(profile, {
        chunkId = chunk.id,
        instanceCount = #chunkFolder:GetDescendants(),
    })

    return chunkFolder
end

function ImportService.ImportManifest(manifest, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    Profiler.clear()
    -- PERFORMANCE: Capture instance count for delta tracking
    local profile = Profiler.begin("ImportManifest", true)
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
        landuseImported = 0,
        barriersImported = 0,
    }

    for _, chunk in ipairs(validated.chunks) do
        -- Skip chunks outside loadRadius (studs from world origin)
        local loadRadius = options.loadRadius
        if loadRadius then
            local ox = chunk.originStuds and chunk.originStuds.x or 0
            local oz = chunk.originStuds and chunk.originStuds.z or 0
            local chunkSize = manifest.meta and manifest.meta.chunkSizeStuds or 256
            local centerX = ox + chunkSize * 0.5
            local centerZ = oz + chunkSize * 0.5
            if math.sqrt(centerX * centerX + centerZ * centerZ) > loadRadius then
                continue
            end
        end

        local chunkOptions = table.clone(options)
        chunkOptions.config = config
        ImportService.ImportChunk(chunk, chunkOptions)

        stats.chunksImported += 1
        stats.roadsImported += #(chunk.roads or {})
        stats.railsImported += #(chunk.rails or {})
        stats.buildingsImported += #(chunk.buildings or {})
        stats.waterImported += #(chunk.water or {})
        stats.propsImported += #(chunk.props or {})
        stats.landuseImported += #(chunk.landuse or {})
        stats.barriersImported += #(chunk.barriers or {})
    end

    local finalInstanceCount = #worldRoot:GetDescendants()
    Profiler.finish(profile, {
        worldRoot = worldRoot:GetFullName(),
        chunksImported = stats.chunksImported,
        totalInstances = finalInstanceCount,
    })

    -- sessions are auto-trimmed inside Profiler (MAX_SESSIONS cap)

    Logger.info(
        "Imported manifest",
        validated.meta.worldName,
        "chunks=" .. stats.chunksImported,
        "roads=" .. stats.roadsImported,
        "rails=" .. stats.railsImported,
        "buildings=" .. stats.buildingsImported,
        "landuse=" .. stats.landuseImported,
        "barriers=" .. stats.barriersImported,
        "instances=" .. finalInstanceCount
    )

    if options.printReport then
        Profiler.printReport()
    end

    return stats
end

return ImportService
