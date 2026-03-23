local SubplanRollout = {}

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function listToSet(values)
    local set = nil
    for _, value in ipairs(values or {}) do
        if isNonEmptyString(value) then
            if set == nil then
                set = {}
            end
            set[value] = true
        end
    end
    return set
end

local function countKeys(map)
    local total = 0
    for _ in pairs(map or {}) do
        total += 1
    end
    return total
end

function SubplanRollout.Resolve(config)
    local rollout = if type(config) == "table" then config.SubplanRollout else nil
    if type(rollout) ~= "table" then
        return {
            enabled = false,
            allowedLayerSet = nil,
            allowlistedChunkIdSet = nil,
            allowedLayerCount = 0,
            allowlistedChunkCount = 0,
            mode = "disabled",
        }
    end

    local enabled = rollout.Enabled == true
    local allowedLayerSet = listToSet(rollout.AllowedLayers)
    local allowlistedChunkIdSet = listToSet(rollout.AllowedChunkIds)
    local allowedLayerCount = countKeys(allowedLayerSet)
    local allowlistedChunkCount = countKeys(allowlistedChunkIdSet)
    local mode = "all"
    if not enabled then
        mode = "disabled"
    elseif allowedLayerCount > 0 and allowlistedChunkCount > 0 then
        mode = "layers+allowlist"
    elseif allowedLayerCount > 0 then
        mode = "layers"
    elseif allowlistedChunkCount > 0 then
        mode = "allowlist"
    end

    return {
        enabled = enabled,
        allowedLayerSet = allowedLayerSet,
        allowlistedChunkIdSet = allowlistedChunkIdSet,
        allowedLayerCount = allowedLayerCount,
        allowlistedChunkCount = allowlistedChunkCount,
        mode = mode,
    }
end

function SubplanRollout.IsEnabled(config)
    return SubplanRollout.Resolve(config).enabled
end

function SubplanRollout.Describe(config)
    local rollout = SubplanRollout.Resolve(config)
    return {
        enabled = rollout.enabled,
        mode = rollout.mode,
        allowedLayerCount = rollout.allowedLayerCount,
        allowlistedChunkCount = rollout.allowlistedChunkCount,
    }
end

function SubplanRollout.GetAllowedSubplans(chunkLike, config)
    local rollout = SubplanRollout.Resolve(config)
    local subplans = if type(chunkLike) == "table" then chunkLike.subplans else nil
    if not rollout.enabled or type(subplans) ~= "table" or #subplans == 0 then
        return nil
    end

    local chunkId = if type(chunkLike) == "table" then chunkLike.id else nil
    if rollout.allowlistedChunkIdSet ~= nil and not rollout.allowlistedChunkIdSet[chunkId] then
        return nil
    end

    if rollout.allowedLayerSet == nil then
        return subplans
    end

    local filtered = {}
    for _, subplan in ipairs(subplans) do
        local layer = if type(subplan) == "table" then subplan.layer else nil
        if rollout.allowedLayerSet[layer] then
            filtered[#filtered + 1] = subplan
        end
    end

    if #filtered == 0 then
        return nil
    end

    return filtered
end

function SubplanRollout.GetFullySchedulableSubplans(chunkLike, config)
    local fullSubplans = if type(chunkLike) == "table" then chunkLike.subplans else nil
    if type(fullSubplans) ~= "table" or #fullSubplans == 0 then
        return nil
    end

    local allowedSubplans = SubplanRollout.GetAllowedSubplans(chunkLike, config)
    if allowedSubplans == nil or #allowedSubplans ~= #fullSubplans then
        return nil
    end

    return allowedSubplans
end

return SubplanRollout
