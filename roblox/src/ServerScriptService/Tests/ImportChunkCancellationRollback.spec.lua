return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ImportService = require(script.Parent.Parent.ImportService)
    local TerrainBuilder = require(script.Parent.Parent.ImportService.Builders.TerrainBuilder)

    Workspace.Terrain:Clear()

    local chunk = {
        id = "cancelled_terrain_chunk",
        originStuds = { x = 0, y = 0, z = 0 },
        terrain = {
            cellSizeStuds = 16,
            width = 8,
            depth = 8,
            heights = table.create(8 * 8, 20),
            material = "Grass",
        },
        roads = {},
        rails = {},
        buildings = {},
        water = {},
        props = {},
        landuse = {},
        barriers = {},
    }

    local originalBuild = TerrainBuilder.Build
    local cancelAfterTerrainBuild = false

    TerrainBuilder.Build = function(parent, terrainChunk, preparedPlan)
        originalBuild(parent, terrainChunk, preparedPlan)
        cancelAfterTerrainBuild = true
    end

    local ok, chunkFolder = pcall(function()
        return ImportService.ImportChunk(chunk, {
            worldRootName = "GeneratedWorld_ImportChunkCancellationRollback",
            config = {
                TerrainMode = "paint",
                RoadMode = "none",
                BuildingMode = "none",
                WaterMode = "none",
                LanduseMode = "none",
            },
            shouldCancel = function()
                return cancelAfterTerrainBuild
            end,
        })
    end)

    TerrainBuilder.Build = originalBuild

    Assert.truthy(ok, ("expected cancelled terrain import not to throw, got: %s"):format(tostring(chunkFolder)))
    Assert.equal(chunkFolder, nil, "expected cancelled terrain import to return nil")

    local hit = Workspace:Raycast(Vector3.new(64, 100, 64), Vector3.new(0, -200, 0))
    Assert.falsy(
        hit and hit.Instance == Workspace.Terrain,
        "expected cancelled terrain import to roll back terrain writes instead of leaving a terrain footprint behind"
    )

    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_ImportChunkCancellationRollback")
    if worldRoot then
        worldRoot:Destroy()
    end
    Workspace.Terrain:Clear()
end
