local TerrainBuilder = require(script.Parent.Builders.TerrainBuilder)
local PropBuilder = require(script.Parent.Builders.PropBuilder)
local Profiler = require(script.Parent.Profiler)

local ChunkLoader = {}

local registry = {}

function ChunkLoader.RegisterChunk(chunkId, folder, chunk)
	registry[chunkId] = {
		folder = folder,
		chunk = chunk,
	}
end

function ChunkLoader.GetChunkFolder(chunkId)
	local entry = registry[chunkId]
	return entry and entry.folder
end

function ChunkLoader.UnloadChunk(chunkId)
	local entry = registry[chunkId]
	if entry then
		local profile = Profiler.begin("UnloadChunk")

		if entry.folder then
			local propsFolder = entry.folder:FindFirstChild("Props")
			if propsFolder then
				PropBuilder.ReleaseAll(propsFolder)
			end
			entry.folder:Destroy()
		end

		if entry.chunk and entry.chunk.terrain then
			TerrainBuilder.Clear(entry.chunk)
		end

		registry[chunkId] = nil

		Profiler.finish(profile, { chunkId = chunkId })
	end
end

function ChunkLoader.ListLoadedChunks()
	local result = {}

	for chunkId, _ in pairs(registry) do
		table.insert(result, chunkId)
	end

	table.sort(result)
	return result
end

function ChunkLoader.Clear()
	for chunkId, _ in pairs(registry) do
		ChunkLoader.UnloadChunk(chunkId)
	end
end

return ChunkLoader
