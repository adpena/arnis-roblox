return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local terrainHeights = table.create(16 * 16, 20)
    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "WaterAlignment",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 2,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                terrain = {
                    cellSizeStuds = 16,
                    width = 16,
                    depth = 16,
                    heights = terrainHeights,
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {},
                water = {
                    {
                        id = "lake_1",
                        kind = "water",
                        footprint = {
                            { x = 64, z = 64 },
                            { x = 128, z = 64 },
                            { x = 128, z = 128 },
                            { x = 64, z = 128 },
                        },
                        holes = {},
                    },
                },
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_WaterAlignment"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
    })

    local ray = Workspace:Raycast(Vector3.new(96, 100, 96), Vector3.new(0, -200, 0))
    Assert.truthy(ray, "expected raycast hit over lake")
    Assert.near(ray.Position.Y, 20, 1.5, "expected water surface near terrain height instead of chunk origin")

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    if worldRoot then
        worldRoot:Destroy()
    end
end
