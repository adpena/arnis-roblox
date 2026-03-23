return function()
    local CollectionService = game:GetService("CollectionService")
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local LanduseBuilder = require(script.Parent.Parent.ImportService.Builders.LanduseBuilder)

    local parent = Instance.new("Folder")
    parent.Name = "LandusePlanningSpec"
    parent.Parent = Workspace

    local originStuds = { x = 0, y = 0, z = 0 }
    local chunk = {
        id = "0_0",
        originStuds = originStuds,
        terrain = {
            cellSizeStuds = 16,
            width = 16,
            depth = 16,
            heights = table.create(16 * 16, 0),
            material = "Grass",
        },
        roads = {},
    }
    local landuseList = {
        {
            id = "park_a",
            kind = "park",
            footprint = {
                { x = 0, z = 0 },
                { x = 24, z = 0 },
                { x = 24, z = 24 },
                { x = 0, z = 24 },
            },
        },
        {
            id = "parking_a",
            kind = "parking",
            footprint = {
                { x = 28, z = 0 },
                { x = 52, z = 0 },
                { x = 52, z = 24 },
                { x = 28, z = 24 },
            },
        },
    }

    local plan = LanduseBuilder.PlanAll(landuseList, originStuds, chunk)
    Assert.truthy(plan, "expected landuse plan")
    Assert.equal(plan.stats.featureCount, 2, "expected both landuse features to be planned")
    Assert.truthy(plan.stats.cellCount > 0, "expected planned landuse cells")
    Assert.truthy(plan.stats.rectCount > 0, "expected planned terrain rects")
    Assert.falsy(parent:FindFirstChild("Detail"), "planning should not materialize detail folders")

    local execution = LanduseBuilder.ExecutePlan(plan, parent)
    Assert.truthy(execution, "expected landuse execution stats")
    Assert.equal(
        execution.terrainFillRects,
        plan.stats.rectCount,
        "expected execution to fill every planned terrain rect exactly once"
    )
    Assert.truthy(
        execution.detailInstances > 0,
        "expected execution to materialize detail instances"
    )

    local detailFolder = parent:FindFirstChild("Detail")
    Assert.truthy(detailFolder, "expected grouped landuse detail folder")
    Assert.truthy(
        CollectionService:HasTag(detailFolder, "LOD_DetailGroup"),
        "expected grouped landuse detail tag"
    )
    local proceduralTree = detailFolder:FindFirstChild("park_tree")
    Assert.truthy(proceduralTree, "expected procedural park tree model")
    Assert.truthy(
        proceduralTree:FindFirstChild("Trunk"),
        "expected named trunk part for procedural tree"
    )
    Assert.truthy(
        proceduralTree:FindFirstChild("Canopy"),
        "expected named canopy part for procedural tree"
    )

    local giantPark = {
        id = "park_hot",
        kind = "park",
        footprint = {
            { x = 0, z = 0 },
            { x = 224, z = 0 },
            { x = 224, z = 224 },
            { x = 0, z = 224 },
        },
    }
    local fullHotPlan = LanduseBuilder.PlanAll({ giantPark }, originStuds, chunk)
    local boundedPlans = {
        LanduseBuilder.PlanAll({
            table.clone({
                id = giantPark.id,
                kind = giantPark.kind,
                footprint = giantPark.footprint,
                subplanBounds = {
                    minX = 0,
                    minY = 0,
                    maxX = 112,
                    maxY = 112,
                },
            }),
        }, originStuds, chunk),
        LanduseBuilder.PlanAll({
            table.clone({
                id = giantPark.id,
                kind = giantPark.kind,
                footprint = giantPark.footprint,
                subplanBounds = {
                    minX = 112,
                    minY = 0,
                    maxX = 224,
                    maxY = 112,
                },
            }),
        }, originStuds, chunk),
        LanduseBuilder.PlanAll({
            table.clone({
                id = giantPark.id,
                kind = giantPark.kind,
                footprint = giantPark.footprint,
                subplanBounds = {
                    minX = 0,
                    minY = 112,
                    maxX = 112,
                    maxY = 224,
                },
            }),
        }, originStuds, chunk),
        LanduseBuilder.PlanAll({
            table.clone({
                id = giantPark.id,
                kind = giantPark.kind,
                footprint = giantPark.footprint,
                subplanBounds = {
                    minX = 112,
                    minY = 112,
                    maxX = 224,
                    maxY = 224,
                },
            }),
        }, originStuds, chunk),
    }
    local boundedCellCount = 0
    for index, boundedPlan in ipairs(boundedPlans) do
        Assert.truthy(
            boundedPlan.stats.cellCount > 0,
            ("expected bounded hot subplan %d to keep cells"):format(index)
        )
        Assert.truthy(
            boundedPlan.stats.cellCount < fullHotPlan.stats.cellCount,
            ("expected bounded hot subplan %d to reduce cell count"):format(index)
        )
        boundedCellCount += boundedPlan.stats.cellCount
    end
    Assert.equal(
        boundedCellCount,
        fullHotPlan.stats.cellCount,
        "expected bounded hot landuse plans to partition planned cells without loss"
    )

    parent:Destroy()
end
