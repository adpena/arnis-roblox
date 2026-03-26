return function()
    local Workspace = game:GetService("Workspace")
    local HttpService = game:GetService("HttpService")

    local Assert = require(script.Parent.Assert)
    local ImportService = require(script.Parent.Parent.ImportService)
    local CanonicalWorldContract = require(script.Parent.Parent.ImportService.CanonicalWorldContract)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local AustinPreviewBuilder = require(script.Parent.Parent.StudioPreview.AustinPreviewBuilder)
    local AustinPreviewTelemetry = require(script.Parent.Parent.StudioPreview.AustinPreviewTelemetry)

    local originalLoadNamedShardedSampleHandle = ManifestLoader.LoadNamedShardedSampleHandle
    local originalLoadShardedModuleHandle = ManifestLoader.LoadShardedModuleHandle
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
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_STATE_EPOCH_ATTR, nil)
        Workspace:SetAttribute("VertigoPreviewAppliedStateEpoch", nil)
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
            {
                id = "2_0",
                originStuds = { x = 512, y = 0, z = 0 },
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
            fullSelectionCallCount = 0,
        }

        function handle:GetChunkIdsWithinRadius(_focusPoint, radius)
            if radius == nil then
                self.fullSelectionCallCount += 1
                return { "0_0", "1_0", "2_0" }
            end

            self.radiusCallCount += 1
            return { "0_0", "1_0" }
        end

        function handle:GetChunkFingerprint(chunkId)
            return chunkId .. ":" .. tag
        end

        function handle:GetChunk(chunkId)
            local originX = if chunkId == "2_0" then 512 elseif chunkId == "1_0" then 256 else 0
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

        local fullLoadCalls = {}
        local previewLoadCalls = {}
        local freezeCalls = {}
        local importCalls = {}
        local cancelOnFirstImport = false
        local bumpStateOnlyEpochOnFirstImport = false
        local bumpPreviewStateOnlyEpochOnFirstImport = false
        local manifestTag = "live"

        ManifestLoader.LoadNamedShardedSampleHandle = function(indexName, timeoutSeconds, options)
            local fresh = type(options) == "table" and options.freshRequire == true
            local handle = makeHandle(if fresh then manifestTag .. ":fresh" else manifestTag)
            table.insert(fullLoadCalls, {
                indexName = indexName,
                timeoutSeconds = timeoutSeconds,
                options = options,
                handle = handle,
            })
            return handle
        end

        ManifestLoader.LoadShardedModuleHandle = function(indexModule, shardFolder, timeoutSeconds, options)
            local fresh = type(options) == "table" and options.freshRequire == true
            local handle = makeHandle(if fresh then manifestTag .. ":preview:fresh" else manifestTag .. ":preview")
            table.insert(previewLoadCalls, {
                indexName = indexModule.Name,
                indexModule = indexModule,
                shardFolderName = shardFolder.Name,
                shardFolder = shardFolder,
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
                    (Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR) or 0) + 1
                )
            end

            if bumpStateOnlyEpochOnFirstImport then
                bumpStateOnlyEpochOnFirstImport = false
                Workspace:SetAttribute(
                    AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR,
                    (Workspace:GetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR) or 0) + 1
                )
            end

            if bumpPreviewStateOnlyEpochOnFirstImport then
                bumpPreviewStateOnlyEpochOnFirstImport = false
                Workspace:SetAttribute(
                    AustinPreviewBuilder.PREVIEW_STATE_EPOCH_ATTR,
                    (Workspace:GetAttribute(AustinPreviewBuilder.PREVIEW_STATE_EPOCH_ATTR) or 0) + 1
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

        -- Live preview should stay on the derived preview accelerator family and reuse the cached handle.
        Workspace:SetAttribute("VertigoSyncHash", "live-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 1)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 1)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(4)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(#previewLoadCalls, 1, "expected live preview to load the derived preview accelerator once")
        Assert.equal(
            previewLoadCalls[1].indexName,
            AustinPreviewBuilder.FALLBACK_PREVIEW_INDEX_NAME,
            "expected live preview to load the derived preview accelerator family"
        )
        Assert.equal(
            previewLoadCalls[1].shardFolderName,
            AustinPreviewBuilder.FALLBACK_PREVIEW_CHUNKS_NAME,
            "expected live preview to use the derived preview chunk folder"
        )
        Assert.truthy(previewLoadCalls[1].options == nil, "expected live preview to use the built StudioPreview fixture")
        Assert.equal(#freezeCalls, 0, "expected live preview not to freeze manifest handles")
        Assert.equal(
            previewLoadCalls[1].handle.radiusCallCount,
            2,
            "expected live preview to resolve preview chunk ids once per build"
        )
        Assert.equal(
            previewLoadCalls[1].handle.fullSelectionCallCount,
            0,
            "expected preview builds not to opt into full-bake chunk selection"
        )

        -- Request-driven preview mode should preserve the derived preview selection path.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
        freezeCalls = {}
        importCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "request-preview-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 3)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 3)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build({
            mode = "preview",
        })

        Assert.equal(
            Workspace:GetAttribute("VertigoPreviewSyncState"),
            "idle",
            "expected request-driven preview builds to stay in-flight until chunk sync completes"
        )
        Assert.equal(#previewLoadCalls, 1, "expected request-driven preview mode to load the preview accelerator once")
        Assert.equal(
            previewLoadCalls[1].indexName,
            AustinPreviewBuilder.FALLBACK_PREVIEW_INDEX_NAME,
            "expected request-driven preview mode to load the derived preview accelerator family"
        )
        Assert.equal(#importCalls, 2, "expected request-driven preview mode to preserve radius-limited chunk imports")
        Assert.equal(
            previewLoadCalls[1].handle.radiusCallCount,
            1,
            "expected request-driven preview mode to use preview chunk selection"
        )
        Assert.equal(
            previewLoadCalls[1].handle.fullSelectionCallCount,
            0,
            "expected request-driven preview mode not to switch into full-bake chunk selection"
        )
        local previewRoot = Workspace:FindFirstChild(AustinPreviewBuilder.WORLD_ROOT_NAME)
        Assert.truthy(previewRoot ~= nil, "expected preview request mode to create the preview root")
        Assert.equal(
            previewRoot:FindFirstChild("PreviewFocus"),
            nil,
            "expected preview request mode not to add helper geometry by default"
        )
        local previewTelemetryJson = Workspace:GetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR)
        Assert.truthy(type(previewTelemetryJson) == "string", "expected preview builds to publish project facts")
        local previewTelemetry = HttpService:JSONDecode(previewTelemetryJson)
        Assert.equal(
            previewTelemetry.projectFacts.preview.sync_state,
            "idle",
            "expected preview project facts to settle back to idle after preview builds"
        )
        Assert.equal(
            previewTelemetry.projectFacts.full_bake.active,
            false,
            "expected preview builds not to report active full-bake work"
        )

        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
        freezeCalls = {}
        importCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "debug-helper-preview-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 4)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 4)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build({
            mode = "preview",
            debugHelpers = true,
        })

        previewRoot = Workspace:FindFirstChild(AustinPreviewBuilder.WORLD_ROOT_NAME)
        Assert.truthy(previewRoot ~= nil, "expected debug helper preview build to create the preview root")
        Assert.truthy(
            previewRoot:FindFirstChild("PreviewFocus") ~= nil,
            "expected debug helper preview requests to opt into helper geometry explicitly"
        )

        -- State-only source churn should not trigger visible chunk reimports when the semantic chunk content is unchanged.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
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

        Assert.equal(#importCalls, 2, "expected initial semantic preview build to import both chunks")

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
        fullLoadCalls = {}
        previewLoadCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "live-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 2)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 2)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(#previewLoadCalls, 1, "expected preview rebuild after Clear to reload the preview accelerator")

        -- Hard pause should force a fresh manifest load and freeze the selected chunk set.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
        freezeCalls = {}
        importCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "rewound-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 7)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 7)
        Workspace:SetAttribute("VertigoSyncTimeTravel", true)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", true)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(#previewLoadCalls, 1, "expected hard pause preview to reload the preview accelerator")
        Assert.equal(
            previewLoadCalls[1].indexName,
            AustinPreviewBuilder.FALLBACK_PREVIEW_INDEX_NAME,
            "expected hard pause preview to reload the derived preview accelerator family"
        )
        Assert.equal(
            previewLoadCalls[1].shardFolderName,
            AustinPreviewBuilder.FALLBACK_PREVIEW_CHUNKS_NAME,
            "expected hard pause preview to reload the derived preview chunk folder"
        )
        Assert.truthy(previewLoadCalls[1].options == nil, "expected hard pause preview to use the built StudioPreview fixture")
        Assert.equal(#freezeCalls, 1, "expected hard pause to freeze the selected Austin preview chunk set")
        Assert.equal(#freezeCalls[1].chunkIds, 2, "expected hard pause to freeze the visible chunk ids")
        Assert.truthy(#importCalls >= 1, "expected preview build to import frozen chunks")
        Assert.equal(
            previewLoadCalls[1].handle.radiusCallCount,
            1,
            "expected hard pause preview to resolve preview chunk ids once"
        )
        Assert.equal(
            previewLoadCalls[1].handle.fullSelectionCallCount,
            0,
            "expected hard pause preview mode not to request full-bake chunk selection"
        )

        -- Full-bake requests should expand chunk selection beyond the preview radius without changing the canonical family.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
        freezeCalls = {}
        importCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "full-bake-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 8)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 8)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build({
            mode = "full_bake",
        })
        waitForTasks(4)

        Assert.equal(#previewLoadCalls, 0, "expected full-bake requests not to use the preview accelerator family")
        Assert.equal(#fullLoadCalls, 1, "expected full-bake requests to load the canonical Austin manifest")
        Assert.equal(
            fullLoadCalls[1].indexName,
            CanonicalWorldContract.resolveCanonicalManifestFamily("full_bake"),
            "expected full-bake requests to load the canonical Austin manifest family"
        )
        Assert.equal(#importCalls, 3, "expected full-bake requests to import all authored chunks")
        Assert.equal(
            fullLoadCalls[1].handle.radiusCallCount,
            0,
            "expected full-bake requests not to use radius-bounded chunk selection"
        )
        Assert.equal(
            fullLoadCalls[1].handle.fullSelectionCallCount,
            1,
            "expected full-bake requests to select chunks authoritatively through the request"
        )
        local fullBakeTelemetryJson = Workspace:GetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR)
        Assert.truthy(type(fullBakeTelemetryJson) == "string", "expected full-bake builds to publish project facts")
        local fullBakeTelemetry = HttpService:JSONDecode(fullBakeTelemetryJson)
        Assert.equal(
            fullBakeTelemetry.projectFacts.full_bake.active,
            false,
            "expected full-bake project facts to clear active state once the build settles"
        )
        Assert.equal(
            fullBakeTelemetry.projectFacts.full_bake.last_result,
            "success",
            "expected full-bake project facts to record the latest result separately from preview state"
        )

        -- If the preview invalidation epoch changes mid-build, the current preview should finish coherently
        -- and then rerun, rather than cancelling into a visible flash.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
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
        Assert.equal(liveChunkCount, 2, "expected deferred preview invalidation to preserve imported preview chunks")

        -- State-only time-travel epoch changes should not cancel the preview when the geometry invalidation epoch is stable.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
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
        Assert.equal(liveChunkCount, 2, "expected state-only epoch changes to preserve imported preview chunks")

        -- Hard-pause time-travel epoch changes should also defer cleanly instead of cancelling the visible preview.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
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

        -- State-only preview epoch changes should be tracked separately so they do not bounce the
        -- geometry rebuild path.
        clearPreviewState()
        fullLoadCalls = {}
        previewLoadCalls = {}
        freezeCalls = {}
        importCalls = {}
        bumpPreviewStateOnlyEpochOnFirstImport = true

        Workspace:SetAttribute("VertigoSyncHash", "state-epoch-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 50)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_INVALIDATION_EPOCH_ATTR, 50)
        Workspace:SetAttribute(AustinPreviewBuilder.PREVIEW_STATE_EPOCH_ATTR, 50)
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(6)

        Assert.equal(#previewLoadCalls, 1, "expected state-only preview epoch changes to keep using the preview accelerator")
        Assert.equal(#importCalls, 2, "expected state-only preview epoch changes not to duplicate chunk imports")
        Assert.equal(
            Workspace:GetAttribute("VertigoPreviewAppliedStateEpoch"),
            51,
            "expected deferred state-only preview epoch changes to be applied after chunk sync completes"
        )
        Assert.equal(
            Workspace:GetAttribute("VertigoPreviewDeferredStateEpoch"),
            nil,
            "expected state-only preview epoch changes to clear once the state refresh is applied"
        )
    end, debug.traceback)

    ManifestLoader.LoadNamedShardedSampleHandle = originalLoadNamedShardedSampleHandle
    ManifestLoader.LoadShardedModuleHandle = originalLoadShardedModuleHandle
    ManifestLoader.FreezeHandleForChunkIds = originalFreezeHandleForChunkIds
    ImportService.ImportChunk = originalImportChunk
    clearPreviewState()

    if not ok then
        error(err, 0)
    end
end
