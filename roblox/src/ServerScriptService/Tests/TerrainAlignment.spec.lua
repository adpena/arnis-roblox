return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local GroundSampler = require(script.Parent.Parent.ImportService.GroundSampler)
    local Assert = require(script.Parent.Assert)

    local terrainHeights = table.create(16 * 16, 20)
    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "TerrainAlignment",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 2,
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
                roads = {
                    {
                        id = "ground_road",
                        kind = "secondary",
                        material = "Asphalt",
                        widthStuds = 8,
                        hasSidewalk = false,
                        points = {
                            { x = 32, y = 20, z = 128 },
                            { x = 224, y = 20, z = 128 },
                        },
                    },
                },
                rails = {},
                buildings = {
                    {
                        id = "ground_building",
                        footprint = {
                            { x = 64, z = 64 },
                            { x = 96, z = 64 },
                            { x = 96, z = 96 },
                            { x = 64, z = 96 },
                        },
                        baseY = 28,
                        height = 24,
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

    local worldRootName = "GeneratedWorld_TerrainAlignment"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected terrain alignment world root")

    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected terrain alignment chunk folder")

    local roadsFolder = chunkFolder:FindFirstChild("Roads")
    Assert.truthy(roadsFolder, "expected roads folder")
    Assert.equal(#roadsFolder:GetChildren(), 0, "expected terrain-following roads to avoid accidental bridge parts")

    local buildingModel = chunkFolder:FindFirstChild("Buildings"):FindFirstChild("ground_building")
    Assert.truthy(buildingModel, "expected ground building model")

    local wall = buildingModel:FindFirstChild("ground_building_wall1")
    Assert.truthy(wall, "expected building wall")

    local groundY = GroundSampler.sampleWorldHeight(manifest.chunks[1], 64, 64)
    local wallBottomY = wall.Position.Y - wall.Size.Y * 0.5
    Assert.near(wallBottomY, groundY, 0.001, "expected building base to sit on sampled terrain")

    worldRoot:Destroy()
end
