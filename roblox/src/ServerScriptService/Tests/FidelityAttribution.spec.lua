return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "FidelityAttribution",
            generator = "test",
            source = "unit",
            metersPerStud = 0.3,
            chunkSizeStuds = 256,
            totalFeatures = 1,
        },
        chunks = {
            {
                id = "attrib_chunk",
                originStuds = { x = 0, y = 0, z = 0 },
                terrain = {
                    cellSizeStuds = 16,
                    width = 16,
                    depth = 16,
                    heights = table.create(16 * 16, 0),
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {
                    {
                        id = "attrib_building",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 16 },
                            { x = 0, z = 16 },
                        },
                        baseY = 4,
                        height = 12,
                        levels = 1,
                        roof = "flat",
                        material = "Concrete",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_FidelityAttribution"
    local importRunId = "fidelity-run-test"

    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        importRunId = importRunId,
        config = {
            BuildingMode = "shellMesh",
            TerrainMode = "none",
            RoadMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected fidelity attribution world root")

    local building =
        worldRoot:FindFirstChild("attrib_chunk"):FindFirstChild("Buildings"):FindFirstChild("attrib_building")
    Assert.truthy(building, "expected attributed building model")
    Assert.equal(
        building:GetAttribute("ArnisSourceId"),
        "attrib_building",
        "expected building to publish its authoritative source id"
    )
    Assert.equal(
        building:GetAttribute("ArnisChunkId"),
        "attrib_chunk",
        "expected building to publish its authoritative chunk id"
    )
    Assert.equal(
        building:GetAttribute("ArnisImportRunId"),
        importRunId,
        "expected building to publish the current import run id"
    )
    Assert.near(
        building:GetAttribute("ArnisImportBuildingBaseY"),
        4,
        1e-6,
        "expected building to keep publishing its resolved base height"
    )
    Assert.near(
        building:GetAttribute("ArnisImportBuildingHeight"),
        12,
        1e-6,
        "expected building to keep publishing its resolved height"
    )
    Assert.near(
        building:GetAttribute("ArnisImportBuildingTopY"),
        16,
        1e-6,
        "expected building to keep publishing its resolved top height"
    )

    worldRoot:Destroy()
end
