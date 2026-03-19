return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "RoomCoplanarMerge",
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
                        id = "merge_building",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 48, z = 0 },
                            { x = 48, z = 32 },
                            { x = 0, z = 32 },
                        },
                        baseY = 0,
                        levels = 1,
                        roof = "flat",
                        material = "Concrete",
                        rooms = {
                            {
                                id = "left",
                                footprint = {
                                    { x = 0, z = 0 },
                                    { x = 24, z = 0 },
                                    { x = 24, z = 32 },
                                    { x = 0, z = 32 },
                                },
                                floorY = 0,
                                height = 0.2,
                                floorMaterial = "WoodPlanks",
                            },
                            {
                                id = "right",
                                footprint = {
                                    { x = 24, z = 0 },
                                    { x = 48, z = 0 },
                                    { x = 48, z = 32 },
                                    { x = 24, z = 32 },
                                },
                                floorY = 0,
                                height = 0.2,
                                floorMaterial = "WoodPlanks",
                            },
                        },
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_RoomCoplanarMerge"
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
    Assert.truthy(worldRoot, "expected coplanar merge world root")

    local building = worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("merge_building")
    Assert.truthy(building, "expected merge building model")
    local roomsFolder = building:FindFirstChild("Rooms")
    Assert.truthy(roomsFolder, "expected Rooms folder under merge building")
    local floorsFolder = roomsFolder:FindFirstChild("Floors")
    local ceilingsFolder = roomsFolder:FindFirstChild("Ceilings")
    local partitionsFolder = roomsFolder:FindFirstChild("Partitions")
    Assert.truthy(floorsFolder, "expected Floors folder under merge building")
    Assert.truthy(ceilingsFolder, "expected Ceilings folder under merge building")
    Assert.truthy(partitionsFolder, "expected Partitions folder under merge building")

    local floorParts = {}
    local ceilingParts = {}
    local partitionWalls = {}
    for _, child in ipairs(floorsFolder:GetDescendants()) do
        if child:IsA("Part") and string.find(child.Name, "^floor_") then
            floorParts[#floorParts + 1] = child
        end
    end
    for _, child in ipairs(ceilingsFolder:GetDescendants()) do
        if child:IsA("Part") and string.find(child.Name, "^ceiling_") then
            ceilingParts[#ceilingParts + 1] = child
        end
    end
    for _, child in ipairs(partitionsFolder:GetDescendants()) do
        if child:IsA("Part") and child.Name == "Wall" then
            partitionWalls[#partitionWalls + 1] = child
        end
    end

    Assert.equal(#floorParts, 1, "expected coplanar adjacent room floors to merge into one slab")
    Assert.equal(#ceilingParts, 1, "expected coplanar adjacent room ceilings to merge into one slab")
    Assert.equal(#partitionWalls, 1, "expected one shared partition wall between adjacent rooms")
    Assert.near(floorParts[1].Size.X, 48, 1e-6, "expected merged floor slab to span both rooms")
    Assert.near(ceilingParts[1].Size.X, 48, 1e-6, "expected merged ceiling slab to span both rooms")

    worldRoot:Destroy()
end
