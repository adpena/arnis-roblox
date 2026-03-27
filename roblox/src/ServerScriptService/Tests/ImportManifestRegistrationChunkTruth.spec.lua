return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local ImportService = require(script.Parent.Parent.ImportService)

    local worldRootName = "GeneratedWorld_ImportManifestRegistrationChunkTruth"
    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "ImportManifestRegistrationChunkTruth",
            generator = "test",
            source = "test",
            metersPerStud = 0.3,
            chunkSizeStuds = 256,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 0,
        },
        chunkRefs = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                partitionVersion = "subplans.v1",
                subplans = {
                    {
                        id = "terrain",
                        layer = "terrain",
                        featureCount = 1,
                        streamingCost = 8,
                    },
                },
            },
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {},
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
                subplans = {
                    {
                        id = "terrain",
                        layer = "terrain",
                        featureCount = 1,
                        streamingCost = 8,
                    },
                    {
                        id = "landuse:nw",
                        layer = "landuse",
                        featureCount = 1,
                        streamingCost = 4,
                    },
                },
            },
        },
    }

    ChunkLoader.Clear()
    ImportService.ResetSubplanState()

    local stats = ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        startupChunkCount = 1,
        registrationChunksById = {
            ["0_0"] = manifest.chunkRefs[1],
        },
        config = {
            TerrainMode = "none",
            RoadMode = "none",
            BuildingMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
            EnableAtmosphere = false,
            EnableDayNightCycle = false,
            EnableMinimap = false,
        },
    })

    Assert.equal(stats.chunksImported, 1, "expected one imported chunk")

    local chunkEntry = ChunkLoader.GetChunkEntry("0_0", worldRootName)
    Assert.truthy(chunkEntry, "expected startup chunk to be registered")
    Assert.equal(
        chunkEntry.chunk,
        manifest.chunkRefs[1],
        "expected startup registration to keep the canonical registration chunk ref"
    )
    Assert.equal(
        chunkEntry.chunk.subplans[1].id,
        "terrain",
        "expected canonical registration chunk metadata to survive registration"
    )
    Assert.equal(
        chunkEntry.chunk.subplans[2],
        nil,
        "expected canonical registration chunk metadata to exclude materialized-only startup subplans"
    )

    local subplanState = ImportService.GetSubplanState("0_0", worldRootName)
    Assert.truthy(
        subplanState.completedWorkItems["0_0:terrain"],
        "expected canonical terrain subplan to be marked complete"
    )
    Assert.falsy(
        subplanState.completedWorkItems["0_0:landuse:nw"],
        "expected materialized-only startup subplans to stay out of registration state"
    )

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    if worldRoot then
        worldRoot:Destroy()
    end
    ChunkLoader.Clear()
    ImportService.ResetSubplanState(nil, worldRootName)
end
