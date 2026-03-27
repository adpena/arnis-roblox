return function()
    local RunAll = require(script.Parent.RunAll)
    local Assert = require(script.Parent.Assert)
    local Workspace = game:GetService("Workspace")

    local testsFolder = Instance.new("Folder")
    testsFolder.Name = "SyntheticTests"

    local function addModule(name)
        local module = Instance.new("ModuleScript")
        module.Name = name
        module.Parent = testsFolder
        return module
    end

    addModule("Alpha.spec")
    addModule("Beta.spec")
    addModule("Gamma.helper")

    local allModules = RunAll.collectSpecModules(testsFolder, {})
    Assert.equal(#allModules, 2, "expected collectSpecModules to return all spec modules")
    Assert.equal(allModules[1].Name, "Alpha.spec", "expected alphabetic module ordering for stable execution")
    Assert.equal(allModules[2].Name, "Beta.spec", "expected alphabetic module ordering for stable execution")

    local exactFilter = RunAll.collectSpecModules(testsFolder, {
        specNameFilter = "Beta.spec",
    })
    Assert.equal(#exactFilter, 1, "expected exact filter to select one spec")
    Assert.equal(exactFilter[1].Name, "Beta.spec", "expected exact filter to match module name")

    local luaSuffixFilter = RunAll.collectSpecModules(testsFolder, {
        specNameFilter = "Alpha.spec.lua",
    })
    Assert.equal(#luaSuffixFilter, 1, "expected .lua suffix filter to normalize")
    Assert.equal(luaSuffixFilter[1].Name, "Alpha.spec", "expected normalized filter to match module name")

    local missingFilter = RunAll.collectSpecModules(testsFolder, {
        specNameFilter = "Missing.spec",
    })
    Assert.equal(#missingFilter, 0, "expected unmatched filter to exclude all modules")

    Workspace:SetAttribute(RunAll.SUITE_ACTIVE_ATTR, nil)
    local callbackRan = false
    local callbackResult = RunAll.withSuiteExecutionGuard(function()
        callbackRan = true
        Assert.equal(
            Workspace:GetAttribute(RunAll.SUITE_ACTIVE_ATTR),
            true,
            "expected RunAll to mark the suite-active guard while executing"
        )
        return "guard-ok"
    end)
    Assert.equal(callbackRan, true, "expected suite guard callback to run")
    Assert.equal(callbackResult, "guard-ok", "expected suite guard to return the callback result")
    Assert.equal(
        Workspace:GetAttribute(RunAll.SUITE_ACTIVE_ATTR),
        nil,
        "expected RunAll to restore the suite-active guard after execution"
    )

    Workspace:SetAttribute(RunAll.SUITE_ACTIVE_ATTR, "previous")
    local sawPrevious = false
    RunAll.withSuiteExecutionGuard(function()
        sawPrevious = true
        Assert.equal(
            Workspace:GetAttribute(RunAll.SUITE_ACTIVE_ATTR),
            true,
            "expected suite guard to override any prior value while active"
        )
    end)
    Assert.equal(sawPrevious, true, "expected suite guard to run when restoring previous values")
    Assert.equal(
        Workspace:GetAttribute(RunAll.SUITE_ACTIVE_ATTR),
        "previous",
        "expected suite guard to restore the previous attribute value"
    )
    Workspace:SetAttribute(RunAll.SUITE_ACTIVE_ATTR, nil)

    testsFolder:Destroy()
end
