return function()
	local Workspace = game:GetService("Workspace")
	local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
	local StreamingService = require(script.Parent.Parent.ImportService.StreamingService)
	local Assert = require(script.Parent.Assert)

	-- 1. Setup a test manifest with one chunk
	local testManifest = {
		schemaVersion = "0.2.0",
		meta = {
			worldName = "LODTest",
			generator = "test",
			source = "test",
			metersPerStud = 1,
			chunkSizeStuds = 100,
			bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
			totalFeatures = 1,
		},
		chunks = {
			{
				id = "lod_chunk",
				originStuds = { x = 0, y = 0, z = 0 },
				roads = {}, 
				buildings = {
					{
						id = "b1",
						footprint = { {x=10, z=10}, {x=20, z=10}, {x=20, z=20} },
						baseY = 0, height = 10, roof = "flat"
					}
				}, 
				water = {}, props = {},
			}
		}
	}

	local testOptions = {
		worldRootName = "LODTestWorld",
		config = {
			StreamingEnabled = true,
			StreamingTargetRadius = 1000, -- Low LOD limit
			HighDetailRadius = 500,      -- High LOD limit
			ChunkSizeStuds = 100,
			BuildingMode = "shellMesh",
			RoadMode = "mesh",
			TerrainMode = "none",
			WaterMode = "none",
		}
	}

	local function getBuildingsCount()
		local worldRoot = Workspace:FindFirstChild("LODTestWorld")
		if not worldRoot then return 0 end
		local chunkFolder = worldRoot:FindFirstChild("lod_chunk")
		if not chunkFolder then return 0 end
		local buildingsFolder = chunkFolder:FindFirstChild("Buildings")
		if not buildingsFolder then return 0 end
		return #buildingsFolder:GetChildren()
	end

	-- 2. Start streaming
	ChunkLoader.Clear()
	StreamingService.Start(testManifest, testOptions)

	-- 3. High LOD: Focal point at 0,0,0
	StreamingService.Update(Vector3.new(0, 0, 0))
	Assert.equal(getBuildingsCount() > 0, true, "expected buildings at High LOD")

	-- 4. Low LOD: Focal point at 750,0,750 (outside 500, inside 1000)
	StreamingService.Update(Vector3.new(750, 0, 750))
	Assert.equal(getBuildingsCount(), 0, "expected NO buildings at Low LOD")

	-- 5. Back to High LOD
	StreamingService.Update(Vector3.new(0, 0, 0))
	Assert.equal(getBuildingsCount() > 0, true, "expected buildings to return at High LOD")

	-- 6. Unload: Focal point at 2000,0,2000
	StreamingService.Update(Vector3.new(2000, 0, 2000))
	local loaded = ChunkLoader.ListLoadedChunks()
	Assert.equal(#loaded, 0, "expected chunk to be unloaded")

	-- Cleanup
	StreamingService.Stop()
	local worldRoot = Workspace:FindFirstChild("LODTestWorld")
	if worldRoot then
		worldRoot:Destroy()
	end
	ChunkLoader.Clear()
end
