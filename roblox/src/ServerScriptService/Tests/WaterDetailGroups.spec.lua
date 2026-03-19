return function()
    local Workspace = game:GetService("Workspace")
    local CollectionService = game:GetService("CollectionService")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "WaterDetailGroups",
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
                    heights = table.create(16 * 16, 0),
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {},
                water = {
                    {
                        id = "river_1",
                        points = {
                            { x = 0, y = 4, z = 32 },
                            { x = 32, y = 4, z = 32 },
                            { x = 64, y = 4, z = 32 },
                        },
                        widthStuds = 10,
                    },
                    {
                        id = "lake_1",
                        footprint = {
                            { x = 96, z = 32 },
                            { x = 128, z = 32 },
                            { x = 128, z = 64 },
                            { x = 96, z = 64 },
                        },
                    },
                },
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_WaterDetailGroups"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            TerrainMode = "none",
            RoadMode = "none",
            BuildingMode = "none",
            WaterMode = "mesh",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected water detail groups world root")
    local waterFolder = worldRoot:FindFirstChild("0_0"):FindFirstChild("Water")
    Assert.truthy(waterFolder, "expected water folder")
    local detailFolder = waterFolder:FindFirstChild("Detail")
    Assert.truthy(detailFolder, "expected water detail folder")
    Assert.truthy(CollectionService:HasTag(detailFolder, "LOD_DetailGroup"), "expected water detail group tag")
    Assert.equal(detailFolder:GetAttribute("ArnisLodGroupKind"), "detail", "expected water detail lod group kind")

    local surfaceCount = 0
    for _, child in ipairs(detailFolder:GetChildren()) do
        if child:IsA("Part") and string.find(child.Name, "WaterSurface", 1, true) then
            surfaceCount += 1
            Assert.truthy(CollectionService:HasTag(child, "LOD_Detail"), "expected grouped water detail tag")
            Assert.near(
                child:GetAttribute("ArnisBaseTransparency"),
                0.4,
                1e-6,
                "expected water surface base transparency"
            )
            Assert.near(
                child:GetAttribute("BaseTransparency"),
                0.4,
                1e-6,
                "expected water surface legacy base transparency for grouped visibility/reactives"
            )
        end
    end
    Assert.truthy(surfaceCount >= 2, "expected grouped ribbon and polygon water surfaces")

    local chunkEntry = ChunkLoader.GetChunkEntry("0_0")
    Assert.truthy(chunkEntry, "expected water detail chunk entry")
    Assert.truthy(chunkEntry.lodGroups and #chunkEntry.lodGroups.detail >= 1, "expected registered water detail group")

    worldRoot:Destroy()
end
