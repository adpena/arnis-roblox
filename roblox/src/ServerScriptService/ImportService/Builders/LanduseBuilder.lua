local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local LanduseBuilder = {}

local FILL_DEPTH = 2  -- studs deep (thin overlay on terrain surface)

-- Maps landuse/natural kind → Roblox terrain material
-- Full palette: Grass, LeafyGrass, Sand, Rock, Mud, Ground, Concrete, Asphalt,
--   Pavement, Cobblestone, Slate, Sandstone, Brick, Granite, Limestone, Basalt,
--   SmoothPlastic, Snow, Ice, Glacier, SaltFlat, CrackedLava, Water
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
	salt_pond         = Enum.Material.SaltFlat,
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

-- Fills the AABB of a landuse polygon with the appropriate terrain material.
-- Uses a thin fill at the terrain surface level.
function LanduseBuilder.BuildOne(landuse, originStuds)
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
end

function LanduseBuilder.BuildAll(landuseList, originStuds)
	if not landuseList or #landuseList == 0 then return end
	for _, landuse in ipairs(landuseList) do
		LanduseBuilder.BuildOne(landuse, originStuds)
	end
end

return LanduseBuilder
