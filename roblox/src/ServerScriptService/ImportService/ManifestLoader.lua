local ServerStorage = game:GetService("ServerStorage")

local ManifestLoader = {}

function ManifestLoader.LoadFromModule(moduleName)
    local sampleData = ServerStorage:WaitForChild("SampleData")
    local moduleScript = sampleData:WaitForChild(moduleName)
    return require(moduleScript)
end

return ManifestLoader
