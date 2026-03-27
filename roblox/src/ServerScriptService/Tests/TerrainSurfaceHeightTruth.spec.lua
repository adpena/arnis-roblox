return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local GroundSampler = require(script.Parent.Parent.ImportService.GroundSampler)
    local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)
    local Assert = require(script.Parent.Assert)

    local terrainHeights = table.create(16 * 16, 20)
    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "TerrainSurfaceHeightTruth",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 1,
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
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_TerrainSurfaceHeightTruth"
    local config = {
        TerrainMode = "paint",
        RoadMode = "none",
        BuildingMode = "none",
        WaterMode = "none",
        LanduseMode = "none",
        StreamingEnabled = true,
        StreamingTargetRadius = 512,
        HighDetailRadius = 256,
        ChunkSizeStuds = 256,
    }

    local ok, err = xpcall(function()
        ImportService.ImportManifest(manifest, {
            clearFirst = true,
            worldRootName = worldRootName,
            config = config,
        })

        local startupEntry = ChunkLoader.GetChunkEntry("0_0")
        Assert.truthy(startupEntry, "expected startup import to register terrain chunk")
        Assert.truthy(
            startupEntry.configSignature ~= nil,
            "expected startup-imported chunk to register a config signature for streaming parity"
        )
        Assert.truthy(
            startupEntry.layerSignatures ~= nil and startupEntry.layerSignatures.terrain ~= nil,
            "expected startup-imported chunk to register terrain layer signatures for streaming parity"
        )

        local worldRoot = Workspace:FindFirstChild(worldRootName)
        Assert.truthy(worldRoot, "expected terrain truth world root")
        local chunkFolder = worldRoot:FindFirstChild("0_0")
        Assert.truthy(chunkFolder, "expected terrain truth chunk folder")

        local sentinel = Instance.new("Folder")
        sentinel.Name = "StartupSentinel"
        sentinel.Parent = chunkFolder

        local expectedGroundY = GroundSampler.sampleRenderedSurfaceHeight(manifest.chunks[1], 128, 128)
        local ray = Workspace:Raycast(Vector3.new(128, 100, 128), Vector3.new(0, -200, 0))

        Assert.truthy(ray, "expected terrain raycast hit")
        Assert.truthy(ray.Instance == Workspace.Terrain, "expected raycast to hit terrain")
        Assert.near(
            ray.Position.Y,
            expectedGroundY,
            0.75,
            ("expected terrain surface height to stay close to rendered terrain height; got terrainY=%s expectedY=%s"):format(
                tostring(ray.Position.Y),
                tostring(expectedGroundY)
            )
        )

        StreamingService.Start(manifest, {
            worldRootName = worldRootName,
            config = config,
        })
        StreamingService.Update(Vector3.new(128, 0, 128))

        Assert.truthy(
            chunkFolder:FindFirstChild("StartupSentinel") ~= nil,
            "expected streaming reconciliation to preserve already-loaded startup chunk content"
        )
    end, debug.traceback)

    StreamingService.Stop()

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    if worldRoot then
        worldRoot:Destroy()
    end

    if not ok then
        error(err, 0)
    end
end
