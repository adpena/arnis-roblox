return function()
    local Workspace = game:GetService("Workspace")
    local CollectionService = game:GetService("CollectionService")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "RoomTruth",
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
                        id = "room_building",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 48, z = 0 },
                            { x = 48, z = 32 },
                            { x = 0, z = 32 },
                        },
                        baseY = 10,
                        levels = 2,
                        roof = "flat",
                        material = "Concrete",
                        rooms = {
                            {
                                id = "room_a",
                                name = "Room A",
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
                                id = "room_b",
                                name = "Room B",
                                footprint = {
                                    { x = 24, z = 0 },
                                    { x = 48, z = 0 },
                                    { x = 48, z = 32 },
                                    { x = 24, z = 32 },
                                },
                                floorY = 0,
                                height = 1.2,
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

    local worldRootName = "GeneratedWorld_RoomTruth"
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
    Assert.truthy(worldRoot, "expected room truth world root")

    local building = worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("room_building")
    Assert.truthy(building, "expected room building model")
    Assert.near(
        building:GetAttribute("ArnisImportBuildingBaseY"),
        10,
        1e-6,
        "expected building shell to publish its resolved base height"
    )
    Assert.near(
        building:GetAttribute("ArnisImportBuildingHeight"),
        28,
        1e-6,
        "expected building shell to publish its resolved height"
    )

    local roomsFolder = building:FindFirstChild("Rooms")
    Assert.truthy(roomsFolder, "expected Rooms folder under building model")
    Assert.truthy(
        CollectionService:HasTag(roomsFolder, "LOD_InteriorGroup"),
        "expected Rooms folder to be tagged as an interior LOD group"
    )
    Assert.equal(roomsFolder:GetAttribute("ArnisLodGroupKind"), "interior", "expected interior group kind")
    local chunkEntry = ChunkLoader.GetChunkEntry("0_0")
    Assert.truthy(chunkEntry, "expected chunk entry for room truth world")
    Assert.truthy(
        chunkEntry.lodGroups and #chunkEntry.lodGroups.interior >= 1,
        "expected registered interior lod groups"
    )
    for _, descendant in ipairs(roomsFolder:GetDescendants()) do
        if descendant:IsA("Part") then
            Assert.falsy(
                CollectionService:HasTag(descendant, "LOD_Interior"),
                "expected room descendants to rely on grouped interior ownership"
            )
        end
    end
    Assert.truthy(#roomsFolder:GetChildren() >= 2, "expected room geometry to be created")
    local floorsFolder = roomsFolder:FindFirstChild("Floors")
    Assert.truthy(floorsFolder, "expected shared floors folder under Rooms")
    local ceilingsFolder = roomsFolder:FindFirstChild("Ceilings")
    Assert.truthy(ceilingsFolder, "expected shared ceilings folder under Rooms")
    local partitionsFolder = roomsFolder:FindFirstChild("Partitions")
    Assert.truthy(partitionsFolder, "expected shared partition folder under Rooms")

    local function collectRoomParts(folder)
        local parts = {}
        for _, child in ipairs(folder:GetDescendants()) do
            if child:IsA("Part") then
                parts[#parts + 1] = child
            end
        end
        return parts
    end

    local floorParts = collectRoomParts(floorsFolder)
    local ceilingParts = collectRoomParts(ceilingsFolder)
    local roomParts = table.clone(floorParts)
    for _, part in ipairs(ceilingParts) do
        roomParts[#roomParts + 1] = part
    end
    Assert.truthy(#roomParts >= 2, "expected at least one slab per room")
    local roomFloorParts = {}
    local roomCeilingParts = {}
    local roomWallParts = {}
    for _, roomPart in ipairs(floorParts) do
        if string.find(roomPart.Name, "^floor_") then
            roomFloorParts[#roomFloorParts + 1] = roomPart
        end
    end
    for _, roomPart in ipairs(ceilingParts) do
        if string.find(roomPart.Name, "^ceiling_") then
            roomCeilingParts[#roomCeilingParts + 1] = roomPart
        end
    end
    for _, partitionPart in ipairs(collectRoomParts(partitionsFolder)) do
        if partitionPart.Name == "Wall" then
            roomWallParts[#roomWallParts + 1] = partitionPart
        end
    end
    Assert.equal(#roomFloorParts, 2, "expected rectangular rooms to collapse to one floor slab each")
    Assert.equal(
        #roomCeilingParts,
        1,
        "expected coplanar adjacent room ceilings to batch into one shared ceiling surface"
    )
    Assert.equal(
        #roomWallParts,
        1,
        "expected adjacent rooms to emit one shared interior wall without duplicating shell edges"
    )
    Assert.near(
        roomWallParts[1].Size.Y,
        12.8,
        1e-6,
        "expected shared partition height to use the overlapping vertical span of adjacent rooms"
    )

    local function pointCovered(pointX, pointZ)
        for _, roomPart in ipairs(roomParts) do
            local localPoint = roomPart.CFrame:PointToObjectSpace(Vector3.new(pointX, roomPart.Position.Y, pointZ))
            if math.abs(localPoint.X) <= roomPart.Size.X * 0.5 and math.abs(localPoint.Z) <= roomPart.Size.Z * 0.5 then
                return true
            end
        end
        return false
    end

    Assert.truthy(pointCovered(12, 16), "expected room floor coverage inside room A")
    Assert.truthy(pointCovered(36, 16), "expected room floor coverage inside room B")
    Assert.falsy(pointCovered(60, 16), "expected no room floor coverage outside building footprint")
    Assert.near(
        roomParts[1].Position.Y,
        10.1,
        1e-6,
        "expected room geometry to follow exact built building base height"
    )

    worldRoot:Destroy()
end
