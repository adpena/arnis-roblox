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
    Assert.truthy(execution.detailInstances > 0, "expected execution to materialize detail instances")

    local detailFolder = parent:FindFirstChild("Detail")
    Assert.truthy(detailFolder, "expected grouped landuse detail folder")
    Assert.truthy(CollectionService:HasTag(detailFolder, "LOD_DetailGroup"), "expected grouped landuse detail tag")

    parent:Destroy()
end
