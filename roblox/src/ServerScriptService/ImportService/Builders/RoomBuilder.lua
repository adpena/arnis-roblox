local AssetService = game:GetService("AssetService")

local RoomBuilder = {}

local function offsetPoint(point, origin)
	return Vector3.new(point.x + origin.x, origin.y, point.z + origin.z)
end

-- Generates floor slab geometry into an existing EditableMesh
local function addRoomToMesh(editableMesh, points, floorY, height, indices)
	local bottomIndices = {}
	local topIndices = {}

	-- 1. Create vertices for the slab
	for _, p in ipairs(points) do
		local bottomPos = Vector3.new(p.x, p.y + floorY, p.z)
		local topPos = Vector3.new(p.x, p.y + floorY + height, p.z)
		
		local bIdx = editableMesh:AddVertex(bottomPos)
		local tIdx = editableMesh:AddVertex(topPos)
		
		table.insert(bottomIndices, bIdx)
		table.insert(topIndices, tIdx)
	end

	-- 2. Create slab side triangles
	local count = #points
	for i = 1, count do
		local nextI = i % count + 1
		local b1 = bottomIndices[i]
		local b2 = bottomIndices[nextI]
		local t1 = topIndices[i]
		local t2 = topIndices[nextI]

		editableMesh:AddTriangle(b1, t1, b2)
		editableMesh:AddTriangle(t1, t2, b2)
	end

	-- 3. Create top and bottom triangles (floor/ceiling)
	if indices and #indices >= 3 then
		for i = 1, #indices, 3 do
			local i1 = topIndices[indices[i] + 1]
			local i2 = topIndices[indices[i + 1] + 1]
			local i3 = topIndices[indices[i + 2] + 1]
			if i1 and i2 and i3 then
				editableMesh:AddTriangle(i1, i2, i3) -- Top
			end
			
			local b1 = bottomIndices[indices[i] + 1]
			local b2 = bottomIndices[indices[i + 1] + 1]
			local b3 = bottomIndices[indices[i + 2] + 1]
			if b1 and b2 and b3 then
				editableMesh:AddTriangle(b1, b3, b2) -- Bottom (inverted)
			end
		end
	end
end

function RoomBuilder.BuildAll(parent, buildings, originStuds)
	-- We'll merge rooms by floor material to keep draw calls low
	local groups = {}
	for _, bldg in ipairs(buildings) do
		for _, room in ipairs(bldg.rooms or {}) do
			local mat = room.floorMaterial or "WoodPlanks"
			if not groups[mat] then
				groups[mat] = {}
			end
			table.insert(groups[mat], { room = room, buildingIndices = bldg.indices })
		end
	end

	for matName, group in pairs(groups) do
		local meshPart = Instance.new("MeshPart")
		meshPart.Name = "MergedRooms_" .. matName
		meshPart.Anchored = true
		meshPart.CanCollide = true
		
		local successMat, material = pcall(function()
			return Enum.Material[matName]
		end)
		meshPart.Material = successMat and material or Enum.Material.WoodPlanks
		
		meshPart.Transparency = 0 -- Keep slabs opaque
		meshPart.Parent = parent

		local editableMesh
		local success, _ = pcall(function()
			editableMesh = AssetService:CreateEditableMesh()
		end)

		if success and editableMesh then
			for _, entry in ipairs(group) do
				local points = {}
				for _, p in ipairs(entry.room.footprint) do
					table.insert(points, offsetPoint(p, originStuds))
				end
				if #points >= 3 then
					addRoomToMesh(editableMesh, points, entry.room.floorY, entry.room.height, entry.buildingIndices)
				end
			end
			editableMesh.Parent = meshPart
		else
			meshPart:Destroy()
		end
	end
end

return RoomBuilder
