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
        }

        function handle:GetChunkIdsWithinRadius(_focusPoint, _radius)
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

        ManifestLoader.LoadNamedShardedSampleHandle = function(indexName, timeoutSeconds, options)
            table.insert(loadCalls, {
                indexName = indexName,
                timeoutSeconds = timeoutSeconds,
                options = options,
            })

            local fresh = type(options) == "table" and options.freshRequire == true
            return makeHandle(if fresh then "fresh" else "live")
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
        Workspace:SetAttribute("VertigoSyncTimeTravel", false)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", false)
        AustinPreviewBuilder.Build()
        waitForTasks(4)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(#loadCalls, 1, "expected live preview to reuse cached full Austin manifest handle")
        Assert.truthy(loadCalls[1].options.freshRequire ~= true, "expected live preview to avoid fresh require")
        Assert.equal(#freezeCalls, 0, "expected live preview not to freeze manifest handles")

        -- Hard pause should force a fresh manifest load and freeze the selected chunk set.
        clearPreviewState()
        loadCalls = {}
        freezeCalls = {}
        importCalls = {}

        Workspace:SetAttribute("VertigoSyncHash", "rewound-hash")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 7)
        Workspace:SetAttribute("VertigoSyncTimeTravel", true)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", true)
        AustinPreviewBuilder.Build()
        waitForTasks(4)

        Assert.equal(#loadCalls, 1, "expected hard pause to reload the Austin manifest handle")
        Assert.truthy(loadCalls[1].options.freshRequire == true, "expected hard pause to use fresh require")
        Assert.equal(#freezeCalls, 1, "expected hard pause to freeze the selected Austin preview chunk set")
        Assert.equal(#freezeCalls[1].chunkIds, 2, "expected hard pause to freeze the visible chunk ids")
        Assert.truthy(#importCalls >= 1, "expected preview build to import frozen chunks")

        -- If the epoch changes mid-build, stale preview imports must cancel instead of repainting live.
        clearPreviewState()
        loadCalls = {}
        freezeCalls = {}
        importCalls = {}
        cancelOnFirstImport = true

        Workspace:SetAttribute("VertigoSyncHash", "rewound-hash-2")
        Workspace:SetAttribute(AustinPreviewBuilder.TIME_TRAVEL_EPOCH_ATTR, 20)
        Workspace:SetAttribute("VertigoSyncTimeTravel", true)
        Workspace:SetAttribute("VertigoSyncTimeTravelHardPause", true)
        AustinPreviewBuilder.Build()
        waitForTasks(6)

        Assert.equal(
            Workspace:GetAttribute("VertigoPreviewSyncState"),
            "cancelled",
            "expected stale preview work to cancel when the time-travel epoch changes"
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
        Assert.equal(liveChunkCount, 0, "expected cancelled preview build not to leave imported stale chunks behind")

        -- Integration smoke: the real full Austin handle should remain provisioned and chunked.
        clearPreviewState()
        local realHandle = originalLoadNamedShardedSampleHandle(AustinPreviewBuilder.FULL_MANIFEST_INDEX_NAME)
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
