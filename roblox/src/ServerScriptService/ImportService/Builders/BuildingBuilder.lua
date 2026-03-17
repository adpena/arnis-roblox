local BuildingBuilder = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local Logger = require(ReplicatedStorage.Shared.Logger)

-- Material mapping (fallback)
local FALLBACK_MATERIAL_PALETTE = {
	default = Enum.Material.Concrete,
	industrial = Enum.Material.Metal,
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
	return Vector3.new(point.x + origin.x, origin.y, point.z + origin.z)
end

-- Triangulate a simple convex polygon for the roof (fallback)
local function addFanTriangulation(editableMesh, vertexIndices)
	if #vertexIndices < 3 then
		return
	end
	for i = 2, #vertexIndices - 1 do
		editableMesh:AddTriangle(vertexIndices[1], vertexIndices[i], vertexIndices[i + 1])
	end
end

-- Generates geometric detailing (cornices, ledges) along a facade segment
local function addDetailing(editableMesh, p1, p2, baseY, height, levels)
	if not levels or levels <= 0 then return end
	
	local floorHeight = height / levels
	local normal = Vector3.new(p2.Z - p1.Z, 0, p1.X - p2.X).Unit
	local extrusionDepth = 0.5
	local ledgeThickness = 0.3
	
	for i = 1, levels do
		local floorBottomY = baseY + (i - 1) * floorHeight
		local corniceY = floorBottomY + floorHeight
		
		-- Simple floor divider (cornice) at the top of each level
		if i < levels or height > 5 then
			local c1 = p1 + Vector3.new(0, corniceY, 0)
			local c2 = p2 + Vector3.new(0, corniceY, 0)
			local e1 = c1 + normal * extrusionDepth
			local e2 = c2 + normal * extrusionDepth
			local b1 = e1 - Vector3.new(0, ledgeThickness, 0)
			local b2 = e2 - Vector3.new(0, ledgeThickness, 0)
			
			local v1 = editableMesh:AddVertex(c1)
			local v2 = editableMesh:AddVertex(c2)
			local v3 = editableMesh:AddVertex(e1)
			local v4 = editableMesh:AddVertex(e2)
			local v5 = editableMesh:AddVertex(b1)
			local v6 = editableMesh:AddVertex(b2)
			
			-- Cornice top face
			editableMesh:AddTriangle(v1, v3, v2)
			editableMesh:AddTriangle(v3, v4, v2)
			-- Cornice front face
			editableMesh:AddTriangle(v3, v5, v4)
			editableMesh:AddTriangle(v5, v6, v4)
		end
	end
end

-- Generates building shell geometry into an existing EditableMesh
local function addBuildingToMesh(editableMesh, points, baseY, height, indices, levels, _roofLevels)
	local bottomIndices = {}
	local topIndices = {}

	-- 1. Create vertices
	local cumulativeDist = 0
	for i, p in ipairs(points) do
		local prevP = points[i > 1 and i-1 or #points]
		cumulativeDist += (Vector3.new(p.X, 0, p.Z) - Vector3.new(prevP.X, 0, prevP.Z)).Magnitude
		
		local bottomPos = Vector3.new(p.x, p.y + baseY, p.z)
		local topPos = Vector3.new(p.x, p.y + baseY + height, p.z)
		
		local bIdx = editableMesh:AddVertex(bottomPos)
		local tIdx = editableMesh:AddVertex(topPos)
		
		-- Facade UV mapping
		local uvX = cumulativeDist / 10.0
		local floorHeight = 12.0
		if levels and levels > 0 then
			floorHeight = height / levels
		end
		
		local uvYBottom = (p.y + baseY) / floorHeight
		local uvYTop = (p.y + baseY + height) / floorHeight
		
		editableMesh:SetVertexUV(bIdx, Vector2.new(uvX, uvYBottom))
		editableMesh:SetVertexUV(tIdx, Vector2.new(uvX, uvYTop))
		
		table.insert(bottomIndices, bIdx)
		table.insert(topIndices, tIdx)
	end

	-- 2. Create wall triangles (quads) and detailing
	local count = #points
	for i = 1, count do
		local nextI = i % count + 1
		local b1 = bottomIndices[i]
		local b2 = bottomIndices[nextI]
		local t1 = topIndices[i]
		local t2 = topIndices[nextI]

		editableMesh:AddTriangle(b1, t1, b2)
		editableMesh:AddTriangle(t1, t2, b2)
		
		-- Add procedural detailing geometry
		addDetailing(editableMesh, points[i], points[nextI], baseY, height, levels)
	end

	-- 3. Create roof triangles
	if indices and #indices >= 3 then
		for i = 1, #indices, 3 do
			local i1 = topIndices[indices[i] + 1]
			local i2 = topIndices[indices[i + 1] + 1]
			local i3 = topIndices[indices[i + 2] + 1]
			if i1 and i2 and i3 then
				local p1 = editableMesh:GetVertexPosition(i1)
				local p2 = editableMesh:GetVertexPosition(i2)
				local p3 = editableMesh:GetVertexPosition(i3)
				
				editableMesh:SetVertexUV(i1, Vector2.new(p1.X / 20, p1.Z / 20))
				editableMesh:SetVertexUV(i2, Vector2.new(p2.X / 20, p2.Z / 20))
				editableMesh:SetVertexUV(i3, Vector2.new(p3.X / 20, p3.Z / 20))
				
				editableMesh:AddTriangle(i1, i2, i3)
			end
		end
	else
		addFanTriangulation(editableMesh, topIndices)
	end
end

-- Build ALL buildings in a chunk using Part-based geometry.
function BuildingBuilder.BuildAll(parent, buildings, originStuds)
	if not buildings or #buildings == 0 then
		return
	end

	for _, bldg in ipairs(buildings) do
		BuildingBuilder.FallbackBuild(parent, bldg, originStuds)
	end
end

function BuildingBuilder.Build(parent, building, originStuds)
	return BuildingBuilder.BuildAll(parent, { building }, originStuds)
end

function BuildingBuilder.FallbackBuild(parent, building, originStuds)
	local material = getMaterial(building.material, building.kind)
	local color = getColor3(building.color)
	local minX, minZ, maxX, maxZ
	for _, p in ipairs(building.footprint) do
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

	if not minX then return end

	local sizeX = math.max(1, maxX - minX)
	local sizeZ = math.max(1, maxZ - minZ)
	local sizeY = math.max(1, building.height)

	local part = Instance.new("Part")
	part.Name = (building.id or "Building") .. "_Box"
	part.Anchored = true
	part.Size = Vector3.new(sizeX, sizeY, sizeZ)
	part.CFrame = CFrame.new(minX + sizeX * 0.5, originStuds.y + building.baseY + sizeY * 0.5, minZ + sizeZ * 0.5)
	part.Material = material
	if color then
		part.Color = color
	end
	part.Parent = parent
end

return BuildingBuilder
