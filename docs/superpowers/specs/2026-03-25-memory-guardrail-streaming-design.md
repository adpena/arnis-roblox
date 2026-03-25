# Memory Guardrail Streaming Design

Date: 2026-03-25
Status: Draft

## Problem Statement

The current streaming scheduler has pacing controls, but it does not have a real memory admission policy.

That leaves the system exposed to a bad failure mode:

- chunk and subplan imports remain logically correct
- fidelity is preserved
- but aggregate memory pressure can still climb until local development, Studio validation, or test runs become unstable

This is especially visible in development and testing, where long-lived editor state, local tooling, browser helpers, and build/test workloads can combine with importer activity and push the machine into swap pressure or process death.

We need a guardrail that prevents catastrophic over-admission of work without introducing any of the wrong tradeoffs:

- no fidelity degradation
- no builder-specific hacks
- no content eviction in the first pass
- no loss of source-to-manifest or manifest-to-scene observability

## Goals

- Prevent avoidable out-of-memory and severe swap-pressure failures during streaming-heavy local development and testing.
- Keep the guardrail in the scheduler admission layer, not in individual builders.
- Preserve source truth, manifest truth, chunk ownership, and deterministic scheduling contracts.
- Avoid visible fidelity regressions, partial content suppression, or geometry simplification.
- Support both local development and future production-server deployment through profile-driven configuration.
- Expose enough telemetry to explain why work was admitted, deferred, or resumed.

## Non-Goals

- No runtime fidelity downgrade when memory pressure rises.
- No active eviction of already-loaded chunks or subplans in the first pass.
- No builder-local throttling rules.
- No host-specific memory logic becoming canonical import truth.
- No attempt to solve planet-scale network streaming in this step.

## Recommended Approach

Use a scheduler-level admission guardrail with a pause-and-resume policy.

The core policy is:

1. Estimate the memory cost of resident chunk/subplan content plus in-flight work.
2. Before admitting more work, compare that estimated pressure against a configured profile budget.
3. If the budget would be exceeded, stop admitting new work for the current update cycle.
4. Let already-admitted work finish normally.
5. Resume admitting new work once estimated pressure falls back below the resume threshold.

This is the correct first implementation because it is the safest way to reduce catastrophic memory failures without compromising fidelity or spreading policy into builders.

## Alternatives Considered

### 1. Scheduler admission guardrail only

Pros:

- clean architectural boundary
- low regression risk
- preserves fidelity
- works with existing chunk/subplan scheduler structure

Cons:

- requires good cost estimation to be effective

Recommended.

### 2. Builder-local memory controls

Pros:

- allows per-builder special handling

Cons:

- wrong separation of concerns
- hard to reason about globally
- high risk of hidden fidelity regressions

Rejected.

### 3. Active eviction or degradation of loaded content

Pros:

- can recover memory more aggressively

Cons:

- changes visible scene behavior
- much harder to make deterministic
- high risk of bounce, churn, and user-visible jank

Rejected for the first pass.

## Architecture

### A. Guardrail Lives in Streaming Admission

The guardrail belongs in `StreamingService`, where work items are already:

- collected
- prioritized
- budgeted per update
- admitted into `ImportService.ImportChunk(...)` or `ImportService.ImportChunkSubplan(...)`

This keeps the policy above individual builders and aligned with existing scheduler responsibilities.

Important rule:

- once a work item is admitted, the builders execute normally
- the guardrail only controls admission of new work

### B. Core Memory Model

The guardrail needs a deterministic internal estimate of scheduler-owned memory pressure.

It should track:

- `residentEstimatedCost`
  - estimated cost of currently loaded chunks and imported subplans
- `inFlightEstimatedCost`
  - estimated cost of work admitted this cycle but not yet fully reconciled into resident state
- `nextWorkItemEstimatedCost`
  - estimated cost of the candidate chunk or subplan being considered for admission

The scheduler decision should be based on:

- `residentEstimatedCost + inFlightEstimatedCost + nextWorkItemEstimatedCost`

against:

- `MemoryGuardrails.EstimatedBudgetBytes`

The estimate is intentionally scheduler-owned and approximate. It is not a promise about exact host RSS.

### C. Estimated Cost Inputs

The core estimate should derive from deterministic authored data wherever possible.

Preferred sources, in order:

1. explicit chunk or subplan `estimatedMemoryCost`
2. existing `streamingCost` scaled through a documented conversion function
3. stable feature-count heuristics by layer

Important rules:

- the same authored manifest should yield the same estimated cost inputs
- host-specific measurements may inform safety decisions, but they must not replace the deterministic cost model
- cost estimation is scheduler metadata, not canonical world truth

### D. Optional Host Probe

For local development and test automation, an optional host-memory probe may provide an additional safety brake.

This probe is outside canonical importer truth.

It may read host-level pressure through:

- Studio harness wrappers
- local dev bootstrap scripts
- environment-fed telemetry

It must not be required for normal runtime correctness.

Allowed use:

- if host pressure is clearly beyond a configured safety threshold, temporarily pause new admissions even if deterministic estimated cost remains below budget

Disallowed use:

- changing chunk ownership
- changing import semantics
- changing builder output

### D1. Repository Boundary

The canonical guardrail policy belongs in `arnis-roblox`.

`arnis-roblox` owns:

- runtime profile resolution
- chunk and subplan admission
- pause and resume state transitions
- estimated-cost accounting
- telemetry contract for memory admission decisions

`vertigo-sync` may optionally contribute host-side pressure observations for local development or Studio automation, but only as a non-authoritative signal source.

Important rules:

- `vertigo-sync` must not own the admission policy
- `vertigo-sync` must not define canonical memory truth
- `vertigo-sync` must not change import semantics
- if the host probe is unavailable, `arnis-roblox` still behaves correctly using deterministic estimated-cost budgeting alone

### E. Pause-And-Resume State Machine

The first-pass policy is admission pause only.

States:

1. `normal`
   - scheduler admits work as usual
2. `guarded_pause`
   - scheduler does not admit new work because budget or host-pressure guardrail is active
3. `resume_pending`
   - scheduler has observed pressure recovery and may resume admission on the next update

Transitions:

- `normal -> guarded_pause`
  - admitting the next work item would exceed budget
  - or optional host probe reports pressure beyond threshold
- `guarded_pause -> resume_pending`
  - estimated pressure drops below the configured resume threshold
  - and optional host probe no longer indicates critical pressure
- `resume_pending -> normal`
  - next update cycle begins with budget available

Important rules:

- no loaded content is evicted in this design
- no admitted work is cancelled just because the pause engaged
- the pause only prevents additional admission

### F. Hysteresis

The guardrail must avoid pause/resume flapping.

Required config:

- `EstimatedBudgetBytes`
- `ResumeBudgetRatio`

Recommended behavior:

- pause when projected usage exceeds `EstimatedBudgetBytes`
- resume only when current estimated usage falls below:
  - `EstimatedBudgetBytes * ResumeBudgetRatio`

Recommended initial values:

- `local_dev`
  - `EstimatedBudgetBytes = 4 * 1024^3`
  - `ResumeBudgetRatio = 0.85`
- `production_server`
  - higher budget by profile
  - same or slightly tighter resume ratio

### G. Config Surface

Add a `MemoryGuardrails` block to `WorldConfig.lua`, resolved through `StreamingRuntimeConfig.lua` like the existing streaming profiles.

Proposed shape:

```lua
MemoryGuardrails = {
    Enabled = true,
    EstimatedBudgetBytes = 4 * 1024 * 1024 * 1024,
    ResumeBudgetRatio = 0.85,
    CountResidentChunkCost = true,
    CountInFlightCost = true,
    HostProbe = {
        Enabled = false,
        CriticalAvailableBytes = nil,
        CriticalPressureLevel = nil,
    },
},
```

And inside `StreamingProfiles`:

```lua
StreamingProfiles = {
    local_dev = {
        MemoryGuardrails = {
            Enabled = true,
            EstimatedBudgetBytes = 4 * 1024 * 1024 * 1024,
            ResumeBudgetRatio = 0.85,
            HostProbe = {
                Enabled = true,
            },
        },
    },
    production_server = {
        MemoryGuardrails = {
            Enabled = true,
            EstimatedBudgetBytes = 8 * 1024 * 1024 * 1024,
            ResumeBudgetRatio = 0.9,
            HostProbe = {
                Enabled = false,
            },
        },
    },
}
```

The exact numbers can be tuned later, but the contract should be profile-driven from the start.

### H. Observability

The scheduler must expose structured telemetry so memory pauses are explainable.

Required fields:

- current profile name
- guardrail enabled state
- estimated budget bytes
- resume threshold bytes
- resident estimated cost
- in-flight estimated cost
- paused state
- paused reason
  - `estimated_budget`
  - `host_pressure`
- deferred work item count
- last resume reason
- last admitted work item id

Preferred surfaces:

- `Workspace` attributes for quick Studio inspection
- logger/profiler events for durable traces
- optional harness-exported markers for automated audit/test reports

### I. Determinism And Source Truth

This guardrail must not corrupt the existing architecture.

Required invariants:

- chunk ownership remains unchanged
- subplan ownership remains unchanged
- source-to-manifest mappings remain unchanged
- importing the same full set of work items still yields the same scene result
- guardrail decisions only affect timing of admission, not final output

This keeps the memory guardrail compatible with:

- chunk/subplan auditability
- replayable scheduler reasoning
- future world-scale streaming work

## Data Flow

1. `StreamingRuntimeConfig.Resolve(...)` produces a profile-resolved `MemoryGuardrails` config.
2. `StreamingService` computes prioritized candidate work items as it does today.
3. Before each admission, `StreamingService` computes projected estimated pressure.
4. If the projection exceeds the guardrail, the work item is deferred and the scheduler enters `guarded_pause`.
5. Already-admitted work completes normally.
6. On later updates, the scheduler recomputes pressure and resumes once the resume threshold is satisfied.
7. Telemetry records each pause and resume transition.

## Failure Handling

### Underestimated Cost

If estimated costs are too low, the guardrail may admit too much work.

Mitigation:

- prefer explicit estimated costs in manifest/subplan metadata
- preserve optional host-pressure braking in dev/testing
- record admitted-vs-observed cost telemetry for later tuning

### Overestimated Cost

If estimated costs are too high, the scheduler may become overly conservative.

Mitigation:

- use hysteresis rather than hard permanent pause
- record deferred counts and pause duration
- tune conversion factors through measured runs

### Missing Host Probe

The system must remain correct when no host probe exists.

Mitigation:

- host probe is optional
- deterministic estimated budget remains the canonical gate

## Testing Strategy

### Unit Coverage

- `StreamingRuntimeConfig` resolves `MemoryGuardrails` correctly by profile.
- `StreamingService` pauses admission when projected pressure exceeds budget.
- `StreamingService` resumes only after usage drops below the hysteresis threshold.
- in-flight work is allowed to finish after pause.
- loaded chunks are not evicted when pause engages.

### Integration Coverage

- staged chunk/subplan import remains scene-equivalent with guardrails enabled.
- no preview bounce is introduced solely by guardrail pause/resume.
- local-dev profile and production-server profile resolve distinct budgets without changing final imported scene truth.

### Harness Coverage

- optional local harness can inject host-pressure readings and confirm admission pauses without altering final scene content.
- metrics are exported so Austin fidelity and streaming runs can explain pauses rather than silently stalling.

## Rollout Plan

1. Add config shape and profile resolution.
2. Implement deterministic estimated-cost accounting in `StreamingService`.
3. Add pause/resume state transitions with telemetry only.
4. Add optional host-probe integration for local dev/testing.
5. Verify no regression in scene equivalence, fidelity, or preview stability.
6. Tune budgets using real Austin runs.

## Why This Is The Correct First Step

This design solves the immediate operational problem without violating the architecture.

It does not:

- mutate builder behavior
- discard content
- hide fidelity regressions behind “performance mode”

It does:

- put safety at the right abstraction boundary
- preserve observability
- create a clean foundation for future scheduler intelligence and world-scale streaming

That is the right tradeoff for the current system.
