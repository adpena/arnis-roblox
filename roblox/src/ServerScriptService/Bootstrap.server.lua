local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ImportService = require(script.Parent.ImportService)
local StreamingService = require(script.Parent.ImportService.StreamingService)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local RUN_ON_BOOT = false

if not RUN_ON_BOOT then
    return
end

local sampleData = ServerStorage:WaitForChild("SampleData")
local manifest = require(sampleData:WaitForChild("SampleManifest"))

if DefaultWorldConfig.StreamingEnabled then
	StreamingService.Start(manifest, {
		worldRootName = "GeneratedWorld",
		clearFirst = true,
	})
else
	ImportService.ImportManifest(manifest, {
		clearFirst = true,
		worldRootName = "GeneratedWorld",
	})
end
