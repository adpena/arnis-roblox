--[[
  BootstrapAustin.server.lua
  Automatically imports the Austin, TX manifest when the game starts.
  This runs on Play (server-side) so you can open Studio, hit Play, and see Austin.

  To disable: set ENABLED = false below.
--]]

local ENABLED = true

if not ENABLED then
	return
end

local RunAustin = require(script.Parent.ImportService.RunAustin)

print("[BootstrapAustin] Starting Austin, TX import...")

-- Performance settings that must be set before world generation
Workspace.StreamingEnabled = true
Workspace.StreamingTargetRadius = 256
Workspace.StreamingMinRadius = 64
Workspace.Terrain.SmoothingEnabled = true

RunAustin.run()
print("[BootstrapAustin] Done.")

-- Place the spawn point near world origin at Congress Ave ground level.
-- We raycast AFTER import so terrain exists when we sample height.
local spawn = Instance.new("SpawnLocation")
spawn.Name = "CongressAveSpawn"
spawn.Size = Vector3.new(6, 1, 6)
spawn.Anchored = true
spawn.Material = Enum.Material.Concrete
spawn.BrickColor = BrickColor.new("Medium stone grey")
spawn.Parent = Workspace

local ray = Workspace:Raycast(Vector3.new(0, 1000, 0), Vector3.new(0, -2000, 0))
local spawnY = ray and (ray.Position.Y + 5) or 5
spawn.CFrame = CFrame.new(0, spawnY, 0)

-- Lighting
local Lighting = game:GetService("Lighting")
Lighting.Ambient = Color3.fromRGB(120, 100, 80)       -- warm Texas ambient
Lighting.Brightness = 3.5
Lighting.ColorShift_Bottom = Color3.fromRGB(255, 200, 120)
Lighting.ColorShift_Top = Color3.fromRGB(180, 220, 255)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.8
Lighting.ExposureCompensation = 0.3
Lighting.GeographicLatitude = 30.265    -- Austin, TX
Lighting.TimeOfDay = "16:30:00"         -- late afternoon golden hour
Lighting.ShadowSoftness = 0.3
Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 180)

-- Atmosphere
local atmo = Instance.new("Atmosphere", Lighting)
atmo.Density = 0.35
atmo.Offset = 0.2
atmo.Color = Color3.fromRGB(255, 220, 170)   -- warm Texas haze
atmo.Decay = Color3.fromRGB(100, 80, 60)
atmo.Glare = 0.4
atmo.Haze = 1.8

-- Bloom post-processing
local bloom = Instance.new("BloomEffect", Lighting)
bloom.Intensity = 0.4
bloom.Size = 24
bloom.Threshold = 0.95

-- Sun rays
local sunRays = Instance.new("SunRaysEffect", Lighting)
sunRays.Intensity = 0.08
sunRays.Spread = 0.5

-- Color correction for cinematic look
local cc = Instance.new("ColorCorrectionEffect", Lighting)
cc.Brightness = 0.02
cc.Contrast = 0.08
cc.Saturation = 0.15
cc.TintColor = Color3.fromRGB(255, 248, 235)

print("[BootstrapAustin] Spawn and atmosphere configured.")
