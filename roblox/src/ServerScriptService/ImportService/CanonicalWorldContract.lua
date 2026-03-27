local ServerStorage = game:GetService("ServerStorage")

local AustinSpawn = require(script.Parent.AustinSpawn)
local ManifestLoader = require(script.Parent.ManifestLoader)

local CanonicalWorldContract = {}

CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME = "AustinManifestIndex"
CanonicalWorldContract.LOCAL_DEV_FULL_BAKE_MATERIALIZATION_INDEX_NAMES = {
    "AustinCanonicalManifestIndex",
}
CanonicalWorldContract.LOCAL_DEV_PLAY_MATERIALIZATION_INDEX_NAMES = {
    "AustinCanonicalManifestIndex",
}

function CanonicalWorldContract.resolveCanonicalManifestFamily(_policyMode)
    return CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME
end

local function getSampleDataFolder()
    return ServerStorage:FindFirstChild("SampleData")
end

function CanonicalWorldContract.resolveCanonicalMaterializationCandidates(policyMode)
    local candidates = {}
    local sampleData = getSampleDataFolder()
    if sampleData then
        local preferredIndexNames = CanonicalWorldContract.LOCAL_DEV_FULL_BAKE_MATERIALIZATION_INDEX_NAMES
        if policyMode == "play" then
            preferredIndexNames = CanonicalWorldContract.LOCAL_DEV_PLAY_MATERIALIZATION_INDEX_NAMES
        end
        for _, manifestIndexName in ipairs(preferredIndexNames) do
            if sampleData:FindFirstChild(manifestIndexName) ~= nil then
                candidates[#candidates + 1] = manifestIndexName
            end
        end
    end

    local canonicalFamily = CanonicalWorldContract.resolveCanonicalManifestFamily(policyMode)
    candidates[#candidates + 1] = canonicalFamily
    return candidates
end

function CanonicalWorldContract.resolveCanonicalMaterializationFamily(policyMode)
    return CanonicalWorldContract.resolveCanonicalMaterializationCandidates(policyMode)[1]
end

function CanonicalWorldContract.loadCanonicalManifestSource(policyMode, timeoutSeconds, options)
    local candidates = CanonicalWorldContract.resolveCanonicalMaterializationCandidates(policyMode)
    local lastError = nil
    for _, manifestIndexName in ipairs(candidates) do
        local ok, handle = pcall(
            ManifestLoader.LoadNamedShardedSampleHandle,
            manifestIndexName,
            timeoutSeconds,
            options
        )
        if ok then
            return handle, manifestIndexName, CanonicalWorldContract.resolveCanonicalManifestFamily(policyMode)
        end
        lastError = handle
    end

    if lastError ~= nil then
        error(lastError)
    end

    error("Canonical world contract did not resolve any manifest materialization candidates")
end

function CanonicalWorldContract.resolveCanonicalAnchor(manifestSource, loadRadius, loadCenter)
    return AustinSpawn.resolveCanonicalAnchorValues(manifestSource, loadRadius, loadCenter)
end

function CanonicalWorldContract.resolveBoundedEnvelope(manifestSource, loadRadius, loadCenter)
    local anchor = CanonicalWorldContract.resolveCanonicalAnchor(manifestSource, loadRadius, loadCenter)
    local selectedChunks = anchor.selectedChunks or {}
    local chunkIds = table.create(#selectedChunks)
    for index, chunk in ipairs(selectedChunks) do
        chunkIds[index] = chunk.id
    end

    return {
        manifestFamily = CanonicalWorldContract.resolveCanonicalManifestFamily(),
        anchor = anchor,
        focusPoint = anchor.focusPoint,
        spawnPoint = anchor.spawnPoint,
        lookTarget = anchor.lookTarget,
        selectedChunks = selectedChunks,
        chunkIds = chunkIds,
    }
end

return CanonicalWorldContract
