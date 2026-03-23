return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local GroundSampler = require(script.Parent.Parent.ImportService.GroundSampler)
    local Assert = require(script.Parent.Assert)

    local terrainHeights = table.create(16 * 16, 20)
    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "TerrainSurfaceHeightTruth",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 1,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                terrain = {
                    cellSizeStuds = 16,
                    width = 16,
                    depth = 16,
                    heights = terrainHeights,
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_TerrainSurfaceHeightTruth"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            TerrainMode = "paint",
            RoadMode = "none",
            BuildingMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local expectedGroundY = GroundSampler.sampleRenderedSurfaceHeight(manifest.chunks[1], 128, 128)
    local ray = Workspace:Raycast(Vector3.new(128, 100, 128), Vector3.new(0, -200, 0))

    Assert.truthy(ray, "expected terrain raycast hit")
    Assert.truthy(ray.Instance == Workspace.Terrain, "expected raycast to hit terrain")
    Assert.near(
        ray.Position.Y,
        expectedGroundY,
        0.75,
        ("expected terrain surface height to stay close to rendered terrain height; got terrainY=%s expectedY=%s"):format(
            tostring(ray.Position.Y),
            tostring(expectedGroundY)
        )
    )

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    if worldRoot then
        worldRoot:Destroy()
    end
end
