local ImportPlanCache = {}

local TerrainBuilder = require(script.Parent.Builders.TerrainBuilder)
local LanduseBuilder = require(script.Parent.Builders.LanduseBuilder)
local RoadChunkPlan = require(script.Parent.RoadChunkPlan)

local planCache = {}
local cacheStats = {
    hits = 0,
    misses = 0,
    clears = 0,
}

local FOLDER_BY_LAYER = {
    terrain = "Terrain",
    roads = "Roads",
    rails = "Rails",
    buildings = "Buildings",
    water = "Water",
    props = "Props",
    landuse = "Landuse",
    barriers = "Barriers",
}

local function stablePairsKeys(map)
    local keys = {}
    for key, value in pairs(map or {}) do
        if value ~= nil then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function stringifyMap(map)
    local keys = stablePairsKeys(map)
    if #keys == 0 then
        return "none"
    end

    local parts = table.create(#keys)
    for index, key in ipairs(keys) do
        parts[index] = tostring(key) .. "=" .. tostring(map[key])
    end
    return table.concat(parts, ",")
end

local function deriveConfigSignature(config)
    return table.concat({
        tostring(config and config.TerrainMode or "default"),
        tostring(config and config.RoadMode or "default"),
        tostring(config and config.BuildingMode or "default"),
        tostring(config and config.WaterMode or "default"),
        tostring(config and config.LanduseMode or "default"),
    }, "|")
end

local function derivePresenceSignature(chunk)
    return table.concat({
        tostring(chunk.id or ""),
        tostring(chunk.terrain ~= nil),
        tostring(#(chunk.roads or {})),
        tostring(#(chunk.rails or {})),
        tostring(#(chunk.buildings or {})),
        tostring(#(chunk.water or {})),
        tostring(#(chunk.props or {})),
        tostring(#(chunk.landuse or {})),
        tostring(#(chunk.barriers or {})),
    }, "|")
end

local function shouldImportLayer(layers, layerName)
    return layers == nil or layers[layerName] == true
end

local function freezePlan(plan)
    table.freeze(plan.folderSpecs)
    table.freeze(plan.actions)
    return table.freeze(plan)
end

function ImportPlanCache.GetOrCreatePlan(chunk, options)
    options = options or {}

    local config = options.config or {}
    local layers = options.layers
    local configSignature = options.configSignature or deriveConfigSignature(config)
    local layerSignatureKey = stringifyMap(options.layerSignatures)
    local requestedLayerKey = stringifyMap(layers)
    local presenceKey = derivePresenceSignature(chunk)
    local selectiveLayers = layers ~= nil

    local key = table.concat({
        presenceKey,
        "config=" .. configSignature,
        "layerSig=" .. layerSignatureKey,
        "layers=" .. requestedLayerKey,
        "selective=" .. tostring(selectiveLayers),
    }, "|")

    local cached = planCache[key]
    if cached then
        cacheStats.hits += 1
        return cached
    end
    cacheStats.misses += 1

    local folderSpecs = {}

    local function addFolderSpec(layerName, condition, requestLayerName)
        local gateLayerName = requestLayerName or layerName
        if condition and shouldImportLayer(layers, gateLayerName) then
            folderSpecs[layerName] = {
                name = FOLDER_BY_LAYER[layerName],
                clearChildren = selectiveLayers,
            }
        end
    end

    addFolderSpec("terrain", true)
    addFolderSpec("roads", true)
    addFolderSpec("rails", true, "roads")
    addFolderSpec("buildings", true)
    addFolderSpec("water", true)
    addFolderSpec("props", true)
    addFolderSpec("landuse", true)
    addFolderSpec("barriers", true)

    local actions = {}

    local function pushAction(kind)
        actions[#actions + 1] = kind
    end

    if shouldImportLayer(layers, "terrain") and chunk.terrain and config.TerrainMode ~= "none" then
        pushAction("terrain")
    end
    if shouldImportLayer(layers, "landuse") and chunk.landuse and #chunk.landuse > 0 then
        pushAction("landuse")
    end
    if shouldImportLayer(layers, "roads") and config.RoadMode ~= "none" then
        pushAction("roads")
        if chunk.roads and #chunk.roads > 0 and chunk.terrain and config.TerrainMode ~= "none" then
            pushAction("roadImprint")
        end
    end
    if shouldImportLayer(layers, "barriers") then
        pushAction("barriers")
    end
    if shouldImportLayer(layers, "buildings") and config.BuildingMode ~= "none" then
        pushAction("buildings")
    end
    if shouldImportLayer(layers, "water") and config.WaterMode ~= "none" then
        pushAction("water")
    end
    if shouldImportLayer(layers, "props") then
        pushAction("props")
    end

    local actionSet = {}
    for _, action in ipairs(actions) do
        actionSet[action] = true
    end

    local prepared = {}
    if actionSet.terrain then
        prepared.terrain = TerrainBuilder.PrepareChunk(chunk)
    end
    if actionSet.roads or actionSet.roadImprint then
        prepared.roads = RoadChunkPlan.build(chunk.roads or {}, chunk.originStuds or { x = 0, y = 0, z = 0 }, chunk)
    end
    if actionSet.landuse then
        prepared.landuse =
            LanduseBuilder.PlanAll(chunk.landuse or {}, chunk.originStuds or { x = 0, y = 0, z = 0 }, chunk)
    end

    cached = freezePlan({
        key = key,
        selectiveLayers = selectiveLayers,
        configSignature = configSignature,
        folderSpecs = folderSpecs,
        actions = actions,
        actionSet = actionSet,
        prepared = prepared,
    })
    planCache[key] = cached
    return cached
end

function ImportPlanCache.Clear()
    cacheStats.clears += 1
    table.clear(planCache)
end

function ImportPlanCache.GetStats()
    local stats = {
        hits = cacheStats.hits,
        misses = cacheStats.misses,
        clears = cacheStats.clears,
        size = 0,
    }
    for _ in pairs(planCache) do
        stats.size += 1
    end
    return stats
end

return ImportPlanCache
