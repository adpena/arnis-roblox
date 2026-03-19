return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = ManifestLoader.LoadNamedSample("SampleMultiChunkManifest")

    local stats = ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_MultiChunkTest",
    })

    -- We expect two chunks from the multi-chunk sample fixture
    Assert.equal(stats.chunksImported, 2, "expected two imported chunks")

    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_MultiChunkTest")
    Assert.truthy(worldRoot, "expected GeneratedWorld_MultiChunkTest to exist")

    local chunk00 = worldRoot:FindFirstChild("0_0")
    local chunk10 = worldRoot:FindFirstChild("1_0")
    Assert.truthy(chunk00, "expected chunk 0_0 folder")
    Assert.truthy(chunk10, "expected chunk 1_0 folder")

    worldRoot:Destroy()
end
