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

function Profiler.clear()
    table.clear(sessions)
end

return Profiler
