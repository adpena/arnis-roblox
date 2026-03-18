local ServerStorage = game:GetService("ServerStorage")

local ImportService = require(script.Parent)

local RunAustin = {}
RunAustin.LOAD_RADIUS = 1500

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
        loadRadius = RunAustin.LOAD_RADIUS, -- studs; load only chunks near downtown Congress Ave
    })

    print(
        ("[RunAustin] Imported Austin manifest: chunks=%d roads=%d buildings=%d props=%d"):format(
            stats.chunksImported,
            stats.roadsImported,
            stats.buildingsImported,
            stats.propsImported
        )
    )

    return manifestOrErr, stats
end

return RunAustin
