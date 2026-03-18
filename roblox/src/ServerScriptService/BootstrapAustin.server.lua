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
RunAustin.run()
print("[BootstrapAustin] Done.")

-- Place the spawn point near world origin at Congress Ave ground level
local spawn = Instance.new("SpawnLocation")
spawn.Name = "CongressAveSpawn"
spawn.Size = Vector3.new(6, 1, 6)
spawn.CFrame = CFrame.new(0, 5, 0)  -- Y=5: just above flat terrain surface at origin
spawn.Anchored = true
spawn.Material = Enum.Material.Concrete
spawn.BrickColor = BrickColor.new("Medium stone grey")
spawn.Parent = Workspace

-- Austin, TX atmosphere: warm afternoon sun
local Lighting = game:GetService("Lighting")
Lighting.TimeOfDay = "15:30:00"   -- 3:30 PM golden hour
Lighting.GeographicLatitude = 30.265  -- Austin latitude for correct sun angle
Lighting.Brightness = 2
Lighting.Ambient = Color3.fromRGB(70, 60, 55)
Lighting.OutdoorAmbient = Color3.fromRGB(130, 120, 110)
Lighting.ShadowSoftness = 0.25
Lighting.FogEnd = 3000
Lighting.FogColor = Color3.fromRGB(180, 170, 160)

-- Atmosphere effect
local atmos = Instance.new("Atmosphere")
atmos.Density = 0.4
atmos.Offset = 0.1
atmos.Color = Color3.fromRGB(199, 170, 140)
atmos.Decay = Color3.fromRGB(100, 80, 60)
atmos.Glare = 0.3
atmos.Haze = 1.5
atmos.Parent = Lighting

print("[BootstrapAustin] Spawn and atmosphere configured.")
