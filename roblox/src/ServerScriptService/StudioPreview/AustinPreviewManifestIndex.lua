return {
    schemaVersion = "0.2.0",
    meta = {
        worldName = "AustinPreviewDowntown",
        generator = "arbx_roblox_export",
        source = "pipeline-export",
        metersPerStud = 1,
        chunkSizeStuds = 256,
        bbox = { minLat = 30.245, minLon = -97.765, maxLat = 30.305, maxLon = -97.715 },
        totalFeatures = 868,
        canonicalAnchor = {
            positionOffsetFromHeuristicStuds = { x = 0, y = 0, z = -192 },
            lookDirectionStuds = {
                x = 0,
                y = 0,
                z = 1,
            },
        },
        notes = {
            "exported via chunker from features",
            "studio preview subset extracted from rust/out/austin-manifest.json",
        },
    },
    shardFolder = "AustinPreviewManifestChunks",
    shards = {
        "AustinPreviewManifestIndex_001",
        "AustinPreviewManifestIndex_002",
        "AustinPreviewManifestIndex_003",
        "AustinPreviewManifestIndex_004",
    },
    chunkCount = 4,
    fragmentCount = 4,
    chunksPerShard = 1,
    chunkRefs = {
        {
            id = "-1_-1",
            originStuds = { x = -256, y = -1.198, z = -256 },
            shards = { "AustinPreviewManifestIndex_001" },
        },
        { id = "0_-1", originStuds = { x = 0, y = 2.4244, z = -256 }, shards = { "AustinPreviewManifestIndex_002" } },
        { id = "-1_0", originStuds = { x = -256, y = -1.5474, z = 0 }, shards = { "AustinPreviewManifestIndex_003" } },
        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_004" } },
    },
}
