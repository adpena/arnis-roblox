return function()
    local Assert = require(script.Parent.Assert)
    local AustinPreviewBuilder = require(script.Parent.Parent.StudioPreview.AustinPreviewBuilder)
    local CanonicalWorldContract = require(script.Parent.Parent.ImportService.CanonicalWorldContract)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local RunAustin = require(script.Parent.Parent.ImportService.RunAustin)
    local previewFolder = script.Parent.Parent:WaitForChild("StudioPreview")

    local canonicalFamily = CanonicalWorldContract.resolveCanonicalManifestFamily("preview")
    local previewFamily = AustinPreviewBuilder.FALLBACK_PREVIEW_INDEX_NAME
    Assert.equal(
        canonicalFamily,
        RunAustin.getManifestName(),
        "expected preview and play local-dev parity to share one canonical manifest family"
    )
    Assert.equal(
        previewFamily,
        "AustinPreviewManifestIndex",
        "expected edit preview to keep using the derived accelerator family"
    )
    local sharedRadius = 500
    local previewHandle = ManifestLoader.LoadShardedModuleHandle(
        previewFolder:WaitForChild(previewFamily),
        previewFolder:WaitForChild(AustinPreviewBuilder.FALLBACK_PREVIEW_CHUNKS_NAME)
    )

    local previewEnvelope = CanonicalWorldContract.resolveBoundedEnvelope(previewHandle, sharedRadius)
    Assert.equal(
        previewEnvelope.manifestFamily,
        canonicalFamily,
        "expected preview envelopes to report the canonical Austin family as world truth"
    )
    Assert.equal(
        type(previewHandle.meta.canonicalAnchor),
        "table",
        "expected the derived preview accelerator to carry explicit canonical anchor metadata"
    )
    Assert.equal(
        previewHandle.meta.notes[1],
        "studio preview subset derived from rust/out/austin-manifest.json",
        "expected the derived preview accelerator to document its canonical source"
    )
    Assert.near(
        previewEnvelope.focusPoint.X,
        previewHandle.meta.canonicalAnchor.positionStuds.x,
        0.001,
        "expected the derived preview accelerator to preserve the canonical focus X"
    )
    Assert.near(
        previewEnvelope.focusPoint.Z,
        previewHandle.meta.canonicalAnchor.positionStuds.z,
        0.001,
        "expected the derived preview accelerator to preserve the canonical focus Z"
    )
    Assert.near(
        previewEnvelope.spawnPoint.X,
        previewHandle.meta.canonicalAnchor.positionStuds.x,
        0.001,
        "expected the derived preview accelerator to preserve the canonical spawn X"
    )
    Assert.near(
        previewEnvelope.spawnPoint.Z,
        previewHandle.meta.canonicalAnchor.positionStuds.z,
        0.001,
        "expected the derived preview accelerator to preserve the canonical spawn Z"
    )
    Assert.near(
        previewEnvelope.lookTarget.X,
        previewEnvelope.spawnPoint.X + previewHandle.meta.canonicalAnchor.lookDirectionStuds.x,
        0.001,
        "expected the derived preview accelerator to preserve the canonical look target X"
    )
    Assert.near(
        previewEnvelope.lookTarget.Z,
        previewEnvelope.spawnPoint.Z + previewHandle.meta.canonicalAnchor.lookDirectionStuds.z,
        0.001,
        "expected the derived preview accelerator to preserve the canonical look target Z"
    )
    Assert.truthy(
        type(previewEnvelope.chunkIds) == "table" and #previewEnvelope.chunkIds > 0,
        "expected the derived preview accelerator to retain a non-empty chunk slice"
    )
    local previewChunkIds = {}
    for _, chunkRef in ipairs(previewHandle.chunkRefs or {}) do
        previewChunkIds[chunkRef.id] = true
    end
    for _, chunkId in ipairs(previewEnvelope.chunkIds) do
        Assert.truthy(
            previewChunkIds[chunkId] == true,
            "expected derived preview chunk ids to come from the preview accelerator source"
        )
    end
end
