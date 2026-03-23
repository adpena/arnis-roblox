return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "ShellMeshOwnership",
            generator = "test",
            source = "unit",
            metersPerStud = 0.3,
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
                roads = {},
                rails = {},
                buildings = {
                    {
                        id = "tower_a",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 20 },
                            { x = 0, z = 20 },
                        },
                        baseY = 0,
                        height = 18,
                        levels = 4,
                        roof = "flat",
                        usage = "office",
                        material = "Concrete",
                    },
                    {
                        id = "tower_b",
                        footprint = {
                            { x = 30, z = 0 },
                            { x = 54, z = 0 },
                            { x = 54, z = 18 },
                            { x = 30, z = 18 },
                        },
                        baseY = 0,
                        height = 16,
                        levels = 3,
                        roof = "flat",
                        usage = "commercial",
                        material = "Concrete",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_ShellMeshOwnership"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            BuildingMode = "shellMesh",
            TerrainMode = "none",
            RoadMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected shell mesh ownership world root")

    local buildingsFolder = worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings")
    Assert.truthy(buildingsFolder, "expected buildings folder")
    Assert.falsy(
        buildingsFolder:FindFirstChild("MergedMeshes"),
        "expected shellMesh path to avoid chunk-global merged shell bucket"
    )

    for _, buildingName in ipairs({ "tower_a", "tower_b" }) do
        local building = buildingsFolder:FindFirstChild(buildingName)
        Assert.truthy(building, "expected imported building model " .. buildingName)
        local shellFolder = building:FindFirstChild("Shell")
        Assert.truthy(shellFolder, "expected shell folder on " .. buildingName)

        local shellPartCount = 0
        for _, descendant in ipairs(shellFolder:GetDescendants()) do
            if descendant:IsA("BasePart") then
                shellPartCount += 1
            end
        end

        Assert.truthy(shellPartCount >= 1, "expected direct shell geometry for " .. buildingName)
    end

    worldRoot:Destroy()
end
