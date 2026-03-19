local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ImportService = require(script.Parent.ImportService)
local StreamingService = require(script.Parent.ImportService.StreamingService)
local ManifestLoader = require(script.Parent.ImportService.ManifestLoader)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local RUN_ON_BOOT = false

if not RUN_ON_BOOT then
    return
end

local manifest = ManifestLoader.LoadNamedSample("SampleManifest")

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
