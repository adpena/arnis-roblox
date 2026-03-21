return function()
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local Assert = require(script.Parent.Assert)

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

    local workItems = {
        {
            chunkId = "0_1",
            subplan = {
                id = "terrain",
                layer = "terrain",
                streamingCost = 500,
            },
            ring = 1,
            forwardBias = 0.1,
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "roads:west",
                layer = "roads",
                streamingCost = 1,
            },
            ring = 0,
            forwardBias = 0.5,
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "terrain",
                layer = "terrain",
                streamingCost = 999,
            },
            ring = 0,
            forwardBias = 0.5,
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "landuse",
                layer = "landuse",
                streamingCost = 5,
            },
            ring = 0,
            forwardBias = 0.5,
        },
        {
            chunkId = "1_0",
            subplan = {
                id = "roads",
                layer = "roads",
                streamingCost = 100,
            },
            ring = 0,
            forwardBias = 0.5,
        },
        {
            chunkId = "0_0",
            subplan = {
                id = "roads",
                layer = "roads",
                streamingCost = 2,
            },
            ring = 0,
            forwardBias = 0.5,
        },
    }

    local sorted = ChunkPriority.SortWorkItems(workItems)
    local orderedIds = {}
    for _, item in ipairs(sorted) do
        table.insert(orderedIds, item.chunkId .. ":" .. item.subplan.id)
    end

    Assert.equal(
        table.concat(orderedIds, ","),
        "0_0:terrain,0_0:landuse,0_0:roads:west,0_0:roads,1_0:roads,0_1:terrain",
        "expected canonical chunk+subplan ordering before adaptive costs are applied"
    )

    Assert.equal(
        ChunkPriority.GetFeatureCount({
            id = "0_0",
            featureCount = 7,
        }),
        7,
        "expected chunk-level feature count accessor to read aggregate chunk hints"
    )
    Assert.equal(
        ChunkPriority.GetStreamingCost({
            id = "0_0",
            streamingCost = 12,
        }),
        12,
        "expected chunk-level streaming cost accessor to read aggregate chunk hints"
    )
end
