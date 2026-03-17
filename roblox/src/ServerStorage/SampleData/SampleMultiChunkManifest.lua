return {
    schemaVersion = "0.2.0",
    meta = {
        worldName = "SampleMultiChunkWorld",
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
        totalFeatures = 2,
        notes = {
            "Synthetic multi-chunk sample for importer scaffolding",
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
                    id = "road_main_0",
                    kind = "primary",
                    material = "Asphalt",
                    color = { r = 68, g = 68, b = 68 },
                    widthStuds = 10,
                    points = {
                        { x = 0, y = 2, z = 64 },
                        { x = 128, y = 2, z = 64 },
                        { x = 256, y = 2, z = 64 },
                    },
                },
            },
            rails = {},
            buildings = {},
            water = {},
            props = {},
        },
        {
            id = "1_0",
            originStuds = { x = 256, y = 0, z = 0 },
            terrain = {
                cellSizeStuds = 16,
                width = 4,
                depth = 4,
                heights = {
                    0, 0, 0, 0,
                    0, 0, 0, 0,
                    0, 0, 0, 0,
                    0, 0, 0, 0,
                },
                material = "Grass",
            },
            roads = {
                {
                    id = "road_main_1",
                    kind = "primary",
                    material = "Asphalt",
                    color = { r = 68, g = 68, b = 68 },
                    widthStuds = 10,
                    points = {
                        { x = 256, y = 2, z = 64 },
                        { x = 384, y = 2, z = 64 },
                        { x = 512, y = 2, z = 64 },
                    },
                },
            },
            rails = {},
            buildings = {},
            water = {},
            props = {},
        },
    },
}

