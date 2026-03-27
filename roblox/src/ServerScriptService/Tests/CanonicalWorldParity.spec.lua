return function()
    local ServerStorage = game:GetService("ServerStorage")

    local Assert = require(script.Parent.Assert)
    local AustinPreviewBuilder = require(script.Parent.Parent.StudioPreview.AustinPreviewBuilder)
    local CanonicalWorldContract = require(script.Parent.Parent.ImportService.CanonicalWorldContract)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local RunAustin = require(script.Parent.Parent.ImportService.RunAustin)

    local canonicalFamily = CanonicalWorldContract.resolveCanonicalManifestFamily("preview")
    Assert.equal(
        canonicalFamily,
        RunAustin.getManifestName(),
        "expected preview and play local-dev parity to share one canonical manifest family"
    )
    Assert.equal(
        canonicalFamily,
        CanonicalWorldContract.resolveCanonicalManifestFamily("full_bake"),
        "expected full-bake policy to keep the canonical Austin family as world truth"
    )
    Assert.equal(
        RunAustin.getRuntimeManifestCandidates()[#RunAustin.getRuntimeManifestCandidates()],
        canonicalFamily,
        "expected play/full_bake routes to keep the same canonical family as the final fallback"
    )
    Assert.equal(
        CanonicalWorldContract.resolveCanonicalMaterializationFamily("preview"),
        CanonicalWorldContract.resolveCanonicalMaterializationFamily("play"),
        "expected preview and play to resolve through the same highest-priority canonical materialization"
    )
    local sharedRadius = 500
    local previewHandle, previewMaterializationFamily =
        CanonicalWorldContract.loadCanonicalManifestSource("preview")
    local canonicalHandle, canonicalMaterializationFamily =
        CanonicalWorldContract.loadCanonicalManifestSource("full_bake")
    local previewCandidates = CanonicalWorldContract.resolveCanonicalMaterializationCandidates("preview")
    local canonicalCandidates = CanonicalWorldContract.resolveCanonicalMaterializationCandidates("full_bake")
    local expectedPreviewMaterializationCandidate = false
    for _, candidate in ipairs(previewCandidates) do
        if candidate == previewMaterializationFamily then
            expectedPreviewMaterializationCandidate = true
            break
        end
    end
    Assert.truthy(
        expectedPreviewMaterializationCandidate,
        "expected preview loading to resolve through a canonical materialization candidate"
    )
    local expectedMaterializationCandidate = false
    for _, candidate in ipairs(canonicalCandidates) do
        if candidate == canonicalMaterializationFamily then
            expectedMaterializationCandidate = true
            break
        end
    end
    Assert.truthy(
        expectedMaterializationCandidate,
        "expected canonical full-bake loading to resolve through a canonical materialization candidate"
    )

    local previewEnvelope = CanonicalWorldContract.resolveBoundedEnvelope(previewHandle, sharedRadius)
    local canonicalEnvelope = CanonicalWorldContract.resolveBoundedEnvelope(canonicalHandle, sharedRadius)
    Assert.equal(
        previewEnvelope.manifestFamily,
        canonicalFamily,
        "expected preview envelopes to report the canonical Austin family as world truth"
    )
    Assert.equal(
        canonicalEnvelope.manifestFamily,
        canonicalFamily,
        "expected full-bake envelopes to report the canonical Austin family as world truth"
    )
    Assert.equal(
        previewMaterializationFamily,
        CanonicalWorldContract.resolveCanonicalMaterializationFamily("preview"),
        "expected preview loading to use the canonical preview materialization"
    )
    Assert.near(
        previewEnvelope.focusPoint.X,
        canonicalEnvelope.focusPoint.X,
        0.001,
        "expected preview and full-bake routes to preserve the canonical focus X"
    )
    Assert.near(
        previewEnvelope.focusPoint.Y,
        canonicalEnvelope.focusPoint.Y,
        0.001,
        "expected preview and full-bake routes to preserve the canonical focus Y"
    )
    Assert.near(
        previewEnvelope.focusPoint.Z,
        canonicalEnvelope.focusPoint.Z,
        0.001,
        "expected preview and full-bake routes to preserve the canonical focus Z"
    )
    Assert.near(
        previewEnvelope.spawnPoint.X,
        canonicalEnvelope.spawnPoint.X,
        0.001,
        "expected preview and full-bake routes to preserve the canonical spawn X"
    )
    Assert.near(
        previewEnvelope.spawnPoint.Y,
        canonicalEnvelope.spawnPoint.Y,
        0.001,
        "expected preview and full-bake routes to preserve the canonical spawn Y"
    )
    Assert.near(
        previewEnvelope.lookTarget.X,
        canonicalEnvelope.lookTarget.X,
        0.001,
        "expected preview and full-bake routes to preserve the canonical look target X"
    )
    Assert.near(
        previewEnvelope.lookTarget.Z,
        canonicalEnvelope.lookTarget.Z,
        0.001,
        "expected preview and full-bake routes to preserve the canonical look target Z"
    )
    Assert.truthy(
        type(previewEnvelope.chunkIds) == "table" and #previewEnvelope.chunkIds > 0,
        "expected the canonical preview materialization to retain a non-empty chunk slice"
    )
    Assert.truthy(
        type(canonicalEnvelope.chunkIds) == "table" and #canonicalEnvelope.chunkIds > 0,
        "expected the canonical full-bake family to retain a non-empty chunk slice"
    )
    local canonicalChunkIds = {}
    for _, chunkRef in ipairs(canonicalHandle.chunkRefs or {}) do
        canonicalChunkIds[chunkRef.id] = true
    end
    local previewChunkIds = {}
    for _, chunkRef in ipairs(previewHandle.chunkRefs or {}) do
        previewChunkIds[chunkRef.id] = true
    end
    for _, chunkId in ipairs(previewEnvelope.chunkIds) do
        Assert.truthy(
            previewChunkIds[chunkId] == true,
            "expected preview chunk ids to come from the canonical preview materialization"
        )
    end
    for _, chunkId in ipairs(canonicalEnvelope.chunkIds) do
        Assert.truthy(
            canonicalChunkIds[chunkId] == true,
            "expected canonical full-bake chunk ids to come from the canonical Austin family"
        )
    end

    local sampleData = ServerStorage:WaitForChild("SampleData")
    local fallbackIndexA = Instance.new("ModuleScript")
    fallbackIndexA.Name = "CanonicalWorldParityRetryIndexA"
    fallbackIndexA.Parent = sampleData
    local fallbackIndexB = Instance.new("ModuleScript")
    fallbackIndexB.Name = "CanonicalWorldParityRetryIndexB"
    fallbackIndexB.Parent = sampleData

    local originalPlayMaterializationNames = CanonicalWorldContract.LOCAL_DEV_PLAY_MATERIALIZATION_INDEX_NAMES
    local originalLoadNamedShardedSampleHandle = ManifestLoader.LoadNamedShardedSampleHandle
    local loadAttempts = {}

    local ok, err = pcall(function()
        CanonicalWorldContract.LOCAL_DEV_PLAY_MATERIALIZATION_INDEX_NAMES = {
            fallbackIndexA.Name,
            fallbackIndexB.Name,
        }
        ManifestLoader.LoadNamedShardedSampleHandle = function(indexName, timeoutSeconds, options)
            loadAttempts[#loadAttempts + 1] = {
                indexName = indexName,
                timeoutSeconds = timeoutSeconds,
                options = options,
            }
            if indexName == fallbackIndexA.Name then
                error("synthetic canonical materialization failure")
            end
            return {
                schemaVersion = "0.4.0",
                meta = {
                    worldName = "CanonicalWorldParityRetry",
                    chunkSizeStuds = 256,
                },
                chunkRefs = {
                    {
                        id = "0_0",
                        originStuds = { x = 0, y = 0, z = 0 },
                    },
                },
            }, indexName, CanonicalWorldContract.resolveCanonicalManifestFamily("play")
        end

        local _, resolvedIndexName, resolvedFamily = CanonicalWorldContract.loadCanonicalManifestSource("play")
        Assert.equal(
            resolvedIndexName,
            fallbackIndexB.Name,
            "expected canonical materialization loading to retry after the first candidate fails"
        )
        Assert.equal(
            resolvedFamily,
            CanonicalWorldContract.resolveCanonicalManifestFamily("play"),
            "expected canonical materialization loading to keep the canonical family stable"
        )
        Assert.equal(#loadAttempts, 2, "expected canonical materialization loading to try later candidates")
        Assert.equal(
            loadAttempts[1].indexName,
            fallbackIndexA.Name,
            "expected the first canonical candidate to be attempted before retrying"
        )
        Assert.equal(
            loadAttempts[2].indexName,
            fallbackIndexB.Name,
            "expected canonical materialization loading to reach the later candidate"
        )
    end)

    fallbackIndexA:Destroy()
    fallbackIndexB:Destroy()
    CanonicalWorldContract.LOCAL_DEV_PLAY_MATERIALIZATION_INDEX_NAMES = originalPlayMaterializationNames
    ManifestLoader.LoadNamedShardedSampleHandle = originalLoadNamedShardedSampleHandle

    Assert.truthy(ok, err)
end
