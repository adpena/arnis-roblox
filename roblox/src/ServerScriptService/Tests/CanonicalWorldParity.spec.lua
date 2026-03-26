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
    local playHandle = {
        schemaVersion = previewHandle.schemaVersion,
        meta = {
            worldName = "ExportedWorld",
            chunkSizeStuds = 256,
            canonicalAnchor = {
                positionStuds = {
                    x = previewEnvelope.focusPoint.X,
                    y = previewEnvelope.focusPoint.Y,
                    z = previewEnvelope.focusPoint.Z,
                },
                lookDirectionStuds = {
                    x = 0,
                    y = 0,
                    z = 1,
                },
            },
        },
        chunks = previewEnvelope.selectedChunks,
    }
    local playEnvelope = CanonicalWorldContract.resolveBoundedEnvelope(playHandle, sharedRadius)

    Assert.near(previewEnvelope.focusPoint.X, playEnvelope.focusPoint.X, 0.001, "expected preview and play to resolve the same canonical focus X for the shared envelope")
    Assert.near(previewEnvelope.focusPoint.Z, playEnvelope.focusPoint.Z, 0.001, "expected preview and play to resolve the same canonical focus Z for the shared envelope")
    Assert.near(previewEnvelope.spawnPoint.X, playEnvelope.spawnPoint.X, 0.001, "expected preview and play to resolve the same canonical spawn X for the shared envelope")
    Assert.near(previewEnvelope.spawnPoint.Z, playEnvelope.spawnPoint.Z, 0.001, "expected preview and play to resolve the same canonical spawn Z for the shared envelope")
    Assert.equal(
        #previewEnvelope.chunkIds,
        #playEnvelope.chunkIds,
        "expected preview and play to select the same chunk slice from the shared envelope"
    )
    for index, chunkId in ipairs(previewEnvelope.chunkIds) do
        Assert.equal(
            chunkId,
            playEnvelope.chunkIds[index],
            "expected preview and play to keep chunk selection order stable"
        )
    end
    Assert.equal(
        previewEnvelope.manifestFamily,
        canonicalFamily,
        "expected preview envelopes to report the canonical Austin family as world truth"
    )
    Assert.equal(
        playEnvelope.manifestFamily,
        canonicalFamily,
        "expected play to keep the canonical Austin family explicit"
    )
end
