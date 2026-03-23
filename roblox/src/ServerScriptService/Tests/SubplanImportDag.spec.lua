return function()
    local Workspace = game:GetService("Workspace")

    local ImportService = require(script.Parent.Parent.ImportService)
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
                    { x = 16, y = 0, z = 32 },
                    { x = 240, y = 0, z = 32 },
                },
            },
        },
        rails = {},
        buildings = {
            {
                id = "building_1",
                material = "Brick",
                baseY = 0,
                height = 24,
                roof = "flat",
                footprint = {
                    { x = 160, z = 128 },
                    { x = 224, z = 128 },
                    { x = 224, z = 192 },
                    { x = 160, z = 192 },
                },
            },
        },
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
            {
                id = "roads:west",
                layer = "roads",
                featureCount = 1,
                streamingCost = 6,
                bounds = {
                    minX = 0,
                    minY = 0,
                    maxX = 128,
                    maxY = 256,
                },
            },
            {
                id = "roads:east",
                layer = "roads",
                featureCount = 1,
                streamingCost = 6,
                bounds = {
                    minX = 128,
                    minY = 0,
                    maxX = 256,
                    maxY = 256,
                },
            },
            { id = "buildings", layer = "buildings", featureCount = 1, streamingCost = 12 },
        },
    }

    local worldRootName = "GeneratedWorld_SubplanImportDag"
    local config = {
        TerrainMode = "none",
        RoadMode = "mesh",
        BuildingMode = "none",
        WaterMode = "none",
        LanduseMode = "terrain",
    }

    local ok, err = pcall(function()
        ImportService.ResetSubplanState(chunk.id)
        ImportService.ImportChunkSubplan(chunk, chunk.subplans[2], {
            worldRootName = worldRootName,
            config = config,
        })
    end)

    Assert.falsy(ok, "expected roads subplan import to fail before landuse prerequisite")
    Assert.truthy(
        type(err) == "string" and string.find(err, "landuse", 1, true) ~= nil,
        "expected prerequisite error to mention landuse"
    )

    ImportService.ResetSubplanState(chunk.id)
    ImportService.ImportChunkSubplan(chunk, chunk.subplans[1], {
        worldRootName = worldRootName,
        config = config,
    })
    ImportService.ImportChunkSubplan(chunk, chunk.subplans[2], {
        worldRootName = worldRootName,
        config = config,
    })

    local okMissingSibling, errMissingSibling = pcall(function()
        ImportService.ImportChunkSubplan(chunk, chunk.subplans[4], {
            worldRootName = worldRootName,
            config = config,
        })
    end)

    Assert.falsy(
        okMissingSibling,
        "expected buildings subplan import to fail until every bounded roads sibling is complete"
    )
    Assert.truthy(
        type(errMissingSibling) == "string"
            and string.find(errMissingSibling, "roads", 1, true) ~= nil,
        "expected sibling prerequisite error to mention roads"
    )

    ImportService.ImportChunkSubplan(chunk, chunk.subplans[3], {
        worldRootName = worldRootName,
        config = config,
    })
    ImportService.ImportChunkSubplan(chunk, chunk.subplans[4], {
        worldRootName = worldRootName,
        config = config,
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    if worldRoot then
        worldRoot:Destroy()
    end
end
