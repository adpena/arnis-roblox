return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoadStepsAuditTruth",
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
                        id = "steps_way",
                        kind = "steps",
                        subkind = "none",
                        hasSidewalk = false,
                        material = "Slate",
                        widthStuds = 8,
                        points = {
                            { x = 32, y = 0, z = 64 },
                            { x = 96, y = 8, z = 64 },
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

    local worldRootName = "GeneratedWorld_RoadStepsAuditTruth"
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

    local countedSteps = 0
    local sourceCount = 0
    for _, child in ipairs(roadsFolder:GetDescendants()) do
        if child:IsA("BasePart") and (child.Name == "Step" or child.Name == "FlatPath") then
            countedSteps += 1
            Assert.equal(
                child:GetAttribute("ArnisRoadSurfaceRole"),
                "road",
                "expected steps to audit as road surfaces"
            )
            Assert.equal(
                child:GetAttribute("ArnisRoadKind"),
                "steps",
                "expected steps to preserve road kind"
            )
            Assert.equal(
                child:GetAttribute("ArnisRoadSubkind"),
                "none",
                "expected steps to preserve subkind"
            )
            Assert.equal(
                child:GetAttribute("ArnisRoadSourceIds"),
                "steps_way",
                "expected steps to preserve source id"
            )
            sourceCount += child:GetAttribute("ArnisRoadSourceCount") or 0
        end
    end

    Assert.truthy(countedSteps >= 1, "expected one or more step parts")
    Assert.equal(sourceCount, 1, "expected step slabs to audit as one source road feature")

    worldRoot:Destroy()
end
