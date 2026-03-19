local InstancePool = {}
InstancePool.__index = InstancePool

-- Creates a new pool for a specific template or class
function InstancePool.new(template)
    local self = setmetatable({}, InstancePool)
    self.template = template -- Can be a string (ClassName) or an Instance (Prefab)
    self.pool = {}
    return self
end

function InstancePool:Acquire()
    local instance = table.remove(self.pool)
    if instance then
        return instance
    end

    if type(self.template) == "string" then
        return Instance.new(self.template)
    else
        return self.template:Clone()
    end
end

function InstancePool:Release(instance)
    if not instance then
        return
    end
    instance.Parent = nil
    table.insert(self.pool, instance)
end

function InstancePool:Drain()
    for _, instance in ipairs(self.pool) do
        instance:Destroy()
    end
    self.pool = {}
end

return InstancePool
