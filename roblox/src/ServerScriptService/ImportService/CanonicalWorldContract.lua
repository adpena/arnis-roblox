local AustinSpawn = require(script.Parent.AustinSpawn)

local CanonicalWorldContract = {}

CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME = "AustinManifestIndex"

function CanonicalWorldContract.resolveCanonicalManifestFamily(_policyMode)
    return CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME
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
