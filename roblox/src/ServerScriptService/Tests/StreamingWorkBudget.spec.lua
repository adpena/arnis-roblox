return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local ImportService = require(script.Parent.Parent.ImportService)
    local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)

    local originalImportChunk = ImportService.ImportChunk
    local importOrder = {}

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
            worldName = "StreamingWorkBudgetTest",
            generator = "test",
            source = "test",
            metersPerStud = 0.3,
            chunkSizeStuds = 100,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
        },
        chunkRefs = {
            {
                id = "chunk_a",
                originStuds = { x = 0, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 1,
            },
            {
                id = "chunk_b",
                originStuds = { x = 100, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 1,
            },
            {
                id = "chunk_c",
                originStuds = { x = 200, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 1,
            },
        },
        GetChunk = function(_, chunkId)
            if chunkId == "chunk_a" then
                return makeChunk(chunkId, 0)
            elseif chunkId == "chunk_b" then
                return makeChunk(chunkId, 100)
            end
            return makeChunk(chunkId, 200)
        end,
    }

    local options = {
        worldRootName = "StreamingWorkBudgetWorld",
        config = {
            StreamingEnabled = true,
            StreamingTargetRadius = 500,
            HighDetailRadius = 500,
            ChunkSizeStuds = 100,
            StreamingMaxWorkItemsPerUpdate = 2,
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

    local ok, err = xpcall(function()
        ChunkLoader.Clear()
        StreamingService.Start(manifest, options)

        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(
            #importOrder,
            2,
            "expected one streaming update to respect the max work-item budget"
        )
        Assert.equal(importOrder[1], "chunk_a", "expected nearest chunk to load first")
        Assert.equal(importOrder[2], "chunk_b", "expected second-nearest chunk to load second")

        StreamingService.Update(Vector3.new(0, 0, 0))
        Assert.equal(#importOrder, 3, "expected deferred work to remain queued for the next update")
        Assert.equal(
            importOrder[3],
            "chunk_c",
            "expected final queued chunk to import on the second update"
        )
    end, debug.traceback)

    ImportService.ImportChunk = originalImportChunk
    StreamingService.Stop()
    local worldRoot = Workspace:FindFirstChild("StreamingWorkBudgetWorld")
    if worldRoot then
        worldRoot:Destroy()
    end
    ChunkLoader.Clear()

    if not ok then
        error(err, 0)
    end
end
