return function()
    local CanonicalWorldContract = require(script.Parent.Parent.ImportService.CanonicalWorldContract)
    local RunAustin = require(script.Parent.Parent.ImportService.RunAustin)
    local Assert = require(script.Parent.Assert)

    Assert.equal(
        RunAustin.getManifestName(),
        CanonicalWorldContract.resolveCanonicalManifestFamily("play"),
        "expected play mode to use the canonical full-bake Austin manifest family"
    )
    Assert.equal(
        RunAustin.CANONICAL_MANIFEST_INDEX_NAME,
        "AustinManifestIndex",
        "expected the runtime canonical manifest constant to stay locked to the full-bake Austin family"
    )

    local candidates = RunAustin.getRuntimeManifestCandidates()
    Assert.truthy(#candidates >= 1, "expected at least one runtime manifest candidate")
    Assert.equal(
        candidates[#candidates],
        "AustinManifestIndex",
        "expected runtime candidates to keep the canonical Austin family as the final fallback"
    )
    Assert.equal(
        candidates[1],
        CanonicalWorldContract.resolveCanonicalMaterializationFamily("play"),
        "expected runtime selection to resolve through the canonical materialization contract"
    )
end
