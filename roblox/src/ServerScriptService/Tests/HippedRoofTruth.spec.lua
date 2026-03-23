return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "HippedRoofTruth",
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
                        id = "hipped_house",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 16 },
                            { x = 0, z = 16 },
                        },
                        baseY = 0,
                        height = 18,
                        roof = "hipped",
                        material = "Brick",
                        wallColor = { r = 204, g = 170, b = 136 },
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_HippedRoofTruth"
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
    Assert.truthy(worldRoot, "expected hipped roof truth world root")

    local building =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("hipped_house")
    Assert.truthy(building, "expected rectangular hipped building")

    local roofParts = {}
    local roofWedgeParts = {}
    for _, descendant in ipairs(building:GetDescendants()) do
        if descendant:IsA("BasePart") and string.find(descendant.Name, "_roof", 1, true) then
            roofParts[#roofParts + 1] = descendant
            local specialMesh = descendant:FindFirstChildOfClass("SpecialMesh")
            if descendant:IsA("Part") and specialMesh then
                roofWedgeParts[#roofWedgeParts + 1] = descendant
            end
        end
    end

    Assert.truthy(#roofParts >= 1, "expected hipped roof to emit visible roof geometry")
    Assert.equal(
        #roofWedgeParts,
        0,
        "expected hipped roof to avoid collapsing into a single bounding-box SpecialMesh wedge"
    )

    worldRoot:Destroy()
end
