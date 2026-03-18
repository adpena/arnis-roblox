local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Shared.Logger)

local RoadBuilder = {}

-- Maps OSM surface tag → Roblox terrain material (checked before kind fallback)
local SURFACE_MATERIAL = {
	asphalt             = Enum.Material.Asphalt,
	concrete            = Enum.Material.Concrete,
	["concrete:plates"] = Enum.Material.Concrete,
	cobblestone         = Enum.Material.Cobblestone,
	paving_stones       = Enum.Material.Pavement,
	bricks              = Enum.Material.Cobblestone,
	sett                = Enum.Material.Cobblestone,
	gravel              = Enum.Material.Ground,
	fine_gravel         = Enum.Material.Ground,
	compacted           = Enum.Material.Ground,
	pebblestone         = Enum.Material.Ground,
	rock                = Enum.Material.Rock,
	unpaved             = Enum.Material.Mud,
	dirt                = Enum.Material.Mud,
	earth               = Enum.Material.Mud,
	grass               = Enum.Material.Grass,
	wood                = Enum.Material.SmoothPlastic,
	stepping_stones     = Enum.Material.Pavement,
	paved               = Enum.Material.Concrete,
	sand                = Enum.Material.Sand,
}

-- Maps road kind → Roblox terrain material for Terrain:FillBlock
local ROAD_MATERIAL = {
	-- Highways: smooth concrete
	motorway      = Enum.Material.Concrete,
	motorway_link = Enum.Material.Concrete,
	trunk         = Enum.Material.Concrete,
	trunk_link    = Enum.Material.Concrete,
	-- Primary/secondary: asphalt
	primary       = Enum.Material.Asphalt,
	primary_link  = Enum.Material.Asphalt,
	secondary     = Enum.Material.Asphalt,
	secondary_link= Enum.Material.Asphalt,
	-- Local streets: asphalt (slightly different feel via paint order)
	tertiary      = Enum.Material.Asphalt,
	tertiary_link = Enum.Material.Asphalt,
	residential   = Enum.Material.Asphalt,
	living_street = Enum.Material.Pavement,
	service       = Enum.Material.Limestone,
	-- Pedestrian / cycling
	footway       = Enum.Material.Pavement,
	path          = Enum.Material.Cobblestone,
	pedestrian    = Enum.Material.SmoothPlastic,
	cycleway      = Enum.Material.Sandstone,
	steps         = Enum.Material.Slate,
	bridleway     = Enum.Material.Ground,
	-- Unpaved
	track         = Enum.Material.Mud,
	unclassified  = Enum.Material.Ground,
	road          = Enum.Material.Ground,
	default       = Enum.Material.Asphalt,
}

local ROAD_THICKNESS = 1  -- studs; road fills 0.5 studs into terrain + 0.5 above
local BRIDGE_THRESHOLD = 3  -- studs above ground to consider a road elevated (bridge)

-- Returns road width in studs: lanes take priority, then explicit widthStuds, then kind defaults.
local function getRoadWidth(road)
	if road.lanes and road.lanes > 0 then
		return road.lanes * 4 + 4
	end
	if road.widthStuds and road.widthStuds > 0 then
		return road.widthStuds
	end
	local KIND_WIDTH = {
		motorway = 24, trunk = 20, primary = 16, secondary = 12,
		tertiary = 10, residential = 8, service = 6,
		footway = 3, cycleway = 3, path = 2, track = 4,
		living_street = 7, unclassified = 8,
	}
	return KIND_WIDTH[road.kind] or 8
end

-- Highway kinds that receive sidewalk kerb strips
local SIDEWALK_KINDS = {
	primary   = true,
	secondary = true,
	tertiary  = true,
	residential = true,
}

local function getMaterial(road)
	-- 1. OSM surface tag takes priority (most specific physical description)
	if road.surface then
		local m = SURFACE_MATERIAL[road.surface]
		if m then return m end
	end
	-- 2. Legacy manifest material name (Enum.Material string)
	if road.material then
		local ok, m = pcall(function() return Enum.Material[road.material] end)
		if ok and m then return m end
	end
	-- 3. Road kind fallback
	return ROAD_MATERIAL[road.kind] or ROAD_MATERIAL.default
end

local function offsetPoint(point, origin)
	return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

-- Paint one road segment into terrain using FillBlock (ground-level roads).
local function paintSegment(terrain, p1, p2, width, material, kind)
	local delta  = p2 - p1
	local length = delta.Magnitude
	if length < 0.01 then return end

	-- Center the slab so its top surface sits at Y=p1.Y (road surface level).
	local midY   = p1.Y - ROAD_THICKNESS * 0.5
	local midPos = Vector3.new(
		(p1.X + p2.X) * 0.5,
		midY,
		(p1.Z + p2.Z) * 0.5
	)

	-- lookAt rotates the CFrame so its -Z axis points toward p2.
	-- FillBlock honours the rotation → oriented slab aligned with the road.
	local cf = CFrame.lookAt(midPos, Vector3.new(p2.X, midY, p2.Z))
	terrain:FillBlock(cf, Vector3.new(width, ROAD_THICKNESS, length), material)

	-- Sidewalk kerbs alongside wide enough roads of appropriate types
	if width >= 8 and SIDEWALK_KINDS[kind] then
		local sidewalkW = 3
		local kerbH = 0.5
		local kerbOffset = (width / 2) + (sidewalkW / 2)
		-- Left kerb
		local cfL = cf * CFrame.new(-kerbOffset, kerbH / 2, 0)
		terrain:FillBlock(cfL, Vector3.new(sidewalkW, kerbH, length), Enum.Material.Pavement)
		-- Right kerb
		local cfR = cf * CFrame.new(kerbOffset, kerbH / 2, 0)
		terrain:FillBlock(cfR, Vector3.new(sidewalkW, kerbH, length), Enum.Material.Pavement)
	end
end

-- Build an elevated bridge/tunnel segment as a Part slab (not terrain).
-- Bridges use a concrete deck Part; tunnels are skipped (underground).
local function paintBridgeSegment(parent, p1, p2, width, material)
	local delta  = p2 - p1
	local length = delta.Magnitude
	if length < 0.01 then return end

	local midX = (p1.X + p2.X) * 0.5
	local midZ = (p1.Z + p2.Z) * 0.5
	local midY = (p1.Y + p2.Y) * 0.5

	local deck = Instance.new("Part")
	deck.Anchored    = true
	deck.CastShadow  = true  -- bridge deck casts meaningful shadows
	deck.Size        = Vector3.new(width, ROAD_THICKNESS, length + 0.1)
	deck.Material    = material
	deck.CFrame      = CFrame.lookAt(
		Vector3.new(midX, midY, midZ),
		Vector3.new(p2.X, midY, p2.Z)
	)
	deck.CollisionFidelity = Enum.CollisionFidelity.Box
	deck.Parent = parent

	-- Guardrail posts every 8 studs on each side
	local numPosts = math.floor(length / 8)
	for k = 0, numPosts do
		local t = (numPosts > 0) and (k / numPosts) or 0
		local px = p1.X + (p2.X - p1.X) * t
		local pz = p1.Z + (p2.Z - p1.Z) * t
		local railY = midY + 1.5
		for _, side in ipairs({-1, 1}) do
			local railCF = CFrame.lookAt(
				Vector3.new(midX, railY, midZ),
				Vector3.new(p2.X, railY, p2.Z)
			) * CFrame.new(side * (width * 0.5 + 0.15), 0, (t - 0.5) * length)
			local post = Instance.new("Part")
			post.Anchored   = true
			post.CastShadow = false
			post.Size       = Vector3.new(0.3, 3, 0.3)
			post.Material   = Enum.Material.Concrete
			post.Color      = Color3.fromRGB(180, 180, 190)
			post.CFrame     = CFrame.new(px + side * (width * 0.5 + 0.15), railY, pz)
			post.Parent     = parent
		end
	end
end

-- Add a white dashed centerline stripe on roads wider than 12 studs.
local function paintCenterline(parent, p1, p2, width)
	if width < 12 then return end
	local delta  = p2 - p1
	local length = delta.Magnitude
	if length < 4 then return end

	local numDashes = math.floor(length / 6)
	if numDashes < 1 then return end
	for k = 0, numDashes - 1 do
		local t = (k + 0.5) / numDashes
		local cx = p1.X + (p2.X - p1.X) * t
		local cz = p1.Z + (p2.Z - p1.Z) * t
		local cy = p1.Y + (p2.Y - p1.Y) * t + 0.05  -- just above road surface

		local dash = Instance.new("Part")
		dash.Anchored    = true
		dash.CastShadow  = false
		dash.CanCollide  = false
		dash.Size        = Vector3.new(0.4, 0.1, math.min(3, length / numDashes * 0.6))
		dash.Material    = Enum.Material.SmoothPlastic
		dash.Color       = Color3.fromRGB(255, 255, 255)
		dash.CFrame      = CFrame.lookAt(
			Vector3.new(cx, cy, cz),
			Vector3.new(p2.X, cy, p2.Z)
		)
		dash.Parent = parent
	end
end

-- Build ALL roads in a chunk by painting them into the terrain.
function RoadBuilder.BuildAll(parent, roads, originStuds)
	if not roads or #roads == 0 then return end
	for _, road in ipairs(roads) do
		RoadBuilder.FallbackBuild(parent, road, originStuds)
	end
end

function RoadBuilder.Build(parent, road, originStuds)
	RoadBuilder.FallbackBuild(parent, road, originStuds)
end

function RoadBuilder.FallbackBuild(parent, road, originStuds)
	local terrain  = Workspace.Terrain
	local material = getMaterial(road)
	local width    = getRoadWidth(road)

	for i = 1, #road.points - 1 do
		local p1 = offsetPoint(road.points[i],     originStuds)
		local p2 = offsetPoint(road.points[i + 1], originStuds)

		-- Check if this segment is elevated (bridge) or underground (tunnel)
		local avgY = (road.points[i].y + road.points[i + 1].y) * 0.5
		if avgY < -BRIDGE_THRESHOLD then
			-- Tunnel: skip rendering (underground)
		elseif avgY > BRIDGE_THRESHOLD then
			-- Bridge: elevated Part deck
			paintBridgeSegment(parent, p1, p2, width, material)
		else
			-- Ground-level: terrain FillBlock
			paintSegment(terrain, p1, p2, width, material, road.kind)
			paintCenterline(parent, p1, p2, width)
		end
	end
end

return RoadBuilder
