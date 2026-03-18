local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local LanduseBuilder = {}

local FILL_DEPTH = 2  -- studs deep (thin overlay on terrain surface)

-- Maps landuse/natural kind → Roblox terrain material
-- Full palette: Grass, LeafyGrass, Sand, Rock, Mud, Ground, Concrete, Asphalt,
--   Pavement, Cobblestone, Slate, Sandstone, Brick, Granite, Limestone, Basalt,
--   SmoothPlastic, Snow, Ice, Glacier, CrackedLava, Water
local KIND_MATERIAL = {
	-- Green spaces
	park              = Enum.Material.Grass,
	garden            = Enum.Material.Grass,
	recreation_ground = Enum.Material.Grass,
	village_green     = Enum.Material.Grass,
	grass             = Enum.Material.Grass,
	meadow            = Enum.Material.Grass,
	flowerbed         = Enum.Material.Grass,
	leisure           = Enum.Material.Grass,
	-- Dense vegetation
	forest            = Enum.Material.LeafyGrass,
	wood              = Enum.Material.LeafyGrass,
	scrub             = Enum.Material.LeafyGrass,
	heath             = Enum.Material.LeafyGrass,
	greenfield        = Enum.Material.LeafyGrass,
	-- Agriculture
	farmland          = Enum.Material.Mud,
	farmyard          = Enum.Material.Mud,
	orchard           = Enum.Material.Mud,
	vineyard          = Enum.Material.Mud,
	allotments        = Enum.Material.Mud,
	greenhouse_horticulture = Enum.Material.Mud,
	-- Arid / exposed ground
	beach             = Enum.Material.Sand,
	sand              = Enum.Material.Sand,
	dune              = Enum.Material.Sand,
	bare_rock         = Enum.Material.Rock,
	cliff             = Enum.Material.Rock,
	scree             = Enum.Material.Granite,
	shingle           = Enum.Material.Slate,
	-- Volcanic
	lava              = Enum.Material.CrackedLava,
	volcano           = Enum.Material.Basalt,
	-- Frozen
	glacier           = Enum.Material.Glacier,
	ice               = Enum.Material.Ice,
	snow              = Enum.Material.Snow,
	-- Wetlands / water-adjacent
	wetland           = Enum.Material.Mud,
	marsh             = Enum.Material.Mud,
	swamp             = Enum.Material.Mud,
	-- Residential / civic
	residential       = Enum.Material.Ground,
	cemetery          = Enum.Material.Sandstone,
	religious         = Enum.Material.Sandstone,
	-- Commercial / urban
	commercial        = Enum.Material.Limestone,
	retail            = Enum.Material.Limestone,
	civic             = Enum.Material.Concrete,
	office            = Enum.Material.Concrete,
	education         = Enum.Material.Brick,
	hospital          = Enum.Material.SmoothPlastic,
	-- Industrial / infrastructure
	industrial        = Enum.Material.SmoothPlastic,
	warehouse         = Enum.Material.SmoothPlastic,
	railway           = Enum.Material.Slate,
	military          = Enum.Material.Concrete,
	-- Paved / transport
	parking           = Enum.Material.Asphalt,
	road              = Enum.Material.Asphalt,
	airport           = Enum.Material.Concrete,
	aerodrome         = Enum.Material.Concrete,
	port              = Enum.Material.Cobblestone,
	marina            = Enum.Material.Cobblestone,
	-- Degraded / brownfield
	brownfield        = Enum.Material.Mud,
	landfill          = Enum.Material.Mud,
	quarry            = Enum.Material.Sandstone,
	construction      = Enum.Material.Ground,
	-- Salt flats / mineral
	salt_pond         = Enum.Material.Sand,
	plateau           = Enum.Material.Sandstone,
}

local function getMaterial(kind, materialName)
	-- Try the pre-computed material name from the manifest first
	if materialName then
		local ok, m = pcall(function() return Enum.Material[materialName] end)
		if ok and m then return m end
	end
	return KIND_MATERIAL[kind] or Enum.Material.Ground
end

-- Scatter park benches at pseudo-random but deterministic positions.
local function placeParkFurniture(cx, cz, sizeX, sizeZ, parent)
	local area = sizeX * sizeZ
	local count = math.min(8, math.floor(area / 400))
	if count <= 0 then return end
	math.randomseed(math.floor(cx * 1000 + cz))
	for _ = 1, count do
		local bx = cx + (math.random() - 0.5) * sizeX * 0.7
		local bz = cz + (math.random() - 0.5) * sizeZ * 0.7
		local bench = Instance.new("Part", parent)
		bench.Name = "ParkBench"
		bench.Anchored = true
		bench.CanCollide = false
		bench.Size = Vector3.new(3, 0.3, 0.6)
		bench.CFrame = CFrame.new(bx, 0.15, bz) * CFrame.Angles(0, math.random() * math.pi, 0)
		bench.Material = Enum.Material.WoodPlanks
		bench.Color = Color3.fromRGB(139, 90, 43)
		bench.CastShadow = false
	end
end

-- Tree density per square stud by kind
local TREE_DENSITY = {
	forest = 1/80,   -- ~1 tree per 80 sq studs (dense canopy)
	wood   = 1/80,
	scrub  = 1/160,  -- sparse scrub
	heath  = 1/200,
	park   = 1/250,  -- scattered park trees
	garden = 1/300,
}

-- Canopy colors by terrain type
local FOREST_CANOPY = {
	forest = BrickColor.new("Bright green"),
	wood   = BrickColor.new("Dark green"),
	scrub  = BrickColor.new("Olive"),
	heath  = BrickColor.new("Sand green"),
	park   = BrickColor.new("Bright green"),
	garden = BrickColor.new("Bright green"),
}

-- Scatter procedural trees across a vegetation area.
local function placeVegetation(kind, cx, cz, sizeX, sizeZ, baseY, parent)
	local density = TREE_DENSITY[kind]
	if not density then return end
	local area = sizeX * sizeZ
	local count = math.min(60, math.floor(area * density))
	if count <= 0 then return end
	local canopyColor = FOREST_CANOPY[kind] or BrickColor.new("Bright green")

	math.randomseed(math.floor(cx * 997 + cz * 1009 + kind:byte(1, 1)))
	for _ = 1, count do
		local tx = cx + (math.random() - 0.5) * sizeX * 0.92
		local tz = cz + (math.random() - 0.5) * sizeZ * 0.92
		local scale = 0.7 + math.random() * 0.6
		local trunkH = 6 * scale
		local canopyR = (3.5 + math.random() * 2.5) * scale

		local model = Instance.new("Model")
		model.Name = kind .. "_tree"

		local trunk = Instance.new("Part")
		trunk.Anchored  = true
		trunk.CanCollide = false
		trunk.CastShadow = false
		trunk.Size = Vector3.new(0.8 * scale, trunkH, 0.8 * scale)
		trunk.Shape = Enum.PartType.Cylinder
		trunk.CFrame = CFrame.new(tx, baseY + trunkH * 0.5, tz) * CFrame.Angles(0, 0, math.pi * 0.5)
		trunk.Material = Enum.Material.Wood
		trunk.Color = Color3.fromRGB(90, 65, 40)
		trunk.Parent = model

		local canopy = Instance.new("Part")
		canopy.Anchored  = true
		canopy.CanCollide = false
		canopy.CastShadow = false
		canopy.Shape = Enum.PartType.Ball
		canopy.Size = Vector3.new(canopyR * 2, canopyR * 2, canopyR * 2)
		canopy.CFrame = CFrame.new(tx, baseY + trunkH + canopyR * 0.6, tz)
		canopy.Material = Enum.Material.LeafyGrass
		canopy.BrickColor = canopyColor
		canopy.Parent = model

		model.Parent = parent
	end
end

-- Fills the AABB of a landuse polygon with the appropriate terrain material.
-- Uses a thin fill at the terrain surface level.
function LanduseBuilder.BuildOne(landuse, originStuds, parent)
	if not landuse.footprint or #landuse.footprint < 3 then return end

	local terrain = Workspace.Terrain
	local mat = getMaterial(landuse.kind, landuse.material)

	-- Compute AABB of the footprint
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(landuse.footprint) do
		local wx = p.x + originStuds.x
		local wz = p.z + originStuds.z
		if wx < minX then minX = wx end
		if wz < minZ then minZ = wz end
		if wx > maxX then maxX = wx end
		if wz > maxZ then maxZ = wz end
	end

	local sizeX = math.max(1, maxX - minX)
	local sizeZ = math.max(1, maxZ - minZ)

	-- Fill a thin slab at ground level
	local cf = CFrame.new(
		(minX + maxX) * 0.5,
		originStuds.y - FILL_DEPTH * 0.5,
		(minZ + maxZ) * 0.5
	)
	terrain:FillBlock(cf, Vector3.new(sizeX, FILL_DEPTH, sizeZ), mat)

	local cx = (minX + maxX) * 0.5
	local cz = (minZ + maxZ) * 0.5
	local baseY = originStuds.y

	-- Scatter benches in parks
	if landuse.kind == "park" or landuse.kind == "garden" then
		placeParkFurniture(cx, cz, sizeX, sizeZ, parent or Workspace)
	end

	-- Scatter trees in vegetation areas
	placeVegetation(landuse.kind, cx, cz, sizeX, sizeZ, baseY, parent or Workspace)
end

function LanduseBuilder.BuildAll(landuseList, originStuds, parent)
	if not landuseList or #landuseList == 0 then return end
	for _, landuse in ipairs(landuseList) do
		LanduseBuilder.BuildOne(landuse, originStuds, parent)
	end
end

return LanduseBuilder
