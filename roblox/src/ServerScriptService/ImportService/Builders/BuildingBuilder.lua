local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local BuildingBuilder = {}

local WALL_THICKNESS = 0.6  -- studs
local MIN_EDGE = 0.5        -- ignore edges shorter than this

-- Material palette keyed by OSM building usage (used for wall Parts — any Enum.Material valid)
local USAGE_MATERIAL = {
	residential    = Enum.Material.Brick,
	apartments     = Enum.Material.Brick,
	house          = Enum.Material.Brick,
	commercial     = Enum.Material.Concrete,
	retail         = Enum.Material.Concrete,
	office         = Enum.Material.Glass,
	industrial     = Enum.Material.Metal,
	warehouse      = Enum.Material.Metal,
	church         = Enum.Material.SmoothPlastic,
	school         = Enum.Material.SmoothPlastic,
	hospital       = Enum.Material.SmoothPlastic,
	yes            = Enum.Material.Concrete,
	default        = Enum.Material.Concrete,
}

-- Floor material for Terrain:FillBlock — must be a valid terrain material (no Glass/Metal/Neon)
local USAGE_FLOOR_MATERIAL = {
	residential    = Enum.Material.Brick,
	apartments     = Enum.Material.Brick,
	house          = Enum.Material.Brick,
	commercial     = Enum.Material.Concrete,
	retail         = Enum.Material.Concrete,
	office         = Enum.Material.Concrete,      -- Glass → Concrete floor
	industrial     = Enum.Material.Concrete,      -- Metal → Concrete floor
	warehouse      = Enum.Material.Concrete,
	church         = Enum.Material.SmoothPlastic,
	school         = Enum.Material.SmoothPlastic,
	hospital       = Enum.Material.SmoothPlastic,
	yes            = Enum.Material.Concrete,
	default        = Enum.Material.Concrete,
}

local function getFloorMaterial(building)
	local usage = building.usage or building.kind or "default"
	return USAGE_FLOOR_MATERIAL[usage] or USAGE_FLOOR_MATERIAL.default
end

local USAGE_COLOR = {
	residential = Color3.fromRGB(180, 120, 90),
	apartments  = Color3.fromRGB(165, 110, 80),
	commercial  = Color3.fromRGB(150, 150, 160),
	retail      = Color3.fromRGB(160, 140, 130),
	office      = Color3.fromRGB(140, 160, 180),
	industrial  = Color3.fromRGB(120, 120, 120),
	warehouse   = Color3.fromRGB(110, 110, 110),
	default     = Color3.fromRGB(160, 150, 140),
}

local function getMaterial(building)
	local usage = building.usage or building.kind or "default"
	return USAGE_MATERIAL[usage] or USAGE_MATERIAL.default
end

local function getColor(building)
	if building.color and building.color.r then
		return Color3.fromRGB(building.color.r, building.color.g, building.color.b)
	end
	local usage = building.usage or building.kind or "default"
	return USAGE_COLOR[usage] or USAGE_COLOR.default
end

local function hashId(id)
	local h = 5381
	for i = 1, #id do
		h = ((h * 33) + string.byte(id, i)) % 2147483647
	end
	return h
end

local function pointInPolygon(px, pz, poly)
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, zi = poly[i].x, poly[i].z
		local xj, zj = poly[j].x, poly[j].z
		if ((zi > pz) ~= (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi) then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function fillInterior(footprint, baseY, material, parent)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(footprint) do
		if p.x < minX then minX = p.x end
		if p.z < minZ then minZ = p.z end
		if p.x > maxX then maxX = p.x end
		if p.z > maxZ then maxZ = p.z end
	end

	local GRID_SIZE = 4  -- 4-stud grid matching voxel resolution
	local x = minX + GRID_SIZE * 0.5
	while x < maxX do
		local z = minZ + GRID_SIZE * 0.5
		while z < maxZ do
			if pointInPolygon(x, z, footprint) then
				workspace.Terrain:FillBlock(
					CFrame.new(x, baseY, z),
					Vector3.new(GRID_SIZE, GRID_SIZE, GRID_SIZE),
					material
				)
			end
			z = z + GRID_SIZE
		end
		x = x + GRID_SIZE
	end
end

local function getBuildingHeight(building)
	local METERS_PER_STUD = 0.3  -- 1 stud ≈ 0.3 meters (Roblox convention for real-world scale)
	if building.height_m and building.height_m > 0 then
		return math.max(4, building.height_m / METERS_PER_STUD)
	elseif building.levels and building.levels > 0 then
		return math.max(4, building.levels * 14)  -- ~14 studs per floor (4.2m)
	else
		local USAGE_HEIGHT_M = {
			-- residential
			apartments = 15,  house = 6,  detached = 6,  terrace = 6,
			residential = 9,  dormitory = 12,  bungalow = 4,
			-- commercial/civic
			commercial = 12,  retail = 6,  office = 20,  bank = 10,
			supermarket = 8,  mall = 12,  hotel = 20,
			-- civic/public
			hospital = 23,  school = 8,  university = 12,
			civic = 10,  government = 12,  courthouse = 12,
			-- industrial
			industrial = 10,  warehouse = 8,  factory = 10,
			-- religious
			religious = 12,  church = 15,  cathedral = 25,  mosque = 12,  temple = 10,
			-- utility/misc
			garage = 3,  shed = 2.5,  barn = 6,  greenhouse = 3,
			-- defaults by general category
			building = 10,  yes = 10,
		}
		local heightM = USAGE_HEIGHT_M[building.usage] or 10
		return math.max(4, heightM / METERS_PER_STUD)
	end
end

-- Build roof geometry based on building.roof shape.
-- footprint: array of world-space Vector3 points (worldPts)
local function buildRoof(building, footprint, baseY, height, color, mat, parent)
	local bldgName = building.id or "Building"
	local roofShape = (building.roof or "flat"):lower()

	-- Compute bounding box
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(footprint) do
		if p.X < minX then minX = p.X end
		if p.Z < minZ then minZ = p.Z end
		if p.X > maxX then maxX = p.X end
		if p.Z > maxZ then maxZ = p.Z end
	end
	local footprintW = math.max(1, maxX - minX)
	local footprintL = math.max(1, maxZ - minZ)
	local centerX = (minX + maxX) * 0.5
	local centerZ = (minZ + maxZ) * 0.5

	if roofShape == "gabled" then
		-- Ridge runs along the longer axis; panels tilt inward from both shorter edges.
		local ridgeAxisIsZ = footprintL >= footprintW
		local shortExtent  = ridgeAxisIsZ and footprintW or footprintL
		local longExtent   = ridgeAxisIsZ and footprintL or footprintW
		local halfWidth    = shortExtent * 0.5
		local rise         = shortExtent * 0.3
		local angle        = math.atan(rise / halfWidth)
		local panelW       = halfWidth / math.cos(angle)
		local cy           = baseY + height + rise * 0.5

		local p1 = Instance.new("Part")
		p1.Name     = bldgName .. "_roof_p1"
		p1.Anchored = true
		p1.CastShadow = true
		p1.Material = mat
		p1.Color    = color

		local p2 = Instance.new("Part")
		p2.Name     = bldgName .. "_roof_p2"
		p2.Anchored = true
		p2.CastShadow = true
		p2.Material = mat
		p2.Color    = color

		if ridgeAxisIsZ then
			-- Panels tilt around Z axis: left half (+angle), right half (-angle)
			p1.Size   = Vector3.new(panelW, 0.8, longExtent)
			p1.CFrame = CFrame.new(centerX - halfWidth * 0.5, cy, centerZ) * CFrame.Angles(0, 0, angle)
			p2.Size   = Vector3.new(panelW, 0.8, longExtent)
			p2.CFrame = CFrame.new(centerX + halfWidth * 0.5, cy, centerZ) * CFrame.Angles(0, 0, -angle)
		else
			-- Panels tilt around X axis: front half (-angle), back half (+angle)
			p1.Size   = Vector3.new(longExtent, 0.8, panelW)
			p1.CFrame = CFrame.new(centerX, cy, centerZ - halfWidth * 0.5) * CFrame.Angles(-angle, 0, 0)
			p2.Size   = Vector3.new(longExtent, 0.8, panelW)
			p2.CFrame = CFrame.new(centerX, cy, centerZ + halfWidth * 0.5) * CFrame.Angles(angle, 0, 0)
		end
		p1.Parent = parent
		p2.Parent = parent
		return

	elseif roofShape == "pyramidal" or roofShape == "hipped" then
		local rise = math.min(footprintW, footprintL) * 0.3
		local apex = Instance.new("Part")
		apex.Name     = bldgName .. "_roof"
		apex.Anchored = true
		apex.Size     = Vector3.new(footprintW, rise * 2, footprintL)
		local mesh = Instance.new("SpecialMesh", apex)
		mesh.MeshType = Enum.MeshType.Wedge
		apex.CFrame   = CFrame.new(centerX, baseY + height + rise, centerZ)
		apex.Material = mat
		apex.Color    = color
		apex.CastShadow = true
		apex.Parent   = parent
		return

	elseif roofShape == "dome" then
		local dome = Instance.new("Part")
		dome.Name     = bldgName .. "_roof"
		dome.Anchored = true
		dome.Shape    = Enum.PartType.Ball
		dome.Size     = Vector3.new(footprintW, footprintW * 0.5, footprintL)
		dome.CFrame   = CFrame.new(centerX, baseY + height + footprintW * 0.25, centerZ)
		dome.Material = mat
		dome.Color    = color
		dome.CastShadow = true
		dome.Parent   = parent
		return
	end

	-- Default / flat / skillion / mansard / gambrel → flat slab (thickness 0.8)
	local roof = Instance.new("Part")
	roof.Name     = bldgName .. "_roof"
	roof.Anchored = true
	roof.Size     = Vector3.new(footprintW, 0.8, footprintL)
	roof.CFrame   = CFrame.new(centerX, baseY + height + 0.4, centerZ)
	roof.Material = mat
	roof.Color    = color
	roof.CastShadow = true
	roof.Parent   = parent
end

-- Build a single building as polygon wall Parts + roof
function BuildingBuilder.FallbackBuild(parent, building, originStuds)
	local fp = building.footprint
	if not fp or #fp < 2 then return end

	-- Seed RNG for deterministic output
	math.randomseed(hashId(building.id or tostring(building)))

	local baseY = originStuds.y + (building.baseY or 0)
	local height = getBuildingHeight(building)
	local mat = getMaterial(building)
	local color = getColor(building)
	local bldgName = building.id or "Building"

	local model = Instance.new("Model")
	model.Name = bldgName
	model.Parent = parent

	-- World coordinates of footprint vertices
	local worldPts = {}
	for _, p in ipairs(fp) do
		table.insert(worldPts, Vector3.new(
			p.x + originStuds.x,
			baseY,
			p.z + originStuds.z
		))
	end

	-- One wall Part per edge
	local n = #worldPts
	for i = 1, n do
		local p1 = worldPts[i]
		local p2 = worldPts[(i % n) + 1]
		local dx = p2.X - p1.X
		local dz = p2.Z - p1.Z
		local edgeLen = math.sqrt(dx*dx + dz*dz)
		if edgeLen < MIN_EDGE then continue end

		local midX = (p1.X + p2.X) * 0.5
		local midZ = (p1.Z + p2.Z) * 0.5
		local midY = baseY + height * 0.5

		local wall = Instance.new("Part")
		wall.Name = bldgName .. "_wall" .. i
		wall.Anchored = true
		wall.Size = Vector3.new(edgeLen, height, WALL_THICKNESS)
		wall.CFrame = CFrame.lookAt(
			Vector3.new(midX, midY, midZ),
			Vector3.new(p2.X, midY, p2.Z)
		)
		wall.Material = mat
		wall.Color = color
		wall.CastShadow = true
		wall.Parent = model
	end

	-- Fill interior with terrain (uses terrain-safe floor materials only)
	local footprintRelative = {}
	for _, p in ipairs(fp) do
		table.insert(footprintRelative, {x = p.x + originStuds.x, z = p.z + originStuds.z})
	end
	fillInterior(footprintRelative, baseY, getFloorMaterial(building), model)

	buildRoof(building, worldPts, baseY, height, color, mat, model)
end

-- PartBuild is the same as FallbackBuild (polygon walls)
BuildingBuilder.PartBuild = BuildingBuilder.FallbackBuild

function BuildingBuilder.BuildAll(parent, buildings, originStuds)
	if not buildings or #buildings == 0 then return end
	for _, bldg in ipairs(buildings) do
		BuildingBuilder.FallbackBuild(parent, bldg, originStuds)
	end
end

function BuildingBuilder.Build(parent, building, originStuds)
	BuildingBuilder.FallbackBuild(parent, building, originStuds)
end

return BuildingBuilder

