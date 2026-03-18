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
end
