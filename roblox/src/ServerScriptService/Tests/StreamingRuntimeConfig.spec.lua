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
    Assert.truthy(
        resolvedDefault.StreamingEnabled,
        "expected resolved local_dev profile to keep streaming enabled"
    )
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
    Assert.truthy(
        resolvedDefault.MemoryGuardrails.Enabled,
        "expected local_dev profile to keep memory guardrails enabled"
    )
    Assert.equal(
        resolvedDefault.MemoryGuardrails.EstimatedBudgetBytes,
        4 * 1024 * 1024 * 1024,
        "expected local_dev profile to keep the lower memory budget"
    )
    Assert.equal(
        resolvedDefault.MemoryGuardrails.ResumeBudgetRatio,
        0.85,
        "expected local_dev profile to keep the default resume ratio"
    )
    Assert.truthy(
        resolvedDefault.MemoryGuardrails.HostProbe.Enabled,
        "expected local_dev profile to enable host probing"
    )

    local resolvedProduction = StreamingRuntimeConfig.Resolve({
        StreamingProfile = "production_server",
        StreamingEnabled = true,
        StreamingTargetRadius = 4096,
        HighDetailRadius = 2048,
        StreamingMaxWorkItemsPerUpdate = 4,
        StreamingImportFrameBudgetSeconds = 1 / 240,
        MemoryGuardrails = WorldConfig.MemoryGuardrails,
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
    Assert.equal(
        resolvedProduction.MemoryGuardrails.EstimatedBudgetBytes,
        8 * 1024 * 1024 * 1024,
        "expected production profile to widen the memory budget"
    )
    Assert.equal(
        resolvedProduction.MemoryGuardrails.ResumeBudgetRatio,
        0.9,
        "expected production profile to use the tighter resume ratio"
    )
    Assert.falsy(
        resolvedProduction.MemoryGuardrails.HostProbe.Enabled,
        "expected production profile to disable host probing"
    )

    local resolvedUnknown = StreamingRuntimeConfig.Resolve({
        StreamingProfile = "unknown_profile",
        StreamingEnabled = true,
        StreamingTargetRadius = 512,
        MemoryGuardrails = WorldConfig.MemoryGuardrails,
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
    Assert.truthy(
        resolvedUnknown.MemoryGuardrails.Enabled,
        "expected unknown profile names to preserve the base memory guardrail config"
    )
    Assert.truthy(
        resolvedUnknown.MemoryGuardrails.CountResidentChunkCost,
        "expected unknown profile names to preserve resident chunk cost counting"
    )
    Assert.truthy(
        resolvedUnknown.MemoryGuardrails.CountInFlightCost,
        "expected unknown profile names to preserve in-flight cost counting"
    )
    Assert.equal(
        resolvedUnknown.MemoryGuardrails.EstimatedBudgetBytes,
        4 * 1024 * 1024 * 1024,
        "expected unknown profile names to preserve the base memory budget"
    )
    Assert.equal(
        resolvedUnknown.MemoryGuardrails.ResumeBudgetRatio,
        0.85,
        "expected unknown profile names to preserve the base resume ratio"
    )
    Assert.equal(
        resolvedUnknown.MemoryGuardrails.HostProbe.Enabled,
        false,
        "expected unknown profile names to preserve host probe disabled by default"
    )
    Assert.equal(
        resolvedUnknown.MemoryGuardrails.HostProbe.CriticalAvailableBytes,
        nil,
        "expected unknown profile names to preserve unset critical available bytes"
    )
    Assert.equal(
        resolvedUnknown.MemoryGuardrails.HostProbe.CriticalPressureLevel,
        nil,
        "expected unknown profile names to preserve unset critical pressure level"
    )

    local resolvedListReplacement = StreamingRuntimeConfig.Resolve({
        StreamingProfile = "custom_lists",
        SubplanRollout = {
            Enabled = false,
            AllowedLayers = { "base_landuse", "base_roads" },
            AllowedChunkIds = { 11, 12 },
        },
        StreamingProfiles = {
            custom_lists = {
                SubplanRollout = {
                    Enabled = true,
                    AllowedLayers = {},
                    AllowedChunkIds = { 99 },
                },
            },
        },
    })
    Assert.equal(
        resolvedListReplacement.SubplanRollout.Enabled,
        true,
        "expected nested record fields to keep merging when array-like tables replace cleanly"
    )
    Assert.equal(
        #resolvedListReplacement.SubplanRollout.AllowedLayers,
        0,
        "expected empty list overrides to replace existing array contents"
    )
    Assert.equal(
        #resolvedListReplacement.SubplanRollout.AllowedChunkIds,
        1,
        "expected array-like overrides to replace existing chunk allowlists"
    )
    Assert.equal(
        resolvedListReplacement.SubplanRollout.AllowedChunkIds[1],
        99,
        "expected chunk allowlist replacement to keep the override element"
    )

    local resolvedPartialNested = StreamingRuntimeConfig.Resolve({
        StreamingProfile = "partial_nested",
        MemoryGuardrails = {
            Enabled = true,
            EstimatedBudgetBytes = 1,
            ResumeBudgetRatio = 0.5,
            CountResidentChunkCost = true,
            CountInFlightCost = false,
            HostProbe = {
                Enabled = false,
                CriticalAvailableBytes = 123,
                CriticalPressureLevel = 0.8,
            },
        },
        StreamingProfiles = {
            partial_nested = {
                MemoryGuardrails = {
                    HostProbe = {
                        Enabled = true,
                    },
                },
            },
        },
    })
    Assert.truthy(
        resolvedPartialNested.MemoryGuardrails.CountResidentChunkCost,
        "expected partial nested overrides to preserve resident cost counting"
    )
    Assert.falsy(
        resolvedPartialNested.MemoryGuardrails.CountInFlightCost,
        "expected partial nested overrides to preserve in-flight cost counting"
    )
    Assert.equal(
        resolvedPartialNested.MemoryGuardrails.HostProbe.Enabled,
        true,
        "expected partial nested overrides to update only the targeted nested field"
    )
    Assert.equal(
        resolvedPartialNested.MemoryGuardrails.HostProbe.CriticalAvailableBytes,
        123,
        "expected partial nested overrides to preserve sibling nested fields"
    )
    Assert.equal(
        resolvedPartialNested.MemoryGuardrails.HostProbe.CriticalPressureLevel,
        0.8,
        "expected partial nested overrides to preserve sibling nested fields"
    )
end
