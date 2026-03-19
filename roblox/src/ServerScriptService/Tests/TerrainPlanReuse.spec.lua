return function()
    local TerrainBuilder = require(script.Parent.Parent.ImportService.Builders.TerrainBuilder)
    local Assert = require(script.Parent.Assert)

    local chunk = {
        id = "terrain_plan_reuse",
        originStuds = { x = 0, y = 0, z = 0 },
        terrain = {
            cellSizeStuds = 16,
            width = 4,
            depth = 4,
            heights = {
                0,
                1,
                2,
                3,
                1,
                2,
                3,
                4,
                2,
                3,
                4,
                5,
                3,
                4,
                5,
                6,
            },
            material = "Grass",
        },
    }

    local firstPlan = TerrainBuilder.PrepareChunk(chunk)
    local secondPlan = TerrainBuilder.PrepareChunk(chunk)

    Assert.truthy(firstPlan, "expected terrain build plan to be created")
    Assert.equal(firstPlan, secondPlan, "expected terrain build plan to be reused for the same chunk table")
    Assert.equal(
        TerrainBuilder.GetPreparedChunkPlan(chunk),
        firstPlan,
        "expected prepared terrain build plan to stay attached to the chunk"
    )
end
