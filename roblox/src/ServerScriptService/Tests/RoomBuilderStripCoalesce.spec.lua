return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoomStripCoalesce",
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
                        id = "strip_merge_building",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 24 },
                            { x = 0, z = 24 },
                        },
                        baseY = 0,
                        height = 14,
                        levels = 1,
                        roof = "flat",
                        material = "Concrete",
                        rooms = {
                            {
                                id = "l_room",
                                name = "L Room",
                                footprint = {
                                    { x = 0, z = 0 },
                                    { x = 24, z = 0 },
                                    { x = 24, z = 8 },
                                    { x = 8, z = 8 },
                                    { x = 8, z = 24 },
                                    { x = 0, z = 24 },
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

    local worldRootName = "GeneratedWorld_RoomStripCoalesce"
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
    Assert.truthy(worldRoot, "expected strip coalesce world root")

    local building = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("strip_merge_building")
    Assert.truthy(building, "expected strip merge building")
    local roomsFolder = building:FindFirstChild("Rooms")
    local floorsFolder = roomsFolder and roomsFolder:FindFirstChild("Floors")
    local ceilingsFolder = roomsFolder and roomsFolder:FindFirstChild("Ceilings")
    Assert.truthy(floorsFolder, "expected Floors folder")
    Assert.truthy(ceilingsFolder, "expected Ceilings folder")

    local floorParts = {}
    local ceilingParts = {}
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

    Assert.equal(
        #floorParts,
        2,
        "expected adjacent identical scanline strips to coalesce into two floor slabs"
    )
    Assert.equal(
        #ceilingParts,
        2,
        "expected adjacent identical scanline strips to coalesce into two ceiling slabs"
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

    Assert.truthy(pointCovered(floorParts, 4, 20), "expected coverage in tall leg of L room")
    Assert.truthy(pointCovered(floorParts, 20, 4), "expected coverage in short leg of L room")
    Assert.falsy(pointCovered(floorParts, 20, 20), "expected no floor coverage in missing quadrant")
    Assert.truthy(
        pointCovered(ceilingParts, 4, 20),
        "expected ceiling coverage in tall leg of L room"
    )
    Assert.truthy(
        pointCovered(ceilingParts, 20, 4),
        "expected ceiling coverage in short leg of L room"
    )
    Assert.falsy(
        pointCovered(ceilingParts, 20, 20),
        "expected no ceiling coverage in missing quadrant"
    )

    worldRoot:Destroy()
end
