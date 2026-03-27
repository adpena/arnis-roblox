return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "OpaqueCivicFacadeTruth",
            generator = "test",
            source = "unit",
            metersPerStud = 0.3,
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
                    heights = table.create(16 * 16, 0),
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {
                    {
                        id = "civic_limestone",
                        name = "State Capitol Annex",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 36, z = 0 },
                            { x = 36, z = 28 },
                            { x = 0, z = 28 },
                        },
                        baseY = 0,
                        height = 28,
                        levels = 6,
                        roof = "flat",
                        usage = "government",
                        material = "Limestone",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_OpaqueCivicFacadeTruth"
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
    Assert.truthy(worldRoot, "expected civic facade truth world root")

    local building = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("civic_limestone")
    Assert.truthy(building, "expected imported civic building")
    local shellFolder = building:FindFirstChild("Shell")
    Assert.truthy(shellFolder, "expected shell folder for civic shell-mesh building")

    local glassFacadePartCount = 0
    for _, descendant in ipairs(building:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Material == Enum.Material.Glass then
            glassFacadePartCount += 1
        end
    end

    Assert.equal(
        glassFacadePartCount,
        0,
        "expected opaque civic shell to avoid fabricated glass facade bands"
    )

    for _, descendant in ipairs(shellFolder:GetDescendants()) do
        if descendant:IsA("BasePart") then
            Assert.equal(
                descendant.Transparency,
                0,
                "expected opaque civic shell geometry to stay non-transparent in shell-mesh mode"
            )
        end
    end

    worldRoot:Destroy()
end
