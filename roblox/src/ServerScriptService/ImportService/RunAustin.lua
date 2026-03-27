local ImportService = require(script.Parent)
local CanonicalWorldContract = require(script.Parent.CanonicalWorldContract)
local ManifestLoader = require(script.Parent.ManifestLoader)
local Profiler = require(script.Parent.Profiler)
local Workspace = game:GetService("Workspace")

local RunAustin = {}
RunAustin.LOAD_RADIUS = 1500
RunAustin.FRAME_BUDGET_SECONDS = 1 / 240
RunAustin.STARTUP_CHUNK_COUNT = 2
RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS = 30
RunAustin.CANONICAL_MANIFEST_INDEX_NAME = CanonicalWorldContract.resolveCanonicalManifestFamily()

local function reportPhase(options, phase)
    if type(options) ~= "table" then
        return
    end
    local reporter = options.phaseReporter
    if type(reporter) == "function" then
        reporter(phase)
    end
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
    return RunAustin.CANONICAL_MANIFEST_INDEX_NAME
end

function RunAustin.getRuntimeManifestCandidates()
    return {
        RunAustin.CANONICAL_MANIFEST_INDEX_NAME,
    }
end

function RunAustin.loadManifestSource()
    print(("[RunAustin] Loading canonical manifest source %s"):format(RunAustin.CANONICAL_MANIFEST_INDEX_NAME))
    return ManifestLoader.LoadNamedShardedSampleHandle(
        RunAustin.CANONICAL_MANIFEST_INDEX_NAME,
        RunAustin.MANIFEST_WAIT_TIMEOUT_SECONDS
    ),
        RunAustin.CANONICAL_MANIFEST_INDEX_NAME
end

function RunAustin.run(options)
    options = options or {}
    setPerfAttribute("Status", "loading")
    reportPhase(options, "loading_manifest")
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
    reportPhase(options, "importing_startup")
    local boundedEnvelope = CanonicalWorldContract.resolveBoundedEnvelope(manifestSource, RunAustin.LOAD_RADIUS)
    local anchor = boundedEnvelope.anchor
    -- Use the exact runtime spawn anchor as the import/load center so edit preview,
    -- play-mode chunk coverage, and the eventual player spawn stay locked together.
    local spawnPoint = boundedEnvelope.spawnPoint
    local loadCenter = boundedEnvelope.focusPoint
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
    local initialChunks = boundedEnvelope.selectedChunks
    if type(initialChunks) ~= "table" or #initialChunks == 0 then
        initialChunks = manifestSource:LoadChunksWithinRadius(loadCenter, RunAustin.LOAD_RADIUS)
    end
    local startupChunkRefsById = {}
    for _, chunk in ipairs(initialChunks) do
        local chunkId = chunk and chunk.id
        if type(chunkId) == "string" and chunkId ~= "" then
            startupChunkRefsById[chunkId] = manifestSource:ResolveChunkRef(chunkId)
        end
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
        registrationChunksById = startupChunkRefsById,
    })
    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_Austin")
    setPerfAttribute("WorldRootName", "GeneratedWorld_Austin")
    if worldRoot then
        setPerfAttribute("WorldRootExists", 1)
        setPerfAttribute("WorldRootChildCount", #worldRoot:GetChildren())
        setPerfAttribute("WorldRootDescendantCount", #worldRoot:GetDescendants())
    else
        setPerfAttribute("WorldRootExists", 0)
        setPerfAttribute("WorldRootChildCount", 0)
        setPerfAttribute("WorldRootDescendantCount", 0)
    end
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
        lookTarget = boundedEnvelope.lookTarget,
    }
end

return RunAustin
