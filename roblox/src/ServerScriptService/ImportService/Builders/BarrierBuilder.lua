local BarrierBuilder = {}

local BARRIER_HEIGHT = {
	wall           = 8,
	city_wall      = 8,
	fence          = 4,
	hedge          = 4,
	retaining_wall = 6,
	guard_rail     = 3,
	kerb           = 0.5,
	default        = 2,
}

-- Thickness (X-axis size) per kind in studs.
local BARRIER_THICKNESS = {
	wall           = 3,
	city_wall      = 3,
	fence          = 0.3,
	hedge          = 2,
	retaining_wall = 3,
	guard_rail     = 0.2,
	kerb           = 0.5,
	default        = 0.5,
}

local BARRIER_MATERIAL = {
	wall           = Enum.Material.Brick,
	city_wall      = Enum.Material.Brick,
	fence          = Enum.Material.WoodPlanks,
	hedge          = Enum.Material.LeafyGrass,
	retaining_wall = Enum.Material.Concrete,
	guard_rail     = Enum.Material.Metal,
	kerb           = Enum.Material.Concrete,
	default        = Enum.Material.SmoothPlastic,
}

function BarrierBuilder.BuildAll(chunk, parent)
	local barriers = chunk.barriers
	if not barriers or #barriers == 0 then return 0 end
	local origin = chunk.originStuds
	local ox, oy, oz = origin.x, origin.y, origin.z
	local count = 0
	for _, barrier in ipairs(barriers) do
		local kind      = barrier.kind or "fence"
		local height    = BARRIER_HEIGHT[kind]    or BARRIER_HEIGHT.default
		local thickness = BARRIER_THICKNESS[kind] or BARRIER_THICKNESS.default
		local mat       = BARRIER_MATERIAL[kind]  or BARRIER_MATERIAL.default
		local pts       = barrier.points
		if pts and #pts >= 2 then
			for i = 1, #pts - 1 do
				local p1  = Vector3.new(pts[i].x + ox,   pts[i].y + oy,   pts[i].z + oz)
				local p2  = Vector3.new(pts[i+1].x + ox, pts[i+1].y + oy, pts[i+1].z + oz)
				local len = (p2 - p1).Magnitude
				if len > 0.1 then
					local startPos = p1 + Vector3.new(0, height * 0.5, 0)
					local endPos   = p2 + Vector3.new(0, height * 0.5, 0)
					local midPos   = (startPos + endPos) * 0.5
					local part = Instance.new("Part")
					part.Name      = kind
					part.Size      = Vector3.new(thickness, height, len)
					part.Material  = mat
					part.Anchored  = true
					part.CanCollide = true
					part.CFrame    = CFrame.lookAt(midPos, endPos)
					part.Parent = parent
					count = count + 1
				end
			end
		end
	end
	return count
end

return BarrierBuilder
