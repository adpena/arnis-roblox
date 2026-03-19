local WorldConfig = {
    ChunkSizeStuds = 256,

    TerrainMode = "voxel", -- Options: "none", "debugParts", "voxel"
    RoadMode = "mesh", -- Options: "none", "parts", "mesh", "hybrid"
    BuildingMode = "shellMesh", -- Options: "none", "shellParts", "shellMesh", "prefab"
    WaterMode = "mesh", -- Added for completeness
    LanduseMode = "fill", -- Options: "none", "fill"

    StreamingEnabled = false, -- importer-driven chunk streaming; keep off until runtime path is validated for your map
    StreamingTargetRadius = 4096, -- Distance to keep any representation loaded
    HighDetailRadius = 2048, -- Distance to keep full buildings/water/props loaded

    InstanceBudget = {
        MaxPerChunk = 2000, -- Increased for higher detail
        MaxPropsPerChunk = 500,
    },
}

return WorldConfig
