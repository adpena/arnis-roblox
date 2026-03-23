return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ImportService = require(script.Parent.Parent.ImportService)
    local RoadBuilder = require(script.Parent.Parent.ImportService.Builders.RoadBuilder)
    local BuildingBuilder = require(script.Parent.Parent.ImportService.Builders.BuildingBuilder)

    local originalRoadMeshBuildAll = RoadBuilder.MeshBuildAll
    local originalBuildingMeshBuildAll = BuildingBuilder.MeshBuildAll

    local roadReceivedMaybeYield = false
    local buildingReceivedMaybeYield = false

    RoadBuilder.MeshBuildAll = function(
        parent,
        roads,
        originStuds,
        chunk,
        preparedChunkPlan,
        maybeYield
    )
        roadReceivedMaybeYield = type(maybeYield) == "function"
        return originalRoadMeshBuildAll(
            parent,
            roads,
            originStuds,
            chunk,
            preparedChunkPlan,
            maybeYield
        )
    end

    BuildingBuilder.MeshBuildAll = function(
        parent,
        buildings,
        originStuds,
        chunk,
        config,
        maybeYield
    )
        buildingReceivedMaybeYield = type(maybeYield) == "function"
        return originalBuildingMeshBuildAll(
            parent,
            buildings,
            originStuds,
            chunk,
            config,
            maybeYield
        )
    end

    local ok, err = pcall(function()
        local manifest = {
            schemaVersion = "0.4.0",
            meta = {
                worldName = "MeshModePacing",
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
                    terrain = nil,
                    roads = {
                        {
                            id = "r1",
                            kind = "secondary",
                            material = "Asphalt",
                            widthStuds = 16,
                            hasSidewalk = false,
                            points = {
                                { x = 0, y = 0, z = 16 },
                                { x = 96, y = 0, z = 16 },
                            },
                        },
                    },
                    rails = {},
                    buildings = {
                        {
                            id = "b1",
                            footprint = {
                                { x = 0, z = 0 },
                                { x = 24, z = 0 },
                                { x = 24, z = 24 },
                                { x = 0, z = 24 },
                            },
                            baseY = 0,
                            height = 18,
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

        ImportService.ImportManifest(manifest, {
            clearFirst = true,
            worldRootName = "GeneratedWorld_MeshModePacing",
            nonBlocking = true,
            frameBudgetSeconds = 1 / 240,
            config = {
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "shellMesh",
                WaterMode = "none",
                LanduseMode = "none",
            },
        })

        Assert.truthy(
            roadReceivedMaybeYield,
            "expected ImportService mesh road path to pass maybeYield callback"
        )
        Assert.truthy(
            buildingReceivedMaybeYield,
            "expected ImportService shellMesh building path to pass maybeYield callback"
        )

        local worldRoot = Workspace:FindFirstChild("GeneratedWorld_MeshModePacing")
        if worldRoot then
            worldRoot:Destroy()
        end
    end)

    RoadBuilder.MeshBuildAll = originalRoadMeshBuildAll
    BuildingBuilder.MeshBuildAll = originalBuildingMeshBuildAll

    if not ok then
        error(err)
    end
end
