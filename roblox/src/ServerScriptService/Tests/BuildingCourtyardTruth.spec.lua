return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "BuildingCourtyardTruth",
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
                        id = "courtyard_building",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 48, z = 0 },
                            { x = 48, z = 48 },
                            { x = 0, z = 48 },
                            { x = 0, z = 0 },
                        },
                        holes = {
                            {
                                { x = 16, z = 16 },
                                { x = 32, z = 16 },
                                { x = 32, z = 32 },
                                { x = 16, z = 32 },
                                { x = 16, z = 16 },
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

    local worldRootName = "GeneratedWorld_BuildingCourtyardTruth"
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
    Assert.truthy(worldRoot, "expected courtyard test world root")

    local buildingModel = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("courtyard_building")
    Assert.truthy(buildingModel, "expected courtyard building model")

    local wallParts = {}
    for _, descendant in ipairs(buildingModel:GetDescendants()) do
        if descendant:IsA("BasePart") and string.find(descendant.Name, "_wall", 1, true) then
            wallParts[#wallParts + 1] = descendant
        end
    end

    Assert.truthy(#wallParts >= 8, "expected outer and inner wall loops for courtyard building")

    local roofProbe = Workspace:GetPartBoundsInBox(CFrame.new(24, 12.2, 24), Vector3.new(6, 2, 6))
    local overlappingRoofParts = 0
    for _, part in ipairs(roofProbe) do
        if part:IsDescendantOf(buildingModel) and string.find(part.Name, "_roof", 1, true) then
            overlappingRoofParts += 1
        end
    end

    Assert.equal(
        overlappingRoofParts,
        0,
        "expected courtyard void to remain open instead of being roofed over"
    )

    worldRoot:Destroy()
end
