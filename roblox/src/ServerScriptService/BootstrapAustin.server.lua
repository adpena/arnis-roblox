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
