return function()
    local Assert = require(script.Parent.Assert)
    local SubplanRollout = require(script.Parent.Parent.ImportService.SubplanRollout)

    local chunk = {
        id = "hot_1",
        subplans = {
            { id = "terrain", layer = "terrain" },
            { id = "roads", layer = "roads" },
            { id = "buildings", layer = "buildings" },
        },
    }

    Assert.falsy(
        SubplanRollout.IsEnabled({}),
        "expected subplan rollout to stay disabled without an explicit config"
    )
    Assert.equal(
        SubplanRollout.GetAllowedSubplans(chunk, {}),
        nil,
        "expected disabled rollout to keep whole-chunk scheduling"
    )

    local layerOnly = SubplanRollout.GetAllowedSubplans(chunk, {
        SubplanRollout = {
            Enabled = true,
            AllowedLayers = { "terrain" },
        },
    })
    Assert.equal(#layerOnly, 1, "expected layer rollout to filter subplans")
    Assert.equal(layerOnly[1].id, "terrain", "expected only the allowlisted layer to survive")

    local allowlisted = SubplanRollout.GetAllowedSubplans(chunk, {
        SubplanRollout = {
            Enabled = true,
            AllowedChunkIds = { "hot_1" },
        },
    })
    Assert.equal(#allowlisted, 3, "expected allowlisted chunk to keep all of its subplans")

    local nonAllowlisted = SubplanRollout.GetAllowedSubplans({
        id = "cold_1",
        subplans = chunk.subplans,
    }, {
        SubplanRollout = {
            Enabled = true,
            AllowedChunkIds = { "hot_1" },
        },
    })
    Assert.equal(
        nonAllowlisted,
        nil,
        "expected non-allowlisted chunks to keep whole-chunk scheduling"
    )

    local combined = SubplanRollout.GetAllowedSubplans(chunk, {
        SubplanRollout = {
            Enabled = true,
            AllowedLayers = { "terrain", "roads" },
            AllowedChunkIds = { "hot_1" },
        },
    })
    Assert.equal(#combined, 2, "expected combined gate to filter by chunk id and layer")
    Assert.equal(combined[1].id, "terrain", "expected source order to survive rollout filtering")
    Assert.equal(combined[2].id, "roads", "expected source order to survive rollout filtering")

    local allLayers = SubplanRollout.GetFullySchedulableSubplans(chunk, {
        SubplanRollout = {
            Enabled = true,
            AllowedLayers = {},
            AllowedChunkIds = {},
        },
    })
    Assert.equal(
        #allLayers,
        3,
        "expected empty allowed-layer config to keep every subplan schedulable"
    )
    Assert.equal(allLayers[1].id, "terrain", "expected full rollout to preserve source order")
    Assert.equal(allLayers[2].id, "roads", "expected full rollout to preserve source order")
    Assert.equal(allLayers[3].id, "buildings", "expected full rollout to preserve source order")
end
