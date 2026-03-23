return function()
    local RunAustin = require(script.Parent.Parent.ImportService.RunAustin)
    local Assert = require(script.Parent.Assert)

    Assert.equal(
        RunAustin.RUNTIME_PRIMARY_MANIFEST_INDEX_NAME,
        "AustinHDManifestIndex",
        "expected play mode to default to the HD Austin runtime manifest"
    )
    Assert.equal(
        RunAustin.RUNTIME_SECONDARY_MANIFEST_INDEX_NAME,
        "AustinManifestIndex",
        "expected the standard Austin manifest to remain an explicit runtime fallback"
    )

    local candidates = RunAustin.getRuntimeManifestCandidates()
    Assert.equal(#candidates, 2, "expected exactly two runtime manifest candidates")
    Assert.equal(
        candidates[1],
        "AustinHDManifestIndex",
        "expected the HD Austin manifest to be tried before the standard fallback"
    )
    Assert.equal(
        candidates[2],
        "AustinManifestIndex",
        "expected the standard Austin manifest to remain available as a fallback"
    )
end
