return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
    local ImportService = require(script.Parent.Parent.ImportService)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local AustinPreviewBuilder = require(script.Parent.Parent.StudioPreview.AustinPreviewBuilder)

    local originalImportChunk = ImportService.ImportChunk
    local originalImportChunkSubplan = ImportService.ImportChunkSubplan
    local originalGetSubplanState = ImportService.GetSubplanState
    local originalResetSubplanState = ImportService.ResetSubplanState
    local originalLoadNamedShardedSampleHandle = ManifestLoader.LoadNamedShardedSampleHandle
    local originalLoadShardedModuleHandle = ManifestLoader.LoadShardedModuleHandle
    local originalSubplanRollout = table.clone(DefaultWorldConfig.SubplanRollout)

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

    local function cloneState(state)
        return {
            importedLayers = table.clone(state and state.importedLayers or {}),
            completedWorkItems = table.clone(state and state.completedWorkItems or {}),
            failedWorkItems = table.clone(state and state.failedWorkItems or {}),
        }
    end

    local function waitForTasks(iterations)
        for _ = 1, iterations do
            task.wait()
        end
    end

    local function clearPreviewState()
        AustinPreviewBuilder.Clear()
        Workspace:SetAttribute("VertigoSyncHash", nil)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, nil)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, nil)
        Workspace:SetAttribute("VertigoPreviewSyncState", nil)
        Workspace:SetAttribute("VertigoPreviewManifestSource", nil)
    end

    local ok, err = xpcall(function()
        clearPreviewState()

        DefaultWorldConfig.SubplanRollout.Enabled = true
        DefaultWorldConfig.SubplanRollout.AllowedLayers = {}
        DefaultWorldConfig.SubplanRollout.AllowedChunkIds = { "0_0" }

        local previewOrder = {}
        local resetCalls = {}
        local staleStateByChunkId = {
            ["0_0"] = {
                importedLayers = {
                    terrain = true,
                },
                completedWorkItems = {
                    ["0_0:terrain"] = true,
                },
                failedWorkItems = {},
            },
        }

        ImportService.GetSubplanState = function(chunkId)
            return cloneState(staleStateByChunkId[chunkId])
        end

        ImportService.ResetSubplanState = function(chunkId)
            if type(chunkId) == "string" then
                resetCalls[#resetCalls + 1] = chunkId
                staleStateByChunkId[chunkId] = nil
                return
            end
            table.clear(staleStateByChunkId)
        end

        ImportService.ImportChunk = function(chunk, options)
            local chunkFolder = ensureChunkFolder(options.worldRootName, chunk.id)
            previewOrder[#previewOrder + 1] = "chunk:" .. chunk.id
            return chunkFolder, 0
        end

        ImportService.ImportChunkSubplan = function(chunk, subplan, options)
            local chunkFolder = ensureChunkFolder(options.worldRootName, chunk.id)
            previewOrder[#previewOrder + 1] = ("subplan:%s:%s"):format(chunk.id, subplan.id)
            return chunkFolder, 0
        end

        local function makeHandle()
            local handle = {
                schemaVersion = "0.4.0",
                meta = {
                    worldName = "PreviewSubplanStateReconcile",
                    chunkSizeStuds = 100,
                    canonicalAnchor = {
                        positionStuds = { x = 0, y = 0, z = 0 },
                        lookDirectionStuds = { x = 1, y = 0, z = 0 },
                    },
                },
                chunkRefs = {
                    {
                        id = "0_0",
                        originStuds = { x = 0, y = 0, z = 0 },
                        shards = { "fake" },
                        featureCount = 2,
                        streamingCost = 16,
                        partitionVersion = "subplans.v1",
                        subplans = {
                            {
                                id = "terrain",
                                layer = "terrain",
                                featureCount = 1,
                                streamingCost = 8,
                            },
                            {
                                id = "landuse:nw",
                                layer = "landuse",
                                featureCount = 1,
                                streamingCost = 8,
                            },
                        },
                    },
                },
            }

            function handle:GetChunkIdsWithinRadius()
                return { "0_0" }
            end

            function handle:GetChunkFingerprint(chunkId)
                return chunkId .. ":fingerprint"
            end

            function handle:GetChunk(chunkId)
                return {
                    id = chunkId,
                    originStuds = { x = 0, y = 0, z = 0 },
                    terrain = {
                        cellSizeStuds = 16,
                        width = 8,
                        depth = 8,
                        heights = table.create(64, 0),
                        material = "Grass",
                    },
                    roads = {},
                    rails = {},
                    barriers = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {
                        {
                            id = "park_0",
                            kind = "park",
                            footprint = {
                                { x = 0, z = 0 },
                                { x = 96, z = 0 },
                                { x = 96, z = 96 },
                                { x = 0, z = 96 },
                            },
                        },
                    },
                    subplans = {
                        { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 8 },
                        {
                            id = "landuse:nw",
                            layer = "landuse",
                            featureCount = 1,
                            streamingCost = 8,
                        },
                    },
                }
            end

            return handle
        end

        ManifestLoader.LoadNamedShardedSampleHandle = function()
            return makeHandle()
        end

        ManifestLoader.LoadShardedModuleHandle = function()
            return makeHandle()
        end

        local previewRoot = Instance.new("Folder")
        previewRoot.Name = AustinPreviewBuilder.WORLD_ROOT_NAME
        previewRoot.Parent = Workspace

        Workspace:SetAttribute("VertigoSyncHash", "preview-subplan-state-reconcile")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 1)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 1)
        AustinPreviewBuilder.Build()
        waitForTasks(6)

        Assert.equal(
            resetCalls[1],
            "0_0",
            "expected preview sync to clear stale subplan state for missing chunk folders"
        )
        Assert.equal(
            previewOrder[1],
            "subplan:0_0:terrain",
            "expected preview sync to re-import terrain before later bounded subplans after stale state reset"
        )
        Assert.equal(
            previewOrder[2],
            "subplan:0_0:landuse:nw",
            "expected bounded landuse subplan to follow terrain after reconciliation"
        )
    end, debug.traceback)

    ImportService.ImportChunk = originalImportChunk
    ImportService.ImportChunkSubplan = originalImportChunkSubplan
    ImportService.GetSubplanState = originalGetSubplanState
    ImportService.ResetSubplanState = originalResetSubplanState
    ManifestLoader.LoadNamedShardedSampleHandle = originalLoadNamedShardedSampleHandle
    ManifestLoader.LoadShardedModuleHandle = originalLoadShardedModuleHandle
    DefaultWorldConfig.SubplanRollout.Enabled = originalSubplanRollout.Enabled
    DefaultWorldConfig.SubplanRollout.AllowedLayers = originalSubplanRollout.AllowedLayers
    DefaultWorldConfig.SubplanRollout.AllowedChunkIds = originalSubplanRollout.AllowedChunkIds
    clearPreviewState()

    if not ok then
        error(err, 0)
    end
end
