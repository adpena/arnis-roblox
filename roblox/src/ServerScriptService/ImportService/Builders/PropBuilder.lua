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

local function buildStreetLamp(x, y, z, parent)
	local model = Instance.new("Model", parent)
	model.Name = "StreetLamp"

	-- Pole
	local pole = Instance.new("Part", model)
	pole.Name = "Pole"
	pole.Anchored = true
	pole.Size = Vector3.new(0.3, 10, 0.3)
	pole.CFrame = CFrame.new(x, y + 5, z)
	pole.Material = Enum.Material.Metal
	pole.Color = Color3.fromRGB(80, 80, 80)
	pole.CastShadow = false

	-- Arm
	local arm = Instance.new("Part", model)
	arm.Name = "Arm"
	arm.Anchored = true
	arm.Size = Vector3.new(1.5, 0.2, 0.2)
	arm.CFrame = CFrame.new(x + 0.75, y + 9.8, z)
	arm.Material = Enum.Material.Metal
	arm.Color = Color3.fromRGB(80, 80, 80)
	arm.CastShadow = false

	-- Light head
	local head = Instance.new("Part", model)
	head.Name = "LightHead"
	head.Anchored = true
	head.Size = Vector3.new(0.8, 0.4, 0.8)
	head.CFrame = CFrame.new(x + 1.5, y + 9.6, z)
	head.Material = Enum.Material.Neon
	head.Color = Color3.fromRGB(255, 240, 200)
	head.CastShadow = false

	-- Point light
	local light = Instance.new("PointLight", head)
	light.Brightness = 3
	light.Range = 30
	light.Color = Color3.fromRGB(255, 240, 200)
	light.Shadows = true
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

	if prop.kind == "street_lamp" or prop.kind == "amenity_street_lamp" then
		local wx = prop.position.x + originStuds.x
		local wy = prop.position.y + originStuds.y
		local wz = prop.position.z + originStuds.z
		return buildStreetLamp(wx, wy, wz, parent)
	end

	if prop.kind == "bench" then
		local wx = prop.position.x + originStuds.x
		local wy = prop.position.y + originStuds.y
		local wz = prop.position.z + originStuds.z
		local bench = Instance.new("Part")
		bench.Name = "Bench"
		bench.Anchored = true
		bench.CanCollide = false
		bench.CastShadow = false
		bench.Size = Vector3.new(2, 0.25, 0.6)
		bench.CFrame = CFrame.new(wx, wy + 0.8, wz) * CFrame.Angles(0, math.rad(prop.yawDegrees or 0), 0)
		bench.Material = Enum.Material.WoodPlanks
		bench.Color = Color3.fromRGB(139, 90, 43)
		bench.Parent = parent
		return bench
	end

	if prop.kind == "bus_stop" then
		local wx = prop.position.x + originStuds.x
		local wy = prop.position.y + originStuds.y
		local wz = prop.position.z + originStuds.z
		local model = Instance.new("Model")
		model.Name = "BusStop"
		local pole = Instance.new("Part")
		pole.Anchored = true; pole.CastShadow = false; pole.CanCollide = false
		pole.Size = Vector3.new(0.2, 5, 0.2)
		pole.CFrame = CFrame.new(wx, wy + 2.5, wz)
		pole.Material = Enum.Material.Metal
		pole.Color = Color3.fromRGB(180, 180, 190)
		pole.Parent = model
		local sign = Instance.new("Part")
		sign.Anchored = true; sign.CastShadow = false; sign.CanCollide = false
		sign.Size = Vector3.new(0.8, 0.5, 0.1)
		sign.CFrame = CFrame.new(wx, wy + 5.2, wz)
		sign.Material = Enum.Material.SmoothPlastic
		sign.Color = Color3.fromRGB(0, 80, 180)
		sign.Parent = model
		model.Parent = parent
		return model
	end

	if prop.kind == "traffic_signal" then
		local wx = prop.position.x + originStuds.x
		local wy = prop.position.y + originStuds.y
		local wz = prop.position.z + originStuds.z
		local model = Instance.new("Model")
		model.Name = "TrafficSignal"
		local pole = Instance.new("Part")
		pole.Anchored = true; pole.CastShadow = false; pole.CanCollide = false
		pole.Size = Vector3.new(0.25, 9, 0.25)
		pole.CFrame = CFrame.new(wx, wy + 4.5, wz)
		pole.Material = Enum.Material.Metal
		pole.Color = Color3.fromRGB(60, 60, 60)
		pole.Parent = model
		local head = Instance.new("Part")
		head.Anchored = true; head.CastShadow = false; head.CanCollide = false
		head.Size = Vector3.new(1, 2.5, 0.6)
		head.CFrame = CFrame.new(wx, wy + 9.5, wz)
		head.Material = Enum.Material.SmoothPlastic
		head.Color = Color3.fromRGB(30, 30, 30)
		head.Parent = model
		local light = Instance.new("Part")
		light.Anchored = true; light.CastShadow = false; light.CanCollide = false
		light.Size = Vector3.new(0.6, 0.6, 0.2)
		light.CFrame = CFrame.new(wx, wy + 9.0, wz + 0.3)
		light.Material = Enum.Material.Neon
		light.Color = Color3.fromRGB(0, 210, 80)
		light.Parent = model
		model.Parent = parent
		return model
	end

	if prop.kind == "waste_basket" then
		local wx = prop.position.x + originStuds.x
		local wy = prop.position.y + originStuds.y
		local wz = prop.position.z + originStuds.z
		local bin = Instance.new("Part")
		bin.Name = "WasteBasket"
		bin.Anchored = true; bin.CastShadow = false; bin.CanCollide = false
		bin.Size = Vector3.new(0.8, 1.2, 0.8)
		bin.CFrame = CFrame.new(wx, wy + 0.6, wz)
		bin.Material = Enum.Material.Metal
		bin.Color = Color3.fromRGB(70, 70, 70)
		bin.Parent = parent
		return bin
	end

	if prop.kind == "fire_hydrant" then
		local wx = prop.position.x + originStuds.x
		local wy = prop.position.y + originStuds.y
		local wz = prop.position.z + originStuds.z
		local hydrant = Instance.new("Part")
		hydrant.Name = "FireHydrant"
		hydrant.Anchored = true; hydrant.CastShadow = false; hydrant.CanCollide = false
		hydrant.Size = Vector3.new(0.6, 1.0, 0.6)
		hydrant.CFrame = CFrame.new(wx, wy + 0.5, wz)
		hydrant.Material = Enum.Material.SmoothPlastic
		hydrant.Color = Color3.fromRGB(220, 30, 30)
		hydrant.Parent = parent
		return hydrant
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
