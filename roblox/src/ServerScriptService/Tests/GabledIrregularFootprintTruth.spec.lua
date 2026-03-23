return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "GabledIrregularFootprintTruth",
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
                        id = "l_shape_gabled",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 32, z = 0 },
                            { x = 32, z = 16 },
                            { x = 16, z = 16 },
                            { x = 16, z = 32 },
                            { x = 0, z = 32 },
                        },
                        baseY = 0,
                        height = 18,
                        roof = "gabled",
                        usage = "residential",
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

    local worldRootName = "GeneratedWorld_GabledIrregularFootprintTruth"
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
    Assert.truthy(worldRoot, "expected irregular gabled roof truth world root")

    local building =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("l_shape_gabled")
    Assert.truthy(building, "expected irregular gabled building")
    local shellFolder = building:FindFirstChild("Shell")
    Assert.truthy(shellFolder, "expected shell folder for irregular gabled building")
    local hasClosureDeck = false
    for _, descendant in ipairs(shellFolder:GetDescendants()) do
        if
            descendant:IsA("BasePart")
            and string.find(descendant.Name, "l_shape_gabled_roof_closure", 1, true)
        then
            hasClosureDeck = true
            break
        end
    end
    Assert.truthy(
        hasClosureDeck,
        "expected irregular gabled fallback roof to be marked as a closure deck"
    )

    local function countRoofHits(center)
        local hits = Workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(4, 4, 4))
        local count = 0
        for _, part in ipairs(hits) do
            if part:IsDescendantOf(building) and string.find(part.Name, "_roof", 1, true) then
                count += 1
            end
        end
        return count
    end

    Assert.truthy(
        countRoofHits(Vector3.new(8, 19, 8)) >= 1,
        "expected occupied footprint to remain roofed"
    )
    Assert.equal(
        countRoofHits(Vector3.new(24, 19, 24)),
        0,
        "expected irregular gabled footprint to avoid roofing the empty L-shape corner"
    )

    worldRoot:Destroy()
end
