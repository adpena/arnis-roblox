local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local MinimapService = {}

local WORLD_ROOT_ATTR = "ArnisMinimapWorldRootName"
local ENABLED_ATTR = "ArnisMinimapEnabled"
local CHUNK_JSON_ATTR = "ArnisMinimapChunkJson"
local CHUNK_ID_ATTR = "ArnisMinimapChunkId"

local function copyPoints(points)
    local result = table.create(#(points or {}))
    for index, point in ipairs(points or {}) do
        result[index] = {
            x = point.x,
            z = point.z,
        }
    end
    return result
end

local function copyLanduse(landuse)
    local result = table.create(#(landuse or {}))
    for index, entry in ipairs(landuse or {}) do
        result[index] = {
            kind = entry.kind,
            footprint = copyPoints(entry.footprint),
        }
    end
    return result
end

local function copyRoads(roads)
    local result = table.create(#(roads or {}))
    for index, road in ipairs(roads or {}) do
        result[index] = {
            kind = road.kind,
            widthStuds = road.widthStuds,
            points = copyPoints(road.points),
        }
    end
    return result
end

local function copyBuildings(buildings)
    local result = table.create(#(buildings or {}))
    for index, building in ipairs(buildings or {}) do
        result[index] = {
            footprint = copyPoints(building.footprint),
        }
    end
    return result
end

local function copyWater(water)
    local result = table.create(#(water or {}))
    for index, entry in ipairs(water or {}) do
        result[index] = {
            footprint = copyPoints(entry.footprint),
            points = copyPoints(entry.points),
            widthStuds = entry.widthStuds,
        }
    end
    return result
end

local function buildChunkSnapshot(chunkData)
    local origin = chunkData.originStuds or {}
    return {
        id = chunkData.id,
        originStuds = {
            x = origin.x or 0,
            z = origin.z or 0,
        },
        landuse = copyLanduse(chunkData.landuse),
        roads = copyRoads(chunkData.roads),
        buildings = copyBuildings(chunkData.buildings),
        water = copyWater(chunkData.water),
    }
end

function MinimapService.RegisterChunk(chunkFolder, chunkData)
    if not chunkFolder or type(chunkData) ~= "table" then
        return
    end

    chunkFolder:SetAttribute(CHUNK_ID_ATTR, chunkData.id or chunkFolder.Name)
    chunkFolder:SetAttribute(CHUNK_JSON_ATTR, HttpService:JSONEncode(buildChunkSnapshot(chunkData)))
end

function MinimapService.ClearChunk(chunkFolder)
    if not chunkFolder then
        return
    end

    chunkFolder:SetAttribute(CHUNK_JSON_ATTR, nil)
    chunkFolder:SetAttribute(CHUNK_ID_ATTR, nil)
end

function MinimapService.Start(options)
    local resolvedOptions = options or {}
    Workspace:SetAttribute(ENABLED_ATTR, true)
    Workspace:SetAttribute(WORLD_ROOT_ATTR, resolvedOptions.worldRootName or "GeneratedWorld")
end

function MinimapService.Stop()
    Workspace:SetAttribute(ENABLED_ATTR, false)
    Workspace:SetAttribute(WORLD_ROOT_ATTR, nil)
end

return MinimapService
