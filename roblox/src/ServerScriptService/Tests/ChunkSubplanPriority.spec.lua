return function()
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local Assert = require(script.Parent.Assert)
    local focusPoint = Vector3.new(128, 0, 128)
    local chunkSizeStuds = 256
    local forwardVector = Vector3.new(1, 0, 0)
    local observedCostById = {
        ["1_0"] = 50,
        ["0_1"] = 10,
        ["0_-1"] = 1,
    }

    Assert.equal(type(ChunkPriority.GetFeatureCount), "function", "expected chunk-level GetFeatureCount API to exist")
    Assert.equal(type(ChunkPriority.GetStreamingCost), "function", "expected chunk-level GetStreamingCost API to exist")
    Assert.equal(
        type(ChunkPriority.SortChunkIdsByPriority),
        "function",
        "expected chunk-level SortChunkIdsByPriority API to exist"
    )
    Assert.equal(
        type(ChunkPriority.SortChunkEntriesByPriority),
        "function",
        "expected chunk-level SortChunkEntriesByPriority API to exist"
    )

    local chunkRefById = {
        ["1_0"] = {
            id = "1_0",
            originStuds = { x = 256, y = 0, z = 0 },
            roads = {},
            props = {},
        },
        ["0_1"] = {
            id = "0_1",
            originStuds = { x = 0, y = 0, z = 256 },
            roads = {},
            buildings = { { id = "b1" } },
        },
        ["-1_0"] = {
            id = "-1_0",
            originStuds = { x = -256, y = 0, z = 0 },
            roads = {},
            streamingCost = 1,
        },
    }

    local chunkIds = { "0_1", "-1_0", "1_0" }
    local sortedChunkIds = ChunkPriority.SortChunkIdsByPriority(
        chunkIds,
        chunkRefById,
        focusPoint,
        chunkSizeStuds,
        forwardVector,
        observedCostById
    )
    Assert.truthy(sortedChunkIds == chunkIds, "expected chunk id sort to mutate the passed array in place")
    Assert.equal(
        table.concat(chunkIds, ","),
        "1_0,0_1,-1_0",
        "expected chunk id priority to use focus point and forward bias before lexical fallback"
    )

    local chunkEntries = {
        {
            id = "0_1",
            originStuds = { x = 0, y = 0, z = 256 },
            roads = {},
            buildings = { { id = "b1" } },
        },
        {
            id = "-1_0",
            originStuds = { x = -256, y = 0, z = 0 },
            roads = {},
            streamingCost = 1,
        },
        {
            id = "1_0",
            originStuds = { x = 256, y = 0, z = 0 },
            roads = {},
            props = {},
        },
    }
    local sortedChunkEntries = ChunkPriority.SortChunkEntriesByPriority(
        chunkEntries,
        focusPoint,
        chunkSizeStuds,
        forwardVector,
        observedCostById
    )
    Assert.truthy(sortedChunkEntries == chunkEntries, "expected chunk entry sort to mutate the passed array in place")
    Assert.equal(
        table.concat({ chunkEntries[1].id, chunkEntries[2].id, chunkEntries[3].id }, ","),
        "1_0,0_1,-1_0",
        "expected chunk entry priority to preserve chunk-level semantics"
    )

    local observedCostChunkIds = { "0_1", "0_-1" }
    local observedCostChunkRefById = {
        ["0_1"] = {
            id = "0_1",
            originStuds = { x = 0, y = 0, z = 256 },
            roads = {},
        },
        ["0_-1"] = {
            id = "0_-1",
            originStuds = { x = 0, y = 0, z = -256 },
            roads = {},
        },
    }
    ChunkPriority.SortChunkIdsByPriority(
        observedCostChunkIds,
        observedCostChunkRefById,
        focusPoint,
        chunkSizeStuds,
        forwardVector,
        observedCostById
    )
    Assert.equal(
        table.concat(observedCostChunkIds, ","),
        "0_-1,0_1",
        "expected observed runtime costs to break ties when distance and forward bias are equal"
    )

    local workItems = {
        {
            chunkId = "1_0",
            subplan = {
                id = "terrain",
                layer = "terrain",
                streamingCost = 500,
            },
            originStuds = { x = 256, y = 0, z = 0 },
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "roads:west",
                layer = "roads",
                streamingCost = 1,
            },
            originStuds = { x = 0, y = 0, z = 0 },
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "terrain",
                layer = "terrain",
                streamingCost = 999,
            },
            originStuds = { x = 0, y = 0, z = 0 },
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "landuse",
                layer = "landuse",
                streamingCost = 5,
            },
            originStuds = { x = 0, y = 0, z = 0 },
        },
        {
            chunkId = "0_1",
            subplan = {
                id = "roads",
                layer = "roads",
                streamingCost = 100,
            },
            originStuds = { x = 0, y = 0, z = 256 },
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "roads",
                layer = "roads",
                streamingCost = 2,
            },
            originStuds = { x = 0, y = 0, z = 0 },
        },
    }

    local sorted = ChunkPriority.SortWorkItems(workItems, focusPoint, chunkSizeStuds, forwardVector, observedCostById)
    Assert.truthy(sorted == workItems, "expected work item sort to mutate the passed array in place")
    local orderedIds = {}
    for _, item in ipairs(sorted) do
        table.insert(orderedIds, item.chunkId .. ":" .. item.subplan.id)
    end

    Assert.equal(
        table.concat(orderedIds, ","),
        "0_0:terrain,0_0:landuse,0_0:roads:west,0_0:roads,1_0:terrain,0_1:roads",
        "expected canonical chunk+subplan ordering before adaptive costs are applied"
    )

    Assert.equal(
        ChunkPriority.GetFeatureCount({
            id = "0_0",
            roads = { { id = "r1" }, { id = "r2" } },
            buildings = { { id = "b1" } },
            terrain = {},
        }),
        4,
        "expected chunk-level feature count accessor to derive aggregate counts when hints are absent"
    )
    Assert.equal(
        ChunkPriority.GetStreamingCost({
            id = "0_0",
            roads = { { id = "r1" }, { id = "r2" } },
            buildings = { { id = "b1" } },
            terrain = {},
        }),
        28,
        "expected chunk-level streaming cost accessor to derive weighted cost when hints are absent"
    )
    Assert.equal(
        ChunkPriority.GetFeatureCount({
            id = "0_0",
            featureCount = 7,
        }),
        7,
        "expected explicit featureCount hint to remain authoritative when present"
    )
    Assert.equal(
        ChunkPriority.GetStreamingCost({
            id = "0_0",
            streamingCost = 12,
        }),
        12,
        "expected explicit streamingCost hint to remain authoritative when present"
    )
end
