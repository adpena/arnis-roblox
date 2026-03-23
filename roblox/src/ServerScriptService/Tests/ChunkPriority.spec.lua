return function()
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local Assert = require(script.Parent.Assert)

    local focusPoint = Vector3.new(0, 0, 0)
    local chunkSize = 100

    local chunkRefById = {
        near_fast = {
            id = "near_fast",
            originStuds = { x = 0, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        near_hot = {
            id = "near_hot",
            originStuds = { x = 20, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        near_behind = {
            id = "near_behind",
            originStuds = { x = -20, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
    }

    local ids = { "near_hot", "near_behind", "near_fast" }
    ChunkPriority.SortChunkIdsByPriority(
        ids,
        chunkRefById,
        focusPoint,
        chunkSize,
        Vector3.new(1, 0, 0),
        {
            near_hot = 900,
            near_fast = 10,
        }
    )

    Assert.equal(ids[1], "near_fast", "expected forward low-observed-cost chunk first")
    Assert.equal(ids[2], "near_hot", "expected forward hot chunk after cooler forward chunk")
    Assert.equal(ids[3], "near_behind", "expected behind chunk last within same band")
end
