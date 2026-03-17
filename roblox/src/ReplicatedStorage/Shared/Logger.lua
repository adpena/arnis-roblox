local Logger = {}

local function formatArgs(...)
    local values = table.pack(...)
    local parts = {}

    for index = 1, values.n do
        parts[index] = tostring(values[index])
    end

    return table.concat(parts, " ")
end

function Logger.info(...)
    print("[ArnisRoblox]", formatArgs(...))
end

function Logger.warn(...)
    warn("[ArnisRoblox]", formatArgs(...))
end

function Logger.error(...)
    error("[ArnisRoblox] " .. formatArgs(...), 2)
end

return Logger
