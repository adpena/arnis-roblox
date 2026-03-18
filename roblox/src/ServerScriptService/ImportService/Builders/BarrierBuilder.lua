local Workspace = game:GetService("Workspace")

local BarrierBuilder = {}

local BARRIER_HEIGHT = {
	wall           = 4,
	fence          = 3,
	hedge          = 3,
	retaining_wall = 6,
	guard_rail     = 2,
	kerb           = 0.5,
	city_wall      = 8,
	default        = 2,
}

local BARRIER_MATERIAL = {
	wall           = Enum.Material.Brick,
	fence          = Enum.Material.Slate,
	hedge          = Enum.Material.Grass,
	retaining_wall = Enum.Material.Concrete,
	guard_rail     = Enum.Material.Concrete,
	kerb           = Enum.Material.Concrete,
	city_wall      = Enum.Material.Brick,
	default        = Enum.Material.SmoothPlastic,
}

function BarrierBuilder.BuildAll(chunk, _parent)
	local barriers = chunk.barriers
	if not barriers or #barriers == 0 then return 0 end
	local count = 0
	for _, barrier in ipairs(barriers) do
		local kind   = barrier.kind or "fence"
		local height = BARRIER_HEIGHT[kind]   or BARRIER_HEIGHT.default
		local mat    = BARRIER_MATERIAL[kind] or BARRIER_MATERIAL.default
		local pts    = barrier.points
		if pts and #pts >= 2 then
			for i = 1, #pts - 1 do
				local p1  = Vector3.new(pts[i].x,   pts[i].y,   pts[i].z)
				local p2  = Vector3.new(pts[i+1].x, pts[i+1].y, pts[i+1].z)
				local mid = (p1 + p2) * 0.5
				local len = (p2 - p1).Magnitude
				if len > 0.1 then
					local cf = CFrame.lookAt(mid, p2) * CFrame.new(0, height * 0.5, 0)
					Workspace.Terrain:FillBlock(cf, Vector3.new(0.5, height, len), mat)
					count = count + 1
				end
			end
		end
	end
	return count
end

return BarrierBuilder
