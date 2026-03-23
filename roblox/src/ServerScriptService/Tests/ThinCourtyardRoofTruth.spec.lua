return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "ThinCourtyardRoofTruth",
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
                        id = "thin_courtyard",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 18, z = 0 },
                            { x = 18, z = 18 },
                            { x = 0, z = 18 },
                            { x = 0, z = 0 },
                        },
                        holes = {
                            {
                                { x = 3, z = 3 },
                                { x = 15, z = 3 },
                                { x = 15, z = 15 },
                                { x = 3, z = 15 },
                                { x = 3, z = 3 },
                            },
                        },
                        baseY = 0,
                        height = 12,
                        roof = "flat",
                        usage = "residential",
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

    local worldRootName = "GeneratedWorld_ThinCourtyardRoofTruth"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            BuildingMode = "part",
            TerrainMode = "none",
            RoadMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected thin courtyard roof truth world root")

    local building =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("thin_courtyard")
    Assert.truthy(building, "expected thin courtyard building model")

    local roofParts = {}
    for _, descendant in ipairs(building:GetDescendants()) do
        if descendant:IsA("BasePart") and string.find(descendant.Name, "_roof", 1, true) then
            roofParts[#roofParts + 1] = descendant
        end
    end

    Assert.truthy(#roofParts >= 1, "expected thin courtyard ring to keep roof geometry")

    local cornerProbe =
        Workspace:GetPartBoundsInBox(CFrame.new(1.5, 12.4, 1.5), Vector3.new(2, 2, 2))
    local cornerRoofParts = 0
    for _, part in ipairs(cornerProbe) do
        if part:IsDescendantOf(building) and string.find(part.Name, "_roof", 1, true) then
            cornerRoofParts += 1
        end
    end

    Assert.truthy(cornerRoofParts >= 1, "expected courtyard perimeter corner to stay roofed")

    local courtyardProbe =
        Workspace:GetPartBoundsInBox(CFrame.new(9, 12.4, 9), Vector3.new(4, 2, 4))
    local courtyardRoofParts = 0
    for _, part in ipairs(courtyardProbe) do
        if part:IsDescendantOf(building) and string.find(part.Name, "_roof", 1, true) then
            courtyardRoofParts += 1
        end
    end

    Assert.equal(courtyardRoofParts, 0, "expected thin courtyard void to remain open")

    worldRoot:Destroy()
end
