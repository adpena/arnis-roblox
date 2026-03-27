return function()
    local Assert = require(script.Parent.Assert)
    local BootstrapStateMachine = require(script.Parent.Parent.ImportService.BootstrapStateMachine)

    local function makeWorkspaceStub()
        local attrs = {}
        return {
            attrs = attrs,
            GetAttribute = function(_, name)
                return attrs[name]
            end,
            SetAttribute = function(_, name, value)
                attrs[name] = value
            end,
        }
    end

    local workspace = makeWorkspaceStub()
    local machine, duplicateInfo = BootstrapStateMachine.begin(workspace, "ServerScriptService.BootstrapAustin.server")
    Assert.truthy(machine, "expected initial bootstrap begin to succeed")
    Assert.falsy(duplicateInfo, "expected no duplicate info for initial bootstrap begin")
    Assert.equal(workspace:GetAttribute(BootstrapStateMachine.STATE_ATTR), "loading_manifest")
    Assert.equal(workspace:GetAttribute(BootstrapStateMachine.STATE_TRACE_ATTR), "loading_manifest")
    Assert.equal(workspace:GetAttribute(BootstrapStateMachine.ATTEMPT_ID_ATTR), "attempt-1")

    BootstrapStateMachine.transition(machine, "importing_startup")
    BootstrapStateMachine.transition(machine, "world_ready")
    Assert.equal(
        workspace:GetAttribute(BootstrapStateMachine.STATE_TRACE_ATTR),
        "loading_manifest,importing_startup,world_ready"
    )

    local ok = pcall(function()
        BootstrapStateMachine.transition(machine, "loading_manifest")
    end)
    Assert.falsy(ok, "expected state regression to fail")

    local duplicateMachine, duplicate =
        BootstrapStateMachine.begin(workspace, "ServerScriptService.BootstrapAustin.server")
    Assert.falsy(duplicateMachine, "expected duplicate bootstrap begin to be rejected")
    Assert.truthy(duplicate, "expected duplicate bootstrap metadata")
    Assert.equal(duplicate.state, "world_ready")
    Assert.equal(duplicate.attemptId, "attempt-1")
    Assert.equal(workspace:GetAttribute(BootstrapStateMachine.DUPLICATE_COUNT_ATTR), 1)

    BootstrapStateMachine.fail(machine)
    Assert.equal(workspace:GetAttribute(BootstrapStateMachine.STATE_ATTR), "failed")

    local retriedMachine, retriedDuplicate =
        BootstrapStateMachine.begin(workspace, "ServerScriptService.BootstrapAustin.server")
    Assert.truthy(retriedMachine, "expected retry after failed state to create a new attempt")
    Assert.falsy(retriedDuplicate, "expected retry after failed state not to count as duplicate")
    Assert.equal(workspace:GetAttribute(BootstrapStateMachine.ATTEMPT_ID_ATTR), "attempt-2")
    Assert.equal(workspace:GetAttribute(BootstrapStateMachine.STATE_TRACE_ATTR), "loading_manifest")
end
