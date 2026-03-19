return function()
    local TerrainBuilder = require(script.Parent.Parent.ImportService.Builders.TerrainBuilder)
    local Assert = require(script.Parent.Assert)

    local chunk = {
        id = "terrain_explicit_material_preservation",
        originStuds = { x = 0, y = 0, z = 0 },
        terrain = {
            cellSizeStuds = 16,
            width = 3,
            depth = 3,
            heights = {
                0,
                0,
                0,
                0,
                40,
                0,
                0,
                0,
                0,
            },
            materials = {
                "Grass",
                "Grass",
                "Grass",
                "Grass",
                "Grass",
                "Grass",
                "Grass",
                "Grass",
                "Grass",
            },
            material = "Grass",
        },
    }

    local plan = TerrainBuilder.PrepareChunk(chunk)

    Assert.truthy(plan, "expected terrain build plan to be created")
    Assert.equal(
        plan.cellMaterials[2][2],
        Enum.Material.Grass,
        "expected explicit grass materials to survive terrain preparation even on steep cells"
    )
end
