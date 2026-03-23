return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ImportService = require(script.Parent.Parent.ImportService)
    local Profiler = require(script.Parent.Parent.ImportService.Profiler)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "LandusePerfTruth",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 8,
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
                water = {},
                props = {},
                barriers = {},
                landuse = {
                    {
                        id = "park_a",
                        kind = "park",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 32, z = 0 },
                            { x = 32, z = 32 },
                            { x = 0, z = 32 },
                        },
                    },
                    {
                        id = "forest_a",
                        kind = "forest",
                        footprint = {
                            { x = 40, z = 0 },
                            { x = 88, z = 0 },
                            { x = 88, z = 40 },
                            { x = 40, z = 40 },
                        },
                    },
                    {
                        id = "parking_a",
                        kind = "parking",
                        footprint = {
                            { x = 0, z = 40 },
                            { x = 32, z = 40 },
                            { x = 32, z = 72 },
                            { x = 0, z = 72 },
                        },
                    },
                    {
                        id = "park_b",
                        kind = "park",
                        footprint = {
                            { x = 96, z = 0 },
                            { x = 144, z = 0 },
                            { x = 144, z = 32 },
                            { x = 96, z = 32 },
                        },
                    },
                    {
                        id = "forest_b",
                        kind = "forest",
                        footprint = {
                            { x = 96, z = 40 },
                            { x = 152, z = 40 },
                            { x = 152, z = 96 },
                            { x = 96, z = 96 },
                        },
                    },
                    {
                        id = "parking_b",
                        kind = "parking",
                        footprint = {
                            { x = 40, z = 48 },
                            { x = 88, z = 48 },
                            { x = 88, z = 88 },
                            { x = 40, z = 88 },
                        },
                    },
                    {
                        id = "garden_a",
                        kind = "garden",
                        footprint = {
                            { x = 0, z = 88 },
                            { x = 32, z = 88 },
                            { x = 32, z = 120 },
                            { x = 0, z = 120 },
                        },
                    },
                    {
                        id = "scrub_a",
                        kind = "scrub",
                        footprint = {
                            { x = 40, z = 96 },
                            { x = 88, z = 96 },
                            { x = 88, z = 136 },
                            { x = 40, z = 136 },
                        },
                    },
                },
            },
        },
    }

    Profiler.clear()
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_LandusePerfTruth",
        config = {
            TerrainMode = "mesh",
            RoadMode = "none",
            BuildingMode = "none",
            WaterMode = "none",
            LanduseMode = "fill",
        },
    })

    local report = Profiler.generateReport()
    local planActivity = nil
    local executeActivity = nil
    for _, activity in ipairs(report.activities) do
        if activity.label == "PlanLanduse" then
            planActivity = activity
        elseif activity.label == "ExecuteLanduse" then
            executeActivity = activity
        end
    end

    Assert.truthy(planActivity, "expected PlanLanduse profiler activity")
    Assert.truthy(executeActivity, "expected ExecuteLanduse profiler activity")
    Assert.equal(planActivity.extra.featureCount, 8, "expected all landuse features to be planned")
    Assert.truthy(planActivity.extra.cellCount > 0, "expected planned cells")
    Assert.truthy(planActivity.extra.rectCount > 0, "expected planned rects")
    Assert.truthy(
        planActivity.extra.cellCount >= 200,
        "expected heavier fixture to plan many cells"
    )
    Assert.truthy(
        planActivity.extra.rectCount <= planActivity.extra.cellCount,
        "expected merged terrain rect count to stay bounded by planned cells"
    )
    Assert.equal(
        executeActivity.extra.terrainFillRects,
        planActivity.extra.rectCount,
        "expected executed terrain rects to match the planned rect count"
    )
    Assert.truthy(
        executeActivity.extra.detailInstances > 0,
        "expected landuse detail instances to be emitted"
    )
    Assert.truthy(
        executeActivity.extra.detailInstances <= planActivity.extra.cellCount,
        "expected detail instance count to stay bounded by planned cells"
    )
    Assert.truthy(
        planActivity.elapsedMs < 1500,
        "expected landuse planning to stay bounded for heavier fixture"
    )
    Assert.truthy(
        executeActivity.elapsedMs < 1500,
        "expected landuse execution to stay bounded for heavier fixture"
    )

    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_LandusePerfTruth")
    if worldRoot then
        worldRoot:Destroy()
    end
end
