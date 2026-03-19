return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local Assert = require(script.Parent.Assert)

    local sampleManifest = ManifestLoader.LoadNamedSample("SampleManifest")

    -- 1. Initial import
    ImportService.ImportManifest(sampleManifest, {
        clearFirst = true,
        worldRootName = "OverwriteTest",
    })

    local loadedBefore = ChunkLoader.ListLoadedChunks()
    Assert.equal(#loadedBefore, 1, "expected 1 chunk loaded")
    Assert.equal(loadedBefore[1], "0_0", "expected chunk 0_0")

    -- 2. Create a minimal manifest with a DIFFERENT chunk
    local otherManifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "Other",
            generator = "test",
            source = "test",
            metersPerStud = 1,
            chunkSizeStuds = 256,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 0,
        },
        chunks = {
            {
                id = "1_1",
                originStuds = { x = 256, y = 0, z = 256 },
                roads = {},
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    -- 3. Import with sync = true
    ImportService.ImportManifest(otherManifest, {
        sync = true,
        worldRootName = "OverwriteTest",
    })

    local loadedAfter = ChunkLoader.ListLoadedChunks()
    Assert.equal(#loadedAfter, 1, "expected 1 chunk loaded after sync")
    Assert.equal(loadedAfter[1], "1_1", "expected chunk 1_1 to be the only one loaded")

    local worldRoot = Workspace:FindFirstChild("OverwriteTest")
    Assert.truthy(worldRoot:FindFirstChild("1_1"), "expected 1_1 folder to exist")
    Assert.falsy(worldRoot:FindFirstChild("0_0"), "expected 0_0 folder to be removed")

    -- Cleanup
    worldRoot:Destroy()
    ChunkLoader.Clear()
end
