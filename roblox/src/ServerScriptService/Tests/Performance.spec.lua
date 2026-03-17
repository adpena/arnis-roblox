return function()
	local ServerStorage = game:GetService("ServerStorage")
	local ImportService = require(script.Parent.Parent.ImportService)
	local Profiler = require(script.Parent.Parent.ImportService.Profiler)
	local Assert = require(script.Parent.Assert)

	local manifest = require(ServerStorage.SampleData.SampleManifest)

	Profiler.clear()
	ImportService.ImportManifest(manifest, {
		clearFirst = true,
		worldRootName = "GeneratedWorld_PerfTest",
		printReport = true,
	})

	local report = Profiler.generateReport()
	Assert.truthy(report, "expected a report")
	Assert.truthy(#report.activities > 0, "expected at least one activity in report")

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

	game:GetService("Workspace"):FindFirstChild("GeneratedWorld_PerfTest"):Destroy()
end
