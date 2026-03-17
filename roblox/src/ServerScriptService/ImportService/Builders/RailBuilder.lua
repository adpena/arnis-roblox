local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local Logger = require(ReplicatedStorage.Shared.Logger)

local RailBuilder = {}

-- Material mapping (fallback)
local FALLBACK_MATERIAL_PALETTE = {
	rail = Enum.Material.Metal,
	subway = Enum.Material.Metal,
	tram = Enum.Material.Metal,
	default = Enum.Material.Metal,
}

local function getMaterial(materialName, kind)
	if materialName then
		local success, material = pcall(function()
			return Enum.Material[materialName]
		end)
		if success and material then
			return material
		end
	end
	return FALLBACK_MATERIAL_PALETTE[kind] or FALLBACK_MATERIAL_PALETTE.default
end

local function getColor3(colorTable)
	if colorTable and colorTable.r then
		return Color3.fromRGB(colorTable.r, colorTable.g, colorTable.b)
	end
	return nil
end

local function offsetPoint(point, origin)
	return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

-- Generates ribbon geometry into an existing EditableMesh with UV mapping
local function addRibbonToMesh(editableMesh, points, width, lanes)
	if #points < 2 then
		return
	end

	local halfWidth = width * 0.5
	local cumulativeDist = 0
	local vertices = {}
	
	-- Multi-track support: repeat texture if lanes > 1
	local uvXScale = lanes or 1

	-- 1. Generate vertices and UVs
	for i = 1, #points do
		local p = points[i]
		local tangent

		if i == 1 then
			tangent = (points[2] - points[1]).Unit
		elseif i == #points then
			tangent = (points[#points] - points[#points - 1]).Unit
			cumulativeDist += (points[#points] - points[#points - 1]).Magnitude
		else
			local d = (points[i] - points[i - 1]).Magnitude
			cumulativeDist += d
			local t1 = (points[i] - points[i - 1]).Unit
			local t2 = (points[i + 1] - points[i]).Unit
			tangent = (t1 + t2).Unit
		end

		local up = Vector3.new(0, 1, 0)
		local right = tangent:Cross(up).Unit * halfWidth

		local v1 = p + right
		local v2 = p - right

		local idx1 = editableMesh:AddVertex(v1)
		local idx2 = editableMesh:AddVertex(v2)

		-- UV mapping for rails:
		-- Y: distance-based, repeat every 4 studs for sleepers (ties)
		local uvY = cumulativeDist / 4.0
		
		editableMesh:SetVertexUV(idx1, Vector2.new(0, uvY))
		editableMesh:SetVertexUV(idx2, Vector2.new(uvXScale, uvY))

		table.insert(vertices, { idx1, idx2 })
	end

	-- 2. Generate triangles
	for i = 1, #points - 1 do
		local cur = vertices[i]
		local nxt = vertices[i + 1]

		editableMesh:AddTriangle(cur[1], nxt[1], cur[2])
		editableMesh:AddTriangle(nxt[1], nxt[2], cur[2])
	end
end

-- Optimized entry point to build ALL rails in a chunk into merged MeshParts
function RailBuilder.BuildAll(parent, rails, originStuds)
	if not rails or #rails == 0 then
		return
	end

	local groups = {}
	for _, rail in ipairs(rails) do
		local material = getMaterial(rail.material, rail.kind)
		local color = getColor3(rail.color)
		local key = material.Name .. (color and tostring(color) or "none")
		
		if not groups[key] then
			groups[key] = {
				material = material,
				color = color,
				rails = {}
			}
		end
		table.insert(groups[key].rails, rail)
	end

	for _, group in pairs(groups) do
		local meshPart = Instance.new("MeshPart")
		meshPart.Name = "MergedRails_" .. group.material.Name
		meshPart.Anchored = true
		meshPart.CanCollide = true
		meshPart.Material = group.material
		if group.color then
			meshPart.Color = group.color
		end
		meshPart.Parent = parent

		local editableMesh
		local success, err = pcall(function()
			editableMesh = AssetService:CreateEditableMesh()
		end)

		if success and editableMesh then
			for _, rail in ipairs(group.rails) do
				local points = {}
				for _, p in ipairs(rail.points) do
					table.insert(points, offsetPoint(p, originStuds))
				end
				addRibbonToMesh(editableMesh, points, rail.widthStuds or 4, rail.lanes)
			end
			editableMesh.Parent = meshPart
		else
			Logger.warn("Failed to create EditableMesh for merged rails:", err or "unknown error")
			meshPart:Destroy()
			for _, rail in ipairs(group.rails) do
				RailBuilder.FallbackBuild(parent, rail, originStuds)
			end
		end
	end
end

function RailBuilder.Build(parent, rail, originStuds)
	return RailBuilder.BuildAll(parent, { rail }, originStuds)
end

function RailBuilder.FallbackBuild(parent, rail, originStuds)
	local material = getMaterial(rail.material, rail.kind)
	local color = getColor3(rail.color)
	for index = 1, #rail.points - 1 do
		local fromPoint = offsetPoint(rail.points[index], originStuds)
		local toPoint = offsetPoint(rail.points[index + 1], originStuds)

		local delta = toPoint - fromPoint
		local length = delta.Magnitude
		if length > 0 then
			local part = Instance.new("Part")
			part.Name = (rail.id or "Rail") .. "_" .. index
			part.Anchored = true
			part.Size = Vector3.new(rail.widthStuds or 4, 0.5, length)
			part.CFrame = CFrame.lookAt(fromPoint + delta * 0.5, toPoint)
			part.Material = material
			if color then
				part.Color = color
			end
			part.Parent = parent
		end
	end
end

return RailBuilder
