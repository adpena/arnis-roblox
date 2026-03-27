return function()
    local Workspace = game:GetService("Workspace")
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local Assert = require(script.Parent.Assert)

    local function createWorldRoot(name)
        local worldRoot = Instance.new("Folder")
        worldRoot.Name = name
        worldRoot.Parent = Workspace
        return worldRoot
    end

    local function registerChunk(worldRoot, chunkId)
        local chunkFolder = Instance.new("Folder")
        chunkFolder.Name = chunkId
        chunkFolder.Parent = worldRoot
        ChunkLoader.RegisterChunk(chunkId, chunkFolder, {
            id = chunkId,
            originStuds = { x = 0, y = 0, z = 0 },
        })
        return chunkFolder
    end

    ChunkLoader.Clear()

    local runtimeRoot = createWorldRoot("ChunkLoaderRuntimeWorld")
    local previewRoot = createWorldRoot("ChunkLoaderPreviewWorld")

    local runtimeSharedFolder = registerChunk(runtimeRoot, "shared_chunk")
    local previewSharedFolder = registerChunk(previewRoot, "shared_chunk")
    registerChunk(runtimeRoot, "runtime_only")

    local runtimeLoaded = ChunkLoader.ListLoadedChunks("ChunkLoaderRuntimeWorld")
    Assert.equal(#runtimeLoaded, 2, "expected runtime world to see only its own chunks")
    Assert.equal(runtimeLoaded[1], "runtime_only", "expected runtime_only chunk in runtime scope")
    Assert.equal(runtimeLoaded[2], "shared_chunk", "expected shared chunk in runtime scope")

    local previewLoaded = ChunkLoader.ListLoadedChunks("ChunkLoaderPreviewWorld")
    Assert.equal(#previewLoaded, 1, "expected preview world to see only its own chunks")
    Assert.equal(previewLoaded[1], "shared_chunk", "expected shared chunk in preview scope")

    local runtimeEntry = ChunkLoader.GetChunkEntry("shared_chunk", "ChunkLoaderRuntimeWorld")
    local previewEntry = ChunkLoader.GetChunkEntry("shared_chunk", "ChunkLoaderPreviewWorld")
    Assert.truthy(runtimeEntry, "expected runtime shared chunk entry")
    Assert.truthy(previewEntry, "expected preview shared chunk entry")
    Assert.equal(runtimeEntry.folder, runtimeSharedFolder, "expected runtime scope to preserve runtime folder")
    Assert.equal(previewEntry.folder, previewSharedFolder, "expected preview scope to preserve preview folder")

    ChunkLoader.UnloadChunk("shared_chunk", false, "ChunkLoaderRuntimeWorld")

    Assert.equal(
        #ChunkLoader.ListLoadedChunks("ChunkLoaderRuntimeWorld"),
        1,
        "expected runtime unload to leave preview scope intact"
    )
    Assert.equal(
        #ChunkLoader.ListLoadedChunks("ChunkLoaderPreviewWorld"),
        1,
        "expected preview scope to remain registered after runtime unload"
    )
    Assert.truthy(
        previewRoot:FindFirstChild("shared_chunk"),
        "expected preview shared chunk folder to survive runtime unload"
    )

    ChunkLoader.Clear("ChunkLoaderPreviewWorld")
    Assert.equal(
        #ChunkLoader.ListLoadedChunks("ChunkLoaderPreviewWorld"),
        0,
        "expected scoped clear to empty preview world only"
    )
    Assert.equal(
        #ChunkLoader.ListLoadedChunks("ChunkLoaderRuntimeWorld"),
        1,
        "expected scoped clear to preserve runtime world"
    )

    ChunkLoader.Clear()
    runtimeRoot:Destroy()
    previewRoot:Destroy()
end
