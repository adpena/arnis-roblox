return function()
    local Workspace = game:GetService("Workspace")
    local CollectionService = game:GetService("CollectionService")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "WaterDetailGroups",
            generator = "test",
            source = "unit",
            metersPerStud = 0.3,
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
                        kind = "river",
                        material = "Water",
                        points = {
                            { x = 0, y = 4, z = 32 },
                            { x = 32, y = 4, z = 32 },
                            { x = 64, y = 4, z = 32 },
                        },
                        widthStuds = 10,
                    },
                    {
                        id = "lake_1",
                        kind = "lake",
                        material = "Water",
                        footprint = {
                            { x = 96, z = 32 },
                            { x = 128, z = 32 },
                            { x = 128, z = 64 },
                            { x = 96, z = 64 },
                        },
                        holes = {
                            {
                                { x = 108, z = 44 },
                                { x = 116, z = 44 },
                                { x = 116, z = 52 },
                                { x = 108, z = 52 },
                            },
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
    Assert.truthy(
        CollectionService:HasTag(detailFolder, "LOD_DetailGroup"),
        "expected water detail group tag"
    )
    Assert.equal(
        detailFolder:GetAttribute("ArnisLodGroupKind"),
        "detail",
        "expected water detail lod group kind"
    )

    local surfaceCount = 0
    for _, child in ipairs(detailFolder:GetChildren()) do
        if child:IsA("Part") and string.find(child.Name, "WaterSurface", 1, true) then
            surfaceCount += 1
            Assert.truthy(
                CollectionService:HasTag(child, "LOD_Detail"),
                "expected grouped water detail tag"
            )
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

    local holeCenter = Vector3.new(112, 0, 48)
    local holeCoveredByWaterSurface = false
    for _, child in ipairs(detailFolder:GetChildren()) do
        if child:IsA("Part") and string.find(child.Name, "PolygonWaterSurface", 1, true) then
            local localPoint = child.CFrame:PointToObjectSpace(holeCenter)
            if
                math.abs(localPoint.X) <= child.Size.X * 0.5
                and math.abs(localPoint.Z) <= child.Size.Z * 0.5
            then
                holeCoveredByWaterSurface = true
                break
            end
        end
    end
    Assert.falsy(
        holeCoveredByWaterSurface,
        "expected polygon water detail surfaces to respect water holes"
    )

    local chunkEntry = ChunkLoader.GetChunkEntry("0_0")
    Assert.truthy(chunkEntry, "expected water detail chunk entry")
    Assert.truthy(
        chunkEntry.lodGroups and #chunkEntry.lodGroups.detail >= 1,
        "expected registered water detail group"
    )

    worldRoot:Destroy()
end
