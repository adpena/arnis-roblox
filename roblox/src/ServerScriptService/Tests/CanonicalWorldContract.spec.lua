return function()
    local Assert = require(script.Parent.Assert)
    local AustinSpawn = require(script.Parent.Parent.ImportService.AustinSpawn)
    local CanonicalWorldContract = require(script.Parent.Parent.ImportService.CanonicalWorldContract)

    local function makeManifestSource()
        return {
            schemaVersion = "0.4.0",
            meta = {
                worldName = "ExportedWorld",
                chunkSizeStuds = 256,
                canonicalAnchor = {
                    positionStuds = {
                        x = -6.0854,
                        y = -0.4639,
                        z = -208.371,
                    },
                    lookDirectionStuds = {
                        x = 0,
                        y = 0,
                        z = 1,
                    },
                },
            },
            chunks = {
                {
                    id = "0_0",
                    originStuds = { x = 0, y = 0, z = 0 },
                    roads = {},
                    buildings = {},
                    props = {},
                },
                {
                    id = "1_0",
                    originStuds = { x = 256, y = 0, z = 0 },
                    roads = {},
                    buildings = {},
                    props = {},
                },
                {
                    id = "2_0",
                    originStuds = { x = 512, y = 0, z = 0 },
                    roads = {},
                    buildings = {},
                    props = {},
                },
            },
        }
    end

    local canonicalFamily = CanonicalWorldContract.resolveCanonicalManifestFamily("preview")
    Assert.equal(
        canonicalFamily,
        "AustinManifestIndex",
        "expected the canonical Austin world family to stay locked to the full-bake manifest"
    )
    Assert.equal(
        CanonicalWorldContract.resolveCanonicalManifestFamily("play"),
        canonicalFamily,
        "expected preview and play to resolve the same canonical family"
    )
    Assert.equal(
        CanonicalWorldContract.resolveCanonicalManifestFamily("full_bake"),
        canonicalFamily,
        "expected full-bake requests to resolve the same canonical family"
    )
    local materializationCandidates = CanonicalWorldContract.resolveCanonicalMaterializationCandidates("full_bake")
    Assert.truthy(
        #materializationCandidates >= 1,
        "expected the canonical contract to expose at least one materialization candidate"
    )
    Assert.equal(
        materializationCandidates[#materializationCandidates],
        canonicalFamily,
        "expected the canonical full-bake family to remain the last-resort materialization candidate"
    )
    Assert.equal(
        CanonicalWorldContract.resolveCanonicalMaterializationFamily("full_bake"),
        materializationCandidates[1],
        "expected canonical materialization resolution to return the highest-priority available candidate"
    )

    local manifestSource = makeManifestSource()
    local canonicalAnchor = AustinSpawn.resolveCanonicalAnchorValues(manifestSource, 500)
    local boundedEnvelope = CanonicalWorldContract.resolveBoundedEnvelope(manifestSource, 500)

    Assert.equal(
        boundedEnvelope.manifestFamily,
        canonicalFamily,
        "expected bounded envelopes to retain the canonical manifest family"
    )
    Assert.truthy(type(boundedEnvelope.anchor) == "table", "expected bounded envelopes to carry a resolved anchor")
    Assert.equal(
        boundedEnvelope.focusPoint,
        canonicalAnchor.focusPoint,
        "expected bounded envelopes to reuse the canonical anchor focus point"
    )
    Assert.equal(
        boundedEnvelope.spawnPoint,
        canonicalAnchor.spawnPoint,
        "expected bounded envelopes to reuse the canonical anchor spawn point"
    )
    Assert.equal(
        boundedEnvelope.lookTarget,
        canonicalAnchor.lookTarget,
        "expected bounded envelopes to reuse the canonical anchor look target"
    )
    Assert.truthy(
        type(boundedEnvelope.chunkIds) == "table" and #boundedEnvelope.chunkIds > 0,
        "expected bounded envelopes to derive a chunk slice from the canonical artifact family"
    )

    local chunkSelectionCalls = 0
    local handleBackedManifest = {
        schemaVersion = "0.4.0",
        meta = manifestSource.meta,
        chunkRefs = manifestSource.chunks,
        GetChunkIdsWithinRadius = function(_self, focusPoint, radius)
            chunkSelectionCalls += 1
            Assert.truthy(focusPoint ~= nil, "expected canonical bounded envelopes to pass a focus point")
            Assert.truthy(radius ~= nil, "expected canonical bounded envelopes to pass a radius")
            return { "0_0", "1_0" }
        end,
        GetChunk = function(_self, chunkId)
            for _, chunk in ipairs(manifestSource.chunks) do
                if chunk.id == chunkId then
                    return chunk
                end
            end
            return nil
        end,
    }

    CanonicalWorldContract.resolveBoundedEnvelope(handleBackedManifest, 500)
    CanonicalWorldContract.resolveBoundedEnvelope(handleBackedManifest, 500)
    Assert.equal(
        chunkSelectionCalls,
        2,
        "expected canonical bounded envelopes to re-resolve chunk selection for each build on handle-backed manifests"
    )
end
