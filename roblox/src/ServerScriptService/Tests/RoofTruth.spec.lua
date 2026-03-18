return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "RoofTruth",
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
                    heights = table.create(16 * 16, 0),
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {
                    {
                        id = "l_shape",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 32, z = 0 },
                            { x = 32, z = 16 },
                            { x = 16, z = 16 },
                            { x = 16, z = 32 },
                            { x = 0, z = 32 },
                        },
                        baseY = 0,
                        height = 20,
                        roof = "flat",
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

    local worldRootName = "GeneratedWorld_RoofTruth"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected roof truth world root")

    local building =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("l_shape")
    Assert.truthy(building, "expected l-shape building")

    local roofParts = {}
    for _, child in ipairs(building:GetChildren()) do
        if child:IsA("Part") and string.find(child.Name, "_roof_", 1, true) then
            roofParts[#roofParts + 1] = child
        end
    end

    Assert.truthy(
        #roofParts > 1,
        "expected flat roof to be footprint strips, not one bounding box slab"
    )

    local function pointCovered(pointX, pointZ)
        for _, roofPart in ipairs(roofParts) do
            local halfX = roofPart.Size.X * 0.5
            local halfZ = roofPart.Size.Z * 0.5
            if
                math.abs(roofPart.Position.X - pointX) <= halfX
                and math.abs(roofPart.Position.Z - pointZ) <= halfZ
            then
                return true
            end
        end
        return false
    end

    Assert.truthy(pointCovered(8, 8), "expected roof to cover occupied footprint")
    Assert.falsy(pointCovered(24, 24), "expected roof to leave empty L-shape corner uncovered")

    worldRoot:Destroy()
end
