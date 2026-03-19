--[[
    WorldConfig — Central configuration for the Arnis HD Pipeline.

    All rendering parameters are configurable here. For open-source users:
    adjust these values based on your hardware capabilities.

    Hardware reference:
    - "insane" preset: M5 Max 36-128GB, RTX 4090+ equivalent
    - "high" preset: M3 Pro 18GB, RTX 3070 equivalent
    - "medium" preset: M1 8GB, GTX 1660 equivalent
]]

local WorldConfig = {
    -- ═══════════════════════════════════════════════════════════════
    -- CHUNK & SCALE
    -- ═══════════════════════════════════════════════════════════════
    ChunkSizeStuds = 256,

    -- ═══════════════════════════════════════════════════════════════
    -- RENDER MODES
    -- ═══════════════════════════════════════════════════════════════
    TerrainMode = "voxel",       -- "none" | "debugParts" | "voxel"
    RoadMode = "mesh",           -- "none" | "parts" | "mesh" | "hybrid"
    BuildingMode = "shellMesh",  -- "none" | "shellParts" | "shellMesh" | "prefab"
    WaterMode = "mesh",          -- "none" | "mesh"
    LanduseMode = "fill",        -- "none" | "fill"

    -- ═══════════════════════════════════════════════════════════════
    -- TERRAIN FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    VoxelSize = 1,               -- studs; 1 = maximum smoothness (4 = fast, 2 = balanced)
    TerrainThickness = 8,        -- studs below surface to fill with solid terrain
    SlopeRockThreshold = 1.0,    -- rise/run ratio above which terrain becomes Rock (≈45°)
    SlopeGroundThreshold = 0.47, -- rise/run ratio above which terrain becomes Ground (≈25°)

    -- ═══════════════════════════════════════════════════════════════
    -- BUILDING FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    EnableWindowRendering = true,
    EnableRoomInteriors = true,
    WindowSpacing = {            -- studs between windows by building usage
        office = 4,
        residential = 6,
        apartments = 6,
        house = 6,
        warehouse = 12,
        industrial = 12,
        default = 8,
    },

    -- ═══════════════════════════════════════════════════════════════
    -- ROAD FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    LaneWidth = 12,              -- studs per lane (~3.6m at 0.3 m/stud)
    EnableStreetLighting = true,
    StreetLightInterval = 50,    -- studs between street lights
    StreetLightRange = 40,       -- PointLight range in studs

    -- ═══════════════════════════════════════════════════════════════
    -- WATER FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    WaterCarveDepth = 4,         -- studs to carve below water surface

    -- ═══════════════════════════════════════════════════════════════
    -- PROP FIDELITY
    -- ═══════════════════════════════════════════════════════════════
    TreeMetersToStuds = 1 / 0.3, -- conversion factor for real-world tree heights
    EnablePalmRendering = true,

    -- ═══════════════════════════════════════════════════════════════
    -- STREAMING & LOD
    -- ═══════════════════════════════════════════════════════════════
    StreamingEnabled = false,
    StreamingTargetRadius = 4096,
    HighDetailRadius = 2048,

    -- ═══════════════════════════════════════════════════════════════
    -- ATMOSPHERE & LIGHTING
    -- ═══════════════════════════════════════════════════════════════
    EnableAtmosphere = true,     -- set false to skip cinematic lighting setup
    EnableDayNightCycle = true,
    DayNightSpeed = 60,          -- 60 = 1 game-day per 24 minutes, 0 = frozen
    DateTime = "auto",           -- "auto" = system time at location, or "2024-06-15T14:00" for specific time

    -- ═══════════════════════════════════════════════════════════════
    -- MINIMAP
    -- ═══════════════════════════════════════════════════════════════
    EnableMinimap = true,
    MinimapRadius = 400,         -- world studs visible in minimap
    MinimapSize = 200,           -- pixel resolution

    -- ═══════════════════════════════════════════════════════════════
    -- AMBIENT CITY LIFE
    -- ═══════════════════════════════════════════════════════════════
    EnableAmbientLife = true,
    MaxParkedCarsPerChunk = 30,
    MaxNPCsPerChunk = 8,

    -- ═══════════════════════════════════════════════════════════════
    -- INSTANCE BUDGETS (set high for powerful hardware)
    -- ═══════════════════════════════════════════════════════════════
    InstanceBudget = {
        MaxPerChunk = 8000,
        MaxPropsPerChunk = 2000,
        MaxWindowsPerChunk = 10000,  -- effectively unlimited on M5 Max
    },
}

return WorldConfig
