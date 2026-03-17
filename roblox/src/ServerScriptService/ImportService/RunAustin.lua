local ServerStorage = game:GetService("ServerStorage")

local ImportService = require(script.Parent)

local RunAustin = {}

function RunAustin.run()
    local success, manifestOrErr = pcall(function()
        return require(ServerStorage.SampleData.AustinManifest)
    end)

    if not success then
        warn("[RunAustin] Failed to load ServerStorage.SampleData.AustinManifest:", manifestOrErr)
        return
    end

    local stats = ImportService.ImportManifest(manifestOrErr, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_Austin",
        printReport = true,
    })

    print(
        ("[RunAustin] Imported Austin manifest: chunks=%d roads=%d buildings=%d props=%d"):format(
            stats.chunksImported,
            stats.roadsImported,
            stats.buildingsImported,
            stats.propsImported
        )
    )
end

return RunAustin

