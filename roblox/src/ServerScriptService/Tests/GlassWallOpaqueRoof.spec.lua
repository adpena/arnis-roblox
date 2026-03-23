return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "GlassWallOpaqueRoof",
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
                        id = "glass_office",
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
                        material = "Glass",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_GlassWallOpaqueRoof"
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
    Assert.truthy(worldRoot, "expected glass wall roof truth world root")

    local building =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("glass_office")
    Assert.truthy(building, "expected glass office building")

    local roofParts = {}
    for _, descendant in ipairs(building:GetDescendants()) do
        if descendant:IsA("BasePart") and string.find(descendant.Name, "_roof", 1, true) then
            roofParts[#roofParts + 1] = descendant
        end
    end

    Assert.truthy(#roofParts >= 1, "expected glass-walled building to keep visible roof geometry")
    for _, roofPart in ipairs(roofParts) do
        Assert.falsy(
            roofPart.Material == Enum.Material.Glass,
            "expected default roof fallback to stay opaque"
        )
        Assert.near(
            roofPart.Transparency,
            0,
            1e-6,
            "expected fallback roof geometry to remain visible"
        )
    end

    worldRoot:Destroy()
end
