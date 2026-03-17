local Controller = {}

function Controller.importSample()
    local ok, result = pcall(function()
        local ServerStorage = game:GetService("ServerStorage")
        local ImportService = require(game:GetService("ServerScriptService"):WaitForChild("ImportService"))
        local manifest = require(ServerStorage:WaitForChild("SampleData"):WaitForChild("SampleManifest"))

        return ImportService.ImportManifest(manifest, {
            clearFirst = true,
            worldRootName = "GeneratedWorld",
        })
    end)

    if ok then
        print("[ArnisRobloxPlugin] Import succeeded", result)
    else
        warn("[ArnisRobloxPlugin] Import failed", result)
    end
end

function Controller.runSmokeTests()
    local ok, result = pcall(function()
        local tests = game:GetService("ServerScriptService"):WaitForChild("Tests")
        local runAll = require(tests:WaitForChild("RunAll"))
        return runAll.run()
    end)

    if ok then
        print("[ArnisRobloxPlugin] Smoke tests completed", result)
    else
        warn("[ArnisRobloxPlugin] Smoke tests failed", result)
    end
end

return Controller
