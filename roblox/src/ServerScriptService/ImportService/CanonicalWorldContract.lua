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
    local chunkIds = anchor.selectedChunks or {}

    if type(manifestSource) == "table" then
        if type(manifestSource.GetChunkIdsWithinRadius) == "function" then
            local ok, idsOrErr = pcall(function()
                return manifestSource:GetChunkIdsWithinRadius(anchor.focusPoint, loadRadius)
            end)
            if ok and type(idsOrErr) == "table" then
                chunkIds = idsOrErr
            end
        elseif type(manifestSource.LoadChunksWithinRadius) == "function" then
            local ok, chunksOrErr = pcall(function()
                return manifestSource:LoadChunksWithinRadius(anchor.focusPoint, loadRadius)
            end)
            if ok and type(chunksOrErr) == "table" then
                local derivedChunkIds = table.create(#chunksOrErr)
                for index, chunk in ipairs(chunksOrErr) do
                    derivedChunkIds[index] = chunk.id
                end
                chunkIds = derivedChunkIds
            end
        end
    end

    return {
        manifestFamily = CanonicalWorldContract.CANONICAL_MANIFEST_INDEX_NAME,
        anchor = anchor,
        focusPoint = anchor.focusPoint,
        spawnPoint = anchor.spawnPoint,
        lookTarget = anchor.lookTarget,
        chunkIds = chunkIds,
    }
end

return CanonicalWorldContract
