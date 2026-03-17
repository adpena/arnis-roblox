local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local RailBuilder = {}

local RAIL_THICKNESS = 1

local function offsetPoint(point, origin)
	return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

local function paintSegment(terrain, p1, p2, width)
	local delta  = p2 - p1
	local length = delta.Magnitude
	if length < 0.01 then return end

	local midY   = p1.Y - RAIL_THICKNESS * 0.5
	local midPos = Vector3.new((p1.X + p2.X) * 0.5, midY, (p1.Z + p2.Z) * 0.5)
	local cf     = CFrame.lookAt(midPos, Vector3.new(p2.X, midY, p2.Z))
	terrain:FillBlock(cf, Vector3.new(width, RAIL_THICKNESS, length), Enum.Material.Cobblestone)
end

function RailBuilder.BuildAll(parent, rails, originStuds)
	if not rails or #rails == 0 then return end
	for _, rail in ipairs(rails) do
		RailBuilder.FallbackBuild(parent, rail, originStuds)
	end
end

function RailBuilder.Build(parent, rail, originStuds)
	RailBuilder.FallbackBuild(parent, rail, originStuds)
end

function RailBuilder.FallbackBuild(_parent, rail, originStuds)
	local terrain = Workspace.Terrain
	local width   = rail.widthStuds or 4
	for i = 1, #rail.points - 1 do
		local p1 = offsetPoint(rail.points[i],     originStuds)
		local p2 = offsetPoint(rail.points[i + 1], originStuds)
		paintSegment(terrain, p1, p2, width)
	end
end

return RailBuilder
