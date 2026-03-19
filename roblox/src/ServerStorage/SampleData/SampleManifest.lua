return {
    schemaVersion = "0.4.0",
    meta = {
        worldName = "SampleAustinLikeBlock",
        generator = "roblox sample data",
        source = "synthetic-scaffold",
        metersPerStud = 0.3,
        chunkSizeStuds = 256,
        bbox = {
            minLat = 30.264,
            minLon = -97.750,
            maxLat = 30.266,
            maxLon = -97.748,
        },
        totalFeatures = 7,
        notes = {
            "Synthetic sample for importer scaffolding",
        },
    },
    chunks = {
        {
            id = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            terrain = {
                cellSizeStuds = 4,
                width = 64,
                depth = 64,
                heights = (function()
                    local h = {}
                    local pattern = {
                        0, 1, 2, 1,
                        1, 2, 3, 2,
                        0, 1, 2, 2,
                        0, 0, 1, 1,
                    }
                    for i = 1, 64 * 64 do
                        h[i] = pattern[((i - 1) % 16) + 1]
                    end
                    return h
                end)(),
                material = "Grass",
            },
            roads = {
                {
                    id = "road_main",
                    kind = "primary",
                    material = "Asphalt",
                    color = { r = 50, g = 50, b = 55 },
                    widthStuds = 10,
                    hasSidewalk = true,
                    surface = "asphalt",
                    elevated = false,
                    tunnel = false,
                    points = {
                        { x = 0, y = 2, z = 64 },
                        { x = 128, y = 2, z = 64 },
                        { x = 256, y = 2, z = 64 },
                    },
                },
            },
            rails = {},
            buildings = {
                {
                    id = "bldg_1",
                    kind = "default",
                    material = "Concrete",
                    wallColor = { r = 200, g = 180, b = 150 },
                    footprint = {
                        { x = 24, z = 24 },
                        { x = 80, z = 24 },
                        { x = 80, z = 72 },
                        { x = 24, z = 72 },
                    },
                    baseY = 2,
                    height = 36,
                    height_m = 11,
                    levels = 3,
                    roofLevels = 0,
                    roof = "flat",
                    facadeStyle = "midrise_mixed",
                },
            },
            water = {
                {
                    id = "water_1",
                    kind = "pond",
                    material = "Water",
                    color = { r = 0, g = 100, b = 200 },
                    surfaceY = 2,
                    footprint = {
                        { x = 24, z = 180 },
                        { x = 112, z = 180 },
                        { x = 132, z = 232 },
                        { x = 18, z = 240 },
                    },
                    holes = {
                        {
                            { x = 62, z = 199 },
                            { x = 78, z = 198 },
                            { x = 74, z = 214 },
                        },
                    },
                },
            },
            props = {
                {
                    id = "tree_1",
                    kind = "tree",
                    position = { x = 120, y = 3, z = 110 },
                    yawDegrees = 0,
                    scale = 1,
                    species = "live_oak",
                },
                {
                    id = "light_1",
                    kind = "light",
                    position = { x = 150, y = 3, z = 68 },
                    yawDegrees = 90,
                    scale = 1,
                },
            },
            landuse = {
                {
                    id = "park_1",
                    kind = "grass",
                    material = "Grass",
                    footprint = {
                        { x = 96, z = 96 },
                        { x = 188, z = 96 },
                        { x = 188, z = 156 },
                        { x = 96, z = 156 },
                    },
                },
            },
            barriers = {
                {
                    id = "hedge_1",
                    kind = "hedge",
                    points = {
                        { x = 92, y = 2, z = 94 },
                        { x = 192, y = 2, z = 94 },
                        { x = 192, y = 2, z = 160 },
                    },
                },
            },
        },
    },
}
