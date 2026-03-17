local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local Logger = require(ReplicatedStorage.Shared.Logger)

local RoadBuilder = {}

-- Material mapping (fallback if manifest doesn't provide one)
local FALLBACK_MATERIAL_PALETTE = {
	primary = Enum.Material.Asphalt,
	secondary = Enum.Material.Asphalt,
	tertiary = Enum.Material.Asphalt,
	service = Enum.Material.Concrete,
	default = Enum.Material.Asphalt,
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
	
	-- Lanes logic: if lanes provided, repeat texture X-times across width
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

		-- UV mapping:
		-- X: 0 to lanes across width
		-- Y: distance-based along length (repeating every 20 studs for markings)
		local uvY = cumulativeDist / 20.0
		
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

-- New optimized entry point to build ALL roads in a chunk into a single MeshPart
function RoadBuilder.BuildAll(parent, roads, originStuds)
	if not roads or #roads == 0 then
		return
	end

	-- Group roads by material and color to minimize MeshParts
	local groups = {}
	for _, road in ipairs(roads) do
		local material = getMaterial(road.material, road.kind)
		local color = getColor3(road.color)
		local key = material.Name .. (color and tostring(color) or "none")
		
		if not groups[key] then
			groups[key] = {
				material = material,
				color = color,
				roads = {}
			}
		end
		table.insert(groups[key].roads, road)
	end

	for _, group in pairs(groups) do
		local meshPart = Instance.new("MeshPart")
		meshPart.Name = "MergedRoads_" .. group.material.Name
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
			for _, road in ipairs(group.roads) do
				local points = {}
				for _, p in ipairs(road.points) do
					table.insert(points, offsetPoint(p, originStuds))
				end
				addRibbonToMesh(editableMesh, points, road.widthStuds or 10, road.lanes)
			end
			editableMesh.Parent = meshPart
		else
			Logger.warn("Failed to create EditableMesh for merged roads:", err or "unknown error")
			meshPart:Destroy()
			for _, road in ipairs(group.roads) do
				RoadBuilder.FallbackBuild(parent, road, originStuds)
			end
		end
	end
end

function RoadBuilder.Build(parent, road, originStuds)
	return RoadBuilder.BuildAll(parent, { road }, originStuds)
end

-- Minimal fallback using segment-based part creation
function RoadBuilder.FallbackBuild(parent, road, originStuds)
	local material = getMaterial(road.material, road.kind)
	local color = getColor3(road.color)
	for index = 1, #road.points - 1 do
		local fromPoint = offsetPoint(road.points[index], originStuds)
		local toPoint = offsetPoint(road.points[index + 1], originStuds)

		local delta = toPoint - fromPoint
		local length = delta.Magnitude
		if length > 0 then
			local part = Instance.new("Part")
			part.Name = (road.id or "Road") .. "_" .. index
			part.Anchored = true
			part.Size = Vector3.new(road.widthStuds or 10, 0.5, length)
			part.CFrame = CFrame.lookAt(fromPoint + delta * 0.5, toPoint)
			part.Material = material
			if color then
				part.Color = color
			end
			part.Parent = parent
		end
	end
end

return RoadBuilder
