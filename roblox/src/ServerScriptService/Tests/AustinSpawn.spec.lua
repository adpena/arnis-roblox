return function()
    local AustinSpawn = require(script.Parent.Parent.ImportService.AustinSpawn)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        meta = {
            chunkSizeStuds = 256,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        kind = "footway",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 50, y = 0, z = 0 },
                        },
                    },
                    {
                        kind = "primary",
                        points = {
                            { x = 100, y = 0, z = 0 },
                            { x = 200, y = 0, z = 0 },
                        },
                    },
                },
            },
            {
                id = "5_5",
                originStuds = { x = 1280, y = 0, z = 1280 },
                roads = {
                    {
                        kind = "primary",
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 100, y = 0, z = 0 },
                        },
                    },
                },
            },
        },
    }

    local spawnPoint = AustinSpawn.findSpawnPoint(manifest, 500)
    Assert.near(
        spawnPoint.X,
        150,
        0.001,
        "expected primary road midpoint to win over nearby footway"
    )
    Assert.near(spawnPoint.Z, 0, 0.001, "expected spawn Z from selected road")
end
