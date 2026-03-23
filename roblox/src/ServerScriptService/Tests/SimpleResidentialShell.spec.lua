return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "SimpleResidentialShell",
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
                        id = "generic_apartments",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 28, z = 0 },
                            { x = 28, z = 18 },
                            { x = 0, z = 18 },
                        },
                        baseY = 0,
                        height = 16,
                        levels = 3,
                        roof = "flat",
                        usage = "apartments",
                        material = "Brick",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_SimpleResidentialShell"
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
    Assert.truthy(worldRoot, "expected simple residential world root")

    local building = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("generic_apartments")
    Assert.truthy(building, "expected imported residential building")

    local shellFolder = building:FindFirstChild("Shell")
    local detailFolder = building:FindFirstChild("Detail")
    Assert.truthy(shellFolder, "expected shell folder")
    Assert.truthy(detailFolder, "expected detail folder")

    local shellPartCount = 0
    for _, descendant in ipairs(shellFolder:GetDescendants()) do
        if descendant:IsA("BasePart") then
            shellPartCount += 1
        end
    end

    local detailPartCount = 0
    for _, descendant in ipairs(detailFolder:GetDescendants()) do
        if descendant:IsA("BasePart") then
            detailPartCount += 1
        end
    end

    Assert.truthy(shellPartCount >= 1, "expected shell geometry for sparse residential building")
    Assert.equal(
        detailPartCount,
        0,
        "expected sparse residential building to avoid fabricated facade/detail geometry"
    )

    worldRoot:Destroy()
end
