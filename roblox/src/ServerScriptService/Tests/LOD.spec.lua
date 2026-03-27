return function()
    local Workspace = game:GetService("Workspace")
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    -- 1. Setup a test manifest with one chunk
    local testManifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "LODTest",
            generator = "test",
            source = "test",
            metersPerStud = 0.3,
            chunkSizeStuds = 100,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 1,
        },
        chunks = {
            {
                id = "lod_chunk",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        id = "r1",
                        kind = "secondary",
                        material = "Asphalt",
                        widthStuds = 8,
                        lit = true,
                        oneway = true,
                        hasSidewalk = false,
                        points = {
                            { x = 0, y = 0, z = 50 },
                            { x = 100, y = 0, z = 50 },
                        },
                    },
                },
                buildings = {
                    {
                        id = "b1",
                        footprint = { { x = 10, z = 10 }, { x = 20, z = 10 }, { x = 20, z = 20 } },
                        baseY = 0,
                        height = 10,
                        roof = "flat",
                        rooms = {
                            {
                                id = "room_1",
                                name = "Room 1",
                                footprint = {
                                    { x = 10, z = 10 },
                                    { x = 20, z = 10 },
                                    { x = 20, z = 20 },
                                },
                                floorY = 0,
                                height = 0.2,
                            },
                        },
                    },
                },
                water = {
                    {
                        id = "pond",
                        kind = "lake",
                        material = "Water",
                        footprint = {
                            { x = 60, z = 10 },
                            { x = 90, z = 10 },
                            { x = 90, z = 40 },
                            { x = 60, z = 40 },
                        },
                        holes = {},
                    },
                },
                props = {
                    {
                        id = "tree_1",
                        kind = "tree",
                        position = { x = 30, y = 0, z = 30 },
                        species = "oak",
                    },
                },
                landuse = {
                    {
                        id = "park_1",
                        kind = "park",
                        footprint = {
                            { x = 10, z = 60 },
                            { x = 40, z = 60 },
                            { x = 40, z = 90 },
                            { x = 10, z = 90 },
                        },
                    },
                },
            },
        },
    }

    local testOptions = {
        worldRootName = "LODTestWorld",
        config = {
            StreamingEnabled = true,
            StreamingTargetRadius = 1000, -- Low LOD limit
            HighDetailRadius = 500, -- High LOD limit
            ChunkSizeStuds = 100,
            BuildingMode = "shellMesh",
            RoadMode = "mesh",
            TerrainMode = "none",
            WaterMode = "mesh",
            LanduseMode = "terrain",
        },
    }

    local function getBuildingsCount()
        local worldRoot = Workspace:FindFirstChild("LODTestWorld")
        if not worldRoot then
            return 0
        end
        local chunkFolder = worldRoot:FindFirstChild("lod_chunk")
        if not chunkFolder then
            return 0
        end
        local buildingsFolder = chunkFolder:FindFirstChild("Buildings")
        if not buildingsFolder then
            return 0
        end
        return #buildingsFolder:GetChildren()
    end

    local function getRoadsCount()
        local worldRoot = Workspace:FindFirstChild("LODTestWorld")
        if not worldRoot then
            return 0
        end
        local chunkFolder = worldRoot:FindFirstChild("lod_chunk")
        if not chunkFolder then
            return 0
        end
        local roadsFolder = chunkFolder:FindFirstChild("Roads")
        if not roadsFolder then
            return 0
        end
        return #roadsFolder:GetChildren()
    end

    local function describeLoadedChunks()
        local loaded = ChunkLoader.ListLoadedChunks(testOptions.worldRootName)
        if #loaded == 0 then
            return "<none>"
        end
        return table.concat(loaded, ",")
    end

    local function getChunkEntry()
        return ChunkLoader.GetChunkEntry("lod_chunk", testOptions.worldRootName)
    end

    local function getPrimaryLodGroup(kind)
        local chunkEntry = getChunkEntry()
        Assert.truthy(chunkEntry, "expected chunk entry")
        Assert.truthy(chunkEntry.lodGroups, "expected chunk lod groups")
        local groups = chunkEntry.lodGroups[kind]
        Assert.truthy(groups and #groups >= 1, "expected chunk lod group for " .. kind)
        return groups[1]
    end

    local function getPropsDetailGroup()
        local worldRoot = Workspace:FindFirstChild("LODTestWorld")
        Assert.truthy(worldRoot, "expected LOD test world root")
        local chunkFolder = worldRoot:FindFirstChild("lod_chunk")
        Assert.truthy(chunkFolder, "expected LOD chunk folder")
        local propsFolder = chunkFolder:FindFirstChild("Props")
        Assert.truthy(propsFolder, "expected props folder")
        local detailFolder = propsFolder:FindFirstChild("Detail")
        Assert.truthy(detailFolder, "expected grouped props detail")
        return detailFolder
    end

    local function getLanduseDetailGroup()
        local worldRoot = Workspace:FindFirstChild("LODTestWorld")
        Assert.truthy(worldRoot, "expected LOD test world root")
        local chunkFolder = worldRoot:FindFirstChild("lod_chunk")
        Assert.truthy(chunkFolder, "expected LOD chunk folder")
        local landuseFolder = chunkFolder:FindFirstChild("Landuse")
        Assert.truthy(landuseFolder, "expected landuse folder")
        local detailFolder = landuseFolder:FindFirstChild("Detail")
        Assert.truthy(detailFolder, "expected grouped landuse detail")
        return detailFolder
    end

    -- 2. Start streaming
    ChunkLoader.Clear()
    StreamingService.Start(testManifest, testOptions)

    -- 3. High LOD: Focal point at 0,0,0
    StreamingService.Update(Vector3.new(0, 0, 0))
    Assert.equal(getBuildingsCount() > 0, true, "expected buildings at High LOD")
    Assert.equal(getRoadsCount() > 0, true, "expected roads at High LOD")
    Assert.equal(
        getPrimaryLodGroup("detail"):GetAttribute("ArnisLodVisible"),
        true,
        "expected detail visible at High LOD"
    )
    Assert.equal(
        getPrimaryLodGroup("interior"):GetAttribute("ArnisLodVisible"),
        true,
        "expected interior visible near focal point"
    )
    Assert.equal(getPropsDetailGroup():GetAttribute("ArnisLodVisible"), true, "expected props visible at High LOD")
    Assert.equal(
        getLanduseDetailGroup():GetAttribute("ArnisLodVisible"),
        true,
        "expected landuse detail visible at High LOD"
    )

    -- 4. Low LOD: Focal point at 750,0,750 (outside 500, inside 1000)
    StreamingService.Update(Vector3.new(750, 0, 750))
    Assert.equal(getBuildingsCount() > 0, true, "expected building shells to stay resident at Low LOD")
    Assert.equal(getRoadsCount() > 0, true, "expected roads to persist at Low LOD")
    Assert.equal(
        getPrimaryLodGroup("detail"):GetAttribute("ArnisLodVisible"),
        false,
        "expected detail hidden at Low LOD"
    )
    Assert.equal(
        getPrimaryLodGroup("interior"):GetAttribute("ArnisLodVisible"),
        false,
        "expected interior hidden at Low LOD"
    )
    Assert.equal(getPropsDetailGroup():GetAttribute("ArnisLodVisible"), false, "expected props hidden at Low LOD")
    Assert.equal(
        getLanduseDetailGroup():GetAttribute("ArnisLodVisible"),
        false,
        "expected landuse detail hidden at Low LOD"
    )

    -- 5. Back to High LOD
    StreamingService.Update(Vector3.new(0, 0, 0))
    Assert.equal(getBuildingsCount() > 0, true, "expected buildings to return at High LOD")
    Assert.equal(getRoadsCount() > 0, true, "expected roads to persist after returning to High LOD")
    Assert.equal(
        getPrimaryLodGroup("detail"):GetAttribute("ArnisLodVisible"),
        true,
        "expected detail to restore at High LOD"
    )
    Assert.equal(
        getPrimaryLodGroup("interior"):GetAttribute("ArnisLodVisible"),
        true,
        "expected interior to restore at High LOD"
    )
    Assert.equal(getPropsDetailGroup():GetAttribute("ArnisLodVisible"), true, "expected props to restore at High LOD")
    Assert.equal(
        getLanduseDetailGroup():GetAttribute("ArnisLodVisible"),
        true,
        "expected landuse detail to restore at High LOD"
    )

    -- 6. Unload: Focal point at 2000,0,2000
    StreamingService.Update(Vector3.new(2000, 0, 2000))
    local loaded = ChunkLoader.ListLoadedChunks(testOptions.worldRootName)
    Assert.equal(#loaded, 0, "expected chunk to be unloaded; loaded=" .. describeLoadedChunks())

    -- Cleanup
    StreamingService.Stop()
    local worldRoot = Workspace:FindFirstChild("LODTestWorld")
    if worldRoot then
        worldRoot:Destroy()
    end
    ChunkLoader.Clear()

    local loadCalls = 0
    local lazySource = {
        meta = testManifest.meta,
        chunkRefs = {
            {
                id = "lod_chunk",
                originStuds = { x = 0, y = 0, z = 0 },
                shards = { "fake_shard" },
            },
        },
        GetChunk = function(_, chunkId)
            loadCalls += 1
            Assert.equal(chunkId, "lod_chunk", "expected lazy source to request lod_chunk")
            return testManifest.chunks[1]
        end,
    }

    ChunkLoader.Clear()
    StreamingService.Start(lazySource, testOptions)
    StreamingService.Update(Vector3.new(0, 0, 0))
    Assert.equal(loadCalls, 1, "expected lazy source to materialize chunk on first load")
    StreamingService.Update(Vector3.new(0, 0, 0))
    Assert.equal(loadCalls, 1, "expected no reload while chunk stays at same LOD")
    StreamingService.Update(Vector3.new(2000, 0, 2000))
    StreamingService.Update(Vector3.new(0, 0, 0))
    Assert.equal(loadCalls, 1, "expected lazy source to reuse cached chunk after unload and re-entry")

    StreamingService.Stop()
    worldRoot = Workspace:FindFirstChild("LODTestWorld")
    if worldRoot then
        worldRoot:Destroy()
    end
    ChunkLoader.Clear()

    local originalImportChunk = ImportService.ImportChunk
    local importCalls = 0
    ImportService.ImportChunk = function(chunk, options)
        importCalls += 1
        return originalImportChunk(chunk, options)
    end

    local ok, err = pcall(function()
        ChunkLoader.Clear()
        StreamingService.Start(testManifest, testOptions)
        StreamingService.Update(Vector3.new(0, 0, 0))
        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(importCalls, 1, "expected no-op high LOD update to skip reimport")
        StreamingService.Update(Vector3.new(750, 0, 750))
        Assert.equal(
            importCalls,
            1,
            "expected low LOD transition to preserve resident shell, props, and water without reimport"
        )
        StreamingService.Update(Vector3.new(750, 0, 750))
        Assert.equal(importCalls, 1, "expected no-op low LOD update to skip reimport")

        StreamingService.Update(Vector3.new(620, 0, 50))
        StreamingService.Update(Vector3.new(540, 0, 50))
        StreamingService.Update(Vector3.new(620, 0, 50))
        Assert.equal(importCalls, 1, "expected high/low jitter near boundary to avoid reimport churn")

        StreamingService.Update(Vector3.new(700, 0, 50))
        Assert.equal(importCalls, 1, "expected hysteresis-driven downgrade to stay rebuild-free for buildings")

        StreamingService.Update(Vector3.new(1070, 0, 50))
        Assert.equal(
            #ChunkLoader.ListLoadedChunks(testOptions.worldRootName),
            1,
            "expected low-LOD chunk to stay resident near stream radius; loaded=" .. describeLoadedChunks()
        )
        StreamingService.Update(Vector3.new(980, 0, 50))
        Assert.equal(importCalls, 1, "expected stream-radius jitter to avoid reimport churn")
        Assert.equal(
            #ChunkLoader.ListLoadedChunks(testOptions.worldRootName),
            1,
            "expected low-LOD chunk to remain resident within unload hysteresis band; loaded=" .. describeLoadedChunks()
        )

        StreamingService.Update(Vector3.new(1250, 0, 50))
        Assert.equal(
            #ChunkLoader.ListLoadedChunks(testOptions.worldRootName),
            0,
            "expected chunk to unload after leaving stream hysteresis band; loaded=" .. describeLoadedChunks()
        )
    end)

    ImportService.ImportChunk = originalImportChunk
    StreamingService.Stop()
    worldRoot = Workspace:FindFirstChild("LODTestWorld")
    if worldRoot then
        worldRoot:Destroy()
    end
    ChunkLoader.Clear()

    if not ok then
        error(err)
    end
end
