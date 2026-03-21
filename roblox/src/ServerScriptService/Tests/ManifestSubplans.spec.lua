return function()
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local Assert = require(script.Parent.Assert)
    local ServerStorage = game:GetService("ServerStorage")

    local container = Instance.new("Folder")
    container.Name = "ManifestSubplansSpecTemp"
    container.Parent = script

    local shardFolder = Instance.new("Folder")
    shardFolder.Name = "ShardFolder"
    shardFolder.Parent = container

    local shardModule = Instance.new("ModuleScript")
    shardModule.Name = "TestShard_001"
    shardModule.Source = [[
        return {
            chunks = {
                {
                    id = "0_0",
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {},
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                },
            },
        }
    ]]
    shardModule.Parent = shardFolder

    local indexModule = Instance.new("ModuleScript")
    indexModule.Name = "ManifestSubplansIndex"
    indexModule.Source = [[
        return {
            schemaVersion = "0.4.0",
            meta = {
                worldName = "ManifestSubplans",
                generator = "test",
                source = "test",
                metersPerStud = 0.3,
                chunkSizeStuds = 256,
                bbox = {
                    minLat = 0,
                    minLon = 0,
                    maxLat = 1,
                    maxLon = 1,
                },
                totalFeatures = 1,
            },
            shardFolder = "ManifestSubplansChunks",
            shards = { "TestShard_001" },
            chunkRefs = {
                {
                    id = "0_0",
                    originStuds = { x = 0, y = 0, z = 0 },
                    featureCount = 1,
                    streamingCost = 8,
                    partitionVersion = "subplans.v1",
                    subplans = {
                        {
                            id = "terrain",
                            layer = "terrain",
                            featureCount = 1,
                            streamingCost = 8,
                        },
                    },
                },
            },
        }
    ]]
    indexModule.Parent = container

    local sampleData = ServerStorage:FindFirstChild("SampleData")
    local createdSampleData = false
    if not sampleData then
        sampleData = Instance.new("Folder")
        sampleData.Name = "SampleData"
        sampleData.Parent = ServerStorage
        createdSampleData = true
    end

    local sampleShardFolder = Instance.new("Folder")
    sampleShardFolder.Name = "ManifestSubplansChunks"
    sampleShardFolder.Parent = sampleData

    local sampleShardModule = shardModule:Clone()
    sampleShardModule.Parent = sampleShardFolder

    local sampleIndexModule = indexModule:Clone()
    sampleIndexModule.Parent = sampleData

    local ok, err = xpcall(function()
        local handle = ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, 0, {
            freshRequire = true,
        })

        Assert.equal(#handle.chunkRefs, 1, "expected one chunk ref")
        Assert.equal(
            handle.chunkRefs[1].partitionVersion,
            "subplans.v1",
            "expected partitionVersion to survive sharded handle load"
        )
        Assert.truthy(type(handle.chunkRefs[1].subplans) == "table", "expected subplans table on loaded chunk ref")
        Assert.equal(
            handle.chunkRefs[1].subplans[1].id,
            "terrain",
            "expected terrain subplan metadata to survive sharded handle load"
        )
        Assert.equal(
            handle.chunkRefs[1].shards[1],
            "TestShard_001",
            "expected shard mapping rebuild to preserve metadata while filling shards"
        )

        local chunk = handle:GetChunk("0_0")
        Assert.equal(chunk.id, "0_0", "expected rebuilt chunk ref to remain loadable")

        local frozen = ManifestLoader.FreezeHandleForChunkIds(handle, { "0_0" })
        Assert.equal(#frozen.chunkRefs, 1, "expected frozen handle to keep selected chunk refs")
        Assert.equal(
            frozen.chunkRefs[1].partitionVersion,
            "subplans.v1",
            "expected frozen handle to keep partitionVersion"
        )
        Assert.truthy(type(frozen.chunkRefs[1].subplans) == "table", "expected frozen handle to keep subplans table")
        Assert.equal(frozen.chunkRefs[1].subplans[1].id, "terrain", "expected frozen handle to keep subplan metadata")
        Assert.equal(frozen.chunkRefs[1].shards[1], "TestShard_001", "expected frozen handle to keep shard metadata")

        local materializedFromHandle = handle:MaterializeManifest()
        Assert.equal(#materializedFromHandle.chunkRefs, 1, "expected materialized handle manifest to keep chunk refs")
        Assert.equal(
            materializedFromHandle.chunkRefs[1].partitionVersion,
            "subplans.v1",
            "expected materialized handle manifest to keep partitionVersion"
        )
        Assert.equal(
            materializedFromHandle.chunkRefs[1].subplans[1].id,
            "terrain",
            "expected materialized handle manifest to keep subplans"
        )
        Assert.equal(
            materializedFromHandle.chunkRefs[1].shards[1],
            "TestShard_001",
            "expected materialized handle manifest to keep rebuilt shard metadata"
        )

        local materializedFromIndex = ManifestLoader.LoadFromShardedModuleIndex(indexModule, shardFolder, 0)
        Assert.equal(#materializedFromIndex.chunkRefs, 1, "expected direct sharded manifest load to keep chunk refs")
        Assert.equal(
            materializedFromIndex.chunkRefs[1].partitionVersion,
            "subplans.v1",
            "expected direct sharded manifest load to keep partitionVersion"
        )
        Assert.equal(
            materializedFromIndex.chunkRefs[1].subplans[1].id,
            "terrain",
            "expected direct sharded manifest load to keep subplans"
        )

        local namedSampleManifest = ManifestLoader.LoadNamedShardedSample("ManifestSubplansIndex", 0)
        Assert.equal(#namedSampleManifest.chunkRefs, 1, "expected named sharded sample load to keep chunk refs")
        Assert.equal(
            namedSampleManifest.chunkRefs[1].partitionVersion,
            "subplans.v1",
            "expected named sharded sample load to keep partitionVersion"
        )
        Assert.equal(
            namedSampleManifest.chunkRefs[1].subplans[1].id,
            "terrain",
            "expected named sharded sample load to keep subplans"
        )
    end, debug.traceback)

    sampleShardFolder:Destroy()
    sampleIndexModule:Destroy()
    if createdSampleData then
        sampleData:Destroy()
    end
    container:Destroy()

    if not ok then
        error(err)
    end
end
