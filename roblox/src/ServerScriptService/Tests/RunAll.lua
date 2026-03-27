local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Shared.Logger)
local TestEZ = require(ReplicatedStorage.Testing.TestEZ)

local RunAll = {}

local function normalizeSpecNameFilter(specNameFilter)
    if type(specNameFilter) ~= "string" or specNameFilter == "" then
        return nil
    end
    if string.sub(specNameFilter, -4) == ".lua" then
        specNameFilter = string.sub(specNameFilter, 1, -5)
    end
    return specNameFilter
end

function RunAll.run(options)
    local testsFolder = script.Parent
    local allResults = {
        passed = 0,
        failed = 0,
        total = 0,
    }
    local specNameFilter = normalizeSpecNameFilter(options and options.specNameFilter or nil)
    if specNameFilter ~= nil then
        Logger.info("Filtering tests to spec:", specNameFilter)
    end

    for _, moduleScript in ipairs(testsFolder:GetChildren()) do
        if
            moduleScript:IsA("ModuleScript")
            and moduleScript.Name:match("%.spec$")
            and (specNameFilter == nil or moduleScript.Name == specNameFilter)
        then
            Logger.info("Running tests:", moduleScript.Name)

            local ok, testBlockOrFn = pcall(function()
                return require(moduleScript)
            end)

            if not ok then
                Logger.warn("Failed to load test module:", moduleScript.Name, testBlockOrFn)
                allResults.failed = allResults.failed + 1
                allResults.total = allResults.total + 1
            else
                local results
                if type(testBlockOrFn) == "function" then
                    -- Old-style test module that returns a function
                    local fnOk, fnErr = pcall(testBlockOrFn)
                    if fnOk then
                        allResults.passed = allResults.passed + 1
                        Logger.info("PASS", moduleScript.Name)
                    else
                        allResults.failed = allResults.failed + 1
                        Logger.warn("FAIL", moduleScript.Name, fnErr)
                    end
                    allResults.total = allResults.total + 1
                else
                    -- TestEZ-style test block
                    results = TestEZ.run(testBlockOrFn, { reporter = "silent" })
                    allResults.passed = allResults.passed + results.passed
                    allResults.failed = allResults.failed + results.failed
                    allResults.total = allResults.total + results.total

                    if results.failed > 0 then
                        Logger.warn(("Test module %s had %d failures"):format(moduleScript.Name, results.failed))
                    else
                        Logger.info("PASS", moduleScript.Name, ("(%d tests)"):format(results.passed))
                    end
                end
            end
        end
    end

    Logger.info(
        ("TestEZ tests complete. total=%d passed=%d failed=%d"):format(
            allResults.total,
            allResults.passed,
            allResults.failed
        )
    )

    if allResults.failed > 0 then
        error(("Tests failed: %d"):format(allResults.failed))
    end

    return allResults
end

return RunAll
