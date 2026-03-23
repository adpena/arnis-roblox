return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
    local ImportService = require(script.Parent.Parent.ImportService)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)
    local AustinPreviewBuilder = require(script.Parent.Parent.StudioPreview.AustinPreviewBuilder)

    local originalImportChunk = ImportService.ImportChunk
    local originalImportChunkSubplan = ImportService.ImportChunkSubplan
    local originalUnloadChunk = ChunkLoader.UnloadChunk
    local originalLoadNamedShardedSampleHandle = ManifestLoader.LoadNamedShardedSampleHandle
    local originalSubplanRollout = table.clone(DefaultWorldConfig.SubplanRollout)

    local function makeChunk(chunkId, originX, subplans)
        return {
            id = chunkId,
            originStuds = { x = originX, y = 0, z = 0 },
            roads = {
                {
                    id = chunkId .. "_road",
                    kind = "secondary",
                    material = "Asphalt",
                    widthStuds = 16,
                    hasSidewalk = true,
                    points = {
                        { x = 8, y = 0, z = 20 },
                        { x = 92, y = 0, z = 20 },
                    },
                },
            },
            rails = {},
            buildings = {},
            water = {},
            props = {},
            landuse = {
                {
                    id = chunkId .. "_park",
                    kind = "park",
                    footprint = {
                        { x = 0, z = 0 },
                        { x = 100, z = 0 },
                        { x = 100, z = 32 },
                        { x = 0, z = 32 },
                    },
                },
            },
            barriers = {},
            subplans = subplans,
        }
    end

    local function ensureChunkFolder(worldRootName, chunkId)
        local worldRoot = Workspace:FindFirstChild(worldRootName)
        if not worldRoot then
            worldRoot = Instance.new("Folder")
            worldRoot.Name = worldRootName
            worldRoot.Parent = Workspace
        end

        local chunkFolder = worldRoot:FindFirstChild(chunkId)
        if not chunkFolder then
            chunkFolder = Instance.new("Folder")
            chunkFolder.Name = chunkId
            chunkFolder.Parent = worldRoot
        end

        return chunkFolder
    end

    local function waitForTasks(iterations)
        for _ = 1, iterations do
            task.wait()
        end
    end

    local function findEntryIndex(entries, needle)
        for index, entry in ipairs(entries) do
            if entry == needle then
                return index
            end
        end
        return nil
    end

    local function clearPreviewState()
        AustinPreviewBuilder.Clear()
        Workspace:SetAttribute("VertigoSyncHash", nil)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, nil)
        Workspace:SetAttribute("VertigoPreviewSyncState", nil)
        Workspace:SetAttribute("VertigoPreviewManifestSource", nil)
    end

    local runtimeSubplans = {
        { id = "landuse", layer = "landuse", featureCount = 1, streamingCost = 8 },
        { id = "roads", layer = "roads", featureCount = 1, streamingCost = 12 },
    }

    local runtimeChunkRefById = {
        ["0_0"] = {
            id = "0_0",
            originStuds = { x = -40, y = 0, z = 0 },
            shards = { "fake" },
            featureCount = 2,
            streamingCost = 20,
            partitionVersion = "subplans.v1",
            subplans = runtimeSubplans,
        },
        ["1_0"] = {
            id = "1_0",
            originStuds = { x = 20, y = 0, z = 0 },
            shards = { "fake" },
            featureCount = 2,
            streamingCost = 20,
            partitionVersion = "subplans.v1",
            subplans = runtimeSubplans,
        },
        ["2_0"] = {
            id = "2_0",
            originStuds = { x = 200, y = 0, z = 0 },
            shards = { "fake" },
            featureCount = 1,
            streamingCost = 5,
        },
    }

    local runtimeManifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "SubplanStreamingRuntime",
            generator = "test",
            source = "test",
            metersPerStud = 0.3,
            chunkSizeStuds = 100,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
        },
        chunkRefs = {
            runtimeChunkRefById["0_0"],
            runtimeChunkRefById["1_0"],
            runtimeChunkRefById["2_0"],
        },
        GetChunk = function(_, chunkId)
            if chunkId == "0_0" then
                return makeChunk("0_0", -40, runtimeSubplans)
            end
            if chunkId == "1_0" then
                return makeChunk("1_0", 20, runtimeSubplans)
            end
            return makeChunk("2_0", 200, nil)
        end,
    }

    local ok, err = xpcall(function()
        local runtimeOrder = {}
        local previewOrder = {}

        ImportService.ImportChunk = function(chunk, options)
            local chunkFolder = ensureChunkFolder(options.worldRootName, chunk.id)
            if options.worldRootName == "StreamingSubplanWorld" then
                runtimeOrder[#runtimeOrder + 1] = "chunk:" .. chunk.id
            elseif options.worldRootName == AustinPreviewBuilder.WORLD_ROOT_NAME then
                previewOrder[#previewOrder + 1] = "chunk:" .. chunk.id
            end
            return chunkFolder
        end

        ImportService.ImportChunkSubplan = function(chunk, subplan, options)
            local chunkFolder = ensureChunkFolder(options.worldRootName, chunk.id)
            local subplanId = if type(subplan) == "table" then subplan.id else tostring(subplan)
            if options.worldRootName == "StreamingSubplanWorld" then
                runtimeOrder[#runtimeOrder + 1] = ("subplan:%s:%s"):format(chunk.id, subplanId)
            elseif options.worldRootName == AustinPreviewBuilder.WORLD_ROOT_NAME then
                previewOrder[#previewOrder + 1] = ("subplan:%s:%s"):format(chunk.id, subplanId)
            end
            return chunkFolder, 0
        end

        ChunkLoader.Clear()
        StreamingService.Start(runtimeManifest, {
            worldRootName = "StreamingSubplanWorld",
            config = {
                StreamingEnabled = true,
                StreamingTargetRadius = 400,
                HighDetailRadius = 400,
                ChunkSizeStuds = 100,
                TerrainMode = "none",
                RoadMode = "mesh",
                BuildingMode = "none",
                WaterMode = "none",
                LanduseMode = "terrain",
                SubplanRollout = {
                    Enabled = true,
                    AllowedLayers = { "landuse", "roads" },
                    AllowedChunkIds = { "0_0", "1_0" },
                },
            },
            preferredLookVector = Vector3.new(1, 0, 0),
        })
        StreamingService.Update(Vector3.new(0, 0, 0))

        Assert.equal(
            table.concat(runtimeOrder, ","),
            "subplan:1_0:landuse,subplan:1_0:roads,subplan:0_0:landuse,subplan:0_0:roads,chunk:2_0",
            "expected runtime streaming to globally schedule same-band subplan work items before whole-chunk fallback"
        )

        StreamingService.Stop()
        local streamingWorld = Workspace:FindFirstChild("StreamingSubplanWorld")
        if streamingWorld then
            streamingWorld:Destroy()
        end
        ChunkLoader.Clear()

        DefaultWorldConfig.SubplanRollout.Enabled = true
        DefaultWorldConfig.SubplanRollout.AllowedLayers = { "landuse", "roads" }
        DefaultWorldConfig.SubplanRollout.AllowedChunkIds = { "0_0", "1_0" }

        local previewSubplans = {
            { id = "landuse", layer = "landuse", featureCount = 1, streamingCost = 8 },
            { id = "roads", layer = "roads", featureCount = 1, streamingCost = 12 },
        }
        local previewChunkRefById = {
            ["0_0"] = {
                id = "0_0",
                originStuds = { x = -40, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 2,
                streamingCost = 20,
                partitionVersion = "subplans.v1",
                subplans = previewSubplans,
            },
            ["1_0"] = {
                id = "1_0",
                originStuds = { x = 20, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 2,
                streamingCost = 20,
                partitionVersion = "subplans.v1",
                subplans = previewSubplans,
            },
            ["2_0"] = {
                id = "2_0",
                originStuds = { x = 600, y = 0, z = 0 },
                shards = { "fake" },
                featureCount = 1,
                streamingCost = 5,
            },
        }

        ChunkLoader.UnloadChunk = function(chunkId)
            previewOrder[#previewOrder + 1] = "unload:" .. tostring(chunkId)
        end

        ManifestLoader.LoadNamedShardedSampleHandle = function()
            local handle = {
                schemaVersion = "0.4.0",
                meta = {
                    worldName = "SubplanStreamingPreview",
                    chunkSizeStuds = 100,
                    canonicalAnchor = {
                        positionStuds = { x = 0, y = 0, z = 0 },
                        lookDirectionStuds = { x = 1, y = 0, z = 0 },
                    },
                },
                chunkRefs = {
                    previewChunkRefById["0_0"],
                    previewChunkRefById["1_0"],
                    previewChunkRefById["2_0"],
                },
            }

            function handle:GetChunkIdsWithinRadius()
                return { "0_0", "1_0", "2_0" }
            end

            function handle:GetChunkFingerprint(chunkId)
                return chunkId .. ":fingerprint"
            end

            function handle:GetChunk(chunkId)
                if chunkId == "0_0" then
                    return makeChunk("0_0", -40, previewSubplans)
                end
                if chunkId == "1_0" then
                    return makeChunk("1_0", 20, previewSubplans)
                end
                return makeChunk("2_0", 600, nil)
            end

            return handle
        end

        clearPreviewState()
        local previewRoot = Instance.new("Folder")
        previewRoot.Name = AustinPreviewBuilder.WORLD_ROOT_NAME
        previewRoot.Parent = Workspace
        local staleChunk = Instance.new("Folder")
        staleChunk.Name = "stale_0"
        staleChunk.Parent = previewRoot
        Workspace:SetAttribute("VertigoSyncHash", "subplan-streaming-preview")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 1)
        AustinPreviewBuilder.Build()
        waitForTasks(6)

        Assert.equal(
            previewOrder[1],
            "subplan:1_0:landuse",
            "expected preview sync to preserve the highest-priority startup work item first"
        )
        local unloadIndex = findEntryIndex(previewOrder, "unload:stale_0")
        Assert.truthy(unloadIndex ~= nil, "expected stale preview chunk to be pruned eventually")
        Assert.truthy(
            unloadIndex > 1,
            "expected preview sync to import startup work before pruning stale preview chunks"
        )
    end, debug.traceback)

    ImportService.ImportChunk = originalImportChunk
    ImportService.ImportChunkSubplan = originalImportChunkSubplan
    ChunkLoader.UnloadChunk = originalUnloadChunk
    ManifestLoader.LoadNamedShardedSampleHandle = originalLoadNamedShardedSampleHandle
    DefaultWorldConfig.SubplanRollout.Enabled = originalSubplanRollout.Enabled
    DefaultWorldConfig.SubplanRollout.AllowedLayers = originalSubplanRollout.AllowedLayers
    DefaultWorldConfig.SubplanRollout.AllowedChunkIds = originalSubplanRollout.AllowedChunkIds

    StreamingService.Stop()
    local streamingWorld = Workspace:FindFirstChild("StreamingSubplanWorld")
    if streamingWorld then
        streamingWorld:Destroy()
    end
    ChunkLoader.Clear()
    clearPreviewState()

    if not ok then
        error(err, 0)
    end
end
