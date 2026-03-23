return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoadMeshSidewalkTruth",
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
                        id = "sidewalk_road",
                        kind = "secondary",
                        material = "Asphalt",
                        widthStuds = 16,
                        hasSidewalk = true,
                        points = {
                            { x = 32, y = 0, z = 64 },
                            { x = 224, y = 0, z = 64 },
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

    local worldRootName = "GeneratedWorld_RoadMeshSidewalkTruth"
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

    local roles = {
        road = 0,
        sidewalk = 0,
        curb = 0,
    }
    local roadKinds = {}
    local roadSubkinds = {}
    local roadSourceCounts = {
        road = 0,
        sidewalk = 0,
        curb = 0,
    }
    local roadSourceIds = {
        road = {},
        sidewalk = {},
        curb = {},
    }

    for _, child in ipairs(roadsFolder:GetDescendants()) do
        if child:IsA("BasePart") then
            local role = child:GetAttribute("ArnisRoadSurfaceRole")
            if role and roles[role] ~= nil then
                roles[role] += 1
                roadSourceCounts[role] += child:GetAttribute("ArnisRoadSourceCount") or 0
                roadSourceIds[role][#roadSourceIds[role] + 1] =
                    child:GetAttribute("ArnisRoadSourceIds")
            end
            local kind = child:GetAttribute("ArnisRoadKind")
            if type(kind) == "string" and kind ~= "" then
                roadKinds[kind] = (roadKinds[kind] or 0) + 1
            end
            local subkind = child:GetAttribute("ArnisRoadSubkind")
            if type(subkind) == "string" and subkind ~= "" then
                roadSubkinds[subkind] = (roadSubkinds[subkind] or 0) + 1
            end
        end
    end

    Assert.truthy(roles.road >= 1, "expected primary road surface mesh")
    Assert.truthy(roles.sidewalk >= 1, "expected sidewalk surface mesh in road mesh mode")
    Assert.truthy(roles.curb >= 1, "expected curb surface mesh in road mesh mode")
    Assert.truthy(
        (roadKinds.secondary or 0) >= 1,
        "expected emitted road surfaces to preserve road kind"
    )
    Assert.truthy(
        (roadSubkinds.sidewalk or 0) >= 1,
        "expected emitted sidewalk surfaces to preserve sidewalk subkind"
    )
    Assert.truthy(
        (roadSubkinds.curb or 0) >= 1,
        "expected emitted curb surfaces to preserve curb subkind"
    )
    Assert.equal(
        roadSourceCounts.road,
        1,
        "expected merged road mesh to preserve one source road count"
    )
    Assert.equal(
        roadSourceCounts.sidewalk,
        1,
        "expected merged sidewalk mesh to preserve one source road count"
    )
    Assert.equal(
        roadSourceCounts.curb,
        1,
        "expected merged curb mesh to preserve one source road count"
    )
    Assert.equal(
        roadSourceIds.road[1],
        "sidewalk_road",
        "expected merged road mesh to preserve source ids"
    )
    Assert.equal(
        roadSourceIds.sidewalk[1],
        "sidewalk_road",
        "expected sidewalk mesh to preserve source ids"
    )
    Assert.equal(
        roadSourceIds.curb[1],
        "sidewalk_road",
        "expected curb mesh to preserve source ids"
    )

    worldRoot:Destroy()
end
