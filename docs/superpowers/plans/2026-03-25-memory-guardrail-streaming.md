# Memory Guardrail Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a scheduler-level memory admission guardrail that pauses new chunk and subplan imports before catastrophic memory pressure while preserving fidelity, determinism, and chunk ownership.

**Architecture:** Keep the canonical policy in `arnis-roblox` by resolving profile-specific `MemoryGuardrails` config through `StreamingRuntimeConfig`, computing deterministic estimated cost inside a focused `MemoryGuardrail` helper, and enforcing pause/resume admission in `StreamingService`. Add optional host-pressure input only as a non-authoritative signal for local development and test harnesses.

**Tech Stack:** Luau runtime/importer modules, Luau Studio specs, Bash/Python harness scripts, existing streaming config and scheduler infrastructure.

---

## File Structure

### Runtime and Scheduler

- Create: `roblox/src/ServerScriptService/ImportService/MemoryGuardrail.lua`
  - owns estimated-cost accounting, hysteresis math, pause/resume state, and telemetry snapshot formatting
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
  - wires guardrail checks into work-item admission without changing builder semantics
- Modify: `roblox/src/ReplicatedStorage/Shared/WorldConfig.lua`
  - adds the canonical `MemoryGuardrails` config block and profile overrides
- Modify: `roblox/src/ReplicatedStorage/Shared/StreamingRuntimeConfig.lua`
  - resolves `MemoryGuardrails` through profile merge like the rest of streaming config

### Tests

- Create: `roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua`
  - focused state-machine and estimation tests
- Modify: `roblox/src/ServerScriptService/Tests/StreamingRuntimeConfig.spec.lua`
  - verifies `MemoryGuardrails` profile resolution
- Modify: `roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua`
  - verifies scheduler admission pauses and resumes without changing final work ordering semantics

### Optional Dev/Test Host Probe

- Modify: `scripts/run_studio_harness.sh`
  - passes optional host-pressure readings into the runtime config surface used by tests
- Modify: `scripts/tests/test_run_studio_harness.py`
  - verifies the harness path stays optional and does not become required

### Docs

- Modify: `docs/superpowers/specs/2026-03-25-memory-guardrail-streaming-design.md`
  - only if implementation details require small clarifications

### Out of Scope

- Do not modify builder modules for this feature.
- Do not move policy into `vertigo-sync`.
- Do not add eviction, degradation, or fidelity fallback behavior.

### Task 1: Add profile-resolved memory guardrail config

**Files:**
- Modify: `roblox/src/ReplicatedStorage/Shared/WorldConfig.lua`
- Modify: `roblox/src/ReplicatedStorage/Shared/StreamingRuntimeConfig.lua`
- Modify: `roblox/src/ServerScriptService/Tests/StreamingRuntimeConfig.spec.lua`

- [ ] **Step 1: Write the failing config-resolution assertions**

Add assertions to `StreamingRuntimeConfig.spec.lua` covering:
- default `local_dev` `MemoryGuardrails.Enabled == true`
- default `local_dev` `EstimatedBudgetBytes == 4 * 1024 * 1024 * 1024`
- profile override behavior for `production_server`
- unknown profiles preserving base `MemoryGuardrails` unchanged

- [ ] **Step 2: Run the focused spec to verify it fails**

Run the Studio spec harness focused on:

```bash
StreamingRuntimeConfig.spec.lua
```

Expected: FAIL because `MemoryGuardrails` does not exist yet.

- [ ] **Step 3: Add canonical config shape to `WorldConfig.lua`**

Define:

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

Also add profile-specific overrides under `StreamingProfiles.local_dev.MemoryGuardrails` and `StreamingProfiles.production_server.MemoryGuardrails`.

- [ ] **Step 4: Keep config resolution purely additive**

In `StreamingRuntimeConfig.lua`:
- rely on the existing deep-merge path
- confirm nested `MemoryGuardrails.HostProbe` tables resolve correctly
- avoid special-case merge code unless tests prove the generic merge is insufficient

- [ ] **Step 5: Re-run the focused spec**

Run the Studio spec harness focused on:

```bash
StreamingRuntimeConfig.spec.lua
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ReplicatedStorage/Shared/WorldConfig.lua roblox/src/ReplicatedStorage/Shared/StreamingRuntimeConfig.lua roblox/src/ServerScriptService/Tests/StreamingRuntimeConfig.spec.lua
git commit -m "feat: add streaming memory guardrail config"
```

### Task 2: Introduce a focused memory guardrail state module

**Files:**
- Create: `roblox/src/ServerScriptService/ImportService/MemoryGuardrail.lua`
- Create: `roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua`

- [ ] **Step 1: Write the failing state-machine spec**

Cover these behaviors in `MemoryGuardrail.spec.lua`:
- disabled guardrails never pause admission
- projected usage over budget enters `guarded_pause`
- admitted work already counted as in-flight is not cancelled by pause
- resume requires dropping below `EstimatedBudgetBytes * ResumeBudgetRatio`
- host probe can trigger pause without rewriting deterministic estimated-cost accounting

- [ ] **Step 2: Run the focused spec to verify it fails**

Run the Studio spec harness focused on:

```bash
MemoryGuardrail.spec.lua
```

Expected: FAIL because the module does not exist yet.

- [ ] **Step 3: Implement minimal helper API**

In `MemoryGuardrail.lua`, add a focused API such as:

```lua
local MemoryGuardrail = {}

function MemoryGuardrail.new(config)
    return {
        config = config,
        state = "normal",
        residentEstimatedCost = 0,
        inFlightEstimatedCost = 0,
        deferredAdmissions = 0,
        lastPauseReason = nil,
        lastResumeReason = nil,
    }
end

function MemoryGuardrail:CanAdmit(nextCost, hostSignal)
    -- returns allowed:boolean, reason:string?
end

function MemoryGuardrail:RecordAdmission(cost)
end

function MemoryGuardrail:RecordCompletion(previousCost, residentCost)
end

function MemoryGuardrail:RecordUnload(cost)
end

function MemoryGuardrail:Snapshot()
end

return MemoryGuardrail
```

Keep the module focused on math, counters, and pause/resume transitions only.

- [ ] **Step 4: Re-run the focused spec**

Run the Studio spec harness focused on:

```bash
MemoryGuardrail.spec.lua
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/MemoryGuardrail.lua roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua
git commit -m "feat: add streaming memory guardrail state machine"
```

### Task 3: Wire pause/resume admission into `StreamingService`

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Modify: `roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua`

- [ ] **Step 1: Extend the scheduler spec with failing pause/resume coverage**

Add focused assertions for:
- work-item admission stops when the next work item would exceed estimated budget
- already-admitted work still completes
- subsequent update cycles resume admission once pressure drops below the hysteresis threshold
- loaded scene content is not evicted when the pause engages

- [ ] **Step 2: Run the focused scheduler spec to verify it fails**

Run the Studio spec harness focused on:

```bash
StreamingPriority.spec.lua
```

Expected: FAIL because `StreamingService` does not use the guardrail yet.

- [ ] **Step 3: Integrate `MemoryGuardrail` into scheduler startup**

In `StreamingService.lua`:
- require `MemoryGuardrail`
- resolve `config.MemoryGuardrails`
- create one guardrail instance for the active streaming session
- reset it on `StreamingService.Stop()`

- [ ] **Step 4: Track estimated resident and in-flight cost**

Use the most deterministic available estimate in this order:
- `subplan.estimatedMemoryCost` or `chunkRef.estimatedMemoryCost` if present
- fallback from `streamingCost`
- conservative zero-safe fallback when neither exists

Record:
- admission cost before import
- resident cost after successful import completion
- unloaded cost when chunks leave the loaded set

Do not modify builder code or chunk ownership.

- [ ] **Step 5: Enforce pause-and-resume admission**

Before each work-item import:
- compute projected pressure
- stop the admission loop for the current update if `CanAdmit(...)` returns false
- keep already-processed work intact

On later update cycles:
- reevaluate through the guardrail and resume naturally once allowed

- [ ] **Step 6: Expose telemetry**

Set `Workspace` attributes or equivalent profiler markers for:
- `ArnisStreamingMemoryGuardrailEnabled`
- `ArnisStreamingMemoryGuardrailState`
- `ArnisStreamingMemoryEstimatedBudgetBytes`
- `ArnisStreamingMemoryResidentEstimatedCost`
- `ArnisStreamingMemoryInFlightEstimatedCost`
- `ArnisStreamingMemoryDeferredAdmissions`
- `ArnisStreamingMemoryLastPauseReason`

- [ ] **Step 7: Re-run the focused scheduler spec**

Run the Studio spec harness focused on:

```bash
StreamingPriority.spec.lua
MemoryGuardrail.spec.lua
StreamingRuntimeConfig.spec.lua
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/StreamingService.lua roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua
git commit -m "feat: enforce streaming memory admission guardrails"
```

### Task 4: Add optional local-dev host-pressure plumbing

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/tests/test_run_studio_harness.py`
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Modify: `roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua`

- [ ] **Step 1: Write the failing optional-host-signal tests**

Cover:
- harness can pass a host-pressure signal when configured
- absence of host-pressure input does not fail the harness
- host-pressure signal can trigger a scheduler pause reason of `host_pressure`

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
python3 -m unittest scripts.tests.test_run_studio_harness -v
```

and the focused Studio spec:

```bash
MemoryGuardrail.spec.lua
```

Expected: FAIL because no host-pressure path exists yet.

- [ ] **Step 3: Add a narrow host-signal injection path**

Keep it optional and local-dev-only:
- pass host-pressure data through harness environment or startup attributes
- read it in `StreamingService` as an optional signal
- feed it into `MemoryGuardrail:CanAdmit(...)`

Do not make `vertigo-sync` or the harness a required runtime dependency.

- [ ] **Step 4: Re-run the targeted tests**

Run:

```bash
python3 -m unittest scripts.tests.test_run_studio_harness -v
```

and the focused Studio spec:

```bash
MemoryGuardrail.spec.lua
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/run_studio_harness.sh scripts/tests/test_run_studio_harness.py roblox/src/ServerScriptService/ImportService/StreamingService.lua roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua
git commit -m "feat: add optional host pressure guardrail input"
```

### Task 5: Verify no fidelity or scheduler regressions

**Files:**
- Modify: `docs/superpowers/specs/2026-03-25-memory-guardrail-streaming-design.md` (only if implementation-learned clarifications are necessary)

- [ ] **Step 1: Run the focused Studio specs**

Run the Studio harness focused on:

```bash
StreamingRuntimeConfig.spec.lua
MemoryGuardrail.spec.lua
StreamingPriority.spec.lua
SubplanImportRetry.spec.lua
```

Expected: PASS.

- [ ] **Step 2: Run the relevant Python harness tests**

Run:

```bash
python3 -m unittest scripts.tests.test_run_studio_harness -v
```

Expected: PASS.

- [ ] **Step 3: Run repo-level verification for touched surfaces**

Run:

```bash
selene --config roblox/selene.toml roblox/src/ServerScriptService/ImportService/MemoryGuardrail.lua roblox/src/ServerScriptService/ImportService/StreamingService.lua roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua roblox/src/ServerScriptService/Tests/StreamingRuntimeConfig.spec.lua
stylua --check roblox/src/ServerScriptService/ImportService/MemoryGuardrail.lua roblox/src/ServerScriptService/ImportService/StreamingService.lua roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua roblox/src/ServerScriptService/Tests/StreamingRuntimeConfig.spec.lua
```

Expected: PASS.

- [ ] **Step 4: Update the spec only if needed**

If implementation reveals a small contract clarification:
- update the spec doc narrowly
- do not widen scope

- [ ] **Step 5: Commit the verification/doc polish**

```bash
git add docs/superpowers/specs/2026-03-25-memory-guardrail-streaming-design.md
git commit -m "docs: finalize memory guardrail implementation notes"
```
