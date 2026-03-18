local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local BuildingBuilder = {}

local WALL_THICKNESS = 0.6  -- studs
local MIN_EDGE = 0.5        -- ignore edges shorter than this

-- Material palette keyed by OSM building usage
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
		local xi, zi = poly[i][1], poly[i][2]
		local xj, zj = poly[j][1], poly[j][2]
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

-- Build a single building as polygon wall Parts + flat roof
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

	-- Fill interior with terrain
	local footprintRelative = {}
	for _, p in ipairs(fp) do
		table.insert(footprintRelative, {p.x + originStuds.x, p.z + originStuds.z})
	end
	local interiorMaterial = Enum.Material.Concrete
	if building.usage == "residential" or building.usage == "house" or
	   building.usage == "apartments" or building.usage == "detached" or
	   building.usage == "terrace" or building.usage == "dormitory" or
	   building.usage == "bungalow" then
		interiorMaterial = Enum.Material.SmoothPlastic
	elseif building.usage == "commercial" or building.usage == "office" or
	       building.usage == "civic" or building.usage == "hospital" then
		interiorMaterial = Enum.Material.Concrete
	else
		interiorMaterial = Enum.Material.Ground
	end
	fillInterior(footprintRelative, baseY, interiorMaterial, model)

	-- Flat roof Part (bounding box, top of building)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(worldPts) do
		if p.X < minX then minX = p.X end
		if p.Z < minZ then minZ = p.Z end
		if p.X > maxX then maxX = p.X end
		if p.Z > maxZ then maxZ = p.Z end
	end
	local roofSX = math.max(1, maxX - minX)
	local roofSZ = math.max(1, maxZ - minZ)
	local roof = Instance.new("Part")
	roof.Name = bldgName .. "_roof"
	roof.Anchored = true
	roof.Size = Vector3.new(roofSX, 0.4, roofSZ)
	roof.CFrame = CFrame.new(
		(minX + maxX) * 0.5,
		baseY + height + 0.2,
		(minZ + maxZ) * 0.5
	)
	roof.Material = mat
	roof.Color = color
	roof.CastShadow = true
	roof.Parent = model
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

