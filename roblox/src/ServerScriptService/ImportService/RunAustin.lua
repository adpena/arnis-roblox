local ImportService = require(script.Parent)
local AustinSpawn = require(script.Parent.AustinSpawn)
local ManifestLoader = require(script.Parent.ManifestLoader)
local Profiler = require(script.Parent.Profiler)
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RunAustin = {}
RunAustin.LOAD_RADIUS = 1500
RunAustin.FRAME_BUDGET_SECONDS = 1 / 240
RunAustin.STARTUP_CHUNK_COUNT = 2
RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS = 30
RunAustin.STUDIO_MANIFEST_INDEX_NAME = "AustinPreviewManifestIndex"
RunAustin.STUDIO_MANIFEST_CHUNKS_NAME = "AustinPreviewManifestChunks"
RunAustin.FULL_MANIFEST_INDEX_NAME = "AustinHDManifestIndex"
RunAustin.RUNTIME_FALLBACK_MANIFEST_INDEX_NAME = "AustinManifestIndex"

local function isStudioEditMode()
    return RunService:IsStudio() and not RunService:IsRunning()
end

local function setPerfAttribute(name, value)
    Workspace:SetAttribute("VertigoAustin" .. name, value)
end

local function emitRunProfile(stats, phaseSummary, manifestSource, focusPoint)
    local chunkRefs = manifestSource.chunkRefs or manifestSource.chunks or {}
    local slowest = phaseSummary.slowest
    local byLabel = phaseSummary.byLabel or {}
    local hottestPhase = byLabel[1]

    setPerfAttribute("ChunkRefs", #chunkRefs)
    setPerfAttribute("ImportedChunks", stats.chunksImported or 0)
    setPerfAttribute("ImportedRoads", stats.roadsImported or 0)
    setPerfAttribute("ImportedBuildings", stats.buildingsImported or 0)
    setPerfAttribute("ImportedProps", stats.propsImported or 0)
    setPerfAttribute("FocusX", math.round(focusPoint.X))
    setPerfAttribute("FocusZ", math.round(focusPoint.Z))
    setPerfAttribute("ProfilerActivities", phaseSummary.totalActivities or 0)
    setPerfAttribute("ProfilerTotalMs", phaseSummary.totalElapsedMs or 0)
    setPerfAttribute("HotPhaseLabel", hottestPhase and hottestPhase.label or "")
    setPerfAttribute("HotPhaseTotalMs", hottestPhase and hottestPhase.totalMs or 0)
    setPerfAttribute("HotPhaseAvgMs", hottestPhase and hottestPhase.avgMs or 0)
    setPerfAttribute("HotPhaseCount", hottestPhase and hottestPhase.count or 0)
    setPerfAttribute("SlowestLabel", slowest and slowest.label or "")
    setPerfAttribute("SlowestMs", slowest and slowest.elapsedMs or 0)

    print(
        string.format(
            "[RunAustin] Perf summary: refs=%d imported=%d total=%.1fms hot=%s %.1fms slowest=%s %.1fms",
            #chunkRefs,
            stats.chunksImported or 0,
            phaseSummary.totalElapsedMs or 0,
            hottestPhase and hottestPhase.label or "n/a",
            hottestPhase and hottestPhase.totalMs or 0,
            slowest and slowest.label or "n/a",
            slowest and slowest.elapsedMs or 0
        )
    )
end

function RunAustin.getManifestName()
    if isStudioEditMode() then
        return RunAustin.STUDIO_MANIFEST_INDEX_NAME
    end

    return RunAustin.FULL_MANIFEST_INDEX_NAME
end

local function runtimeManifestCandidates()
    return {
        RunAustin.FULL_MANIFEST_INDEX_NAME,
        RunAustin.RUNTIME_FALLBACK_MANIFEST_INDEX_NAME,
    }
end

function RunAustin.loadManifestSource()
    if isStudioEditMode() then
        print("[RunAustin] Loading preview manifest source")
        local previewFolder = ServerScriptService:WaitForChild("StudioPreview", RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS)
        if not previewFolder then
            error("ServerScriptService.StudioPreview was not provisioned into the live DataModel")
        end
        local previewIndex =
            previewFolder:WaitForChild(RunAustin.STUDIO_MANIFEST_INDEX_NAME, RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS)
        if not previewIndex then
            error(
                "ServerScriptService.StudioPreview.AustinPreviewManifestIndex was not provisioned into the live DataModel"
            )
        end
        local previewChunks =
            previewFolder:WaitForChild(RunAustin.STUDIO_MANIFEST_CHUNKS_NAME, RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS)
        if not previewChunks then
            error(
                "ServerScriptService.StudioPreview.AustinPreviewManifestChunks was not provisioned into the live DataModel"
            )
        end
        return ManifestLoader.LoadShardedModuleHandle(
            previewIndex,
            previewChunks,
            RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS
        ),
            RunAustin.STUDIO_MANIFEST_INDEX_NAME
    end

    local sampleData = ServerStorage:WaitForChild("SampleData", 5)
    if not sampleData then
        error("ServerStorage.SampleData was not provisioned into the live DataModel")
    end

    local loadErrors = {}
    for index, manifestName in ipairs(runtimeManifestCandidates()) do
        local manifestModule = sampleData:FindFirstChild(manifestName)
        if manifestModule then
            print(("[RunAustin] Loading runtime manifest source %s"):format(manifestName))
            local success, manifestOrErr = pcall(function()
                return ManifestLoader.LoadNamedShardedSampleHandle(
                    manifestName,
                    RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS
                )
            end)
            if success then
                if index > 1 then
                    warn(
                        ("[RunAustin] Falling back to runtime manifest %s because %s is unavailable in the live DataModel"):format(
                            manifestName,
                            RunAustin.FULL_MANIFEST_INDEX_NAME
                        )
                    )
                end
                return manifestOrErr, manifestName
            end
            table.insert(loadErrors, ("%s: %s"):format(manifestName, tostring(manifestOrErr)))
        else
            table.insert(loadErrors, ("%s: module missing from ServerStorage.SampleData"):format(manifestName))
        end
    end

    error(table.concat(loadErrors, "; "))
end

function RunAustin.run()
    setPerfAttribute("Status", "loading")
    print(("[RunAustin] Starting run for manifest %s"):format(RunAustin.getManifestName()))
    local success, manifestOrErr, resolvedManifestName = pcall(function()
        return RunAustin.loadManifestSource()
    end)

    if not success then
        setPerfAttribute("Status", "load_failed")
        warn(("[RunAustin] Failed to load %s:"):format(RunAustin.getManifestName()), manifestOrErr)
        return nil
    end

    local manifestSource = manifestOrErr
    setPerfAttribute("ManifestName", resolvedManifestName or RunAustin.getManifestName())
    print(("[RunAustin] Manifest source loaded from %s"):format(resolvedManifestName or RunAustin.getManifestName()))
    print("[RunAustin] Manifest source loaded")
    local anchor = AustinSpawn.resolveAnchor(manifestSource, RunAustin.LOAD_RADIUS)
    -- Use the exact runtime spawn anchor as the import/load center so edit preview,
    -- play-mode chunk coverage, and the eventual player spawn stay locked together.
    local spawnPoint = anchor.spawnPoint
    local loadCenter = anchor.focusPoint
    setPerfAttribute("FocusX", math.round(loadCenter.X))
    setPerfAttribute("FocusY", math.round(loadCenter.Y))
    setPerfAttribute("FocusZ", math.round(loadCenter.Z))
    setPerfAttribute("SpawnX", math.round(spawnPoint.X))
    setPerfAttribute("SpawnY", math.round(spawnPoint.Y))
    setPerfAttribute("SpawnZ", math.round(spawnPoint.Z))
    print(
        string.format(
            "[RunAustin] Austin anchor: focus=(%.1f, %.1f, %.1f) spawn=(%.1f, %.1f, %.1f)",
            loadCenter.X,
            loadCenter.Y,
            loadCenter.Z,
            spawnPoint.X,
            spawnPoint.Y,
            spawnPoint.Z
        )
    )
    local initialChunks = anchor.selectedChunks
    if type(initialChunks) ~= "table" or #initialChunks == 0 then
        initialChunks = manifestSource:LoadChunksWithinRadius(loadCenter, RunAustin.LOAD_RADIUS)
    end
    local initialManifest = {
        schemaVersion = manifestSource.schemaVersion,
        meta = manifestSource.meta,
        chunks = initialChunks,
    }

    local stats = ImportService.ImportManifest(initialManifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_Austin",
        printReport = true,
        loadRadius = RunAustin.LOAD_RADIUS, -- studs around the manifest focus point
        loadCenter = loadCenter,
        nonBlocking = true,
        frameBudgetSeconds = RunAustin.FRAME_BUDGET_SECONDS,
        startupChunkCount = RunAustin.STARTUP_CHUNK_COUNT,
    })
    local phaseSummary = Profiler.generateSummary()
    emitRunProfile(stats, phaseSummary, manifestSource, loadCenter)
    setPerfAttribute("Status", "ready")

    print(
        ("[RunAustin] Imported Austin manifest: chunks=%d roads=%d buildings=%d props=%d"):format(
            stats.chunksImported,
            stats.roadsImported,
            stats.buildingsImported,
            stats.propsImported
        )
    )

    return {
        manifest = initialManifest,
        manifestSource = manifestSource,
        stats = stats,
        phaseSummary = phaseSummary,
        focusPoint = loadCenter,
        spawnPoint = spawnPoint,
        lookTarget = anchor.lookTarget,
    }
end

return RunAustin
