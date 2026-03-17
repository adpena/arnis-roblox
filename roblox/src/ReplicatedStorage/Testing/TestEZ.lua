--[[
    TestEZ - A minimal BDD-style test framework for Roblox
    Based on the TestEZ API pattern
]]

local TestEZ = {}
TestEZ.__index = TestEZ

local function deepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end

    if type(a) ~= "table" then
        return a == b
    end

    local checkedKeys = {}
    for key, value in pairs(a) do
        checkedKeys[key] = true
        if not deepEqual(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if not checkedKeys[key] then
            return false
        end
    end

    return true
end

local function formatValue(value)
    if value == nil then
        return "nil"
    elseif type(value) == "string" then
        return '"' .. value .. '"'
    elseif type(value) == "table" then
        local parts = {}
        for k, v in pairs(value) do
            table.insert(parts, tostring(k) .. "=" .. formatValue(v))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return tostring(value)
    end
end

local TestEnv = {}
TestEnv.__index = TestEnv

function TestEnv.new()
    local self = setmetatable({}, TestEnv)
    self.tests = {}
    self.beforeEachHooks = {}
    self.afterEachHooks = {}
    return self
end

function TestEnv:beforeEach(fn)
    table.insert(self.beforeEachHooks, fn)
end

function TestEnv:afterEach(fn)
    table.insert(self.afterEachHooks, fn)
end

function TestEnv:it(description, fn)
    table.insert(self.tests, {
        description = description,
        fn = fn,
    })
end

function TestEnv:expect(actual)
    return {
        to = {
            equal = function(expected)
                if actual ~= expected then
                    error(("Expected %s but got %s"):format(formatValue(expected), formatValue(actual)), 2)
                end
            end,
            toBe = function(expected)
                if actual ~= expected then
                    error(("Expected %s but got %s"):format(formatValue(expected), formatValue(actual)), 2)
                end
            end,
            toBeTrue = function()
                if actual ~= true then
                    error(("Expected true but got %s"):format(formatValue(actual)), 2)
                end
            end,
            toBeFalse = function()
                if actual ~= false then
                    error(("Expected false but got %s"):format(formatValue(actual)), 2)
                end
            end,
            toBeNil = function()
                if actual ~= nil then
                    error(("Expected nil but got %s"):format(formatValue(actual)), 2)
                end
            end,
            toNeverThrow = function()
                local ok, err = pcall(actual)
                if not ok then
                    error(("Expected function to not throw, but got: %s"):format(tostring(err)), 2)
                end
            end,
            toThrow = function()
                local ok, _ = pcall(actual)
                if ok then
                    error("Expected function to throw, but it did not", 2)
                end
            end,
        },
        toEqual = function(expected)
            if not deepEqual(actual, expected) then
                error(("Expected %s but got %s"):format(formatValue(expected), formatValue(actual)), 2)
            end
        end,
    }
end

function TestEnv:describe(_description, fn)
    local childEnv = TestEnv.new()
    childEnv.parent = self
    fn(childEnv)
    return childEnv
end

local TestBlock = {}
TestBlock.__index = TestBlock

function TestBlock.new(description, parent)
    local self = setmetatable({}, TestBlock)
    self.description = description
    self.parent = parent
    self.children = {}
    self.tests = {}
    self.beforeEachHooks = {}
    self.afterEachHooks = {}
    return self
end

function TestBlock:beforeEach(fn)
    if self.parent then
        self.parent:beforeEach(fn)
    else
        table.insert(self.beforeEachHooks, fn)
    end
end

function TestBlock:afterEach(fn)
    if self.parent then
        self.parent:afterEach(fn)
    else
        table.insert(self.afterEachHooks, fn)
    end
end

function TestBlock:it(description, fn)
    table.insert(self.tests, {
        description = description,
        fn = fn,
    })
end

function TestBlock:describe(description, fn)
    local child = TestBlock.new(description, self)
    table.insert(self.children, child)
    fn(child)
    return child
end

function TestBlock:expect(actual)
    return {
        to = {
            equal = function(expected)
                if actual ~= expected then
                    error(("Expected %s but got %s"):format(formatValue(expected), formatValue(actual)), 2)
                end
            end,
            toBe = function(expected)
                if actual ~= expected then
                    error(("Expected %s but got %s"):format(formatValue(expected), formatValue(actual)), 2)
                end
            end,
            toBeTrue = function()
                if actual ~= true then
                    error(("Expected true but got %s"):format(formatValue(actual)), 2)
                end
            end,
            toBeFalse = function()
                if actual ~= false then
                    error(("Expected false but got %s"):format(formatValue(actual)), 2)
                end
            end,
            toBeNil = function()
                if actual ~= nil then
                    error(("Expected nil but got %s"):format(formatValue(actual)), 2)
                end
            end,
            toNeverThrow = function()
                local ok, err = pcall(actual)
                if not ok then
                    error(("Expected function to not throw, but got: %s"):format(tostring(err)), 2)
                end
            end,
            toThrow = function()
                local ok, _ = pcall(actual)
                if ok then
                    error("Expected function to throw, but it did not", 2)
                end
            end,
        },
        toEqual = function(expected)
            if not deepEqual(actual, expected) then
                error(("Expected %s but got %s"):format(formatValue(expected), formatValue(actual)), 2)
            end
        end,
    }
end

function TestBlock:runHooks(hooks)
    for _, hook in ipairs(hooks) do
        hook()
    end
end

function TestBlock:run(currentPath, results)
    local allBeforeHooks = {}
    local allAfterHooks = {}

    local parent = self.parent
    while parent do
        if parent.beforeEachHooks then
            for i = #parent.beforeEachHooks, 1, -1 do
                table.insert(allBeforeHooks, parent.beforeEachHooks[i])
            end
        end
        if parent.afterEachHooks then
            for _, hook in ipairs(parent.afterEachHooks) do
                table.insert(allAfterHooks, hook)
            end
        end
        parent = parent.parent
    end

    for i = #allBeforeHooks, 1, -1 do
        allBeforeHooks[i]()
    end

    for _, hook in ipairs(self.beforeEachHooks) do
        hook()
    end

    for _, test in ipairs(self.tests) do
        local testPath = currentPath .. " > " .. test.description
        local ok, err = pcall(test.fn)
        if ok then
            table.insert(results, {
                path = testPath,
                status = "Pass",
            })
        else
            table.insert(results, {
                path = testPath,
                status = "Fail",
                error = tostring(err),
            })
        end
    end

    for _, hook in ipairs(self.afterEachHooks) do
        hook()
    end

    for i = #allAfterHooks, 1, -1 do
        allAfterHooks[i]()
    end

    for _, child in ipairs(self.children) do
        child:run(currentPath .. " > " .. child.description, results)
    end
end

function TestEZ.describe(description, fn)
    local root = TestBlock.new(description, nil)
    fn(root)
    return root
end

function TestEZ.run(testBlock, options)
    options = options or {}
    local results = {}
    testBlock:run(testBlock.description, results)

    local passed = 0
    local failed = 0

    for _, result in ipairs(results) do
        if result.status == "Pass" then
            passed = passed + 1
        else
            failed = failed + 1
            if options.reporter ~= "silent" then
                warn(("FAIL: %s - %s"):format(result.path, result.error or "unknown error"))
            end
        end
    end

    if options.reporter ~= "silent" then
        print(("Test Results: %d passed, %d failed"):format(passed, failed))
    end

    return {
        passed = passed,
        failed = failed,
        total = passed + failed,
        results = results,
    }
end

return TestEZ
