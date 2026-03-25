return function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local Assert = require(script.Parent.Assert)
    local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
    local StreamingRuntimeConfig = require(ReplicatedStorage.Shared.StreamingRuntimeConfig)

    local resolvedDefault = StreamingRuntimeConfig.Resolve(WorldConfig)
    Assert.equal(
        resolvedDefault.StreamingProfile,
        "local_dev",
        "expected local_dev to remain the default streaming profile"
    )
    Assert.truthy(resolvedDefault.StreamingEnabled, "expected resolved local_dev profile to keep streaming enabled")
    Assert.equal(
        resolvedDefault.StreamingMaxWorkItemsPerUpdate,
        2,
        "expected local_dev profile to keep a conservative work-item budget"
    )
    Assert.equal(
        resolvedDefault.SubplanRollout.AllowedLayers[1],
        "landuse",
        "expected local_dev profile to stage rollout through cheaper core layers first"
    )
    Assert.equal(
        resolvedDefault.SubplanRollout.AllowedLayers[2],
        "roads",
        "expected local_dev profile to keep roads in the staged rollout"
    )

    local resolvedProduction = StreamingRuntimeConfig.Resolve({
        StreamingProfile = "production_server",
        StreamingEnabled = true,
        StreamingTargetRadius = 4096,
        HighDetailRadius = 2048,
        StreamingMaxWorkItemsPerUpdate = 4,
        StreamingImportFrameBudgetSeconds = 1 / 240,
        SubplanRollout = {
            Enabled = true,
            AllowedLayers = {},
            AllowedChunkIds = {},
        },
        StreamingProfiles = WorldConfig.StreamingProfiles,
    })
    Assert.equal(
        resolvedProduction.StreamingProfile,
        "production_server",
        "expected explicit production profile selection to survive resolution"
    )
    Assert.equal(
        resolvedProduction.StreamingMaxWorkItemsPerUpdate,
        8,
        "expected production profile to widen the work-item budget"
    )
    Assert.equal(
        resolvedProduction.StreamingTargetRadius,
        6144,
        "expected production profile to widen the streaming radius"
    )
    Assert.equal(
        #resolvedProduction.SubplanRollout.AllowedChunkIds,
        0,
        "expected production profile not to depend on a local-dev chunk allowlist"
    )

    local resolvedUnknown = StreamingRuntimeConfig.Resolve({
        StreamingProfile = "unknown_profile",
        StreamingEnabled = true,
        StreamingTargetRadius = 512,
        StreamingProfiles = WorldConfig.StreamingProfiles,
    })
    Assert.equal(
        resolvedUnknown.StreamingProfile,
        "unknown_profile",
        "expected unknown profile names to round-trip without crashing"
    )
    Assert.equal(
        resolvedUnknown.StreamingTargetRadius,
        512,
        "expected unknown profile names to preserve the base config unchanged"
    )
end
