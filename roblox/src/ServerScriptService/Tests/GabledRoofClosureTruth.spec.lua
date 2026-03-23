return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "GabledRoofClosureTruth",
            generator = "test",
            source = "unit",
            metersPerStud = 0.3,
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
                    heights = table.create(16 * 16, 0),
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {
                    {
                        id = "gable_closure_house",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 16 },
                            { x = 0, z = 16 },
                        },
                        baseY = 0,
                        height = 18,
                        roof = "gabled",
                        usage = "residential",
                        material = "Brick",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_GabledRoofClosureTruth"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            BuildingMode = "shellParts",
            TerrainMode = "none",
            RoadMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected gabled roof closure truth world root")

    local building = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("gable_closure_house")
    Assert.truthy(building, "expected gabled roof closure building")

    local shellFolder = building:FindFirstChild("Shell")
    Assert.truthy(shellFolder, "expected shell folder")

    local closureDeck = shellFolder:FindFirstChild("gable_closure_house_roof_closure")
    Assert.truthy(closureDeck, "expected shaped gabled roof path to emit a closure deck")

    local localCenter =
        closureDeck.CFrame:PointToObjectSpace(Vector3.new(12, closureDeck.Position.Y, 8))
    Assert.truthy(
        math.abs(localCenter.X) <= closureDeck.Size.X * 0.5
            and math.abs(localCenter.Z) <= closureDeck.Size.Z * 0.5,
        "expected closure deck to cover the building footprint center"
    )

    worldRoot:Destroy()
end
