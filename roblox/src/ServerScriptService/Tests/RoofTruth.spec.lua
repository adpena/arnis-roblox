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

    local function collectRoofParts(model)
        local roofParts = {}
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("Part") and string.find(child.Name, "_roof", 1, true) then
                roofParts[#roofParts + 1] = child
            end
        end
        return roofParts
    end

    local roofParts = collectRoofParts(building)
    Assert.truthy(
        #roofParts > 1,
        "expected flat roof to be footprint strips, not one bounding box slab"
    )

    local function pointCovered(pointX, pointZ)
        for _, roofPart in ipairs(roofParts) do
            local localPoint =
                roofPart.CFrame:PointToObjectSpace(Vector3.new(pointX, roofPart.Position.Y, pointZ))
            if
                math.abs(localPoint.X) <= roofPart.Size.X * 0.5
                and math.abs(localPoint.Z) <= roofPart.Size.Z * 0.5
            then
                return true
            end
        end
        return false
    end

    Assert.truthy(pointCovered(8, 8), "expected roof to cover occupied footprint")
    Assert.falsy(pointCovered(24, 24), "expected roof to leave empty L-shape corner uncovered")

    local rotatedManifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "RoofRotationTruth",
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
                        id = "rotated_shape",
                        footprint = {
                            { x = 0, z = 8 },
                            { x = 8, z = 0 },
                            { x = 24, z = 16 },
                            { x = 16, z = 24 },
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

    ImportService.ImportManifest(rotatedManifest, {
        clearFirst = true,
        worldRootName = worldRootName,
    })

    worldRoot = Workspace:FindFirstChild(worldRootName)
    local rotatedBuilding =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("rotated_shape")
    Assert.truthy(rotatedBuilding, "expected rotated building")

    local rotatedRoofParts = collectRoofParts(rotatedBuilding)
    Assert.equal(#rotatedRoofParts, 1, "expected simple rotated roof to use one cheap slab")
    local rotatedRoof = rotatedRoofParts[1]
    Assert.truthy(rotatedRoof, "expected rotated roof strip")
    Assert.truthy(
        math.abs(rotatedRoof.CFrame.LookVector.X) > 0.1
            and math.abs(rotatedRoof.CFrame.LookVector.Z) > 0.1,
        "expected roof strips to rotate with the building instead of staying axis-aligned"
    )

    worldRoot:Destroy()
end
