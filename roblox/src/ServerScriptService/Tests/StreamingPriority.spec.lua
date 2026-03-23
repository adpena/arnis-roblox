return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local ImportService = require(script.Parent.Parent.ImportService)
    local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)

    local originalImportChunk = ImportService.ImportChunk
    local originalImportChunkSubplan = ImportService.ImportChunkSubplan
    local importOrder = {}
    local subplanImportCount = 0

    local function makeChunk(chunkId, originX)
        return {
            id = chunkId,
            originStuds = { x = originX, y = 0, z = 0 },
            roads = {},
            rails = {},
            buildings = {},
            water = {},
            props = {},
            landuse = {},
            barriers = {},
        }
    end

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "StreamingPriorityTest",
            generator = "test",
            source = "test",
            metersPerStud = 0.3,
            chunkSizeStuds = 100,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
        },
        chunkRefs = {
            {
                id = "near_heavy",
                originStuds = { x = -40, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 40,
                streamingCost = 800,
            },
            {
                id = "near_light",
                originStuds = { x = 20, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 2,
                streamingCost = 10,
            },
            {
                id = "far_light",
                originStuds = { x = 120, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 1,
            },
            {
                id = "near_behind",
                originStuds = { x = -120, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 1,
            },
        },
        GetChunk = function(_, chunkId)
            if chunkId == "near_heavy" then
                return makeChunk(chunkId, -40)
            elseif chunkId == "near_light" then
                return makeChunk(chunkId, 20)
            elseif chunkId == "near_behind" then
                return makeChunk(chunkId, -120)
            end
            return makeChunk(chunkId, 120)
        end,
    }

    local options = {
        worldRootName = "StreamingPriorityWorld",
        config = {
            StreamingEnabled = true,
            StreamingTargetRadius = 400,
            HighDetailRadius = 400,
            ChunkSizeStuds = 100,
            TerrainMode = "none",
            RoadMode = "mesh",
            BuildingMode = "shellMesh",
            WaterMode = "mesh",
            LanduseMode = "fill",
        },
        preferredLookVector = Vector3.new(1, 0, 0),
    }

    ImportService.ImportChunk = function(chunk, importOptions)
        importOrder[#importOrder + 1] = chunk.id
        return originalImportChunk(chunk, importOptions)
    end
    ImportService.ImportChunkSubplan = function(...)
        subplanImportCount += 1
        return originalImportChunkSubplan(...)
    end

    local ok, err = xpcall(function()
        ChunkLoader.Clear()
        StreamingService.Start(manifest, options)
        StreamingService.Update(Vector3.new(0, 0, 0))

        Assert.equal(#importOrder, 4, "expected all candidate chunks to load")
        Assert.equal(
            importOrder[1],
            "near_heavy",
            "expected nearest chunk in same distance band to load first"
        )
        Assert.equal(
            importOrder[2],
            "near_light",
            "expected slightly farther chunk in same distance band to defer"
        )
        Assert.equal(
            importOrder[3],
            "near_behind",
            "expected behind-player chunk in same band after forward chunks"
        )
        Assert.equal(
            importOrder[4],
            "far_light",
            "expected farther chunk band to load after nearer band"
        )
        Assert.equal(
            subplanImportCount,
            0,
            "expected rollout-off streaming to preserve whole-chunk fallback"
        )

        local subplanKey = ChunkPriority.BuildPriorityKey(
            {
                chunkId = "near_heavy",
                originStuds = { x = 0, y = 0, z = 0 },
                subplan = {
                    id = "roads_dense",
                    layer = "roads",
                    bounds = { minX = 0, minY = 0, maxX = 20, maxY = 20 },
                    streamingCost = 20,
                    featureCount = 4,
                },
                roads = {},
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
            Vector3.new(0, 0, 0),
            100,
            nil,
            {
                ["near_heavy"] = 5,
                ["near_heavy::roads_dense"] = 17,
            },
            0
        )
        Assert.equal(
            subplanKey.observedCost,
            17,
            "expected subplan-specific observed cost to override chunk-level cost"
        )
    end, debug.traceback)

    ImportService.ImportChunk = originalImportChunk
    ImportService.ImportChunkSubplan = originalImportChunkSubplan
    StreamingService.Stop()
    local worldRoot = Workspace:FindFirstChild("StreamingPriorityWorld")
    if worldRoot then
        worldRoot:Destroy()
    end
    ChunkLoader.Clear()

    if not ok then
        error(err, 0)
    end
end
