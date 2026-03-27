local ImportSignatures = {}

function ImportSignatures.GetChunkSignature(chunkRef)
    if type(chunkRef) ~= "table" then
        return ""
    end

    local origin = chunkRef.originStuds or {}
    local parts = {
        tostring(chunkRef.id or ""),
        tostring(origin.x or 0),
        tostring(origin.y or 0),
        tostring(origin.z or 0),
        tostring(chunkRef.partitionVersion or ""),
        tostring(chunkRef.featureCount or 0),
        tostring(chunkRef.streamingCost or ""),
        tostring(chunkRef.estimatedMemoryCost or ""),
    }

    for _, shard in ipairs(chunkRef.shards or {}) do
        parts[#parts + 1] = tostring(shard)
    end

    for _, subplan in ipairs(chunkRef.subplans or {}) do
        local bounds = type(subplan) == "table" and subplan.bounds or nil
        parts[#parts + 1] = table.concat({
            tostring(type(subplan) == "table" and subplan.id or ""),
            tostring(type(subplan) == "table" and subplan.layer or ""),
            tostring(type(subplan) == "table" and subplan.featureCount or ""),
            tostring(type(subplan) == "table" and subplan.streamingCost or ""),
            tostring(type(subplan) == "table" and subplan.estimatedMemoryCost or ""),
            tostring(type(bounds) == "table" and bounds.minX or ""),
            tostring(type(bounds) == "table" and (bounds.minZ or bounds.minY) or ""),
            tostring(type(bounds) == "table" and bounds.maxX or ""),
            tostring(type(bounds) == "table" and (bounds.maxZ or bounds.maxY) or ""),
        }, "|")
    end

    return table.concat(parts, "::")
end

function ImportSignatures.GetConfigSignature(config)
    return table.concat({
        tostring(config.TerrainMode),
        tostring(config.RoadMode),
        tostring(config.BuildingMode),
        tostring(config.WaterMode),
        tostring(config.LanduseMode),
    }, "|")
end

function ImportSignatures.GetLayerSignatures(config)
    return {
        terrain = tostring(config.TerrainMode),
        roads = tostring(config.RoadMode),
        landuse = tostring(config.LanduseMode),
        barriers = "default",
        buildings = tostring(config.BuildingMode),
        water = tostring(config.WaterMode),
        props = "default",
    }
end

return ImportSignatures
