return function()
    local Workspace = game:GetService("Workspace")
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local Assert = require(script.Parent.Assert)

    ChunkLoader.Clear()
    Assert.equal(
        #ChunkLoader.ListLoadedChunks(),
        0,
        "expected ChunkLoader.Clear to empty any preexisting registry entries"
    )

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
    end

    local destroyedRoot = createWorldRoot("ChunkLoaderDestroyingTestWorld")
    registerChunk(destroyedRoot, "destroy_a")
    registerChunk(destroyedRoot, "destroy_b")
    registerChunk(destroyedRoot, "destroy_c")

    Assert.equal(
        #ChunkLoader.ListLoadedChunks(),
        3,
        "expected three registered chunks before external destroy"
    )

    destroyedRoot:Destroy()

    Assert.equal(
        #ChunkLoader.ListLoadedChunks(),
        0,
        "expected external world-root destroy to unregister registered chunks"
    )

    local worldRoot = createWorldRoot("ChunkLoaderClearTestWorld")
    registerChunk(worldRoot, "clear_a")
    registerChunk(worldRoot, "clear_b")
    registerChunk(worldRoot, "clear_c")

    Assert.equal(#ChunkLoader.ListLoadedChunks(), 3, "expected three registered chunks before clear")

    ChunkLoader.Clear()

    Assert.equal(#ChunkLoader.ListLoadedChunks(), 0, "expected ChunkLoader.Clear to remove every registry entry")
    Assert.equal(#worldRoot:GetChildren(), 0, "expected ChunkLoader.Clear to destroy every registered chunk folder")

    worldRoot:Destroy()
end
