local WorldConfig = {
    MetersPerStud = 1.0,
    ChunkSizeStuds = 256,

    TerrainMode = "voxel", -- Options: "none", "debugParts", "voxel"
    RoadMode = "mesh", -- Options: "none", "parts", "mesh", "hybrid"
    BuildingMode = "shellMesh", -- Options: "none", "shellParts", "shellMesh", "prefab"
    WaterMode = "mesh", -- Added for completeness
    LanduseMode = "fill", -- Options: "none", "fill"

    StreamingEnabled = true,
    StreamingTargetRadius = 4096, -- Distance to keep ANY representation loaded
    HighDetailRadius = 2048, -- Distance to keep full buildings/water/props loaded

    InstanceBudget = {
        MaxPerChunk = 2000, -- Increased for higher detail
        MaxPropsPerChunk = 500,
    },
}

return WorldConfig
