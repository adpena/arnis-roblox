return function()
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local ImportPlanCache = require(script.Parent.Parent.ImportService.ImportPlanCache)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "PlanKeyTest",
            generator = "test",
            source = "test",
            metersPerStud = 1,
            chunkSizeStuds = 100,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 1,
        },
        chunks = {
            {
                id = "plan_chunk",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        id = "road_1",
                        kind = "secondary",
                        material = "Asphalt",
                        widthStuds = 8,
                        points = {
                            { x = 0, y = 0, z = 50 },
                            { x = 100, y = 0, z = 50 },
                        },
                    },
                },
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    ChunkLoader.Clear()
    ImportPlanCache.Clear()

    local options = {
        clearFirst = true,
        worldRootName = "GeneratedWorld_PlanKey",
        configSignature = "cfg-plan-test",
        layerSignatures = {
            terrain = "none",
            roads = "mesh",
            buildings = "none",
            water = "none",
            props = "default",
            landuse = "none",
            barriers = "default",
        },
        config = {
            TerrainMode = "none",
            RoadMode = "mesh",
            BuildingMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
            EnableAtmosphere = false,
            EnableDayNightCycle = false,
        },
    }

    ImportService.ImportManifest(manifest, options)
    local firstEntry = ChunkLoader.GetChunkEntry("plan_chunk", options.worldRootName)
    Assert.truthy(firstEntry, "expected chunk entry after import")
    Assert.truthy(firstEntry.planKey, "expected registered chunk entry to expose plan key")

    ImportService.ImportManifest(manifest, options)
    local secondEntry = ChunkLoader.GetChunkEntry("plan_chunk", options.worldRootName)
    Assert.equal(secondEntry.planKey, firstEntry.planKey, "expected repeated import to preserve deterministic plan key")

    ChunkLoader.Clear()
    local worldRoot = game:GetService("Workspace"):FindFirstChild("GeneratedWorld_PlanKey")
    if worldRoot then
        worldRoot:Destroy()
    end
end
