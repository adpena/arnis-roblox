return function()
    local GroundSampler = require(script.Parent.Parent.ImportService.GroundSampler)
    local Assert = require(script.Parent.Assert)

    local chunk = {
        originStuds = { x = 0, y = 10, z = 0 },
        terrain = {
            cellSizeStuds = 16,
            width = 2,
            depth = 2,
            heights = {
                0,
                16,
                32,
                48,
            },
        },
    }

    Assert.near(
        GroundSampler.sampleWorldHeight(chunk, 8, 8),
        34,
        0.001,
        "expected bilinear interpolation at the center of a 2x2 terrain patch"
    )

    Assert.near(
        GroundSampler.sampleWorldHeight(chunk, 0, 0),
        10,
        0.001,
        "expected exact origin sample at the first terrain cell"
    )

    Assert.near(
        GroundSampler.sampleWorldHeight(chunk, 16, 16),
        58,
        0.001,
        "expected exact sample at the far terrain corner"
    )

    local sampler = GroundSampler.createSampler(chunk)
    Assert.equal(
        sampler,
        GroundSampler.createSampler(chunk),
        "expected sampler creation to reuse cached closure for the same chunk"
    )
    Assert.near(
        sampler(8, 8),
        34,
        0.001,
        "expected compiled sampler to match bilinear interpolation"
    )

    Assert.near(sampler(16, 16), 58, 0.001, "expected compiled sampler to match far-corner sample")

    local renderedSampler = GroundSampler.createRenderedSurfaceSampler(chunk)
    Assert.equal(
        renderedSampler,
        GroundSampler.createRenderedSurfaceSampler(chunk),
        "expected rendered surface sampler creation to reuse cached closure for the same chunk"
    )
    Assert.near(
        GroundSampler.sampleRenderedSurfaceHeight(chunk, 8, 8),
        36,
        0.001,
        "expected rendered terrain surface sampling to include the half-voxel terrain offset"
    )
end
