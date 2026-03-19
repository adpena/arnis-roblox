return function()
    local Workspace = game:GetService("Workspace")
    local TerrainBuilder = require(script.Parent.Parent.ImportService.Builders.TerrainBuilder)
    local Assert = require(script.Parent.Assert)

    local terrain = Workspace.Terrain
    local originalFillBlock = terrain.FillBlock
    local fillCalls = 0

    terrain.FillBlock = function(self, cf, size, material)
        fillCalls += 1
        return originalFillBlock(self, cf, size, material)
    end

    local ok, err = pcall(function()
        TerrainBuilder.ImprintRoads({
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

        Assert.equal(fillCalls, 1, "expected collinear road segments to batch into one terrain imprint")
    end)

    terrain.FillBlock = originalFillBlock

    if not ok then
        error(err)
    end
end
