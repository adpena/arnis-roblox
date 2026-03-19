return {
    schemaVersion = "0.4.0",
    meta = {
        worldName = "SampleMultiChunkWorld",
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
                    id = "road_main_0",
                    kind = "primary",
                    material = "Asphalt",
                    color = { r = 68, g = 68, b = 68 },
                    widthStuds = 10,
                    hasSidewalk = true,
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
            buildings = {},
            water = {},
            props = {},
            landuse = {},
            barriers = {},
        },
        {
            id = "1_0",
            originStuds = { x = 256, y = 0, z = 0 },
            terrain = {
                cellSizeStuds = 4,
                width = 64,
                depth = 64,
                heights = (function()
                    local h = {}
                    for i = 1, 64 * 64 do h[i] = 0 end
                    return h
                end)(),
                material = "Grass",
            },
            roads = {
                {
                    id = "road_main_1",
                    kind = "primary",
                    material = "Asphalt",
                    color = { r = 68, g = 68, b = 68 },
                    widthStuds = 10,
                    hasSidewalk = true,
                    elevated = false,
                    tunnel = false,
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
            landuse = {},
            barriers = {},
        },
    },
}
