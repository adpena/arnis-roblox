return function()
    local ImportService = require(script.Parent.Parent.ImportService)
    local ImportPlanCache = require(script.Parent.Parent.ImportService.ImportPlanCache)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local Profiler = require(script.Parent.Parent.ImportService.Profiler)
    local Assert = require(script.Parent.Assert)

    local manifest = ManifestLoader.LoadNamedSample("SampleManifest")

    ImportPlanCache.Clear()
    Profiler.clear()
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_PerfTest",
        printReport = true,
    })

    local report = Profiler.generateReport()
    local summary = Profiler.generateSummary()
    Assert.truthy(report, "expected a report")
    Assert.truthy(summary, "expected a summary")
    Assert.truthy(#report.activities > 0, "expected at least one activity in report")
    Assert.truthy(summary.totalActivities > 0, "expected summary activities")
    Assert.truthy(summary.totalElapsedMs > 0, "expected positive total elapsed ms")
    Assert.truthy(#summary.byLabel > 0, "expected summary labels")
    Assert.truthy(summary.slowest ~= nil, "expected slowest activity")

    local importManifestActivity = nil
    local importChunkActivity = nil

    for _, activity in ipairs(report.activities) do
        if activity.label == "ImportManifest" then
            importManifestActivity = activity
        elseif activity.label == "ImportChunk" then
            importChunkActivity = activity
        end
    end

    Assert.truthy(importManifestActivity, "expected ImportManifest activity")
    Assert.truthy(importChunkActivity, "expected ImportChunk activity")
    Assert.truthy(importChunkActivity.extra.instanceCount > 0, "expected non-zero instance count")
    Assert.truthy(importManifestActivity.extra.totalInstances > 0, "expected non-zero total instances")
    Assert.truthy(summary.byLabel[1].totalMs >= summary.byLabel[1].avgMs, "expected valid aggregated timings")

    local cacheStats = ImportPlanCache.GetStats()
    Assert.truthy(cacheStats.misses > 0, "expected manifest import to populate import plan cache")
    Assert.truthy(cacheStats.size > 0, "expected populated import plan cache after import")
    local firstPassSize = cacheStats.size
    local firstPassHits = cacheStats.hits
    local firstPassImportManifestMs = importManifestActivity.elapsedMs
    local firstChunkEntry = ChunkLoader.GetChunkEntry("0_0", "GeneratedWorld_PerfTest")
    Assert.truthy(firstChunkEntry, "expected SampleManifest chunk to be registered after first import")
    Assert.truthy(firstChunkEntry.planKey, "expected registered SampleManifest chunk to expose a plan key")

    ImportService.ImportManifest(manifest, {
        clearFirst = false,
        worldRootName = "GeneratedWorld_PerfTest",
        printReport = false,
    })
    local warmedCacheStats = ImportPlanCache.GetStats()
    local warmedChunkEntry = ChunkLoader.GetChunkEntry("0_0", "GeneratedWorld_PerfTest")
    Assert.truthy(warmedChunkEntry, "expected SampleManifest chunk to stay registered after repeated import")
    Assert.truthy(warmedCacheStats.hits > firstPassHits, "expected repeated manifest import to hit import plan cache")
    print(
        ("[ArnisRoblox] Performance.spec cache firstSize=%d warmedSize=%d firstHits=%d warmedHits=%d warmedMisses=%d"):format(
            firstPassSize,
            warmedCacheStats.size,
            firstPassHits,
            warmedCacheStats.hits,
            warmedCacheStats.misses
        )
    )
    Assert.truthy(
        warmedCacheStats.size >= firstPassSize,
        "expected repeated import to retain previously prepared import plan entries"
    )
    Assert.equal(
        warmedChunkEntry.planKey,
        firstChunkEntry.planKey,
        "expected repeated import of same manifest chunk to preserve the same deterministic plan key"
    )

    local warmedReport = Profiler.generateReport()
    local warmedImportManifestActivity = nil
    for _, activity in ipairs(warmedReport.activities) do
        if activity.label == "ImportManifest" then
            warmedImportManifestActivity = activity
        end
    end
    Assert.truthy(warmedImportManifestActivity, "expected repeated import manifest profiler activity")
    local warmedPerfCeiling = math.max(firstPassImportManifestMs * 1.2, firstPassImportManifestMs + 35)
    print(
        ("[ArnisRoblox] Performance.spec firstImportMs=%.2f warmedImportMs=%.2f ceilingMs=%.2f"):format(
            firstPassImportManifestMs,
            warmedImportManifestActivity.elapsedMs,
            warmedPerfCeiling
        )
    )
    Assert.truthy(
        warmedImportManifestActivity.elapsedMs <= warmedPerfCeiling,
        "expected repeated import manifest pass to stay within 20% or 35ms of first pass"
    )

    local worldRoot = game:GetService("Workspace"):FindFirstChild("GeneratedWorld_PerfTest")
    if worldRoot then
        worldRoot:Destroy()
    end
end
