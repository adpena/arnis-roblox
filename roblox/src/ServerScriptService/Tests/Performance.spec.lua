return function()
    local ImportService = require(script.Parent.Parent.ImportService)
    local ImportPlanCache = require(script.Parent.Parent.ImportService.ImportPlanCache)
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
    local firstPassMisses = cacheStats.misses
    local firstPassSize = cacheStats.size
    local firstPassImportManifestMs = importManifestActivity.elapsedMs

    ImportService.ImportManifest(manifest, {
        clearFirst = false,
        worldRootName = "GeneratedWorld_PerfTest",
        printReport = false,
    })
    local warmedCacheStats = ImportPlanCache.GetStats()
    Assert.truthy(warmedCacheStats.hits > 0, "expected repeated manifest import to hit import plan cache")
    Assert.equal(warmedCacheStats.size, firstPassSize, "expected repeated import to keep import plan cache size stable")
    Assert.equal(
        warmedCacheStats.misses,
        firstPassMisses,
        "expected repeated import of same manifest to avoid new import plan cache misses"
    )

    local warmedReport = Profiler.generateReport()
    local warmedImportManifestActivity = nil
    for _, activity in ipairs(warmedReport.activities) do
        if activity.label == "ImportManifest" then
            warmedImportManifestActivity = activity
        end
    end
    Assert.truthy(warmedImportManifestActivity, "expected repeated import manifest profiler activity")
    Assert.truthy(
        warmedImportManifestActivity.elapsedMs <= firstPassImportManifestMs * 1.1,
        "expected repeated import manifest pass to stay within 10% of first pass"
    )

    local worldRoot = game:GetService("Workspace"):FindFirstChild("GeneratedWorld_PerfTest")
    if worldRoot then
        worldRoot:Destroy()
    end
end
