return function()
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local Assert = require(script.Parent.Assert)

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
        "0_0:terrain,0_0:landuse,0_0:roads,0_0:roads:west,1_0:roads,0_1:terrain",
        "expected canonical chunk+subplan ordering before adaptive costs are applied"
    )
end
