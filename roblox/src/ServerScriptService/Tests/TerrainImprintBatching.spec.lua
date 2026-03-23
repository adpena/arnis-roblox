return function()
    local TerrainBuilder = require(script.Parent.Parent.ImportService.Builders.TerrainBuilder)
    local Assert = require(script.Parent.Assert)

    local originalFillBlock = TerrainBuilder._fillBlock
    local fillCalls = 0

    TerrainBuilder._fillBlock = function(runtimeTerrain, cf, size, material)
        fillCalls += 1
        return originalFillBlock(runtimeTerrain, cf, size, material)
    end

    local ok, err = pcall(function()
        TerrainBuilder.ImprintRoads({
            {
                id = "placeholder_without_points",
            },
            {
                segments = {
                    {
                        mode = "ground",
                        p1 = Vector3.new(0, 0, 0),
                    },
                },
            },
            {
                widthStuds = 10,
                material = "Asphalt",
                points = {
                    { x = 0, y = 0, z = 0 },
                    { x = 20, y = 0, z = 0 },
                    { x = 40, y = 0, z = 0 },
                },
            },
        }, { x = 0, y = 0, z = 0 }, nil)

        Assert.equal(
            fillCalls,
            1,
            "expected collinear road segments to batch into one terrain imprint"
        )
    end)

    TerrainBuilder._fillBlock = originalFillBlock

    if not ok then
        error(err)
    end
end
