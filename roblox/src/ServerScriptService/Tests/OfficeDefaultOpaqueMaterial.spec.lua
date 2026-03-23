return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "OfficeDefaultOpaqueMaterial",
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
                        id = "generic_office",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 20 },
                            { x = 0, z = 20 },
                        },
                        baseY = 0,
                        height = 18,
                        levels = 4,
                        material = "default",
                        roof = "flat",
                        usage = "office",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_OfficeDefaultOpaqueMaterial"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            BuildingMode = "shellParts",
            TerrainMode = "none",
            RoadMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected office default material world root")

    local building =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("generic_office")
    Assert.truthy(building, "expected imported office building")

    local shellFolder = building:FindFirstChild("Shell")
    Assert.truthy(shellFolder, "expected shell folder")

    local shellParts = {}
    for _, descendant in ipairs(shellFolder:GetDescendants()) do
        if descendant:IsA("BasePart") and not string.find(descendant.Name, "_roof", 1, true) then
            shellParts[#shellParts + 1] = descendant
        end
    end

    Assert.truthy(#shellParts >= 1, "expected office shell geometry")
    for _, shellPart in ipairs(shellParts) do
        Assert.falsy(
            shellPart.Material == Enum.Material.Glass,
            "expected default office shells to stay opaque"
        )
        Assert.near(
            shellPart.Transparency,
            0,
            1e-6,
            "expected default office shells to remain visible"
        )
    end

    worldRoot:Destroy()
end
