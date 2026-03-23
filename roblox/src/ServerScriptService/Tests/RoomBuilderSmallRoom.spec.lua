return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoomSmallTruth",
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
                        id = "tiny_room_building",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 12, z = 0 },
                            { x = 12, z = 12 },
                            { x = 0, z = 12 },
                        },
                        baseY = 0,
                        height = 14,
                        levels = 1,
                        roof = "flat",
                        material = "Concrete",
                        rooms = {
                            {
                                id = "tiny_triangle",
                                name = "Tiny Triangle",
                                footprint = {
                                    { x = 0, z = 0 },
                                    { x = 6, z = 0 },
                                    { x = 0, z = 8 },
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

    local worldRootName = "GeneratedWorld_RoomSmallTruth"
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
    Assert.truthy(worldRoot, "expected small room truth world root")

    local building = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("tiny_room_building")
    Assert.truthy(building, "expected tiny room building model")
    local roomsFolder = building:FindFirstChild("Rooms")
    Assert.truthy(roomsFolder, "expected Rooms folder under tiny room building")
    local floorsFolder = roomsFolder:FindFirstChild("Floors")
    Assert.truthy(floorsFolder, "expected Floors folder under tiny room building")
    local ceilingsFolder = roomsFolder:FindFirstChild("Ceilings")
    Assert.truthy(ceilingsFolder, "expected Ceilings folder under tiny room building")

    local floorParts = {}
    local ceilingParts = {}
    for _, child in ipairs(floorsFolder:GetDescendants()) do
        if child:IsA("Part") then
            if string.find(child.Name, "^floor_") then
                floorParts[#floorParts + 1] = child
            end
        end
    end
    for _, child in ipairs(ceilingsFolder:GetDescendants()) do
        if child:IsA("Part") and string.find(child.Name, "^ceiling_") then
            ceilingParts[#ceilingParts + 1] = child
        end
    end
    Assert.truthy(
        #floorParts >= 1,
        "expected at least one floor part for small non-rectangular room"
    )
    Assert.truthy(
        #ceilingParts >= 1,
        "expected at least one ceiling part for small non-rectangular room"
    )

    local function pointCovered(parts, pointX, pointZ)
        for _, part in ipairs(parts) do
            local localPoint =
                part.CFrame:PointToObjectSpace(Vector3.new(pointX, part.Position.Y, pointZ))
            if
                math.abs(localPoint.X) <= part.Size.X * 0.5
                and math.abs(localPoint.Z) <= part.Size.Z * 0.5
            then
                return true
            end
        end
        return false
    end

    Assert.truthy(
        pointCovered(floorParts, 2, 2),
        "expected floor coverage inside tiny triangular room"
    )
    Assert.falsy(
        pointCovered(floorParts, 5, 7),
        "expected no floor coverage in bounding-box area outside tiny triangular room"
    )
    Assert.truthy(
        pointCovered(ceilingParts, 2, 2),
        "expected ceiling coverage inside tiny triangular room"
    )
    Assert.falsy(
        pointCovered(ceilingParts, 5, 7),
        "expected no ceiling coverage in bounding-box area outside tiny triangular room"
    )

    worldRoot:Destroy()
end
