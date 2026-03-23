return function()
    local RunAustin = require(script.Parent.Parent.ImportService.RunAustin)
    local Assert = require(script.Parent.Assert)

    Assert.equal(
        RunAustin.RUNTIME_PRIMARY_MANIFEST_INDEX_NAME,
        "AustinManifestIndex",
        "expected play mode to default to the canonical Austin runtime manifest"
    )
    Assert.equal(
        RunAustin.RUNTIME_SECONDARY_MANIFEST_INDEX_NAME,
        "AustinHDManifestIndex",
        "expected HD Austin to remain an explicit secondary runtime fallback"
    )

    local candidates = RunAustin.getRuntimeManifestCandidates()
    Assert.equal(#candidates, 2, "expected exactly two runtime manifest candidates")
    Assert.equal(
        candidates[1],
        "AustinManifestIndex",
        "expected the canonical Austin manifest to be tried before the HD subset"
    )
    Assert.equal(
        candidates[2],
        "AustinHDManifestIndex",
        "expected the HD subset to remain available as a fallback"
    )
end
