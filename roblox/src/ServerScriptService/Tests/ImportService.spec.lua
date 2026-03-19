return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = ManifestLoader.LoadNamedSample("SampleManifest")

    local stats = ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_Test",
    })

    Assert.equal(stats.chunksImported, 1, "expected one imported chunk")

    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_Test")
    Assert.truthy(worldRoot, "expected GeneratedWorld_Test to exist")

    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected chunk folder")

    local chunkFolderRef = chunkFolder
    local repeatStats = ImportService.ImportManifest(manifest, {
        clearFirst = false,
        worldRootName = "GeneratedWorld_Test",
    })
    Assert.equal(repeatStats.chunksImported, 1, "expected one imported chunk on repeat import")

    local chunkFolders = {}
    for _, child in ipairs(worldRoot:GetChildren()) do
        if child.Name == "0_0" then
            chunkFolders[#chunkFolders + 1] = child
        end
    end
    Assert.equal(#chunkFolders, 1, "expected repeat import to keep a single authoritative chunk folder")
    Assert.equal(chunkFolders[1], chunkFolderRef, "expected repeat import to preserve chunk folder instance")

    worldRoot:Destroy()
end
