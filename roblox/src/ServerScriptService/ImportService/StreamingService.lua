local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImportService = require(script.Parent.init)
local ChunkLoader = require(script.Parent.ChunkLoader)
local DefaultWorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Logger = require(ReplicatedStorage.Shared.Logger)

local StreamingService = {}

local streamingManifest = nil
local streamingOptions = nil
local heartbeatConn = nil
local lastUpdate = 0
local UPDATE_INTERVAL = 1.0 -- seconds between distance checks

local LOD_HIGH = "High"
local LOD_LOW = "Low"

-- Registry of chunkId -> current LOD level
local loadedChunkLods = {}

local function getLodConfig(level, baseConfig)
	local config = table.clone(baseConfig)
	if level == LOD_LOW then
		-- Low LOD: keep terrain and roads, hide buildings/water/props
		config.BuildingMode = "none"
		config.WaterMode = "none"
		-- config.RoadMode = "mesh" -- Keep roads for macro shape
	end
	return config
end

function StreamingService.Start(manifest, options)
	if heartbeatConn then
		StreamingService.Stop()
	end

	streamingManifest = manifest
	streamingOptions = options or {}
	local config = streamingOptions.config or DefaultWorldConfig

	if not config.StreamingEnabled then
		Logger.warn("StreamingService.Start called but StreamingEnabled is false in config")
		return
	end

	Logger.info("StreamingService started for world:", manifest.meta.worldName)

	heartbeatConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastUpdate >= UPDATE_INTERVAL then
			lastUpdate = now
			StreamingService.Update()
		end
	end)
end

function StreamingService.Stop()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	streamingManifest = nil
	streamingOptions = nil
	loadedChunkLods = {}
end

function StreamingService.Update(focalPoint)
	if not streamingManifest then return end

	local playerPos
	if focalPoint then
		playerPos = focalPoint
	else
		local player = Players.LocalPlayer
		if not player then
			player = Players:GetPlayers()[1]
		end

		local character = player and player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		playerPos = rootPart.Position
	end

	local config = streamingOptions.config or DefaultWorldConfig
	local targetRadius = config.StreamingTargetRadius or 2048
	local highRadius = config.HighDetailRadius or 1024
	
	local targetRadiusSq = targetRadius * targetRadius
	local highRadiusSq = highRadius * highRadius

	for _, chunk in ipairs(streamingManifest.chunks) do
		local origin = Vector3.new(chunk.originStuds.x, chunk.originStuds.y, chunk.originStuds.z)
		local halfSize = config.ChunkSizeStuds * 0.5
		local center = origin + Vector3.new(halfSize, 0, halfSize)
		
		local distSq = (playerPos - center).Magnitude ^ 2
		
		local targetLod = nil
		if distSq <= highRadiusSq then
			targetLod = LOD_HIGH
		elseif distSq <= targetRadiusSq then
			targetLod = LOD_LOW
		end

		local currentLod = loadedChunkLods[chunk.id]

		if targetLod ~= currentLod then
			if targetLod then
				-- Load or Upgrade/Downgrade
				local chunkOptions = table.clone(streamingOptions)
				chunkOptions.config = getLodConfig(targetLod, config)
				
				ImportService.ImportChunk(chunk, chunkOptions)
				loadedChunkLods[chunk.id] = targetLod
			else
				-- Unload
				ChunkLoader.UnloadChunk(chunk.id)
				loadedChunkLods[chunk.id] = nil
			end
		end
	end
end

return StreamingService
