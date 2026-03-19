local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local Logger = require(ReplicatedStorage.Shared.Logger)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local DayNightCycle = require(script.DayNightCycle)

local Profiler = require(script.Profiler)
local ChunkLoader = require(script.ChunkLoader)
local GroundSampler = require(script.GroundSampler)
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

-- Set up atmospheric and cinematic lighting effects.
-- Called once after all chunks have been imported.
local function setupAtmosphere(manifest)
    local Lighting = game:GetService("Lighting")

    -- Atmosphere
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Parent = Lighting
    end

    atmosphere.Density = 0.3
    atmosphere.Offset = 0.25
    atmosphere.Glare = 0
    atmosphere.Haze = 1
    atmosphere.Color = Color3.fromRGB(199, 210, 225)   -- cool blue-grey
    atmosphere.Decay = Color3.fromRGB(106, 112, 125)   -- distance fade

    -- Sky / sun position (ClockTime and GeographicLatitude are set by DayNightCycle.Configure)
    Lighting.Brightness = 2
    Lighting.EnvironmentDiffuseScale = 1
    Lighting.EnvironmentSpecularScale = 1
    Lighting.GlobalShadows = true
    Lighting.ShadowSoftness = 0.2

    -- Bloom for a cinematic look
    local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
    if not bloom then
        bloom = Instance.new("BloomEffect")
        bloom.Parent = Lighting
    end
    bloom.Intensity = 0.5
    bloom.Size = 24
    bloom.Threshold = 2

    -- Color correction for warmth
    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if not cc then
        cc = Instance.new("ColorCorrectionEffect")
        cc.Parent = Lighting
    end
    cc.Brightness = 0.02
    cc.Contrast = 0.05
    cc.Saturation = 0.1
    cc.TintColor = Color3.fromRGB(255, 248, 240)   -- warm white

    -- Sun rays for god rays through buildings
    local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
    if not sunRays then
        sunRays = Instance.new("SunRaysEffect")
        sunRays.Parent = Lighting
    end
    sunRays.Intensity = 0.15
    sunRays.Spread = 0.8
end

local function normalizePositiveNumber(value)
    if type(value) ~= "number" or value <= 0 then
        return nil
    end

    return value
end

local function getWorldRoot(rootName)
    local worldRoot = Workspace:FindFirstChild(rootName)
    if not worldRoot then
        worldRoot = Instance.new("Folder")
        worldRoot.Name = rootName
        worldRoot.Parent = Workspace
    end

    return worldRoot
end

local function getLoadCenterXZ(loadCenter)
    if typeof(loadCenter) == "Vector3" then
        return loadCenter.X, loadCenter.Z
    end

    if type(loadCenter) == "table" then
        return loadCenter.x or 0, loadCenter.z or 0
    end

    return 0, 0
end

local function getChunkCenterXZ(chunk, manifest)
    local chunkSize = manifest and manifest.meta and manifest.meta.chunkSizeStuds
        or DefaultWorldConfig.ChunkSizeStuds
        or 256
    local origin = chunk.originStuds or {}
    local ox = origin.x or 0
    local oz = origin.z or 0
    return ox + chunkSize * 0.5, oz + chunkSize * 0.5
end

local function makePacingController(options)
    local frameBudgetSeconds = normalizePositiveNumber(options.frameBudgetSeconds)
    local nonBlocking = options.nonBlocking == true and frameBudgetSeconds ~= nil
    local sliceStart = os.clock()

    local function maybeYield(force)
        if not nonBlocking then
            return false
        end

        if not force and os.clock() - sliceStart < frameBudgetSeconds then
            return false
        end

        task.wait()
        sliceStart = os.clock()
        return true
    end

    return nonBlocking, maybeYield
end

local function forEachWithPacing(items, callback, maybeYield)
    for _, item in ipairs(items or {}) do
        callback(item)
        maybeYield(false)
    end
end

local function sortChunksByLoadPriority(chunks, manifest, loadCenter)
    if loadCenter == nil then
        return
    end

    local loadCenterX, loadCenterZ = getLoadCenterXZ(loadCenter)
    table.sort(chunks, function(a, b)
        local ax, az = getChunkCenterXZ(a, manifest)
        local bx, bz = getChunkCenterXZ(b, manifest)
        local da = (ax - loadCenterX) * (ax - loadCenterX) + (az - loadCenterZ) * (az - loadCenterZ)
        local db = (bx - loadCenterX) * (bx - loadCenterX) + (bz - loadCenterZ) * (bz - loadCenterZ)
        if da == db then
            return (a.id or "") < (b.id or "")
        end
        return da < db
    end)
end

local function clearResidualChildren(parent)
    if not parent then
        return
    end

    local children = parent:GetChildren()
    if #children == 0 then
        return
    end

    for _, child in ipairs(children) do
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
        clearResidualChildren(chunkFolder)
    end

    return chunkFolder
end

local function getOrCreateNamedFolder(parent, name)
    local folder = parent:FindFirstChild(name)
    if folder and folder:IsA("Folder") then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function createNamedFolder(parent, name)
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function countChunkArtifactNodes(chunkFolder)
    local total = 0
    for _, group in ipairs(chunkFolder:GetChildren()) do
        total += 1
        total += #group:GetChildren()
    end
    return total
end

local function makeImportChunkOptions(options, config)
    return {
        config = config,
        worldRootName = options.worldRootName,
        frameBudgetSeconds = options.frameBudgetSeconds,
        nonBlocking = options.nonBlocking,
        shouldCancel = options.shouldCancel,
        layers = options.layers,
        configSignature = options.configSignature,
        layerSignatures = options.layerSignatures,
    }
end

local function shouldImportLayer(layers, layerName)
    return layers == nil or layers[layerName] == true
end

function ImportService.ImportChunk(chunk, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    local layers = options.layers
    local selectiveLayers = layers ~= nil
    local _nonBlocking, maybeYield = makePacingController(options)
    local shouldCancel = if type(options.shouldCancel) == "function" then options.shouldCancel else nil

    local function checkpoint(forceYield)
        if shouldCancel and shouldCancel() then
            return true
        end
        maybeYield(forceYield)
        if shouldCancel and shouldCancel() then
            return true
        end
        return false
    end

    -- PERFORMANCE: Capture instance count for delta tracking
    local profile = Profiler.begin("ImportChunk", true)

    -- Authoritative overwrite: ensure any existing version of this chunk is unloaded first.
    -- This prevents duplicate content on re-import.
    if shouldCancel and shouldCancel() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end
    if not selectiveLayers then
        ChunkLoader.UnloadChunk(chunk.id, true)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end
    end

    local worldRootName = options.worldRootName or DEFAULT_WORLD_ROOT_NAME
    local worldRoot = getWorldRoot(worldRootName)
    local chunkFolder = if selectiveLayers
        then getOrCreateNamedFolder(worldRoot, chunk.id)
        else ensureChunkFolder(worldRoot, chunk.id)
    if checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local function prepareLayerFolder(name, clearChildrenFirst)
        local folder = if selectiveLayers
            then getOrCreateNamedFolder(chunkFolder, name)
            else createNamedFolder(chunkFolder, name)
        if clearChildrenFirst then
            if name == "Props" then
                PropBuilder.ReleaseAll(folder)
            end
            clearResidualChildren(folder)
        end
        return folder
    end

    local terrainFolder = nil
    if shouldImportLayer(layers, "terrain") then
        terrainFolder = prepareLayerFolder("Terrain", selectiveLayers)
    end
    if terrainFolder and checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local roadsFolder = nil
    if shouldImportLayer(layers, "roads") then
        roadsFolder = prepareLayerFolder("Roads", selectiveLayers)
    end
    if roadsFolder and checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local railsFolder = nil
    if shouldImportLayer(layers, "roads") then
        railsFolder = prepareLayerFolder("Rails", selectiveLayers)
    end
    if railsFolder and checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local buildingsFolder = nil
    if shouldImportLayer(layers, "buildings") then
        buildingsFolder = prepareLayerFolder("Buildings", selectiveLayers)
    end
    if buildingsFolder and checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local waterFolder = nil
    if shouldImportLayer(layers, "water") then
        waterFolder = prepareLayerFolder("Water", selectiveLayers)
    end
    if waterFolder and checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local propsFolder = nil
    if shouldImportLayer(layers, "props") then
        propsFolder = prepareLayerFolder("Props", selectiveLayers)
    end
    if propsFolder and checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local landuseFolder = nil
    if shouldImportLayer(layers, "landuse") then
        landuseFolder = prepareLayerFolder("Landuse", selectiveLayers)
    end
    if landuseFolder and checkpoint() then
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        return nil
    end

    local barriersFolder = nil
    if shouldImportLayer(layers, "barriers") then
        barriersFolder = prepareLayerFolder("Barriers", selectiveLayers)
    end
    maybeYield()

    if shouldImportLayer(layers, "terrain") and chunk.terrain and config.TerrainMode ~= "none" then
        if selectiveLayers then
            TerrainBuilder.Clear(chunk)
        end
        local p = Profiler.begin("BuildTerrain")
        TerrainBuilder.Build(terrainFolder, chunk)
        Profiler.finish(p)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end
    end

    -- Landuse fills go BEFORE roads so roads paint over them
    if shouldImportLayer(layers, "landuse") and chunk.landuse and #chunk.landuse > 0 then
        local pLanduse = Profiler.begin("BuildLanduse")
        LanduseBuilder.BuildAll(chunk.landuse, chunk.originStuds, landuseFolder, chunk)
        Profiler.finish(pLanduse)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end
    end

    if shouldImportLayer(layers, "roads") and config.RoadMode ~= "none" then
        local pRoads = Profiler.begin("BuildRoads")
        if config.RoadMode == "mesh" then
            -- Merge all ground-level road surfaces into EditableMesh objects
            -- grouped by material/colour to minimise draw calls.
            RoadBuilder.MeshBuildAll(roadsFolder, chunk.roads, chunk.originStuds, chunk)
            maybeYield(false)
            -- Decorations (centerlines, arrows, lights, crosswalks, steps, tunnels)
            -- cannot be merged into the surface mesh; render them as separate Parts.
            RoadBuilder.MeshBuildDecorations(roadsFolder, chunk.roads, chunk.originStuds, chunk)
            maybeYield(false)
            forEachWithPacing(chunk.rails, function(rail)
                RailBuilder.Build(railsFolder, rail, chunk.originStuds)
            end, maybeYield)
        else
            forEachWithPacing(chunk.roads, function(road)
                RoadBuilder.FallbackBuild(roadsFolder, road, chunk.originStuds, chunk)
            end, maybeYield)
            forEachWithPacing(chunk.rails, function(rail)
                RailBuilder.FallbackBuild(railsFolder, rail, chunk.originStuds)
            end, maybeYield)
        end
        Profiler.finish(pRoads)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end

        -- Imprint road surfaces into terrain voxels so slopes are flattened
        -- under road segments. Only runs when both terrain and roads are present.
        if chunk.roads and #chunk.roads > 0 and chunk.terrain and config.TerrainMode ~= "none" then
            local pImprint = Profiler.begin("ImprintRoads")
            TerrainBuilder.ImprintRoads(chunk.roads, chunk.originStuds, chunk)
            Profiler.finish(pImprint)
            if checkpoint() then
                Profiler.finish(profile, {
                    chunkId = chunk.id,
                    cancelled = true,
                })
                return nil
            end
        end
    end

    if shouldImportLayer(layers, "barriers") then
        local pBarriers = Profiler.begin("BuildBarriers")
        BarrierBuilder.BuildAll(chunk, barriersFolder)
        Profiler.finish(pBarriers)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end
    end

    if shouldImportLayer(layers, "buildings") and config.BuildingMode ~= "none" then
        local pBldgs = Profiler.begin("BuildBuildings")
        local windowBudget = {
            used = 0,
            max = (config.InstanceBudget and config.InstanceBudget.MaxWindowsPerChunk) or 10000,
        }
        if config.BuildingMode == "shellMesh" then
            -- Merge opaque wall + flat-roof geometry into per-material EditableMeshes
            -- (10-100x draw call reduction). Windows/shaped roofs remain as Parts.
            local builtModelsById = BuildingBuilder.MeshBuildAll(
                buildingsFolder, chunk.buildings, chunk.originStuds, chunk, config
            )
            -- Build interiors (merged by material across chunk)
            RoomBuilder.BuildAll(buildingsFolder, chunk.buildings, chunk.originStuds, builtModelsById)
        elseif config.BuildingMode == "shellParts" then
            forEachWithPacing(chunk.buildings, function(building)
                BuildingBuilder.PartBuild(buildingsFolder, building, chunk.originStuds, chunk, windowBudget)
            end, maybeYield)
        else
            forEachWithPacing(chunk.buildings, function(building)
                BuildingBuilder.FallbackBuild(buildingsFolder, building, chunk.originStuds, chunk, windowBudget)
            end, maybeYield)
        end

        Profiler.finish(pBldgs)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end
    end

    if shouldImportLayer(layers, "water") and config.WaterMode ~= "none" then
        local pWater = Profiler.begin("BuildWater")
        local waterSampler = if chunk.terrain then GroundSampler.createSampler(chunk) else nil
        if config.WaterMode == "mesh" then
            forEachWithPacing(chunk.water, function(water)
                WaterBuilder.Build(waterFolder, water, chunk.originStuds, chunk, waterSampler)
            end, maybeYield)
        else
            forEachWithPacing(chunk.water, function(water)
                WaterBuilder.FallbackBuild(waterFolder, water, chunk.originStuds, chunk, waterSampler)
            end, maybeYield)
        end
        Profiler.finish(pWater)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end
    end

    if shouldImportLayer(layers, "props") then
        local pProps = Profiler.begin("BuildProps")
        forEachWithPacing(chunk.props, function(prop)
            PropBuilder.Build(propsFolder, prop, chunk.originStuds, chunk)
        end, maybeYield)
        Profiler.finish(pProps)
        if checkpoint() then
            Profiler.finish(profile, {
                chunkId = chunk.id,
                cancelled = true,
            })
            return nil
        end
    end

    ChunkLoader.RegisterChunk(chunk.id, chunkFolder, chunk, {
        configSignature = options.configSignature,
        layerSignatures = options.layerSignatures,
    })

    local artifactCount = countChunkArtifactNodes(chunkFolder)

    Profiler.finish(profile, {
        chunkId = chunk.id,
        instanceCount = artifactCount,
    })

    return chunkFolder, artifactCount
end

function ImportService.ImportManifest(manifest, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    local nonBlocking, maybeYield = makePacingController(options)
    Profiler.clear()
    -- PERFORMANCE: Capture instance count for delta tracking
    local profile = Profiler.begin("ImportManifest", true)
    local validated = ChunkSchema.validateManifest(manifest)
    local worldRootName = options.worldRootName or DEFAULT_WORLD_ROOT_NAME
    local worldRoot = getWorldRoot(worldRootName)

    if options.clearFirst then
        ChunkLoader.Clear() -- This now handles folder destruction and prop releasing
        clearResidualChildren(worldRoot)
        maybeYield(true)
    elseif options.sync then
        -- Sync mode: remove any loaded chunks that are NOT in this manifest
        local manifestChunkIds = {}
        for _, chunk in ipairs(validated.chunks) do
            manifestChunkIds[chunk.id] = true
        end

        for _, loadedChunkId in ipairs(ChunkLoader.ListLoadedChunks()) do
            if not manifestChunkIds[loadedChunkId] then
                ChunkLoader.UnloadChunk(loadedChunkId)
                maybeYield(false)
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
        totalInstances = 0,
    }

    local chunksToImport = table.create(#validated.chunks)
    local loadRadius = options.loadRadius
    local loadRadiusSq = if loadRadius then loadRadius * loadRadius else nil
    local loadCenterX, loadCenterZ = getLoadCenterXZ(options.loadCenter)

    for _, chunk in ipairs(validated.chunks) do
        -- Skip chunks outside loadRadius (studs from loadCenter or world origin)
        if loadRadiusSq then
            local centerX, centerZ = getChunkCenterXZ(chunk, validated)
            local dx = centerX - loadCenterX
            local dz = centerZ - loadCenterZ
            if dx * dx + dz * dz > loadRadiusSq then
                continue
            end
        end

        chunksToImport[#chunksToImport + 1] = chunk
    end

    if #chunksToImport > 1 then
        sortChunksByLoadPriority(chunksToImport, validated, options.loadCenter)
    end

    local startupChunkCount = math.max(0, math.floor(options.startupChunkCount or 0))

    local chunkOptions = makeImportChunkOptions(options, config)

    for chunkIndex, chunk in ipairs(chunksToImport) do
        local _chunkFolder, artifactCount = ImportService.ImportChunk(chunk, chunkOptions)

        stats.chunksImported += 1
        stats.roadsImported += #(chunk.roads or {})
        stats.railsImported += #(chunk.rails or {})
        stats.buildingsImported += #(chunk.buildings or {})
        stats.waterImported += #(chunk.water or {})
        stats.propsImported += #(chunk.props or {})
        stats.landuseImported += #(chunk.landuse or {})
        stats.barriersImported += #(chunk.barriers or {})
        stats.totalInstances += artifactCount or 0

        if nonBlocking then
            maybeYield(chunkIndex <= startupChunkCount)
        end
    end

    Profiler.finish(profile, {
        worldRoot = worldRoot:GetFullName(),
        chunksImported = stats.chunksImported,
        totalInstances = stats.totalInstances,
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
        "instances=" .. stats.totalInstances
    )

    if options.printReport then
        Profiler.printReport()
    end

    if config.EnableAtmosphere ~= false then
        setupAtmosphere(validated)
    end

    if manifest.meta and manifest.meta.bbox then
        local lat = (manifest.meta.bbox.minLat + manifest.meta.bbox.maxLat) / 2
        local lon = (manifest.meta.bbox.minLon + manifest.meta.bbox.maxLon) / 2
        local datetime = config.DateTime or "auto"
        DayNightCycle.Configure(lat, lon, datetime)
    end

    if config.EnableDayNightCycle ~= false then
        DayNightCycle.Start()
    end

    return stats
end

return ImportService
