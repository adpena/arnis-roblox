local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local AustinPreviewTelemetry = {}

AustinPreviewTelemetry.VERSION = 1
AustinPreviewTelemetry.DEFAULT_MAX_RECENT_EVENTS = 16
AustinPreviewTelemetry.WORKSPACE_ATTR = "VertigoPreviewTelemetryJson"

local function defaultProjectFacts()
    return {
        preview = {
            build_active = false,
            state_apply_pending = false,
            sync_state = "idle",
        },
        full_bake = {
            active = false,
            last_result = nil,
        },
    }
end

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local cloned = {}
    for key, entry in pairs(value) do
        cloned[key] = cloneValue(entry)
    end
    return cloned
end

local function sanitizeFieldValue(value)
    local valueType = type(value)
    if valueType == "number" or valueType == "string" or valueType == "boolean" then
        return value
    end
    if value == nil then
        return nil
    end
    return tostring(value)
end

function AustinPreviewTelemetry.newState(options)
    local maxRecentEvents = AustinPreviewTelemetry.DEFAULT_MAX_RECENT_EVENTS
    if type(options) == "table" and type(options.maxRecentEvents) == "number" then
        maxRecentEvents = math.max(1, math.floor(options.maxRecentEvents))
    end

    return {
        version = AustinPreviewTelemetry.VERSION,
        maxRecentEvents = maxRecentEvents,
        counters = {},
        recentEvents = {},
        chunkTotals = {
            imported = 0,
            skipped = 0,
            unloaded = 0,
        },
        projectFacts = defaultProjectFacts(),
        lastEvent = nil,
        lastSync = {},
        lastStateApply = {},
    }
end

function AustinPreviewTelemetry.snapshot(state)
    return {
        version = state.version or AustinPreviewTelemetry.VERSION,
        counters = cloneValue(state.counters or {}),
        recentEvents = cloneValue(state.recentEvents or {}),
        chunkTotals = cloneValue(state.chunkTotals or {}),
        projectFacts = cloneValue(state.projectFacts or defaultProjectFacts()),
        lastEvent = cloneValue(state.lastEvent),
        lastSync = cloneValue(state.lastSync or {}),
        lastStateApply = cloneValue(state.lastStateApply or {}),
    }
end

function AustinPreviewTelemetry.setProjectFacts(state, projectFacts)
    assert(type(state) == "table", "state must be a table")

    local normalized = defaultProjectFacts()
    if type(projectFacts) == "table" then
        local previewFacts = projectFacts.preview
        if type(previewFacts) == "table" then
            if type(previewFacts.build_active) == "boolean" then
                normalized.preview.build_active = previewFacts.build_active
            end
            if type(previewFacts.state_apply_pending) == "boolean" then
                normalized.preview.state_apply_pending = previewFacts.state_apply_pending
            end
            if type(previewFacts.sync_state) == "string" and previewFacts.sync_state ~= "" then
                normalized.preview.sync_state = previewFacts.sync_state
            end
        end

        local fullBakeFacts = projectFacts.full_bake
        if type(fullBakeFacts) == "table" then
            if type(fullBakeFacts.active) == "boolean" then
                normalized.full_bake.active = fullBakeFacts.active
            end
            local lastResult = sanitizeFieldValue(fullBakeFacts.last_result)
            if lastResult ~= nil then
                normalized.full_bake.last_result = lastResult
            end
        end
    end

    state.projectFacts = normalized
    return cloneValue(normalized)
end

function AustinPreviewTelemetry.record(state, eventName, fields)
    assert(type(state) == "table", "state must be a table")
    assert(type(eventName) == "string" and eventName ~= "", "eventName must be a non-empty string")

    local counters = state.counters
    counters[eventName] = (counters[eventName] or 0) + 1

    local event = {
        event = eventName,
        index = counters[eventName],
    }

    if type(fields) == "table" then
        for key, value in pairs(fields) do
            local sanitized = sanitizeFieldValue(value)
            if sanitized ~= nil then
                event[key] = sanitized
            end
        end
    end

    if type(event.imported) == "number" then
        state.chunkTotals.imported += event.imported
    end
    if type(event.skipped) == "number" then
        state.chunkTotals.skipped += event.skipped
    end
    if type(event.unloaded) == "number" then
        state.chunkTotals.unloaded += event.unloaded
    end

    if eventName == "sync_complete" or eventName == "sync_cancelled" then
        state.lastSync = cloneValue(event)
    elseif eventName == "state_apply_succeeded" or eventName == "state_apply_failed" then
        state.lastStateApply = cloneValue(event)
    end

    state.lastEvent = cloneValue(event)
    local recentEvents = state.recentEvents
    recentEvents[#recentEvents + 1] = cloneValue(event)
    while #recentEvents > (state.maxRecentEvents or AustinPreviewTelemetry.DEFAULT_MAX_RECENT_EVENTS) do
        table.remove(recentEvents, 1)
    end

    return event
end

function AustinPreviewTelemetry.flushToWorkspace(state, workspace)
    local target = workspace or Workspace
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(AustinPreviewTelemetry.snapshot(state))
    end)
    if ok then
        target:SetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR, encoded)
    else
        target:SetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR, nil)
    end
end

function AustinPreviewTelemetry.resetWorkspace(workspace)
    local target = workspace or Workspace
    target:SetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR, nil)
end

return AustinPreviewTelemetry
