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
    Assert.equal(#candidates, 1, "expected exactly one runtime manifest candidate")
    Assert.equal(
        candidates[1],
        "AustinManifestIndex",
        "expected runtime candidates to stay on the canonical Austin family"
    )
end
