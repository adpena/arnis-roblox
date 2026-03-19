local Profiler = {}

local sessions = {}
local MAX_SESSIONS = 50
local ENABLE_DEBUG_ANNOTATIONS = false

function Profiler.begin(label, annotateWithDebugProfile)
    local profile = {
        label = label,
        startTime = os.clock(),
        usedDebugAnnotation = false,
    }

    if ENABLE_DEBUG_ANNOTATIONS and annotateWithDebugProfile then
        debug.profilebegin(label)
        profile.usedDebugAnnotation = true
    end

    return profile
end

function Profiler.finish(profile, metadata)
    if profile.usedDebugAnnotation then
        debug.profileend()
    end

    local elapsed = os.clock() - profile.startTime

    local session = {
        label = profile.label,
        elapsedMs = elapsed * 1000,
        timestamp = os.time(),
        metadata = metadata or {},
    }

    table.insert(sessions, session)
    if #sessions > MAX_SESSIONS then
        table.remove(sessions, 1)
    end

    return session
end

function Profiler.printReport()
    print("--- Arnis Profiler Report ---")
    for _, session in ipairs(sessions) do
        local metaStr = ""
        for k, v in pairs(session.metadata) do
            metaStr = metaStr .. k .. "=" .. tostring(v) .. " "
        end
        print(string.format("[%s] %.2fms | %s", session.label, session.elapsedMs, metaStr))
    end
end

function Profiler.generateReport()
    local activities = table.create(#sessions)
    for i, session in ipairs(sessions) do
        activities[i] = {
            label = session.label,
            elapsedMs = session.elapsedMs,
            timestamp = session.timestamp,
            extra = session.metadata,
        }
    end

    return {
        activities = activities,
        total = #activities,
    }
end

local function getSummaryForLabel(summaryByLabel, label)
    local summary = summaryByLabel[label]
    if summary == nil then
        summary = {
            label = label,
            count = 0,
            totalMs = 0,
            avgMs = 0,
            maxMs = 0,
        }
        summaryByLabel[label] = summary
    end

    return summary
end

function Profiler.generateSummary()
    local summaryByLabel = {}
    local slowest = nil
    local totalElapsedMs = 0

    for _, session in ipairs(sessions) do
        totalElapsedMs += session.elapsedMs

        local summary = getSummaryForLabel(summaryByLabel, session.label)
        summary.count += 1
        summary.totalMs += session.elapsedMs
        summary.avgMs = summary.totalMs / summary.count
        if session.elapsedMs > summary.maxMs then
            summary.maxMs = session.elapsedMs
        end

        if slowest == nil or session.elapsedMs > slowest.elapsedMs then
            slowest = {
                label = session.label,
                elapsedMs = session.elapsedMs,
                metadata = session.metadata,
            }
        end
    end

    local byLabel = {}
    for _, summary in pairs(summaryByLabel) do
        table.insert(byLabel, summary)
    end
    table.sort(byLabel, function(a, b)
        if a.totalMs == b.totalMs then
            return a.label < b.label
        end
        return a.totalMs > b.totalMs
    end)

    return {
        totalActivities = #sessions,
        totalElapsedMs = totalElapsedMs,
        byLabel = byLabel,
        slowest = slowest,
    }
end

function Profiler.clear()
    table.clear(sessions)
end

return Profiler
