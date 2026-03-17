local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _Logger = require(ReplicatedStorage.Shared.Logger) -- reserved for future use

local WaterBuilder = {}

local function getMaterial(materialName)
	if materialName then
		local success, material = pcall(function()
			return Enum.Material[materialName]
		end)
		if success and material then
			return material
		end
	end
	return Enum.Material.Water
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

-- Generates ribbon geometry into an existing EditableMesh
local function addRibbonToMesh(editableMesh, points, width)
	if #points < 2 then
		return
	end

	local vertices = {}
	local halfWidth = width * 0.5

	-- 1. Generate vertices
	for i = 1, #points do
		local p = points[i]
		local tangent

		if i == 1 then
			tangent = (points[2] - points[1]).Unit
		elseif i == #points then
			tangent = (points[#points] - points[#points - 1]).Unit
		else
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

-- Generates polygon geometry into an existing EditableMesh
local function addPolygonToMesh(editableMesh, points, indices)
	if #points < 3 then
		return
	end

	local localIndices = {}
	for _, p in ipairs(points) do
		table.insert(localIndices, editableMesh:AddVertex(p))
	end

	if indices and #indices >= 3 then
		for i = 1, #indices, 3 do
			local i1 = localIndices[indices[i] + 1]
			local i2 = localIndices[indices[i + 1] + 1]
			local i3 = localIndices[indices[i + 2] + 1]
			if i1 and i2 and i3 then
				editableMesh:AddTriangle(i1, i2, i3)
			end
		end
	else
		-- Fallback to simple fan triangulation for convex polygons
		for i = 2, #localIndices - 1 do
			editableMesh:AddTriangle(localIndices[1], localIndices[i], localIndices[i + 1])
		end
	end
end

-- Build ALL water features in a chunk using Part-based geometry.
-- EditableMesh is skipped as it is not reliably available in all Studio/server contexts.
function WaterBuilder.BuildAll(parent, waters, originStuds)
	if not waters or #waters == 0 then
		return
	end

	for _, water in ipairs(waters) do
		WaterBuilder.FallbackBuild(parent, water, originStuds)
	end
end

function WaterBuilder.Build(parent, water, originStuds)
	return WaterBuilder.BuildAll(parent, { water }, originStuds)
end

function WaterBuilder.FallbackBuild(parent, water, originStuds)
	local material = getMaterial(water.material)
	local color = getColor3(water.color) or Color3.fromRGB(0, 100, 200)
	if water.points then
		for index = 1, #water.points - 1 do
			local fromPoint = offsetPoint(water.points[index], originStuds)
			local toPoint = offsetPoint(water.points[index + 1], originStuds)

			local delta = toPoint - fromPoint
			local length = delta.Magnitude
			if length > 0 then
				local part = Instance.new("Part")
				part.Name = (water.id or "Water") .. "_" .. index
				part.Anchored = true
				part.Transparency = 0.35
				part.Size = Vector3.new(water.widthStuds or 8, 0.5, length)
				part.CFrame = CFrame.lookAt(fromPoint + delta * 0.5, toPoint)
				part.Color = color
				part.Material = material
				part.Parent = parent
			end
		end
	elseif water.footprint then
		-- Fallback for polygon: simple box
		local minX, minZ, maxX, maxZ
		for _, p in ipairs(water.footprint) do
			local x = p.x + originStuds.x
			local z = p.z + originStuds.z
			if not minX then
				minX, minZ, maxX, maxZ = x, z, x, z
			else
				minX = math.min(minX, x)
				minZ = math.min(minZ, z)
				maxX = math.max(maxX, x)
				maxZ = math.max(maxZ, z)
			end
		end
		if minX then
			local part = Instance.new("Part")
			part.Name = water.id or "WaterBody"
			part.Anchored = true
			part.Transparency = 0.35
			part.Size = Vector3.new(maxX - minX, 0.5, maxZ - minZ)
			part.CFrame = CFrame.new((minX + maxX) * 0.5, originStuds.y, (minZ + maxZ) * 0.5)
			part.Color = color
			part.Material = material
			part.Parent = parent
		end
	end
end

return WaterBuilder
