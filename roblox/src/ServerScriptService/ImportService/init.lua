local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local Logger = require(ReplicatedStorage.Shared.Logger)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local LoadingScreen = require(script.LoadingScreen)
local WorldStateApplier = require(script.WorldStateApplier)

local Profiler = require(script.Profiler)
local ChunkLoader = require(script.ChunkLoader)
local ImportPlanCache = require(script.ImportPlanCache)
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
local AmbientLife = require(script.AmbientLife)
local MinimapService = require(script.MinimapService)
local ImportSignatures = require(script.ImportSignatures)

local ImportService = {}
local subplanStateByChunkId = {}

local DEFAULT_WORLD_ROOT_NAME = "GeneratedWorld"
local CANONICAL_SUBPLAN_LAYERS = table.freeze({
    "terrain",
    "landuse",
    "roads",
    "rails",
    "barriers",
    "buildings",
    "water",
    "props",
})
local CANONICAL_SUBPLAN_LAYER_INDEX = table.freeze({
    terrain = 1,
    landuse = 2,
    roads = 3,
    rails = 4,
    barriers = 5,
    buildings = 6,
    water = 7,
    props = 8,
})

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

local function cloneMapShallow(map)
    local cloned = {}
    for key, value in pairs(map or {}) do
        if type(value) == "table" then
            cloned[key] = table.clone(value)
        else
            cloned[key] = value
        end
    end
    return cloned
end

local function cloneSubplanState(state)
    return {
        importedLayers = cloneMapShallow(state and state.importedLayers or nil),
        completedWorkItems = cloneMapShallow(state and state.completedWorkItems or nil),
        failedWorkItems = cloneMapShallow(state and state.failedWorkItems or nil),
    }
end

local function getSubplanStateKey(chunkId, worldRootName)
    local resolvedWorldRootName = if type(worldRootName) == "string" and worldRootName ~= ""
        then worldRootName
        else DEFAULT_WORLD_ROOT_NAME
    return ("%s::%s"):format(resolvedWorldRootName, chunkId)
end

local function getSubplanState(chunkId, worldRootName)
    local stateKey = getSubplanStateKey(chunkId, worldRootName)
    local state = subplanStateByChunkId[stateKey]
    if state == nil then
        state = {
            importedLayers = {},
            completedWorkItems = {},
            failedWorkItems = {},
        }
        subplanStateByChunkId[stateKey] = state
    end
    return state
end

local function setSubplanState(chunkId, state, worldRootName)
    subplanStateByChunkId[getSubplanStateKey(chunkId, worldRootName)] = state
end

local function clearSubplanState(chunkId, worldRootName)
    subplanStateByChunkId[getSubplanStateKey(chunkId, worldRootName)] = nil
end

local function buildImportedLayerMap(actionSet)
    local importedLayers = {}
    for _, layer in ipairs(CANONICAL_SUBPLAN_LAYERS) do
        if actionSet[layer] then
            importedLayers[layer] = true
        end
    end
    return importedLayers
end

local function resolveSubplan(chunk, subplanOrId)
    if type(subplanOrId) == "table" then
        return subplanOrId
    end

    if type(subplanOrId) == "string" then
        for _, candidate in ipairs(chunk.subplans or {}) do
            if candidate.id == subplanOrId or candidate.layer == subplanOrId then
                return candidate
            end
        end

        return {
            id = subplanOrId,
            layer = subplanOrId,
        }
    end

    error("subplan must be a table or string identifier")
end

local function getSubplanLayer(subplan)
    local layer = if type(subplan) == "table" then subplan.layer or subplan.id else nil
    if type(layer) ~= "string" or layer == "" then
        error("subplan.layer must be a non-empty string")
    end
    if CANONICAL_SUBPLAN_LAYER_INDEX[layer] == nil then
        error(("unsupported subplan layer: %s"):format(tostring(layer)))
    end
    return layer
end

local function getSubplanWorkId(chunkId, subplan)
    local subplanId = if type(subplan) == "table"
            and type(subplan.id) == "string"
            and subplan.id ~= ""
        then subplan.id
        else getSubplanLayer(subplan)
    return ("%s:%s"):format(chunkId, subplanId)
end

local function buildCompletedWorkItemMap(chunk)
    local completedWorkItems = {}
    for _, subplan in ipairs(chunk and chunk.subplans or {}) do
        completedWorkItems[getSubplanWorkId(chunk.id, subplan)] = true
    end
    return completedWorkItems
end

local function getFeaturePoint2(feature)
    if type(feature) ~= "table" then
        return nil, nil
    end

    local position = feature.position
    if type(position) == "table" and type(position.x) == "number" and type(position.z) == "number" then
        return position.x, position.z
    end

    local footprint = feature.footprint
    if type(footprint) == "table" and #footprint > 0 then
        local minX, minZ = math.huge, math.huge
        local maxX, maxZ = -math.huge, -math.huge
        for _, point in ipairs(footprint) do
            local x = point and point.x
            local z = point and point.z
            if type(x) == "number" and type(z) == "number" then
                minX = math.min(minX, x)
                minZ = math.min(minZ, z)
                maxX = math.max(maxX, x)
                maxZ = math.max(maxZ, z)
            end
        end
        if minX ~= math.huge and minZ ~= math.huge and maxX ~= -math.huge and maxZ ~= -math.huge then
            return (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
        end
    end

    local points = feature.points
    if type(points) == "table" and #points > 0 then
        local minX, minZ = math.huge, math.huge
        local maxX, maxZ = -math.huge, -math.huge
        for _, point in ipairs(points) do
            local x = point and point.x
            local z = point and point.z
            if type(x) == "number" and type(z) == "number" then
                minX = math.min(minX, x)
                minZ = math.min(minZ, z)
                maxX = math.max(maxX, x)
                maxZ = math.max(maxZ, z)
            end
        end
        if minX ~= math.huge and minZ ~= math.huge and maxX ~= -math.huge and maxZ ~= -math.huge then
            return (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
        end
    end

    return nil, nil
end

local function getSubplanBounds(subplan)
    if type(subplan) ~= "table" then
        return nil
    end

    local bounds = subplan.bounds
    if type(bounds) ~= "table" then
        return nil
    end

    local minX = bounds.minX
    local minY = bounds.minY
    local maxX = bounds.maxX
    local maxY = bounds.maxY
    if type(minX) ~= "number" or type(minY) ~= "number" or type(maxX) ~= "number" or type(maxY) ~= "number" then
        return nil
    end

    return bounds
end

local function featureBelongsToSubplanBounds(feature, subplanBounds)
    if subplanBounds == nil then
        return true
    end

    local x, z = getFeaturePoint2(feature)
    if type(x) ~= "number" or type(z) ~= "number" then
        return true
    end

    return x >= subplanBounds.minX and x < subplanBounds.maxX and z >= subplanBounds.minY and z < subplanBounds.maxY
end

local function filterFeatureListForSubplan(features, subplanBounds)
    if subplanBounds == nil then
        return features
    end

    local filtered = {}
    for _, feature in ipairs(features or {}) do
        if featureBelongsToSubplanBounds(feature, subplanBounds) then
            filtered[#filtered + 1] = feature
        end
    end
    return filtered
end

local function getFeatureBounds2(feature)
    if type(feature) ~= "table" then
        return nil
    end

    local function accumulatePoints(points, usePosition)
        if type(points) ~= "table" or #points == 0 then
            return nil
        end
        local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
        for _, point in ipairs(points) do
            local x = point and point.x
            local z = if usePosition then point and point.z else point and point.z
            if type(x) == "number" and type(z) == "number" then
                minX = math.min(minX, x)
                minZ = math.min(minZ, z)
                maxX = math.max(maxX, x)
                maxZ = math.max(maxZ, z)
            end
        end
        if minX == math.huge or minZ == math.huge then
            return nil
        end
        return minX, minZ, maxX, maxZ
    end

    local minX, minZ, maxX, maxZ = accumulatePoints(feature.footprint, false)
    if minX ~= nil then
        return minX, minZ, maxX, maxZ
    end

    minX, minZ, maxX, maxZ = accumulatePoints(feature.points, true)
    if minX ~= nil then
        return minX, minZ, maxX, maxZ
    end

    local position = feature.position
    if type(position) == "table" and type(position.x) == "number" and type(position.z) == "number" then
        return position.x, position.z, position.x, position.z
    end

    return nil
end

local function featureIntersectsSubplanBounds(feature, subplanBounds)
    if subplanBounds == nil then
        return true
    end

    local minX, minZ, maxX, maxZ = getFeatureBounds2(feature)
    if minX == nil then
        return true
    end

    return minX < subplanBounds.maxX
        and maxX > subplanBounds.minX
        and minZ < subplanBounds.maxY
        and maxZ > subplanBounds.minY
end

local function filterLanduseFeaturesForSubplan(features, subplanBounds)
    if subplanBounds == nil then
        return features
    end

    local filtered = {}
    for _, feature in ipairs(features or {}) do
        if featureIntersectsSubplanBounds(feature, subplanBounds) then
            local cloned = table.clone(feature)
            cloned.subplanBounds = table.clone(subplanBounds)
            filtered[#filtered + 1] = cloned
        end
    end
    return filtered
end

local function buildChunkForSubplan(chunk, subplan)
    local subplanBounds = getSubplanBounds(subplan)
    if subplanBounds == nil then
        return chunk
    end

    local layer = getSubplanLayer(subplan)
    local filteredChunk = table.clone(chunk)
    if layer == "roads" then
        filteredChunk.roads = filterFeatureListForSubplan(chunk.roads, subplanBounds)
    elseif layer == "rails" then
        filteredChunk.rails = filterFeatureListForSubplan(chunk.rails, subplanBounds)
    elseif layer == "barriers" then
        filteredChunk.barriers = filterFeatureListForSubplan(chunk.barriers, subplanBounds)
    elseif layer == "buildings" then
        filteredChunk.buildings = filterFeatureListForSubplan(chunk.buildings, subplanBounds)
    elseif layer == "water" then
        filteredChunk.water = filterFeatureListForSubplan(chunk.water, subplanBounds)
    elseif layer == "props" then
        filteredChunk.props = filterFeatureListForSubplan(chunk.props, subplanBounds)
    elseif layer == "landuse" then
        filteredChunk.landuse = filterLanduseFeaturesForSubplan(chunk.landuse, subplanBounds)
    end

    return filteredChunk
end

local function finishSubplanImportProfile(profile, chunkId, subplan, workId, layer, status, artifactCount)
    if profile == nil then
        return
    end

    local metadata = {
        chunkId = chunkId,
        subplanId = subplan and subplan.id or layer,
        subplanLayer = layer,
        workId = workId,
        status = status,
    }
    if artifactCount ~= nil then
        metadata.artifactCount = artifactCount
    end

    if status == "cancelled" then
        metadata.cancelled = true
        metadata.cancelledWorkId = workId
    elseif status == "failed" then
        metadata.failed = true
        metadata.failedWorkId = workId
    elseif status == "completed" then
        metadata.completed = true
        metadata.completedWorkId = workId
    end

    Profiler.finish(profile, metadata)
end

local function getChunkActionSet(chunk, config)
    local fullPlan = ImportPlanCache.GetOrCreatePlan(chunk, {
        config = config,
    })
    return fullPlan.actionSet
end

local function layerHasCompleteSubplans(chunk, state, layer)
    local foundSubplan = false
    for _, candidate in ipairs(chunk.subplans or {}) do
        if getSubplanLayer(candidate) == layer then
            foundSubplan = true
            if not (state.completedWorkItems and state.completedWorkItems[getSubplanWorkId(chunk.id, candidate)]) then
                return false
            end
        end
    end
    return foundSubplan
end

local function validateSubplanPrerequisites(chunk, subplan, config, worldRootName)
    local targetLayer = getSubplanLayer(subplan)
    local targetLayerIndex = CANONICAL_SUBPLAN_LAYER_INDEX[targetLayer]
    local actionSet = getChunkActionSet(chunk, config)
    local state = getSubplanState(chunk.id, worldRootName)
    local missing = {}

    for _, layer in ipairs(CANONICAL_SUBPLAN_LAYERS) do
        local layerIndex = CANONICAL_SUBPLAN_LAYER_INDEX[layer]
        if layerIndex >= targetLayerIndex then
            break
        end
        if
            actionSet[layer]
            and not state.importedLayers[layer]
            and not layerHasCompleteSubplans(chunk, state, layer)
        then
            missing[#missing + 1] = layer
        end
    end

    if #missing > 0 then
        error(
            ("Cannot import subplan %s for chunk %s before prerequisites: %s"):format(
                getSubplanWorkId(chunk.id, subplan),
                tostring(chunk.id),
                table.concat(missing, ", ")
            )
        )
    end
end

local function makeImportChunkOptions(options, config)
    return {
        config = config,
        worldRootName = options.worldRootName,
        meshCollisionPolicy = options.meshCollisionPolicy,
        frameBudgetSeconds = options.frameBudgetSeconds,
        nonBlocking = options.nonBlocking,
        shouldCancel = options.shouldCancel,
        layers = options.layers,
        configSignature = options.configSignature,
        layerSignatures = options.layerSignatures,
        onChunkProfile = options.onChunkProfile,
    }
end

function ImportService.ImportChunk(chunk, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    local registrationChunk = if type(options.registrationChunk) == "table" then options.registrationChunk else chunk
    local layers = options.layers
    local subplan = if type(options.subplan) == "table" then options.subplan else nil
    local plan = ImportPlanCache.GetOrCreatePlan(chunk, {
        config = config,
        configSignature = options.configSignature,
        layerSignatures = options.layerSignatures,
        layers = layers,
    })
    local prepared = plan.prepared or {}
    local selectiveLayers = plan.selectiveLayers
    local _nonBlocking, maybeYield = makePacingController(options)
    local shouldCancel = if type(options.shouldCancel) == "function" then options.shouldCancel else nil
    local onChunkProfile = if type(options.onChunkProfile) == "function" then options.onChunkProfile else nil
    local chunkProfile = {
        chunkId = chunk.id,
        worldRootName = options.worldRootName or DEFAULT_WORLD_ROOT_NAME,
        terrainMs = 0,
        landuseMs = 0,
        landusePlanMs = 0,
        landuseExecuteMs = 0,
        landuseTerrainFillMs = 0,
        landuseDetailMs = 0,
        landuseCellCount = 0,
        landuseRectCount = 0,
        landuseDetailInstanceCount = 0,
        roadsMs = 0,
        roadsSurfaceMs = 0,
        roadsDecorationMs = 0,
        roadSurfaceAccumulatorCount = 0,
        roadSurfaceMeshPartCount = 0,
        roadSurfaceSegmentCount = 0,
        roadSurfaceRoadCount = 0,
        roadSurfaceVertexCount = 0,
        roadSurfaceTriangleCount = 0,
        roadSurfaceMeshCreateMs = 0,
        roadImprintMs = 0,
        barriersMs = 0,
        buildingsMs = 0,
        buildingMeshPartCount = 0,
        buildingMeshVertexCount = 0,
        buildingMeshTriangleCount = 0,
        buildingMeshCreateMs = 0,
        buildingRoofMeshPartCount = 0,
        waterMs = 0,
        propsMs = 0,
        propFeatureCount = 0,
        propKindCount = 0,
        propTopKind1 = nil,
        propTopKind1Count = 0,
        propTopKind1Ms = 0,
        propTopKind2 = nil,
        propTopKind2Count = 0,
        propTopKind2Ms = 0,
        propTopKind3 = nil,
        propTopKind3Count = 0,
        propTopKind3Ms = 0,
        ambientMs = 0,
        cancelled = false,
        subplanId = subplan and subplan.id or nil,
        subplanLayer = subplan and getSubplanLayer(subplan) or nil,
    }
    local mutationStarted = false
    local profile = nil

    local function emitChunkProfile(report)
        if onChunkProfile then
            local ok, err = pcall(onChunkProfile, report)
            if not ok then
                warn(
                    ("[ImportService] onChunkProfile failed for chunk %s: %s"):format(tostring(chunk.id), tostring(err))
                )
            end
        end
    end

    local function cancelImport()
        chunkProfile.cancelled = true
        if mutationStarted then
            ImportService.RollbackCancelledImport(registrationChunk, {
                config = config,
                worldRootName = options.worldRootName,
                layers = layers,
                subplan = subplan,
                configSignature = options.configSignature,
                layerSignatures = options.layerSignatures,
            })
        end
        Profiler.finish(profile, {
            chunkId = chunk.id,
            cancelled = true,
        })
        emitChunkProfile(chunkProfile)
        return nil
    end

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
    profile = Profiler.begin("ImportChunk", true)

    -- Authoritative overwrite: ensure any existing version of this chunk is unloaded first.
    -- This prevents duplicate content on re-import.
    if shouldCancel and shouldCancel() then
        return cancelImport()
    end
    if not selectiveLayers then
        clearSubplanState(chunk.id, options.worldRootName)
        ChunkLoader.UnloadChunk(chunk.id, true, options.worldRootName)
        mutationStarted = true
        if checkpoint() then
            return cancelImport()
        end
    end

    local worldRootName = options.worldRootName or DEFAULT_WORLD_ROOT_NAME
    local worldRoot = getWorldRoot(worldRootName)
    local chunkFolder = if selectiveLayers
        then getOrCreateNamedFolder(worldRoot, chunk.id)
        else ensureChunkFolder(worldRoot, chunk.id)
    mutationStarted = true
    if checkpoint() then
        return cancelImport()
    end

    local function prepareLayerFolder(name, clearChildrenFirst)
        if selectiveLayers then
            local layerFolder = getOrCreateNamedFolder(chunkFolder, name)
            local boundedSubplan = subplan and getSubplanBounds(subplan) ~= nil
            if boundedSubplan then
                local targetName = subplan.id or getSubplanLayer(subplan)
                local subplanFolder = getOrCreateNamedFolder(layerFolder, targetName)
                if clearChildrenFirst then
                    if name == "Props" then
                        PropBuilder.ReleaseAll(subplanFolder)
                    end
                    clearResidualChildren(subplanFolder)
                end
                return subplanFolder
            end

            if clearChildrenFirst then
                if name == "Props" then
                    PropBuilder.ReleaseAll(layerFolder)
                end
                clearResidualChildren(layerFolder)
            end
            return layerFolder
        end

        local folder = createNamedFolder(chunkFolder, name)
        if clearChildrenFirst then
            if name == "Props" then
                PropBuilder.ReleaseAll(folder)
            end
            clearResidualChildren(folder)
        end
        return folder
    end

    local terrainFolder = nil
    if plan.folderSpecs.terrain then
        terrainFolder = prepareLayerFolder(plan.folderSpecs.terrain.name, plan.folderSpecs.terrain.clearChildren)
    end
    if terrainFolder and checkpoint() then
        return cancelImport()
    end

    local roadsFolder = nil
    if plan.folderSpecs.roads then
        roadsFolder = prepareLayerFolder(plan.folderSpecs.roads.name, plan.folderSpecs.roads.clearChildren)
    end
    if roadsFolder and checkpoint() then
        return cancelImport()
    end

    local railsFolder = nil
    if plan.folderSpecs.rails then
        railsFolder = prepareLayerFolder(plan.folderSpecs.rails.name, plan.folderSpecs.rails.clearChildren)
    end
    if railsFolder and checkpoint() then
        return cancelImport()
    end

    local buildingsFolder = nil
    if plan.folderSpecs.buildings then
        buildingsFolder = prepareLayerFolder(plan.folderSpecs.buildings.name, plan.folderSpecs.buildings.clearChildren)
    end
    if buildingsFolder and checkpoint() then
        return cancelImport()
    end

    local waterFolder = nil
    if plan.folderSpecs.water then
        waterFolder = prepareLayerFolder(plan.folderSpecs.water.name, plan.folderSpecs.water.clearChildren)
    end
    if waterFolder and checkpoint() then
        return cancelImport()
    end

    local propsFolder = nil
    if plan.folderSpecs.props then
        propsFolder = prepareLayerFolder(plan.folderSpecs.props.name, plan.folderSpecs.props.clearChildren)
    end
    if propsFolder and checkpoint() then
        return cancelImport()
    end

    local landuseFolder = nil
    if plan.folderSpecs.landuse then
        landuseFolder = prepareLayerFolder(plan.folderSpecs.landuse.name, plan.folderSpecs.landuse.clearChildren)
    end
    if landuseFolder and checkpoint() then
        return cancelImport()
    end

    local barriersFolder = nil
    if plan.folderSpecs.barriers then
        barriersFolder = prepareLayerFolder(plan.folderSpecs.barriers.name, plan.folderSpecs.barriers.clearChildren)
    end
    maybeYield()

    if plan.actionSet.terrain then
        local terrainPlan = prepared.terrain or TerrainBuilder.PrepareChunk(chunk)
        if selectiveLayers then
            TerrainBuilder.Clear(chunk, terrainPlan)
        end
        local p = Profiler.begin("BuildTerrain")
        TerrainBuilder.Build(terrainFolder, chunk, terrainPlan)
        chunkProfile.terrainMs = Profiler.finish(p).elapsedMs
        if checkpoint() then
            return cancelImport()
        end
    end

    -- Landuse fills go BEFORE roads so roads paint over them
    if plan.actionSet.landuse then
        local pLanduse = Profiler.begin("BuildLanduse")
        local landuseStats =
            LanduseBuilder.BuildAll(chunk.landuse, chunk.originStuds, landuseFolder, chunk, prepared.landuse)
        chunkProfile.landuseMs = Profiler.finish(pLanduse).elapsedMs
        chunkProfile.landusePlanMs = tonumber(landuseStats.planMs) or 0
        chunkProfile.landuseExecuteMs = tonumber(landuseStats.executeMs) or 0
        chunkProfile.landuseTerrainFillMs = tonumber(landuseStats.terrainFillMs) or 0
        chunkProfile.landuseDetailMs = tonumber(landuseStats.detailMs) or 0
        chunkProfile.landuseCellCount = tonumber(landuseStats.cellCount) or 0
        chunkProfile.landuseRectCount = tonumber(landuseStats.rectCount) or 0
        chunkProfile.landuseDetailInstanceCount = tonumber(landuseStats.detailInstances) or 0
        if checkpoint() then
            return cancelImport()
        end
    end

    if plan.actionSet.roads then
        local pRoads = Profiler.begin("BuildRoads")
        local roadChunkPlan = prepared.roads
        if config.RoadMode == "mesh" then
            -- Merge all ground-level road surfaces into EditableMesh objects
            -- grouped by material/colour to minimise draw calls.
            local pRoadSurfaces = Profiler.begin("BuildRoadSurfaces")
            local roadSurfaceStats = RoadBuilder.MeshBuildAll(
                roadsFolder,
                chunk.roads,
                chunk.originStuds,
                chunk,
                roadChunkPlan,
                maybeYield,
                {
                    meshCollisionPolicy = options.meshCollisionPolicy,
                }
            )
            chunkProfile.roadsSurfaceMs = Profiler.finish(pRoadSurfaces).elapsedMs
            if roadSurfaceStats then
                chunkProfile.roadSurfaceAccumulatorCount = tonumber(roadSurfaceStats.accumulatorCount) or 0
                chunkProfile.roadSurfaceMeshPartCount = tonumber(roadSurfaceStats.meshPartCount) or 0
                chunkProfile.roadSurfaceSegmentCount = tonumber(roadSurfaceStats.segmentCount) or 0
                chunkProfile.roadSurfaceRoadCount = tonumber(roadSurfaceStats.roadCount) or 0
                chunkProfile.roadSurfaceVertexCount = tonumber(roadSurfaceStats.vertexCount) or 0
                chunkProfile.roadSurfaceTriangleCount = tonumber(roadSurfaceStats.triangleCount) or 0
                chunkProfile.roadSurfaceMeshCreateMs = tonumber(roadSurfaceStats.meshCreateMs) or 0
            end
            maybeYield(false)
            -- Decorations (centerlines, arrows, lights, crosswalks, steps, tunnels)
            -- cannot be merged into the surface mesh; render them as separate Parts.
            local pRoadDecorations = Profiler.begin("BuildRoadDecorations")
            RoadBuilder.MeshBuildDecorations(roadsFolder, chunk.roads, chunk.originStuds, chunk, roadChunkPlan)
            chunkProfile.roadsDecorationMs = Profiler.finish(pRoadDecorations).elapsedMs
            maybeYield(false)
            forEachWithPacing(chunk.rails, function(rail)
                RailBuilder.Build(railsFolder, rail, chunk.originStuds)
            end, maybeYield)
        else
            RoadBuilder.BuildAll(roadsFolder, chunk.roads, chunk.originStuds, chunk, maybeYield, roadChunkPlan)
            forEachWithPacing(chunk.rails, function(rail)
                RailBuilder.FallbackBuild(railsFolder, rail, chunk.originStuds)
            end, maybeYield)
        end
        chunkProfile.roadsMs = Profiler.finish(pRoads).elapsedMs
        if config.RoadMode ~= "mesh" then
            chunkProfile.roadsSurfaceMs = chunkProfile.roadsMs
        end
        if checkpoint() then
            return cancelImport()
        end

        -- Imprint road surfaces into terrain voxels so slopes are flattened
        -- under road segments. Only runs when both terrain and roads are present.
        if plan.actionSet.roadImprint then
            local pImprint = Profiler.begin("ImprintRoads")
            TerrainBuilder.ImprintRoads(roadChunkPlan.roads, chunk.originStuds, chunk)
            chunkProfile.roadImprintMs = Profiler.finish(pImprint).elapsedMs
            if checkpoint() then
                return cancelImport()
            end
        end
    end

    if plan.actionSet.barriers then
        local pBarriers = Profiler.begin("BuildBarriers")
        BarrierBuilder.BuildAll(chunk, barriersFolder)
        chunkProfile.barriersMs = Profiler.finish(pBarriers).elapsedMs
        if checkpoint() then
            return cancelImport()
        end
    end

    if plan.actionSet.buildings then
        local pBldgs = Profiler.begin("BuildBuildings")
        local windowBudget = {
            used = 0,
            max = (config.InstanceBudget and config.InstanceBudget.MaxWindowsPerChunk) or 10000,
        }
        if config.BuildingMode == "shellMesh" then
            -- Merge opaque wall + flat-roof geometry into per-material EditableMeshes
            -- (10-100x draw call reduction). Windows/shaped roofs remain as Parts.
            local meshBuildResult = BuildingBuilder.MeshBuildAll(
                buildingsFolder,
                chunk.buildings,
                chunk.originStuds,
                chunk,
                config,
                maybeYield,
                {
                    meshCollisionPolicy = options.meshCollisionPolicy,
                }
            )
            local builtModelsById = meshBuildResult.builtModelsById or {}
            local buildingMeshStats = meshBuildResult.stats or {}
            chunkProfile.buildingMeshPartCount = tonumber(buildingMeshStats.meshPartCount) or 0
            chunkProfile.buildingMeshVertexCount = tonumber(buildingMeshStats.vertexCount) or 0
            chunkProfile.buildingMeshTriangleCount = tonumber(buildingMeshStats.triangleCount) or 0
            chunkProfile.buildingMeshCreateMs = tonumber(buildingMeshStats.meshCreateMs) or 0
            chunkProfile.buildingRoofMeshPartCount = tonumber(buildingMeshStats.roofMeshPartCount) or 0
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

        chunkProfile.buildingsMs = Profiler.finish(pBldgs).elapsedMs
        if checkpoint() then
            return cancelImport()
        end
    end

    if plan.actionSet.water then
        local pWater = Profiler.begin("BuildWater")
        local waterSampler = if chunk.terrain then GroundSampler.createRenderedSurfaceSampler(chunk) else nil
        if config.WaterMode == "mesh" then
            forEachWithPacing(chunk.water, function(water)
                WaterBuilder.Build(waterFolder, water, chunk.originStuds, chunk, waterSampler)
            end, maybeYield)
        else
            forEachWithPacing(chunk.water, function(water)
                WaterBuilder.FallbackBuild(waterFolder, water, chunk.originStuds, chunk, waterSampler)
            end, maybeYield)
        end
        chunkProfile.waterMs = Profiler.finish(pWater).elapsedMs
        if checkpoint() then
            return cancelImport()
        end
    end

    if plan.actionSet.props then
        local pProps = Profiler.begin("BuildProps")
        local propStatsByKind = {}
        forEachWithPacing(chunk.props, function(prop)
            local propKind = if type(prop.kind) == "string" and prop.kind ~= "" then prop.kind else "unknown"
            local propStats = propStatsByKind[propKind]
            if propStats == nil then
                propStats = {
                    count = 0,
                    elapsedMs = 0,
                }
                propStatsByKind[propKind] = propStats
            end
            local propStart = os.clock()
            PropBuilder.Build(propsFolder, prop, chunk.originStuds, chunk)
            propStats.count += 1
            propStats.elapsedMs += (os.clock() - propStart) * 1000
        end, maybeYield)
        chunkProfile.propsMs = Profiler.finish(pProps).elapsedMs
        chunkProfile.propFeatureCount = #(chunk.props or {})
        local propKindSummaries = {}
        for propKind, propStats in pairs(propStatsByKind) do
            propKindSummaries[#propKindSummaries + 1] = {
                kind = propKind,
                count = propStats.count,
                elapsedMs = propStats.elapsedMs,
            }
        end
        table.sort(propKindSummaries, function(a, b)
            if a.elapsedMs ~= b.elapsedMs then
                return a.elapsedMs > b.elapsedMs
            end
            if a.count ~= b.count then
                return a.count > b.count
            end
            return a.kind < b.kind
        end)
        chunkProfile.propKindCount = #propKindSummaries
        local topKinds = { propKindSummaries[1], propKindSummaries[2], propKindSummaries[3] }
        for index, summary in ipairs(topKinds) do
            chunkProfile[("propTopKind%d"):format(index)] = summary and summary.kind or nil
            chunkProfile[("propTopKind%dCount"):format(index)] = summary and summary.count or 0
            chunkProfile[("propTopKind%dMs"):format(index)] = summary and math.floor(summary.elapsedMs + 0.5) or 0
        end
        if checkpoint() then
            return cancelImport()
        end
    end

    if config.EnableAmbientLife ~= false and propsFolder then
        local pAmbient = Profiler.begin("BuildAmbientLife")
        AmbientLife.PlaceParkedCars(propsFolder, chunk.roads, chunk.originStuds)
        AmbientLife.SpawnNPCs(propsFolder, chunk.roads, chunk.originStuds)
        chunkProfile.ambientMs = Profiler.finish(pAmbient).elapsedMs
        if checkpoint() then
            return cancelImport()
        end
    end

    ChunkLoader.RegisterChunk(chunk.id, chunkFolder, registrationChunk, {
        planKey = plan.key,
        configSignature = options.configSignature,
        chunkSignature = options.chunkSignature,
        layerSignatures = options.layerSignatures,
        worldRootName = options.worldRootName,
    })
    if not selectiveLayers then
        setSubplanState(chunk.id, {
            importedLayers = buildImportedLayerMap(plan.actionSet),
            completedWorkItems = buildCompletedWorkItemMap(registrationChunk),
            failedWorkItems = {},
        }, options.worldRootName)
    end

    local artifactCount = countChunkArtifactNodes(chunkFolder)

    local importSession = Profiler.finish(profile, {
        chunkId = chunk.id,
        instanceCount = artifactCount,
        planKey = plan.key,
    })
    chunkProfile.totalMs = importSession.elapsedMs
    chunkProfile.artifactCount = artifactCount
    emitChunkProfile(chunkProfile)

    return chunkFolder, artifactCount
end

function ImportService.ImportChunkSubplan(chunk, subplanOrId, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    local subplan = resolveSubplan(chunk, subplanOrId)
    local layer = getSubplanLayer(subplan)
    local workId = getSubplanWorkId(chunk.id, subplan)
    local registrationChunk = if type(options.registrationChunk) == "table" then options.registrationChunk else chunk
    local profile = Profiler.begin("ImportChunkSubplan", true)
    local previousState = cloneSubplanState(getSubplanState(chunk.id, options.worldRootName))

    local prerequisitesOk, prerequisitesErr =
        pcall(validateSubplanPrerequisites, registrationChunk, subplan, config, options.worldRootName)
    if not prerequisitesOk then
        finishSubplanImportProfile(profile, chunk.id, subplan, workId, layer, "failed")
        error(prerequisitesErr, 0)
    end

    local subplanOptions = table.clone(options)
    local filteredChunk = buildChunkForSubplan(chunk, subplan)
    subplanOptions.config = config
    subplanOptions.layers = {
        [layer] = true,
    }
    subplanOptions.subplan = subplan
    subplanOptions.registrationChunk = registrationChunk

    local ok, chunkFolder, artifactCount = pcall(function()
        return ImportService.ImportChunk(filteredChunk, subplanOptions)
    end)

    if not ok then
        local failedState = cloneSubplanState(previousState)
        failedState.failedWorkItems[workId] = {
            chunkId = chunk.id,
            subplanId = subplan.id or layer,
            layer = layer,
            message = tostring(chunkFolder),
        }
        setSubplanState(chunk.id, failedState, options.worldRootName)
        finishSubplanImportProfile(profile, chunk.id, subplan, workId, layer, "failed")
        error(chunkFolder, 0)
    end

    if chunkFolder == nil then
        setSubplanState(chunk.id, previousState, options.worldRootName)
        finishSubplanImportProfile(profile, chunk.id, subplan, workId, layer, "cancelled")
        return nil
    end

    local mergedState = cloneSubplanState(previousState)
    mergedState.completedWorkItems[workId] = true
    if layerHasCompleteSubplans(registrationChunk, mergedState, layer) then
        mergedState.importedLayers[layer] = true
    end
    mergedState.failedWorkItems[workId] = nil
    setSubplanState(chunk.id, mergedState, options.worldRootName)
    finishSubplanImportProfile(profile, chunk.id, subplan, workId, layer, "completed", artifactCount)

    return chunkFolder, artifactCount
end

function ImportService.RollbackCancelledImport(chunk, options)
    options = options or {}
    local config = options.config or DefaultWorldConfig
    local subplan = options.subplan
    local cleanupChunk = if type(subplan) == "table" then buildChunkForSubplan(chunk, subplan) else chunk
    local plan = ImportPlanCache.GetOrCreatePlan(cleanupChunk, {
        config = config,
        configSignature = options.configSignature,
        layerSignatures = options.layerSignatures,
        layers = options.layers,
    })
    local selectiveLayers = plan.selectiveLayers
    local prepared = plan.prepared or {}
    local worldRoot = Workspace:FindFirstChild(options.worldRootName or DEFAULT_WORLD_ROOT_NAME)
    local chunkFolder = worldRoot and worldRoot:FindFirstChild(cleanupChunk.id) or nil

    if plan.actionSet.terrain then
        local terrainPlan = prepared.terrain or TerrainBuilder.PrepareChunk(cleanupChunk)
        TerrainBuilder.Clear(cleanupChunk, terrainPlan)
    end

    local function clearImportFolder(folder, releaseProps)
        if folder == nil then
            return
        end
        if releaseProps then
            PropBuilder.ReleaseAll(folder)
        end
        clearResidualChildren(folder)
    end

    if chunkFolder == nil then
        return
    end

    if selectiveLayers then
        for _, folderSpec in pairs(plan.folderSpecs or {}) do
            local layerFolder = chunkFolder:FindFirstChild(folderSpec.name)
            if layerFolder ~= nil then
                local targetFolder = layerFolder
                local boundedSubplan = type(subplan) == "table" and getSubplanBounds(subplan) ~= nil
                if boundedSubplan then
                    targetFolder = layerFolder:FindFirstChild(subplan.id or getSubplanLayer(subplan))
                end
                clearImportFolder(targetFolder, folderSpec.name == "Props")
            end
        end
        return
    end

    local propsFolder = chunkFolder:FindFirstChild("Props")
    if propsFolder ~= nil then
        PropBuilder.ReleaseAll(propsFolder)
    end
    clearResidualChildren(chunkFolder)
end

function ImportService.GetSubplanState(chunkId, worldRootName)
    return cloneSubplanState(getSubplanState(chunkId, worldRootName))
end

function ImportService.ResetSubplanState(chunkId, worldRootName)
    if type(chunkId) == "string" then
        clearSubplanState(chunkId, worldRootName)
        return
    end

    if type(worldRootName) == "string" and worldRootName ~= "" then
        local prefix = worldRootName .. "::"
        for stateKey in pairs(subplanStateByChunkId) do
            if string.sub(stateKey, 1, #prefix) == prefix then
                subplanStateByChunkId[stateKey] = nil
            end
        end
        return
    end

    for stateKey in pairs(subplanStateByChunkId) do
        subplanStateByChunkId[stateKey] = nil
    end
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

    LoadingScreen.Show(validated.meta and validated.meta.worldName or "World")

    if options.clearFirst then
        ChunkLoader.Clear(worldRootName) -- This now handles folder destruction and prop releasing
        clearResidualChildren(worldRoot)
        maybeYield(true)
    elseif options.sync then
        -- Sync mode: remove any loaded chunks that are NOT in this manifest
        local manifestChunkIds = {}
        for _, chunk in ipairs(validated.chunks) do
            manifestChunkIds[chunk.id] = true
        end

        for _, loadedChunkId in ipairs(ChunkLoader.ListLoadedChunks(worldRootName)) do
            if not manifestChunkIds[loadedChunkId] then
                ChunkLoader.UnloadChunk(loadedChunkId, nil, worldRootName)
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
    local registrationChunksById = options.registrationChunksById

    local chunkOptions = makeImportChunkOptions(options, config)
    if chunkOptions.configSignature == nil then
        chunkOptions.configSignature = ImportSignatures.GetConfigSignature(config)
    end
    if chunkOptions.layerSignatures == nil then
        chunkOptions.layerSignatures = ImportSignatures.GetLayerSignatures(config)
    end

    for chunkIndex, chunk in ipairs(chunksToImport) do
        local perChunkOptions = table.clone(chunkOptions)
        local registrationChunk = registrationChunksById and registrationChunksById[chunk.id] or nil
        perChunkOptions.registrationChunk = registrationChunk
        perChunkOptions.chunkSignature = ImportSignatures.GetChunkSignature(registrationChunk or chunk)
        local chunkFolder, artifactCount = ImportService.ImportChunk(chunk, perChunkOptions)

        stats.chunksImported += 1
        stats.roadsImported += #(chunk.roads or {})
        stats.railsImported += #(chunk.rails or {})
        stats.buildingsImported += #(chunk.buildings or {})
        stats.waterImported += #(chunk.water or {})
        stats.propsImported += #(chunk.props or {})
        stats.landuseImported += #(chunk.landuse or {})
        stats.barriersImported += #(chunk.barriers or {})
        stats.totalInstances += artifactCount or 0

        MinimapService.RegisterChunk(chunkFolder, chunk)

        LoadingScreen.UpdateProgress(
            chunkIndex / #chunksToImport,
            string.format("Building chunk %d/%d...", chunkIndex, #chunksToImport)
        )

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

    WorldStateApplier.Apply(validated, config, {
        startMinimap = true,
        hideLoadingScreen = true,
        worldRootName = worldRootName,
    })

    return stats
end

return ImportService
