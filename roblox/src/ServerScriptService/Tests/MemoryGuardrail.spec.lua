return function()
    local Assert = require(script.Parent.Assert)
    local MemoryGuardrail = require(script.Parent.Parent.ImportService.MemoryGuardrail)

    local function makeGuardrail(overrides)
        local config = {
            Enabled = true,
            EstimatedBudgetBytes = 100,
            ResumeBudgetRatio = 0.85,
            CountResidentChunkCost = true,
            CountInFlightCost = true,
            HostProbe = {
                Enabled = true,
                CriticalAvailableBytes = 20,
                CriticalPressureLevel = 0.9,
            },
        }

        if type(overrides) == "table" then
            for key, value in pairs(overrides) do
                config[key] = value
            end
        end

        return MemoryGuardrail.New(config)
    end

    do
        local guardrail = makeGuardrail({
            Enabled = false,
        })

        guardrail:SetProjectedUsageBytes(250)
        guardrail:ObserveHostProbe({
            availableBytes = 1,
            pressureLevel = 0.99,
        })

        local snapshot = guardrail:Snapshot()
        Assert.equal(
            snapshot.state,
            "active",
            "expected disabled guardrails to never enter guarded_pause"
        )
        Assert.falsy(
            snapshot.pauseReason,
            "expected disabled guardrails to avoid recording a pause reason"
        )
    end

    do
        local guardrail = makeGuardrail()

        guardrail:SetProjectedUsageBytes(101)

        local snapshot = guardrail:Snapshot()
        Assert.equal(
            snapshot.state,
            "guarded_pause",
            "expected projected usage over budget to enter guarded_pause"
        )
        Assert.equal(
            snapshot.pauseReason,
            "budget",
            "expected over-budget pauses to record a deterministic budget reason"
        )
    end

    do
        local guardrail = makeGuardrail()

        guardrail:AdmitInFlightBytes(32)
        guardrail:SetProjectedUsageBytes(110)

        local snapshot = guardrail:Snapshot()
        Assert.equal(
            snapshot.state,
            "guarded_pause",
            "expected over-budget accounting to pause even when work is in flight"
        )
        Assert.equal(
            snapshot.inFlightBytes,
            32,
            "expected admitted in-flight work to remain accounted for during pause"
        )
        Assert.equal(
            snapshot.admittedInFlightBytes,
            32,
            "expected pause transitions not to cancel admitted in-flight work"
        )
    end

    do
        local guardrail = makeGuardrail({
            EstimatedBudgetBytes = 100,
            ResumeBudgetRatio = 1.75,
        })

        Assert.equal(
            guardrail:Snapshot().resumeThresholdBytes,
            100,
            "expected invalid resume ratios above 1 to clamp to the budget ceiling"
        )

        guardrail:SetProjectedUsageBytes(101)
        Assert.equal(
            guardrail:Snapshot().state,
            "guarded_pause",
            "expected the guardrail to pause once projected usage exceeds budget"
        )
        Assert.falsy(
            guardrail:Resume(),
            "expected resume to fail while projected usage still exceeds the budget ceiling"
        )

        guardrail:SetProjectedUsageBytes(0)
        Assert.equal(
            guardrail:Snapshot().state,
            "guarded_pause",
            "expected projected usage updates not to auto-clear a paused guardrail"
        )
        Assert.truthy(
            guardrail:Resume(),
            "expected resume to succeed after usage drops below EstimatedBudgetBytes * ResumeBudgetRatio"
        )
        Assert.equal(
            guardrail:Snapshot().state,
            "active",
            "expected resume to clear the paused state explicitly"
        )
    end

    do
        local guardrail = makeGuardrail()

        guardrail:Pause("manual")
        guardrail:SetProjectedUsageBytes(10)
        guardrail:ObserveHostProbe({
            availableBytes = 999,
            pressureLevel = 0.01,
        })

        local snapshot = guardrail:Snapshot()
        Assert.equal(
            snapshot.state,
            "guarded_pause",
            "expected Pause() to keep the guardrail paused across benign updates"
        )
        Assert.equal(
            snapshot.pauseOrigin,
            "manual",
            "expected manual pauses to record an explicit manual pause origin"
        )
        Assert.equal(
            snapshot.pauseReason,
            "manual",
            "expected benign updates not to replace a manual pause reason"
        )

        guardrail:SetResidentBytes(999)
        local afterResidentRefresh = guardrail:Snapshot()
        Assert.equal(
            afterResidentRefresh.state,
            "guarded_pause",
            "expected resident-byte refreshes not to clear or alter pause state"
        )
        Assert.equal(
            afterResidentRefresh.pauseReason,
            "manual",
            "expected resident-byte refreshes not to replace a pause reason"
        )
    end

    do
        local guardrail = makeGuardrail({
            EstimatedBudgetBytes = 100,
            ResumeBudgetRatio = 0.85,
        })

        guardrail:Pause("manual")
        guardrail:SetProjectedUsageBytes(85)
        Assert.equal(
            guardrail:Snapshot().state,
            "guarded_pause",
            "expected a paused guardrail to stay paused at the resume boundary"
        )
        Assert.falsy(
            guardrail:Resume(),
            "expected resume to require projected usage to drop below EstimatedBudgetBytes * ResumeBudgetRatio"
        )

        guardrail:SetProjectedUsageBytes(84)
        Assert.truthy(
            guardrail:Resume(),
            "expected resume to succeed once projected usage drops below the resume boundary"
        )
        Assert.equal(
            guardrail:Snapshot().state,
            "active",
            "expected explicit resume to clear the paused state"
        )
    end

    do
        local zeroRatioGuardrail = makeGuardrail({
            EstimatedBudgetBytes = 100,
            ResumeBudgetRatio = 0,
        })
        local negativeRatioGuardrail = makeGuardrail({
            EstimatedBudgetBytes = 100,
            ResumeBudgetRatio = -0.25,
        })

        Assert.equal(
            zeroRatioGuardrail:Snapshot().resumeThresholdBytes,
            85,
            "expected zero resume ratios to fall back to the safe default"
        )
        Assert.equal(
            negativeRatioGuardrail:Snapshot().resumeThresholdBytes,
            85,
            "expected negative resume ratios to fall back to the safe default"
        )

        zeroRatioGuardrail:SetProjectedUsageBytes(101)
        Assert.equal(
            zeroRatioGuardrail:Snapshot().state,
            "guarded_pause",
            "expected the zero-ratio guardrail to pause on over-budget usage"
        )
        zeroRatioGuardrail:SetProjectedUsageBytes(84)
        Assert.truthy(
            zeroRatioGuardrail:Resume(),
            "expected the zero-ratio guardrail to resume once usage drops below the safe threshold"
        )

        negativeRatioGuardrail:SetProjectedUsageBytes(101)
        Assert.equal(
            negativeRatioGuardrail:Snapshot().state,
            "guarded_pause",
            "expected the negative-ratio guardrail to pause on over-budget usage"
        )
        negativeRatioGuardrail:SetProjectedUsageBytes(84)
        Assert.truthy(
            negativeRatioGuardrail:Resume(),
            "expected the negative-ratio guardrail to resume once usage drops below the safe threshold"
        )
    end

    do
        local guardrail = makeGuardrail()

        guardrail:SetProjectedUsageBytes(60)
        guardrail:ObserveHostProbe({
            availableBytes = 15,
            pressureLevel = 0.95,
        })

        local snapshot = guardrail:Snapshot()
        Assert.equal(
            snapshot.state,
            "guarded_pause",
            "expected a critical host probe to trigger guarded_pause"
        )
        Assert.equal(
            snapshot.pauseReason,
            "host_probe",
            "expected host probe pauses to be recorded separately from deterministic budget pressure"
        )
        Assert.equal(
            snapshot.projectedUsageBytes,
            60,
            "expected host probe pressure not to replace deterministic projected usage accounting"
        )
    end

    do
        local guardrail = makeGuardrail()

        guardrail:SetProjectedUsageBytes(101)
        local budgetSnapshot = guardrail:Snapshot()
        Assert.equal(
            budgetSnapshot.pauseReason,
            "budget",
            "expected over-budget usage to enter a budget pause first"
        )

        guardrail:ObserveHostProbe({
            availableBytes = 15,
            pressureLevel = 0.95,
        })
        local hostProbeSnapshot = guardrail:Snapshot()
        Assert.equal(
            hostProbeSnapshot.pauseReason,
            "host_probe",
            "expected automatic pauses to update to host_probe when host pressure supersedes budget pressure"
        )
        Assert.equal(
            hostProbeSnapshot.pauseOrigin,
            "automatic",
            "expected automatic-cause promotion to keep an automatic pause origin"
        )
    end

    do
        local guardrail = makeGuardrail()

        guardrail:ObserveHostProbe(nil)
        guardrail:ObserveHostProbe({
            availableBytes = "bad",
            pressureLevel = false,
        })

        local snapshot = guardrail:Snapshot()
        Assert.equal(
            snapshot.state,
            "active",
            "expected malformed host-probe samples to be ignored without pausing"
        )
        Assert.falsy(
            snapshot.pauseReason,
            "expected malformed host-probe samples not to create a pause reason"
        )
    end
end
