local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InstancePool = require(script.Parent.Parent.InstancePool)

local PropBuilder = {}

local pools = {}

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

function PropBuilder.Build(parent, prop, originStuds)
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
