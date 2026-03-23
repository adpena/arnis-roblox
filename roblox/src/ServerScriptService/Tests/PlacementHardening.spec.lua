return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "PlacementHardening",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 3,
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
                roads = {
                    {
                        id = "road_1",
                        kind = "primary",
                        material = "Asphalt",
                        widthStuds = 12,
                        hasSidewalk = true,
                        points = {
                            { x = 32, y = 0, z = 128 },
                            { x = 224, y = 0, z = 128 },
                        },
                    },
                },
                rails = {},
                buildings = {},
                water = {},
                props = {
                    {
                        id = "lamp_1",
                        kind = "street_lamp",
                        position = { x = 128, y = 0, z = 128 },
                        yawDegrees = 0,
                        scale = 1,
                    },
                },
                landuse = {
                    {
                        id = "park_1",
                        kind = "park",
                        material = "Grass",
                        footprint = {
                            { x = 16, z = 16 },
                            { x = 240, z = 16 },
                            { x = 240, z = 240 },
                            { x = 16, z = 240 },
                        },
                    },
                },
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_PlacementHardening"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected placement hardening world root")

    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected chunk folder")

    local landuseFolder = chunkFolder:FindFirstChild("Landuse")
    Assert.truthy(landuseFolder, "expected landuse folder")
    Assert.truthy(#landuseFolder:GetChildren() > 0, "expected landuse props to stay chunk-owned")
    local landuseDetailFolder = landuseFolder:FindFirstChild("Detail")
    Assert.truthy(landuseDetailFolder, "expected grouped landuse detail folder")
    local hasParkDetail = false
    for _, child in ipairs(landuseDetailFolder:GetDescendants()) do
        if child.Name == "ParkBench" or child.Name == "park_tree" then
            hasParkDetail = true
            break
        end
    end
    Assert.truthy(hasParkDetail, "expected park detail to live under grouped landuse detail")

    local propsFolder = chunkFolder:FindFirstChild("Props")
    Assert.truthy(propsFolder, "expected props folder")
    local detailFolder = propsFolder:FindFirstChild("Detail")
    Assert.truthy(detailFolder, "expected grouped props detail folder")
    local lamp = detailFolder:FindFirstChild("StreetLamp")
    Assert.truthy(lamp, "expected street lamp model")
    local pole = lamp:FindFirstChild("Pole")
    Assert.truthy(pole, "expected street lamp pole")
    Assert.truthy(
        math.abs(pole.Position.Z - 128) > 1,
        "expected street lamp to shift off road centerline"
    )

    worldRoot:Destroy()
end
