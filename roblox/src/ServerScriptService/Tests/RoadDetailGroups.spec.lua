return function()
    local Workspace = game:GetService("Workspace")
    local CollectionService = game:GetService("CollectionService")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "RoadDetailGroups",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 1,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        id = "main_road",
                        kind = "secondary",
                        material = "Asphalt",
                        widthStuds = 18,
                        lit = true,
                        oneway = true,
                        hasSidewalk = false,
                        points = {
                            { x = 0, y = 0, z = 50 },
                            { x = 150, y = 0, z = 50 },
                        },
                    },
                },
                buildings = {},
                water = {},
                props = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_RoadDetailGroups"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            BuildingMode = "none",
            TerrainMode = "none",
            RoadMode = "mesh",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected road detail groups world root")
    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected chunk folder")
    local roadsFolder = chunkFolder:FindFirstChild("Roads")
    Assert.truthy(roadsFolder, "expected roads folder")
    local detailFolder = roadsFolder:FindFirstChild("Detail")
    Assert.truthy(detailFolder, "expected shared road detail folder")
    Assert.truthy(CollectionService:HasTag(detailFolder, "LOD_DetailGroup"), "expected road detail group tag")
    Assert.equal(detailFolder:GetAttribute("ArnisLodGroupKind"), "detail", "expected detail lod group kind")

    local hasArrow = false
    local hasCenterline = false
    local hasStreetLight = false
    for _, child in ipairs(detailFolder:GetDescendants()) do
        if child:IsA("Part") and child.Name == "OnewayArrow" then
            hasArrow = true
        elseif child:IsA("Part") and child.Name == "CenterlineDash" then
            hasCenterline = true
        elseif child:IsA("Part") and child.Name == "StreetLightHead" then
            hasStreetLight = true
        end
    end
    Assert.truthy(hasArrow, "expected oneway arrows under road detail group")
    Assert.truthy(hasCenterline, "expected centerline detail under road detail group")
    Assert.truthy(hasStreetLight, "expected street light detail under road detail group")
    for _, child in ipairs(detailFolder:GetDescendants()) do
        if
            child:IsA("Instance")
            and (child.Name == "OnewayArrow" or child.Name == "StreetLightHead" or child.Name == "StreetLight")
        then
            Assert.falsy(
                CollectionService:HasTag(child, "LOD_Detail"),
                "expected road detail descendants to rely on grouped detail ownership"
            )
        end
    end

    local chunkEntry = ChunkLoader.GetChunkEntry("0_0")
    Assert.truthy(chunkEntry, "expected chunk entry for road detail world")
    Assert.truthy(chunkEntry.lodGroups and #chunkEntry.lodGroups.detail >= 1, "expected registered detail groups")
    Assert.truthy(
        chunkEntry.reactives and #chunkEntry.reactives.streetLights >= 1,
        "expected registered street-light reactives"
    )

    worldRoot:Destroy()
end
