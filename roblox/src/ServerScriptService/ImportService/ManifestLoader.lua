local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local Logger = require(ReplicatedStorage.Shared.Logger)

local ManifestLoader = {}

function ManifestLoader.LoadFromModule(module)
	if not module:IsA("ModuleScript") then
		error("Manifest must be a ModuleScript")
	end

	local manifest = require(module)
	return ChunkSchema.validateManifest(manifest)
end

function ManifestLoader.LoadSample()
	local sample = require(ServerStorage.SampleData.SampleManifest)
	return ChunkSchema.validateManifest(sample)
end

function ManifestLoader.LoadFromFile(_path)
	-- In Studio, we might use a plugin to read files, 
	-- but for runtime scripts we rely on pre-loaded ModuleScripts.
	Logger.warn("LoadFromFile not implemented for runtime - use LoadFromModule")
	return nil
end

return ManifestLoader
