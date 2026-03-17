return function()
    local Workspace = game:GetService("Workspace")
    local ServerStorage = game:GetService("ServerStorage")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = require(ServerStorage.SampleData.SampleManifest)

    local stats = ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_Test",
    })

    Assert.equal(stats.chunksImported, 1, "expected one imported chunk")

    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_Test")
    Assert.truthy(worldRoot, "expected GeneratedWorld_Test to exist")

    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected chunk folder")

    worldRoot:Destroy()
end
