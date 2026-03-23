return function()
    local ChunkPriority = require(script.Parent.Parent.ImportService.ChunkPriority)
    local Assert = require(script.Parent.Assert)

    local focusPoint = Vector3.new(0, 0, 0)
    local chunkSizeStuds = 100

    Assert.equal(
        type(ChunkPriority.GetFeatureCount),
        "function",
        "expected chunk-level GetFeatureCount API to exist"
    )
    Assert.equal(
        type(ChunkPriority.GetStreamingCost),
        "function",
        "expected chunk-level GetStreamingCost API to exist"
    )
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
    Assert.equal(
        type(ChunkPriority.SortWorkItems),
        "function",
        "expected subplan SortWorkItems helper to exist"
    )

    local directionalChunkRefById = {
        ahead = {
            id = "ahead",
            originStuds = { x = 0, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        behind = {
            id = "behind",
            originStuds = { x = -100, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        farther = {
            id = "farther",
            originStuds = { x = 100, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
    }

    local ids = { "farther", "behind", "ahead" }
    ChunkPriority.SortChunkIdsByPriority(
        ids,
        directionalChunkRefById,
        focusPoint,
        chunkSizeStuds,
        Vector3.new(1, 0, 0),
        nil
    )
    Assert.equal(
        ids[1],
        "ahead",
        "expected nearer forward chunk first within the current live semantics"
    )
    Assert.equal(ids[2], "behind", "expected same-band behind chunk after the forward chunk")
    Assert.equal(ids[3], "farther", "expected farther chunk after the closer distance band")

    local chunkEntries = {
        { ref = directionalChunkRefById.farther },
        { ref = directionalChunkRefById.behind },
        { ref = directionalChunkRefById.ahead },
    }
    ChunkPriority.SortChunkEntriesByPriority(
        chunkEntries,
        focusPoint,
        chunkSizeStuds,
        Vector3.new(1, 0, 0),
        nil
    )
    Assert.equal(
        chunkEntries[1].ref.id,
        "ahead",
        "expected chunk entries to preserve live chunk-level sorting"
    )
    Assert.equal(
        chunkEntries[2].ref.id,
        "behind",
        "expected chunk entry sorting to preserve forward ordering inside the same distance band"
    )
    Assert.equal(
        chunkEntries[3].ref.id,
        "farther",
        "expected chunk entry sorting to preserve band ordering"
    )

    local observedChunkRefById = {
        cool = {
            id = "cool",
            originStuds = { x = 0, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
        hot = {
            id = "hot",
            originStuds = { x = 0, y = 0, z = 0 },
            featureCount = 10,
            streamingCost = 10,
        },
    }
    local observedIds = { "hot", "cool" }
    ChunkPriority.SortChunkIdsByPriority(
        observedIds,
        observedChunkRefById,
        focusPoint,
        chunkSizeStuds,
        nil,
        {
            hot = 900,
            cool = 10,
        }
    )
    Assert.equal(
        table.concat(observedIds, ","),
        "cool,hot",
        "expected observed chunk costs to break ties after distance and direction metrics"
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

    local subplanHintKey = ChunkPriority.BuildPriorityKey({
        chunkId = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        roads = { { id = "r1" } },
        terrain = {},
        subplan = {
            id = "roads:east",
            layer = "roads",
            featureCount = 2,
            streamingCost = 3,
            bounds = {
                minX = 60,
                minY = 40,
                maxX = 90,
                maxY = 60,
            },
        },
    }, Vector3.new(50, 0, 50), chunkSizeStuds, Vector3.new(1, 0, 0), nil, 1)
    Assert.equal(
        subplanHintKey.featureCount,
        2,
        "expected subplan featureCount hints to override chunk aggregates"
    )
    Assert.equal(
        subplanHintKey.streamingCost,
        3,
        "expected subplan streamingCost hints to override chunk aggregates"
    )

    local fallbackSubplanKey = ChunkPriority.BuildPriorityKey({
        chunkId = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        roads = { { id = "r1" } },
        terrain = {},
        subplan = {
            id = "roads",
            layer = "roads",
        },
    }, focusPoint, chunkSizeStuds, nil, nil, 1)
    Assert.equal(
        fallbackSubplanKey.featureCount,
        2,
        "expected subplan work items to derive featureCount from chunk content when aggregate hints are absent"
    )
    Assert.equal(
        fallbackSubplanKey.streamingCost,
        12,
        "expected subplan work items to derive streamingCost from chunk content when aggregate hints are absent"
    )

    local boundedWorkItems = {
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = {
                id = "roads:west",
                layer = "roads",
                featureCount = 1,
                streamingCost = 3,
                bounds = {
                    minX = 0,
                    minY = 40,
                    maxX = 20,
                    maxY = 60,
                },
            },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = {
                id = "roads:east",
                layer = "roads",
                featureCount = 1,
                streamingCost = 3,
                bounds = {
                    minX = 80,
                    minY = 40,
                    maxX = 100,
                    maxY = 60,
                },
            },
        },
    }
    ChunkPriority.SortWorkItems(
        boundedWorkItems,
        Vector3.new(50, 0, 50),
        chunkSizeStuds,
        Vector3.new(1, 0, 0),
        nil
    )
    Assert.equal(
        boundedWorkItems[1].subplan.id,
        "roads:east",
        "expected subplan bounds to affect forward-biased work item ordering"
    )

    local layeredWorkItems = {
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "props", layer = "props", featureCount = 1, streamingCost = 1 },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "barriers", layer = "barriers", featureCount = 1, streamingCost = 1 },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 1 },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "rails", layer = "rails", featureCount = 1, streamingCost = 1 },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "roads", layer = "roads", featureCount = 1, streamingCost = 1 },
        },
    }
    ChunkPriority.SortWorkItems(layeredWorkItems, focusPoint, chunkSizeStuds, nil, nil)
    Assert.equal(
        table.concat({
            layeredWorkItems[1].subplan.id,
            layeredWorkItems[2].subplan.id,
            layeredWorkItems[3].subplan.id,
            layeredWorkItems[4].subplan.id,
            layeredWorkItems[5].subplan.id,
        }, ","),
        "terrain,roads,rails,barriers,props",
        "expected canonical layer ordering to include rails and barriers"
    )

    local sameChunkDagItems = {
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 1 },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = {
                id = "landuse:east",
                layer = "landuse",
                featureCount = 1,
                streamingCost = 1,
                bounds = {
                    minX = 80,
                    minY = 40,
                    maxX = 100,
                    maxY = 60,
                },
            },
        },
    }
    ChunkPriority.SortWorkItems(
        sameChunkDagItems,
        Vector3.new(50, 0, 50),
        chunkSizeStuds,
        Vector3.new(1, 0, 0),
        nil
    )
    Assert.equal(
        table.concat({ sameChunkDagItems[1].subplan.id, sameChunkDagItems[2].subplan.id }, ","),
        "terrain,landuse:east",
        "expected same-chunk subplan ordering to preserve canonical layer prerequisites ahead of bound-based forward bias"
    )

    local equalSiblingItems = {
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "roads:b", layer = "roads", featureCount = 1, streamingCost = 2 },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "roads:a", layer = "roads", featureCount = 1, streamingCost = 2 },
        },
    }
    ChunkPriority.SortWorkItems(equalSiblingItems, focusPoint, chunkSizeStuds, nil, nil)
    Assert.equal(
        table.concat({ equalSiblingItems[1].subplan.id, equalSiblingItems[2].subplan.id }, ","),
        "roads:b,roads:a",
        "expected equivalent sibling subplans to preserve manifest/source order instead of lexical ids"
    )

    local costSiblingItems = {
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = {
                id = "roads:expensive",
                layer = "roads",
                featureCount = 5,
                streamingCost = 20,
            },
        },
        {
            chunkId = "0_0",
            originStuds = { x = 0, y = 0, z = 0 },
            subplan = { id = "roads:cheap", layer = "roads", featureCount = 1, streamingCost = 2 },
        },
    }
    ChunkPriority.SortWorkItems(costSiblingItems, focusPoint, chunkSizeStuds, nil, nil)
    Assert.equal(
        table.concat({ costSiblingItems[1].subplan.id, costSiblingItems[2].subplan.id }, ","),
        "roads:cheap,roads:expensive",
        "expected subplan cost signals to outrank manifest/source order within the same layer"
    )
end
