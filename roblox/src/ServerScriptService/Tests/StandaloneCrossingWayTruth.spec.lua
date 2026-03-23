return function()
    local Workspace = game:GetService("Workspace")
    local CollectionService = game:GetService("CollectionService")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "StandaloneCrossingWayTruth",
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
                        id = "crossing_way",
                        kind = "footway",
                        subkind = "crossing",
                        material = "Pavement",
                        widthStuds = 5,
                        hasSidewalk = false,
                        points = {
                            { x = 128, y = 0, z = 32 },
                            { x = 128, y = 0, z = 224 },
                        },
                    },
                },
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_StandaloneCrossingWayTruth"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            TerrainMode = "none",
            RoadMode = "mesh",
            BuildingMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected world root")
    local roadsFolder = worldRoot:FindFirstChild("0_0"):FindFirstChild("Roads")
    Assert.truthy(roadsFolder, "expected roads folder")

    local crossingSurfaceParts = 0
    local drivableRoadParts = 0
    for _, child in ipairs(roadsFolder:GetDescendants()) do
        if child:IsA("BasePart") then
            if child:GetAttribute("ArnisRoadSurfaceRole") == "crossing" then
                crossingSurfaceParts += 1
            end
            if CollectionService:HasTag(child, "Road") then
                drivableRoadParts += 1
            end
        end
    end

    Assert.truthy(
        crossingSurfaceParts >= 1,
        "expected standalone crossing way to render as crossing surface"
    )
    Assert.equal(
        drivableRoadParts,
        0,
        "expected standalone crossing way to avoid drivable road tagging"
    )

    worldRoot:Destroy()
end
