return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local RoadChunkPlan = require(script.Parent.Parent.ImportService.RoadChunkPlan)
    local Assert = require(script.Parent.Assert)

    local originalBuild = RoadChunkPlan.build
    local buildCalls = 0

    RoadChunkPlan.build = function(...)
        buildCalls += 1
        return originalBuild(...)
    end

    local ok, err = pcall(function()
        local manifest = {
            schemaVersion = "0.2.0",
            meta = {
                worldName = "RoadChunkPlanReuse",
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
                    roads = {
                        {
                            id = "road_1",
                            kind = "secondary",
                            material = "Asphalt",
                            widthStuds = 16,
                            lit = true,
                            oneway = true,
                            hasSidewalk = false,
                            points = {
                                { x = 0, y = 0, z = 64 },
                                { x = 96, y = 0, z = 64 },
                            },
                        },
                        {
                            id = "road_2",
                            kind = "secondary",
                            material = "Asphalt",
                            widthStuds = 16,
                            lit = true,
                            oneway = false,
                            hasSidewalk = false,
                            points = {
                                { x = 0, y = 0, z = 96 },
                                { x = 96, y = 0, z = 96 },
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

        ImportService.ImportManifest(manifest, {
            clearFirst = true,
            worldRootName = "GeneratedWorld_RoadChunkPlanReuse",
            config = {
                BuildingMode = "none",
                TerrainMode = "none",
                RoadMode = "terrain",
                WaterMode = "none",
                LanduseMode = "none",
            },
        })

        Assert.equal(
            buildCalls,
            1,
            "expected one road chunk plan build for the whole imported road layer"
        )

        local worldRoot = Workspace:FindFirstChild("GeneratedWorld_RoadChunkPlanReuse")
        if worldRoot then
            worldRoot:Destroy()
        end
    end)

    RoadChunkPlan.build = originalBuild

    if not ok then
        error(err)
    end
end
