local StreamingRuntimeConfig = {}

local function deepClone(value)
    if type(value) ~= "table" then
        return value
    end

    local cloned = {}
    for key, child in pairs(value) do
        cloned[key] = deepClone(child)
    end
    return cloned
end

local function isArrayLikeTable(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    local maxIndex = 0

    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end

        count = count + 1
        if key > maxIndex then
            maxIndex = key
        end
    end

    if count == 0 then
        return false
    end

    if maxIndex ~= count then
        return false
    end

    for index = 1, count do
        if value[index] == nil then
            return false
        end
    end

    return true
end

local function deepMerge(into, overrides)
    if type(overrides) ~= "table" then
        return into
    end

    for key, value in pairs(overrides) do
        if type(value) == "table" then
            local existing = into[key]
            local isEmptyOverride = next(value) == nil
            local shouldReplaceArray = type(existing) == "table"
                and isEmptyOverride
                and isArrayLikeTable(existing)
            if
                type(existing) == "table"
                and not isArrayLikeTable(value)
                and not shouldReplaceArray
            then
                into[key] = deepMerge(deepClone(existing), value)
            else
                into[key] = deepClone(value)
            end
        else
            into[key] = value
        end
    end

    return into
end

function StreamingRuntimeConfig.Resolve(config)
    local baseConfig = if type(config) == "table" then deepClone(config) else {}
    local profileName = if type(baseConfig.StreamingProfile) == "string"
            and baseConfig.StreamingProfile ~= ""
        then baseConfig.StreamingProfile
        else "local_dev"

    local profiles = if type(baseConfig.StreamingProfiles) == "table"
        then baseConfig.StreamingProfiles
        else nil
    local overrides = if profiles ~= nil and type(profiles[profileName]) == "table"
        then profiles[profileName]
        else nil
    local resolved = deepMerge(baseConfig, overrides)
    resolved.StreamingProfile = profileName
    return resolved
end

return StreamingRuntimeConfig
