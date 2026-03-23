return function()
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local ImportService = require(script.Parent.Parent.ImportService)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local AustinPreviewBuilder = require(script.Parent.Parent.StudioPreview.AustinPreviewBuilder)

    local originalLoadNamedShardedSampleHandle = ManifestLoader.LoadNamedShardedSampleHandle
    local originalFreezeHandleForChunkIds = ManifestLoader.FreezeHandleForChunkIds
    local originalImportChunk = ImportService.ImportChunk

    local function clearPreviewState()
        AustinPreviewBuilder.Clear()
        Workspace:SetAttribute("VertigoSyncHash", nil)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelSeq", nil)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelEpoch", nil)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, nil)
        Workspace:SetAttribute("VertigoPreviewSyncState", nil)
        Workspace:SetAttribute("VertigoPreviewManifestSource", nil)
    end

    local function waitForTasks(iterations)
        for _ = 1, iterations or 3 do
            task.wait()
        end
    end

    local function makeHandle(tag)
        local chunkRefs = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {},
                buildings = {},
                props = {},
            },
            {
                id = "1_0",
                originStuds = { x = 256, y = 0, z = 0 },
                roads = {},
                buildings = {},
                props = {},
            },
        }

        local handle = {
            schemaVersion = "0.3.0",
            meta = {
                worldName = "AustinPreviewHarness",
                chunkSizeStuds = 256,
            },
            chunkRefs = chunkRefs,
            radiusCallCount = 0,
        }

        function handle:GetChunkIdsWithinRadius(_focusPoint, _radius)
            self.radiusCallCount += 1
            return { "0_0", "1_0" }
        end

        function handle:GetChunkFingerprint(chunkId)
            return chunkId .. ":" .. tag
        end

        function handle:GetChunk(chunkId)
            local originX = if chunkId == "1_0" then 256 else 0
            return {
                id = chunkId,
                originStuds = { x = originX, y = 0, z = 0 },
                roads = {},
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            }
        end

        return handle
    end

    local ok, err = xpcall(function()
        clearPreviewState()

        local loadCalls = {}
        local freezeCalls = {}
        local importCalls = {}
        local cancelOnFirstImport = false
        local bumpStateOnlyEpochOnFirstImport = false
        local manifestTag = "live"

        ManifestLoader.LoadNamedShardedSampleHandle = function(indexName, timeoutSeconds, options)
            local fresh = type(options) == "table" and options.freshRequire == true
            local handle = makeHandle(if fresh then manifestTag .. ":fresh" else manifestTag)
            table.insert(loadCalls, {
                indexName = indexName,
                timeoutSeconds = timeoutSeconds,
                options = options,
                handle = handle,
            })
            return handle
        end

        ManifestLoader.FreezeHandleForChunkIds = function(handle, chunkIds)
            table.insert(freezeCalls, {
                handle = handle,
                chunkIds = chunkIds,
            })
            return makeHandle("frozen")
        end

        ImportService.ImportChunk = function(chunk, options)
            table.insert(importCalls, {
                chunkId = chunk.id,
                worldRootName = options.worldRootName,
                hasCancel = type(options.shouldCancel) == "function",
            })

            if cancelOnFirstImport then
                cancelOnFirstImport = false
                Workspace:SetAttribute(
                    AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR,
                    (
                        Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR)
                        or 0
                    ) + 1
                )
            end

            if bumpStateOnlyEpochOnFirstImport then
                bumpStateOnlyEpochOnFirstImport = false
                Workspace:SetAttribute(
                    AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR,
                    (Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) or 0) + 1
                )
            end

            if type(options.shouldCancel) == "function" and options.shouldCancel() then
                return nil
            end

            local worldRoot = Workspace:FindFirstChild(options.worldRootName)
            if not worldRoot then
                worldRoot = Instance.new("Folder")
                worldRoot.Name = options.worldRootName
                worldRoot.Parent = Workspace
            end

            local existing = worldRoot:FindFirstChild(chunk.id)
            if existing then
                existing:Destroy()
            end

            local chunkFolder = Instance.new("Folder")
            chunkFolder.Name = chunk.id
            chunkFolder.Parent = worldRoot
            return chunkFolder
        end

        -- Live mode should use the full manifest path once, then reuse the cached handle.
        Workspace:SetAttribute("VertigoSyncHash", "live-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 1)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 1)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(4)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(
            #loadCalls,
            1,
            "expected live preview to reuse cached full Austin manifest handle"
        )
        Assert.truthy(
            loadCalls[1].options.freshRequire ~= true,
            "expected live preview to avoid fresh require"
        )
        Assert.equal(#freezeCalls, 0, "expected live preview not to freeze manifest handles")
        Assert.equal(
            loadCalls[1].handle.radiusCallCount,
            2,
            "expected live preview to resolve preview chunk ids once per build"
        )

        -- State-only source churn should not trigger visible chunk reimports when the semantic chunk content is unchanged.
        clearPreviewState()
        loadCalls = {}
        freezeCalls = {}
        importCalls = {}
        manifestTag = "live-a"

        Workspace:SetAttribute("VertigoSyncHash", "semantic-a")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 11)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 11)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(
            #importCalls,
            2,
            "expected initial semantic preview build to import both chunks"
        )

        manifestTag = "live-b"
        Workspace:SetAttribute("VertigoSyncHash", "semantic-b")
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 12)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(
            #importCalls,
            2,
            "expected source-only fingerprint churn with identical chunk content not to trigger chunk reimports"
        )

        clearPreviewState()
        loadCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "live-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 2)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 2)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(
            #loadCalls,
            1,
            "expected Clear to invalidate cached full Austin manifest handle"
        )

        -- Hard pause should force a fresh manifest load and freeze the selected chunk set.
        clearPreviewState()
        loadCalls = {}
        freezeCalls = {}
        importCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "rewound-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 7)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 7)
        Workspace:SetAttribute("VertigoSyncTimeTravel", true)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", true)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(#loadCalls, 1, "expected hard pause to reload the Austin manifest handle")
        Assert.truthy(
            loadCalls[1].options.freshRequire == true,
            "expected hard pause to use fresh require"
        )
        Assert.equal(
            #freezeCalls,
            1,
            "expected hard pause to freeze the selected Austin preview chunk set"
        )
        Assert.equal(
            #freezeCalls[1].chunkIds,
            2,
            "expected hard pause to freeze the visible chunk ids"
        )
        Assert.truthy(#importCalls >= 1, "expected preview build to import frozen chunks")
        Assert.equal(
            loadCalls[1].handle.radiusCallCount,
            1,
            "expected hard pause preview to resolve preview chunk ids once"
        )

        -- If the preview invalidation epoch changes mid-build, the current preview should finish coherently
        -- and then rerun, rather than cancelling into a visible flash.
        clearPreviewState()
        loadCalls = {}
        freezeCalls = {}
        importCalls = {}
        cancelOnFirstImport = true

        Workspace:SetAttribute("VertigoSyncHash", "rewound-hash-2")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 20)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 20)
        Workspace:SetAttribute("VertigoSyncTimeTravel", true)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", true)
        AustinPreviewBuilder.Build()
        waitForTasks(6)

        Assert.equal(
            Workspace:GetAttribute("VertigoPreviewSyncState"),
            "idle",
            "expected preview invalidation changes to keep the visible preview coherent"
        )

        local previewRoot = Workspace:FindFirstChild(AustinPreviewBuilder.WORLD_ROOT_NAME)
        local liveChunkCount = 0
        if previewRoot then
            for _, child in ipairs(previewRoot:GetChildren()) do
                if child:IsA("Folder") and child.Name ~= "PreviewFocus" then
                    liveChunkCount += 1
                end
            end
        end
        Assert.equal(
            liveChunkCount,
            2,
            "expected deferred preview invalidation to preserve imported preview chunks"
        )

        -- State-only time-travel epoch changes should not cancel the preview when the geometry invalidation epoch is stable.
        clearPreviewState()
        loadCalls = {}
        freezeCalls = {}
        importCalls = {}
        bumpStateOnlyEpochOnFirstImport = true

        Workspace:SetAttribute("VertigoSyncHash", "state-only-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 30)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 9)
        Workspace:SetAttribute("VertigoSyncTimeTravel", true)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(6)

        Assert.equal(
            Workspace:GetAttribute("VertigoPreviewSyncState"),
            "idle",
            "expected state-only time-travel epoch changes not to cancel the preview build"
        )
        previewRoot = Workspace:FindFirstChild(AustinPreviewBuilder.WORLD_ROOT_NAME)
        liveChunkCount = 0
        if previewRoot then
            for _, child in ipairs(previewRoot:GetChildren()) do
                if child:IsA("Folder") and child.Name ~= "PreviewFocus" then
                    liveChunkCount += 1
                end
            end
        end
        Assert.equal(
            liveChunkCount,
            2,
            "expected state-only epoch changes to preserve imported preview chunks"
        )

        -- Hard-pause time-travel epoch changes should also defer cleanly instead of cancelling the visible preview.
        clearPreviewState()
        loadCalls = {}
        freezeCalls = {}
        importCalls = {}
        bumpStateOnlyEpochOnFirstImport = true

        Workspace:SetAttribute("VertigoSyncHash", "state-only-hard-pause-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 40)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 10)
        Workspace:SetAttribute("VertigoSyncTimeTravel", true)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", true)
        AustinPreviewBuilder.Build()
        waitForTasks(6)

        Assert.equal(
            Workspace:GetAttribute("VertigoPreviewSyncState"),
            "idle",
            "expected hard-pause state-only time-travel epoch changes not to cancel the preview build"
        )
        previewRoot = Workspace:FindFirstChild(AustinPreviewBuilder.WORLD_ROOT_NAME)
        liveChunkCount = 0
        if previewRoot then
            for _, child in ipairs(previewRoot:GetChildren()) do
                if child:IsA("Folder") and child.Name ~= "PreviewFocus" then
                    liveChunkCount += 1
                end
            end
        end
        Assert.equal(
            liveChunkCount,
            2,
            "expected hard-pause state-only epoch changes to preserve imported preview chunks"
        )

        -- Integration smoke: the real full Austin handle should remain provisioned and chunked.
        clearPreviewState()
        local realHandle =
            originalLoadNamedShardedSampleHandle(AustinPreviewBuilder.FULL_MANIFEST_INDEX_NAME)
        Assert.truthy(realHandle ~= nil, "expected full Austin manifest handle to load")
        Assert.truthy(
            type(realHandle.GetChunkIdsWithinRadius) == "function",
            "expected Austin manifest handle radius API"
        )
        Assert.truthy(
            type(realHandle.chunkRefs) == "table" and #realHandle.chunkRefs > 0,
            "expected chunked Austin refs"
        )
    end, debug.traceback)

    ManifestLoader.LoadNamedShardedSampleHandle = originalLoadNamedShardedSampleHandle
    ManifestLoader.FreezeHandleForChunkIds = originalFreezeHandleForChunkIds
    ImportService.ImportChunk = originalImportChunk
    clearPreviewState()

    if not ok then
        error(err, 0)
    end
end
