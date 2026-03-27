return function()
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local Assert = require(script.Parent.Assert)

    local focusPoint = Vector3.new(0, 0, 0)
    local chunkSize = 100

    local chunkRefById = {
        nearest = {
            id = "nearest",
            originStuds = { x = 0, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        forward_hot = {
            id = "forward_hot",
            originStuds = { x = 20, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        near_behind = {
            id = "near_behind",
            originStuds = { x = -120, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        forward_fast = {
            id = "forward_fast",
            originStuds = { x = 20, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
    }

    local ids = { "forward_hot", "near_behind", "nearest" }
    ChunkPriority.SortChunkIdsByPriority(ids, chunkRefById, focusPoint, chunkSize, Vector3.new(1, 0, 0), {
        forward_hot = 10,
        nearest = 900,
    })

    Assert.equal(ids[1], "nearest", "expected nearest chunk to outrank farther same-band chunks")
    Assert.equal(ids[2], "forward_hot", "expected forward chunk next within same band")
    Assert.equal(ids[3], "near_behind", "expected behind chunk last within same band")

    local tiedIds = { "forward_hot", "near_behind", "forward_fast" }
    ChunkPriority.SortChunkIdsByPriority(tiedIds, chunkRefById, focusPoint, chunkSize, Vector3.new(1, 0, 0), {
        forward_hot = 900,
        forward_fast = 10,
    })

    Assert.equal(tiedIds[1], "forward_fast", "expected observed cost to break ties within equivalent forward chunks")
    Assert.equal(tiedIds[2], "forward_hot", "expected hotter equivalent forward chunk after cooler one")
    Assert.equal(tiedIds[3], "near_behind", "expected behind chunk to remain last in tied case")
end
