local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InstancePool = require(script.Parent.Parent.InstancePool)

local PropBuilder = {}

local pools = {}

local function hashId(id)
	local h = 5381
	for i = 1, #id do
		h = ((h * 33) + string.byte(id, i)) % 2147483647
	end
	return h
end

local SPECIES_COLOR = {
	-- Conifers (dark green)
	conifer = BrickColor.new("Dark green"),
	pinus = BrickColor.new("Dark green"),
	picea = BrickColor.new("Dark green"),
	abies = BrickColor.new("Dark green"),
	juniperus = BrickColor.new("Dark green"),
	needleleaved = BrickColor.new("Dark green"),
	-- Palms (tropical)
	palm = BrickColor.new("Bright yellow"),
	phoenix = BrickColor.new("Bright yellow"),
	washingtonia = BrickColor.new("Bright yellow"),
	sabal = BrickColor.new("Bright yellow"),
	-- Oaks (medium green, common in Austin)
	quercus = BrickColor.new("Bright green"),
	oak = BrickColor.new("Bright green"),
	["live oak"] = BrickColor.new("Olive green"),
	["quercus virginiana"] = BrickColor.new("Olive green"),
	-- Deciduous broadleaf (medium)
	broadleaved_deciduous = BrickColor.new("Bright green"),
	maple = BrickColor.new("Bright orange"),
	acer = BrickColor.new("Bright orange"),
	elm = BrickColor.new("Lime green"),
	ulmus = BrickColor.new("Lime green"),
	-- Evergreen broadleaf
	broadleaved_evergreen = BrickColor.new("Olive green"),
	-- Fruit/flowering trees
	prunus = BrickColor.new("Pink"),
	magnolia = BrickColor.new("Light pink"),
	-- Default (Austin's mix of live oak + cedar)
	default = BrickColor.new("Bright green"),
}

local SPECIES_SCALE = {
	conifer = 0.7,
	palm = 0.5,
	oak = 1.2,
	quercus = 1.2,
	default = 1.0,
}

local function getCanopyColor(species)
	if not species then
		return SPECIES_COLOR.default
	end
	local s = species:lower()
	-- Try exact match first
	if SPECIES_COLOR[s] then
		return SPECIES_COLOR[s]
	end
	-- Try prefix match
	for key, color in pairs(SPECIES_COLOR) do
		if s:find(key, 1, true) then
			return color
		end
	end
	return SPECIES_COLOR.default
end

local function getCanopyScale(species)
	if not species then
		return 1.0
	end
	local s = species:lower()
	-- Try exact match first
	if SPECIES_SCALE[s] then
		return SPECIES_SCALE[s]
	end
	-- Try prefix match
	for key, scale in pairs(SPECIES_SCALE) do
		if s:find(key, 1, true) then
			return scale
		end
	end
	return 1.0
end

local function getOrCreatePool(kind)
	if pools[kind] then
		return pools[kind]
	end

	-- Strategy: Use prefabs from ReplicatedStorage if they exist, otherwise use generic placeholders
	local prefab = ReplicatedStorage.Assets.Prefabs:FindFirstChild(kind)
	if prefab then
		pools[kind] = InstancePool.new(prefab)
	else
		-- Placeholder models
		pools[kind] = InstancePool.new("Model")
	end

	return pools[kind]
end

-- Builds a simple procedural tree model (trunk + canopy)
local function buildTree(parent, prop, originStuds)
	-- Seed RNG for deterministic output
	math.randomseed(hashId(prop.id or tostring(prop.position.x) .. tostring(prop.position.z)))

	local worldPos = Vector3.new(
		prop.position.x + originStuds.x,
		prop.position.y + originStuds.y,
		prop.position.z + originStuds.z
	)
	local yaw = math.rad(prop.yawDegrees or 0)
	local scale = prop.scale or 1.0
	local speciesScale = getCanopyScale(prop.species)

	local model = Instance.new("Model")
	model.Name = prop.id or "Tree"

	-- Trunk: Cylinder is axis-Z by default; rotate 90° on Z to stand upright
	local trunkH = 7 * scale
	local trunkR = 0.5 * scale
	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Anchored = true
	trunk.Size = Vector3.new(trunkR * 2, trunkH, trunkR * 2)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH * 0.5, 0)) * CFrame.Angles(0, yaw, math.pi * 0.5)
	trunk.Material = Enum.Material.Wood
	trunk.Color = Color3.fromRGB(101, 79, 55)
	trunk.CastShadow = false
	trunk.Parent = model

	-- Canopy sphere
	local canopyR = (4 + math.random() * 3) * scale * speciesScale
	local canopy = Instance.new("Part")
	canopy.Name = "Canopy"
	canopy.Anchored = true
	canopy.Shape = Enum.PartType.Ball
	canopy.Size = Vector3.new(canopyR * 2, canopyR * 2, canopyR * 2)
	canopy.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH + canopyR * 0.5, 0))
	canopy.Material = Enum.Material.LeafyGrass
	canopy.BrickColor = getCanopyColor(prop.species)
	canopy.CastShadow = false
	canopy.Parent = model

	model.Parent = parent
	return model
end

function PropBuilder.Build(parent, prop, originStuds)
	if prop.kind == "tree" then
		return buildTree(parent, prop, originStuds)
	end

	local pool = getOrCreatePool(prop.kind)
	local instance = pool:Get()

	instance.Name = prop.id or prop.kind
	
	local worldPos = Vector3.new(
		prop.position.x + originStuds.x,
		prop.position.y + originStuds.y,
		prop.position.z + originStuds.z
	)
	
	instance:PivotTo(CFrame.new(worldPos) * CFrame.Angles(0, math.rad(prop.yawDegrees or 0), 0))
	instance.Parent = parent
	
	if prop.scale then
		-- Apply scale if the instance supports it (Models do via Scale property)
		if instance:IsA("Model") then
			instance:ScaleTo(prop.scale)
		end
	end
	
	return instance
end

function PropBuilder.Clear(kind)
	if pools[kind] then
		pools[kind]:Clear()
	end
end

return PropBuilder
