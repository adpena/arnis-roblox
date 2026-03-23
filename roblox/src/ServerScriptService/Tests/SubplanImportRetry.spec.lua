return function()
    local Workspace = game:GetService("Workspace")

    local ImportService = require(script.Parent.Parent.ImportService)
    local RoadBuilder = require(script.Parent.Parent.ImportService.Builders.RoadBuilder)
    local Assert = require(script.Parent.Assert)

    local chunk = {
        id = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        roads = {
            {
                id = "road_1",
                kind = "secondary",
                material = "Asphalt",
                widthStuds = 16,
                hasSidewalk = true,
                points = {
                    { x = 16, y = 0, z = 48 },
                    { x = 240, y = 0, z = 48 },
                },
            },
        },
        rails = {},
        buildings = {},
        water = {},
        props = {},
        landuse = {
            {
                id = "park_1",
                kind = "park",
                footprint = {
                    { x = 0, z = 0 },
                    { x = 256, z = 0 },
                    { x = 256, z = 96 },
                    { x = 0, z = 96 },
                },
            },
        },
        barriers = {},
        subplans = {
            { id = "landuse", layer = "landuse", featureCount = 1, streamingCost = 8 },
            { id = "roads", layer = "roads", featureCount = 1, streamingCost = 12 },
        },
    }

    local config = {
        TerrainMode = "none",
        RoadMode = "mesh",
        BuildingMode = "none",
        WaterMode = "none",
        LanduseMode = "terrain",
    }

    local worldRootName = "GeneratedWorld_SubplanImportRetry"
    ImportService.ResetSubplanState(chunk.id)
    ImportService.ImportChunkSubplan(chunk, chunk.subplans[1], {
        worldRootName = worldRootName,
        config = config,
    })

    local originalBuildAll = RoadBuilder.MeshBuildAll
    RoadBuilder.MeshBuildAll = function()
        error("synthetic road failure")
    end

    local ok, err = pcall(function()
        ImportService.ImportChunkSubplan(chunk, chunk.subplans[2], {
            worldRootName = worldRootName,
            config = config,
        })
    end)

    RoadBuilder.MeshBuildAll = originalBuildAll

    Assert.falsy(ok, "expected synthetic roads subplan failure")
    Assert.truthy(
        type(err) == "string" and string.find(err, "synthetic road failure", 1, true) ~= nil,
        "expected synthetic failure to surface"
    )

    local failedState = ImportService.GetSubplanState(chunk.id)
    Assert.truthy(
        failedState.failedWorkItems["0_0:roads"],
        "expected failed roads work item to be tracked"
    )
    Assert.truthy(
        failedState.importedLayers.landuse,
        "expected successful landuse prerequisite to remain tracked"
    )
    Assert.falsy(
        failedState.importedLayers.roads,
        "expected failed roads layer not to be marked imported"
    )

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected world root after selective subplan import")
    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected chunk folder")
    Assert.truthy(
        chunkFolder:FindFirstChild("Landuse"),
        "expected sibling landuse folder to survive failed retry"
    )

    ImportService.ImportChunkSubplan(chunk, chunk.subplans[2], {
        worldRootName = worldRootName,
        config = config,
    })

    local retriedState = ImportService.GetSubplanState(chunk.id)
    Assert.falsy(
        retriedState.failedWorkItems["0_0:roads"],
        "expected retry success to clear failed work item"
    )
    Assert.truthy(
        retriedState.importedLayers.roads,
        "expected retry success to mark roads imported"
    )
    Assert.truthy(
        chunkFolder:FindFirstChild("Roads"),
        "expected roads folder after successful retry"
    )
    Assert.truthy(
        chunkFolder:FindFirstChild("Landuse"),
        "expected sibling landuse folder to remain after roads retry"
    )

    worldRoot:Destroy()
    ImportService.ResetSubplanState(chunk.id)
end
