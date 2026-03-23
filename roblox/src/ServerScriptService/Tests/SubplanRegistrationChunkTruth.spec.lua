return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ImportService = require(script.Parent.Parent.ImportService)

    local registrationChunk = {
        id = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        subplans = {
            { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 8 },
            { id = "landuse:nw", layer = "landuse", featureCount = 1, streamingCost = 6 },
        },
    }

    local geometryChunk = {
        id = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        terrain = {
            cellSizeStuds = 16,
            width = 8,
            depth = 8,
            heights = table.create(64, 0),
            material = "Grass",
        },
        roads = {},
        rails = {},
        barriers = {},
        buildings = {},
        water = {},
        props = {},
        landuse = {
            {
                id = "park_0",
                kind = "park",
                footprint = {
                    { x = 0, z = 0 },
                    { x = 96, z = 0 },
                    { x = 96, z = 96 },
                    { x = 0, z = 96 },
                },
            },
        },
    }

    local worldRootName = "GeneratedWorld_SubplanRegistrationChunkTruth"
    local config = {
        TerrainMode = "voxel",
        RoadMode = "none",
        BuildingMode = "none",
        WaterMode = "none",
        LanduseMode = "terrain",
    }

    ImportService.ResetSubplanState(geometryChunk.id)
    ImportService.ImportChunkSubplan(geometryChunk, registrationChunk.subplans[1], {
        worldRootName = worldRootName,
        config = config,
        registrationChunk = registrationChunk,
    })

    local ok, err = pcall(function()
        ImportService.ImportChunkSubplan(geometryChunk, registrationChunk.subplans[2], {
            worldRootName = worldRootName,
            config = config,
            registrationChunk = registrationChunk,
        })
    end)

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    if worldRoot then
        worldRoot:Destroy()
    end
    ImportService.ResetSubplanState(geometryChunk.id)

    Assert.truthy(
        ok,
        "expected registration chunk subplan metadata to satisfy terrain prerequisite for bounded landuse"
    )
    Assert.falsy(
        err,
        "expected no prerequisite failure when registration chunk carries subplan metadata"
    )
end
