local WorldConfig = {
    MetersPerStud = 1.0,
    ChunkSizeStuds = 256,

    TerrainMode = "voxel", -- Options: "none", "debugParts", "voxel"
    RoadMode = "mesh", -- Options: "none", "parts", "mesh", "hybrid"
    BuildingMode = "shellMesh", -- Options: "none", "shellParts", "shellMesh", "prefab"
    WaterMode = "mesh", -- Added for completeness

    StreamingEnabled = true,
    StreamingTargetRadius = 2048, -- Distance to keep ANY representation loaded
    HighDetailRadius = 1024, -- Distance to keep full buildings/water/props loaded

    InstanceBudget = {
        MaxPerChunk = 1500,
        MaxPropsPerChunk = 250,
    },
}

return WorldConfig
