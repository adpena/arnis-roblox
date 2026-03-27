local BootstrapStateMachine = {}

BootstrapStateMachine.STATE_ATTR = "ArnisAustinBootstrapState"
BootstrapStateMachine.STATE_TRACE_ATTR = "ArnisAustinBootstrapStateTrace"
BootstrapStateMachine.DUPLICATE_COUNT_ATTR = "ArnisAustinBootstrapDuplicateCount"
BootstrapStateMachine.ENTRY_COUNT_ATTR = "ArnisAustinBootstrapEntryCount"
BootstrapStateMachine.LAST_SCRIPT_PATH_ATTR = "ArnisAustinBootstrapLastScriptPath"
BootstrapStateMachine.ATTEMPT_SEQUENCE_ATTR = "ArnisAustinBootstrapAttemptSequence"
BootstrapStateMachine.ATTEMPT_ID_ATTR = "ArnisAustinBootstrapAttemptId"

local STATE_RANK = table.freeze({
    loading_manifest = 1,
    importing_startup = 2,
    world_ready = 3,
    streaming_ready = 4,
    minimap_ready = 5,
    gameplay_ready = 6,
    failed = math.huge,
})

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function getStateRank(state)
    return STATE_RANK[state]
end

local function appendTrace(trace, state)
    local nextTrace = table.clone(trace)
    nextTrace[#nextTrace + 1] = state
    return nextTrace
end

local function publish(machine, state)
    machine.currentState = state
    machine.currentRank = getStateRank(state)
    machine.trace = appendTrace(machine.trace, state)
    machine.workspace:SetAttribute(BootstrapStateMachine.STATE_ATTR, state)
    machine.workspace:SetAttribute(BootstrapStateMachine.STATE_TRACE_ATTR, table.concat(machine.trace, ","))
end

function BootstrapStateMachine.begin(workspace, scriptPath)
    local entryCount = (workspace:GetAttribute(BootstrapStateMachine.ENTRY_COUNT_ATTR) or 0) + 1
    workspace:SetAttribute(BootstrapStateMachine.ENTRY_COUNT_ATTR, entryCount)
    workspace:SetAttribute(BootstrapStateMachine.LAST_SCRIPT_PATH_ATTR, scriptPath)

    local existingState = workspace:GetAttribute(BootstrapStateMachine.STATE_ATTR)
    if existingState == "failed" then
        workspace:SetAttribute(BootstrapStateMachine.STATE_ATTR, nil)
        workspace:SetAttribute(BootstrapStateMachine.STATE_TRACE_ATTR, nil)
        workspace:SetAttribute(BootstrapStateMachine.ATTEMPT_ID_ATTR, nil)
        existingState = nil
    end

    if isNonEmptyString(existingState) then
        local duplicateCount = (workspace:GetAttribute(BootstrapStateMachine.DUPLICATE_COUNT_ATTR) or 0) + 1
        workspace:SetAttribute(BootstrapStateMachine.DUPLICATE_COUNT_ATTR, duplicateCount)
        return nil,
            {
                duplicateCount = duplicateCount,
                entryCount = entryCount,
                state = existingState,
                attemptId = workspace:GetAttribute(BootstrapStateMachine.ATTEMPT_ID_ATTR),
                scriptPath = scriptPath,
            }
    end

    workspace:SetAttribute(BootstrapStateMachine.DUPLICATE_COUNT_ATTR, 0)
    local attemptSequence = (workspace:GetAttribute(BootstrapStateMachine.ATTEMPT_SEQUENCE_ATTR) or 0) + 1
    local attemptId = "attempt-" .. tostring(attemptSequence)
    workspace:SetAttribute(BootstrapStateMachine.ATTEMPT_SEQUENCE_ATTR, attemptSequence)
    workspace:SetAttribute(BootstrapStateMachine.ATTEMPT_ID_ATTR, attemptId)

    local machine = {
        workspace = workspace,
        scriptPath = scriptPath,
        attemptId = attemptId,
        trace = {},
        currentState = nil,
        currentRank = nil,
    }

    publish(machine, "loading_manifest")
    return machine, nil
end

function BootstrapStateMachine.transition(machine, nextState)
    local nextRank = getStateRank(nextState)
    if nextRank == nil then
        error("unknown bootstrap state: " .. tostring(nextState))
    end

    local currentState = machine.currentState
    if currentState == nextState then
        error("duplicate bootstrap state transition: " .. tostring(nextState))
    end

    if currentState == "failed" or currentState == "gameplay_ready" then
        error("bootstrap state machine is already terminal")
    end

    if nextState ~= "failed" and machine.currentRank ~= nil and nextRank <= machine.currentRank then
        error(string.format("bootstrap state regression from %s to %s", tostring(currentState), tostring(nextState)))
    end

    publish(machine, nextState)
    return machine.attemptId
end

function BootstrapStateMachine.fail(machine)
    return BootstrapStateMachine.transition(machine, "failed")
end

return BootstrapStateMachine
