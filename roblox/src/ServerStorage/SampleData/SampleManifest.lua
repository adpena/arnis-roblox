return {
    schemaVersion = "0.2.0",
    meta = {
        worldName = "SampleAustinLikeBlock",
        generator = "roblox sample data",
        source = "synthetic-scaffold",
        metersPerStud = 1.0,
        chunkSizeStuds = 256,
        bbox = {
            minLat = 30.264,
            minLon = -97.750,
            maxLat = 30.266,
            maxLon = -97.748,
        },
        totalFeatures = 5,
        notes = {
            "Synthetic sample for importer scaffolding",
        },
    },
    chunks = {
        {
            id = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            terrain = {
                cellSizeStuds = 16,
                width = 4,
                depth = 4,
                heights = {
                    0, 1, 2, 1,
                    1, 2, 3, 2,
                    0, 1, 2, 2,
                    0, 0, 1, 1,
                },
                material = "Grass",
            },
            roads = {
                {
                    id = "road_main",
                    kind = "primary",
                    material = "Asphalt",
                    color = { r = 50, g = 50, b = 55 },
                    widthStuds = 10,
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
                    color = { r = 200, g = 180, b = 150 },
                    footprint = {
                        { x = 24, z = 24 },
                        { x = 80, z = 24 },
                        { x = 80, z = 72 },
                        { x = 24, z = 72 },
                    },
                    baseY = 2,
                    height = 36,
                    roof = "flat",
                },
            },
            water = {
                {
                    id = "water_1",
                    kind = "stream",
                    material = "Water",
                    color = { r = 0, g = 100, b = 200 },
                    widthStuds = 8,
                    points = {
                        { x = 32, y = 1, z = 220 },
                        { x = 96, y = 1, z = 190 },
                        { x = 180, y = 1, z = 160 },
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
                },
                {
                    id = "light_1",
                    kind = "light",
                    position = { x = 150, y = 3, z = 68 },
                    yawDegrees = 90,
                    scale = 1,
                },
            },
        },
    },
}
