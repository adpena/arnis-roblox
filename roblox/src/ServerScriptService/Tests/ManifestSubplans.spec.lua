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
        game:SetAttribute(
            "ManifestSubplansShardRequireCount",
            (game:GetAttribute("ManifestSubplansShardRequireCount") or 0) + 1
        )
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
                {
                    id = "1_0",
                    originStuds = { x = 256, y = 0, z = 0 },
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
                totalFeatures = 2,
            },
            shardFolder = "ManifestSubplansChunks",
            shards = { "TestShard_001" },
            chunkRefs = {
                {
                    id = "0_0",
                    originStuds = { x = 0, y = 0, z = 0 },
                    shards = { "StaleShard_999" },
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

    local malformedIndexModule = Instance.new("ModuleScript")
    malformedIndexModule.Name = "ManifestSubplansMalformedIndex"
    malformedIndexModule.Source = [[
        return {
            schemaVersion = "0.4.0",
            meta = {
                worldName = "ManifestSubplansMalformed",
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
                    featureCount = 1.5,
                    partitionVersion = "subplans.v1",
                    subplans = {
                        {
                            id = "terrain",
                            layer = "terrain",
                            featureCount = 1.5,
                            streamingCost = 8,
                        },
                    },
                },
            },
        }
    ]]
    malformedIndexModule.Parent = container

    game:SetAttribute("ManifestSubplansShardRequireCount", 0)

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
        Assert.truthy(
            type(handle.chunkRefs[1].subplans) == "table",
            "expected subplans table on loaded chunk ref"
        )
        Assert.equal(
            handle.chunkRefs[1].subplans[1].id,
            "terrain",
            "expected terrain subplan metadata to survive sharded handle load"
        )
        Assert.equal(
            handle.chunkRefs[1].shards[1],
            "StaleShard_999",
            "expected handle creation to keep additive shard metadata without eagerly scanning shard modules"
        )
        Assert.equal(
            game:GetAttribute("ManifestSubplansShardRequireCount"),
            0,
            "expected sharded handle creation to remain lazy when chunkRefs metadata is present"
        )

        local boundedChunkIds = handle:GetChunkIdsWithinRadius(Vector3.new(128, 0, 128), 32)
        Assert.equal(
            table.concat(boundedChunkIds, ","),
            "0_0",
            "expected bounded radius queries to stay seed-backed instead of forcing canonical full enumeration"
        )
        Assert.equal(
            game:GetAttribute("ManifestSubplansShardRequireCount"),
            0,
            "expected bounded radius queries to remain lazy when seed chunkRefs are present"
        )

        game:SetAttribute("ManifestSubplansShardRequireCount", 0)
        local directHandle = ManifestLoader.LoadShardedModuleHandle(indexModule, shardFolder, 0, {
            freshRequire = true,
        })
        local directChunk = directHandle:GetChunk("0_0")
        Assert.equal(
            directChunk.id,
            "0_0",
            "expected stale seed shard names to fall back to canonical index shards for direct chunk loads"
        )
        Assert.equal(
            directHandle.chunkRefs[1].shards[1],
            "TestShard_001",
            "expected direct chunk load to repair stale seed shard names instead of failing early"
        )
        Assert.equal(
            game:GetAttribute("ManifestSubplansShardRequireCount"),
            1,
            "expected direct chunk fallback to require only the canonical shard on demand"
        )

        game:SetAttribute("ManifestSubplansShardRequireCount", 0)
        local allChunkIds = handle:GetChunkIdsWithinRadius(nil, nil)
        Assert.equal(
            table.concat(allChunkIds, ","),
            "0_0,1_0",
            "expected canonical enumeration to include chunks omitted from additive chunkRefs metadata"
        )
        Assert.equal(
            #handle.chunkRefs,
            2,
            "expected canonical chunk refs to be cached after full enumeration"
        )

        local chunk = handle:GetChunk("0_0")
        Assert.equal(chunk.id, "0_0", "expected rebuilt chunk ref to remain loadable")
        Assert.equal(
            handle.chunkRefs[1].shards[1],
            "TestShard_001",
            "expected canonical shard truth to replace stale shard metadata after chunk materialization"
        )
        Assert.equal(
            game:GetAttribute("ManifestSubplansShardRequireCount"),
            1,
            "expected canonical chunk ref resolution to remain lazy until full enumeration is requested"
        )

        local malformedOk = pcall(function()
            ManifestLoader.LoadShardedModuleHandle(malformedIndexModule, shardFolder, 0, {
                freshRequire = true,
            })
        end)
        Assert.falsy(
            malformedOk,
            "expected malformed chunkRefs/subplans metadata to be rejected at handle creation"
        )
        Assert.equal(
            game:GetAttribute("ManifestSubplansShardRequireCount"),
            1,
            "expected malformed handle creation to fail before loading additional shard modules"
        )

        local frozen = ManifestLoader.FreezeHandleForChunkIds(handle, { "0_0" })
        Assert.equal(#frozen.chunkRefs, 1, "expected frozen handle to keep selected chunk refs")
        Assert.equal(
            frozen.chunkRefs[1].partitionVersion,
            "subplans.v1",
            "expected frozen handle to keep partitionVersion"
        )
        Assert.truthy(
            type(frozen.chunkRefs[1].subplans) == "table",
            "expected frozen handle to keep subplans table"
        )
        Assert.equal(
            frozen.chunkRefs[1].subplans[1].id,
            "terrain",
            "expected frozen handle to keep subplan metadata"
        )
        Assert.equal(
            frozen.chunkRefs[1].shards[1],
            "TestShard_001",
            "expected frozen handle to keep shard metadata"
        )

        local materializedFromHandle = handle:MaterializeManifest()
        Assert.equal(
            #materializedFromHandle.chunkRefs,
            2,
            "expected materialized handle manifest to include canonical chunk refs"
        )
        Assert.equal(
            #materializedFromHandle.chunks,
            2,
            "expected materialized handle manifest to include chunks omitted from additive chunkRefs metadata"
        )
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

        local materializedFromIndex =
            ManifestLoader.LoadFromShardedModuleIndex(indexModule, shardFolder, 0)
        Assert.equal(
            #materializedFromIndex.chunkRefs,
            2,
            "expected direct sharded manifest load to keep canonical chunk refs"
        )
        Assert.equal(
            #materializedFromIndex.chunks,
            2,
            "expected direct sharded manifest load to include all canonical chunks"
        )
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
        Assert.equal(
            materializedFromIndex.chunkRefs[1].shards[1],
            "TestShard_001",
            "expected direct sharded manifest load to keep canonical shard truth"
        )

        local namedSampleManifest =
            ManifestLoader.LoadNamedShardedSample("ManifestSubplansIndex", 0)
        Assert.equal(
            #namedSampleManifest.chunkRefs,
            2,
            "expected named sharded sample load to keep canonical chunk refs"
        )
        Assert.equal(
            #namedSampleManifest.chunks,
            2,
            "expected named sharded sample load to include all canonical chunks"
        )
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
        Assert.equal(
            namedSampleManifest.chunkRefs[1].shards[1],
            "TestShard_001",
            "expected named sharded sample load to keep canonical shard truth"
        )
    end, debug.traceback)

    sampleShardFolder:Destroy()
    sampleIndexModule:Destroy()
    malformedIndexModule:Destroy()
    if createdSampleData then
        sampleData:Destroy()
    end
    game:SetAttribute("ManifestSubplansShardRequireCount", nil)
    container:Destroy()

    if not ok then
        error(err)
    end
end
