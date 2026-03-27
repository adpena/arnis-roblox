return function()
    local HttpService = game:GetService("HttpService")
    local Workspace = game:GetService("Workspace")

    local Assert = require(script.Parent.Assert)
    local AustinPreviewTelemetry = require(script.Parent.Parent.StudioPreview.AustinPreviewTelemetry)

    Workspace:SetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR, nil)

    local state = AustinPreviewTelemetry.newState({
        maxRecentEvents = 3,
    })

    AustinPreviewTelemetry.record(state, "build_scheduled", {
        buildToken = "build-1",
        requestMode = "preview",
    })
    AustinPreviewTelemetry.record(state, "sync_complete", {
        imported = 2,
        skipped = 1,
        unloaded = 0,
        elapsedMs = 42,
    })
    AustinPreviewTelemetry.record(state, "state_apply_succeeded", {
        stateEpoch = 9,
    })
    AustinPreviewTelemetry.record(state, "preview_invalidation_deferred", {
        deferredEpoch = 10,
    })
    AustinPreviewTelemetry.setProjectFacts(state, {
        preview = {
            build_active = false,
            state_apply_pending = false,
            sync_state = "idle",
        },
        full_bake = {
            active = false,
            last_result = "success",
        },
    })

    local snapshot = AustinPreviewTelemetry.snapshot(state)
    Assert.equal(snapshot.version, 1, "expected telemetry snapshot version to be stable")
    Assert.equal(snapshot.counters.build_scheduled, 1, "expected counters to track scheduled preview builds")
    Assert.equal(snapshot.counters.sync_complete, 1, "expected counters to track completed syncs")
    Assert.equal(snapshot.chunkTotals.imported, 2, "expected chunk totals to accumulate imported chunk counts")
    Assert.equal(snapshot.chunkTotals.skipped, 1, "expected chunk totals to accumulate skipped chunk counts")
    Assert.equal(snapshot.lastSync.elapsedMs, 42, "expected the last sync summary to preserve elapsed time")
    Assert.equal(
        snapshot.lastStateApply.stateEpoch,
        9,
        "expected state-apply telemetry to preserve the last applied epoch"
    )
    Assert.equal(#snapshot.recentEvents, 3, "expected recent events to honor the bounded history size")
    Assert.equal(
        snapshot.recentEvents[1].event,
        "sync_complete",
        "expected older events to roll off once the bounded history is full"
    )
    Assert.equal(
        snapshot.projectFacts.preview.sync_state,
        "idle",
        "expected project facts to expose preview sync state without inventing final readiness"
    )
    Assert.equal(
        snapshot.projectFacts.full_bake.last_result,
        "success",
        "expected project facts to preserve the last full-bake result separately from preview state"
    )

    AustinPreviewTelemetry.flushToWorkspace(state, Workspace)
    local encoded = Workspace:GetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR)
    Assert.truthy(type(encoded) == "string" and encoded ~= "", "expected telemetry flush to write JSON")
    local decoded = HttpService:JSONDecode(encoded)
    Assert.equal(decoded.chunkTotals.imported, 2, "expected flushed telemetry JSON to preserve aggregate chunk totals")
    Assert.equal(
        decoded.recentEvents[#decoded.recentEvents].event,
        "preview_invalidation_deferred",
        "expected flushed telemetry JSON to preserve the newest event"
    )
    Assert.equal(
        decoded.projectFacts.preview.build_active,
        false,
        "expected flushed telemetry JSON to preserve compact preview fact state"
    )
    Assert.equal(
        decoded.projectFacts.full_bake.last_result,
        "success",
        "expected flushed telemetry JSON to preserve compact full-bake facts"
    )

    Workspace:SetAttribute(AustinPreviewTelemetry.WORKSPACE_ATTR, nil)
end
