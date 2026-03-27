local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Logger = require(ReplicatedStorage.Shared.Logger)
local TestEZ = require(ReplicatedStorage.Testing.TestEZ)

local RunAll = {}
RunAll.SUITE_ACTIVE_ATTR = "ArnisRunAllSuiteActive"

local function normalizeSpecNameFilter(specNameFilter)
    if type(specNameFilter) ~= "string" then
        return nil
    end

    local trimmed = string.match(specNameFilter, "^%s*(.-)%s*$")
    if trimmed == nil or trimmed == "" then
        return nil
    end

    if string.sub(trimmed, -4) == ".lua" then
        trimmed = string.sub(trimmed, 1, -5)
    end

    if trimmed == "" then
        return nil
    end

    return trimmed
end

function RunAll.collectSpecModules(testsFolder, options)
    local specModules = {}
    local normalizedFilter = normalizeSpecNameFilter(options and options.specNameFilter)

    for _, moduleScript in ipairs(testsFolder:GetChildren()) do
        if moduleScript:IsA("ModuleScript") and moduleScript.Name:match("%.spec$") then
            if normalizedFilter == nil or moduleScript.Name == normalizedFilter then
                table.insert(specModules, moduleScript)
            end
        end
    end

    table.sort(specModules, function(left, right)
        return left.Name < right.Name
    end)

    return specModules
end

function RunAll.withSuiteExecutionGuard(callback)
    local previousValue = Workspace:GetAttribute(RunAll.SUITE_ACTIVE_ATTR)
    Workspace:SetAttribute(RunAll.SUITE_ACTIVE_ATTR, true)

    local ok, resultOrErr = xpcall(callback, debug.traceback)

    Workspace:SetAttribute(RunAll.SUITE_ACTIVE_ATTR, previousValue)

    if not ok then
        error(resultOrErr, 0)
    end

    return resultOrErr
end

function RunAll.run(options)
    return RunAll.withSuiteExecutionGuard(function()
        local testsFolder = options and options.testsFolder or script.Parent
        local allResults = {
            passed = 0,
            failed = 0,
            total = 0,
        }

        for _, moduleScript in ipairs(RunAll.collectSpecModules(testsFolder, options)) do
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
    end)
end

return RunAll
