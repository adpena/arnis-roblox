return function()
    local Workspace = game:GetService("Workspace")
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)
    local Assert = require(script.Parent.Assert)

    -- 1. Setup a test manifest with two distant chunks
    local testManifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "StreamingTest",
            generator = "test",
            source = "test",
            metersPerStud = 1,
            chunkSizeStuds = 100,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 0,
        },
        chunks = {
            {
                id = "near_chunk",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {},
                buildings = {},
                water = {},
                props = {},
            },
            {
                id = "far_chunk",
                originStuds = { x = 2000, y = 0, z = 2000 },
                roads = {},
                buildings = {},
                water = {},
                props = {},
            },
        },
    }

    local testOptions = {
        worldRootName = "StreamingTestWorld",
        config = {
            StreamingEnabled = true,
            StreamingTargetRadius = 500,
            ChunkSizeStuds = 100,
        },
    }

    -- 2. Start streaming
    ChunkLoader.Clear()
    StreamingService.Start(testManifest, testOptions)

    -- 3. Update with focal point at 0,0,0
    StreamingService.Update(Vector3.new(0, 0, 0))

    local loaded = ChunkLoader.ListLoadedChunks(testOptions.worldRootName)
    Assert.equal(#loaded, 1, "expected 1 chunk loaded at origin")
    Assert.equal(loaded[1], "near_chunk", "expected near_chunk to be loaded")

    -- 4. Update with focal point near far_chunk
    StreamingService.Update(Vector3.new(2000, 0, 2000))

    loaded = ChunkLoader.ListLoadedChunks(testOptions.worldRootName)
    Assert.equal(#loaded, 1, "expected 1 chunk loaded at far point")
    Assert.equal(loaded[1], "far_chunk", "expected far_chunk to be loaded and near_chunk unloaded")

    -- 5. Update with focal point between them (radius 500 should see neither)
    StreamingService.Update(Vector3.new(1000, 0, 1000))
    loaded = ChunkLoader.ListLoadedChunks(testOptions.worldRootName)
    Assert.equal(#loaded, 0, "expected no chunks loaded in middle")

    -- Cleanup
    StreamingService.Stop()
    local worldRoot = Workspace:FindFirstChild("StreamingTestWorld")
    if worldRoot then
        worldRoot:Destroy()
    end
    ChunkLoader.Clear()
end
