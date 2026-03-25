# Vertigo Sync Edit Readiness Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace heuristic edit-session readiness checks with one authoritative `vertigo-sync` readiness contract that gates harness, MCP, preview, and later full-bake/export actions without races, churn, or stale-session bugs.

**Architecture:** Implement the readiness engine in `vertigo-sync`, not `arnis-roblox`. `vertigo-sync` will own per-target readiness records, `incarnation_id`, `status_class`, `code`, target-specific epochs, query/event surfaces, and action-precondition enforcement. The Studio plugin and `arnis-roblox` only publish structured facts upward; the Studio harness becomes a strict consumer of the contract instead of inferring readiness from UI state, log patterns, or MCP reachability.

**Tech Stack:** Rust (`vertigo-sync` server/lib/mcp), Luau plugin runtime, Luau project preview modules, Bash/Python Studio harness, existing `/plugin/state` transport, SSE or poll-based readiness query/event surface.

---

## File Structure

### `vertigo-sync`

- Modify: `../vertigo-sync/src/lib.rs`
  - add readiness domain types, state storage, per-target epochs, `incarnation_id`, and action-precondition checks
- Modify: `../vertigo-sync/src/server.rs`
  - add authoritative readiness query/event endpoints and wire them to the shared state
- Modify: `../vertigo-sync/src/mcp.rs`
  - require expected readiness preconditions on target-sensitive plugin commands and MCP-backed actions
- Modify: `../vertigo-sync/src/main.rs`
  - extend embedded-plugin contract assertions so the release artifact cannot drift from the readiness design
- Modify: `../vertigo-sync/assets/plugin_src/00_main.lua`
  - publish plugin-side readiness facts, consume server commands carrying readiness preconditions, and stop acting as a parallel readiness oracle
- Modify: `../vertigo-sync/docs/configuration.md`
  - document target names, query semantics, precondition enforcement, and client usage rules
- Create: `../vertigo-sync/tests/readiness_contract_test.rs`
  - integration coverage for query payloads, stale-incarnation rejection, action-precondition rejection, and target dependency behavior

### `arnis-roblox`

- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
  - publish compact project facts for `preview` and `full_bake_*` instead of defining final readiness
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewTelemetry.lua`
  - expose structured project facts and bounded event history in a transport-friendly shape
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewRequest.lua`
  - keep target names aligned with the readiness contract
- Modify: `roblox/src/ServerScriptService/Tests/AustinPreviewTimeTravel.spec.lua`
  - assert project-side fact publishing and separation of preview vs full-bake semantics
- Modify: `roblox/src/ServerScriptService/Tests/AustinPreviewTelemetry.spec.lua`
  - assert serialized project facts are compact, stable, and sufficient for `vertigo-sync`
- Modify: `docs/superpowers/plans/2026-03-25-roblox-3d-export.md`
  - mark readiness-contract implementation as the prerequisite blocker for authoritative export/full-bake work

### Harness

- Modify: `scripts/run_studio_harness.sh`
  - replace heuristic edit-mode readiness gating with `vertigo-sync` target queries plus action preconditions
- Modify: `scripts/studio_harness_policy.py`
  - centralize readiness polling policy and precondition envelope construction
- Modify: `scripts/tests/test_run_studio_harness.py`
  - encode the new contract so future edits cannot regress back to UI/log heuristics

## Profiling And Lowering Rules

- Profile as each task lands instead of waiting until the end.
- Keep generic readiness/orchestration logic in Rust by default when it belongs to `vertigo-sync`.
- Keep project-specific fact gathering in Luau only while it is cheap, bounded, and clearly project-owned.
- Lower code to Rust when profiling proves a real hotspot in:
  - readiness polling or event fanout
  - JSON or telemetry parsing
  - command-envelope validation
  - large-manifest lookup or filtering
  - repeated harness-side parsing or envelope construction
- Do not lower code speculatively. Measure first, then move the hot loop.
- Every task below ends with a profiling checkpoint. If the new path regresses latency, CPU, or memory materially, stop and move the hot logic down to Rust before continuing.

## Task 1: Add The Authoritative Readiness Domain Model In `vertigo-sync`

**Files:**
- Modify: `../vertigo-sync/src/lib.rs`
- Create: `../vertigo-sync/tests/readiness_contract_test.rs`
- Test: `../vertigo-sync/tests/readiness_contract_test.rs`

- [ ] **Step 1: Write the failing Rust integration tests**

Cover:
- `GET /readiness?target=preview` returns:

```json
{
  "target": "preview",
  "ready": false,
  "epoch": 0,
  "incarnation_id": "inc-1",
  "status_class": "transient",
  "code": "plugin_unavailable",
  "reason": "plugin_unavailable"
}
```

- changing the authoritative incarnation invalidates cached readiness even when the target epoch does not change
- dependent targets cannot remain `ready=true` after prerequisite invalidation
- action-precondition checks fail on target mismatch, epoch mismatch, incarnation mismatch, or `ready=false`

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test -- --nocapture
```

Expected: FAIL because `vertigo-sync` does not yet expose readiness records or action-precondition enforcement.

- [ ] **Step 3: Add the readiness state types in `src/lib.rs`**

Define focused types:

```rust
pub enum ReadinessTarget {
    EditSync,
    Preview,
    FullBakeStart,
    FullBakeResult,
}

pub enum ReadinessStatusClass {
    Ready,
    Transient,
    Blocked,
    Failed,
}

pub struct ReadinessRecord {
    pub target: ReadinessTarget,
    pub ready: bool,
    pub epoch: u64,
    pub incarnation_id: String,
    pub status_class: ReadinessStatusClass,
    pub code: String,
    pub reason: Option<String>,
}

pub struct ReadinessExpectation {
    pub target: ReadinessTarget,
    pub epoch: u64,
    pub incarnation_id: String,
}
```

Store one record per target in shared server state and expose helper methods:
- `current_readiness(target)`
- `advance_epoch_if_invalidated(target, invalidation)`
- `rotate_incarnation(reason)`
- `validate_expectation(expectation) -> Result<(), ReadinessRejection>`

- [ ] **Step 4: Encode dependency rules in the domain model**

Implement:
- `preview.ready=true => edit_sync.ready=true`
- `full_bake_start.ready=true => edit_sync.ready=true`
- `full_bake_result.ready=true => successful full_bake_start for same incarnation`

Reject any update that would violate those invariants.

- [ ] **Step 5: Run the tests to verify pass**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test -- --nocapture
```

Expected: PASS

- [ ] **Step 6: Profile the new domain path**

Measure:
- readiness lookup latency
- epoch update cost
- incarnation rollover cost

Record whether any part of the state update path still lives outside Rust and should be lowered.

- [ ] **Step 7: Commit**

```bash
git -C ../vertigo-sync add src/lib.rs tests/readiness_contract_test.rs
git -C ../vertigo-sync commit -m "feat: add readiness domain model"
```

## Task 2: Expose Query And Event Surfaces From `vertigo-sync`

**Files:**
- Modify: `../vertigo-sync/src/server.rs`
- Modify: `../vertigo-sync/src/lib.rs`
- Modify: `../vertigo-sync/tests/readiness_contract_test.rs`
- Test: `../vertigo-sync/tests/readiness_contract_test.rs`

- [ ] **Step 1: Write the failing endpoint tests**

Cover:
- `GET /readiness?target=edit_sync|preview|full_bake_start|full_bake_result`
- invalid target returns `400`
- readiness event stream emits the same payload shape as the query surface
- stale event consumers can reject payloads by `incarnation_id` or `epoch`

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test::query_and_events -- --nocapture
```

Expected: FAIL because the HTTP contract does not exist yet.

- [ ] **Step 3: Add the authoritative query endpoint**

In `src/server.rs`, add:
- `GET /readiness?target=<target>`

Return `ReadinessRecord` JSON directly. Keep field names identical to the spec.

- [ ] **Step 4: Add the readiness event surface**

Prefer SSE so the harness can react quickly without polling loops fighting the server.

Add:
- `GET /readiness/events?target=<target>`

Emit the same JSON shape used by `GET /readiness`. Do not invent a second schema.

- [ ] **Step 5: Run the tests to verify pass**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test::query_and_events -- --nocapture
```

Expected: PASS

- [ ] **Step 6: Profile query and event overhead**

Measure:
- `GET /readiness` latency under repeated polling
- SSE fanout cost
- serialization overhead per readiness record

If payload shaping or serialization becomes hot, keep the shaping logic in Rust and avoid extra Python-side transformations.

- [ ] **Step 7: Commit**

```bash
git -C ../vertigo-sync add src/server.rs src/lib.rs tests/readiness_contract_test.rs
git -C ../vertigo-sync commit -m "feat: expose readiness query and event APIs"
```

## Task 3: Make The Plugin A Fact Reporter, Not A Readiness Oracle

**Files:**
- Modify: `../vertigo-sync/assets/plugin_src/00_main.lua`
- Modify: `../vertigo-sync/src/main.rs`
- Modify: `../vertigo-sync/tests/readiness_contract_test.rs`
- Test: `../vertigo-sync/src/main.rs`

- [ ] **Step 1: Write the failing plugin-contract tests**

Extend embedded-plugin assertions to require:
- plugin fact payload includes enough local facts for server-owned readiness evaluation
- plugin no longer treats `Plugin initialized` or local preview idle state as public readiness truth
- plugin can carry local session facts through `/plugin/state` without publishing final readiness records

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml --bin vsync embedded_plugin_contains_edit_preview_runtime_contract plugin_source_module_contains_preview_runtime_telemetry -- --nocapture
```

Expected: FAIL because the embedded plugin does not yet encode the readiness contract fields.

- [ ] **Step 3: Publish structured readiness facts from the plugin**

In `00_main.lua`, publish only facts such as:

```lua
plugin_facts = {
    studio_connected = true,
    plugin_attached = true,
    project_loaded = PROJECT.loaded,
    snapshot_state = snapshotState,
    snapshot_apply_in_progress = snapshotApplyInProgress,
    plugin_command_busy = pluginCommandBusy,
}
```

Do not publish:
- `preview_build_in_progress`
- `full_bake_active`
- `ready`
- `status_class`
- `code`
- `incarnation_id`

Those are server-owned readiness outputs or project-owned facts, not plugin-owned facts.

- [ ] **Step 4: Assert the embedded plugin surface**

In `src/main.rs`, add source assertions for:
- readiness fact publishing
- plugin-local fact fields such as `snapshot_state` and `snapshot_apply_in_progress`
- no separate plugin-owned readiness truth

- [ ] **Step 5: Run the tests to verify pass**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml --bin vsync embedded_plugin_contains_edit_preview_runtime_contract plugin_source_module_contains_preview_runtime_telemetry -- --nocapture
```

Expected: PASS

- [ ] **Step 6: Profile plugin fact publication**

Measure:
- `/plugin/state` payload size
- fact publication cadence
- plugin-side time spent serializing readiness facts

If fact generation becomes noisy or alloc-heavy in Luau, shrink the payload first. Only move work downward if the hotspot is real and reusable.

- [ ] **Step 7: Commit**

```bash
git -C ../vertigo-sync add assets/plugin_src/00_main.lua src/main.rs tests/readiness_contract_test.rs
git -C ../vertigo-sync commit -m "refactor: make plugin publish readiness facts only"
```

## Task 4: Enforce Action Preconditions For MCP And Plugin Commands

**Files:**
- Modify: `../vertigo-sync/src/mcp.rs`
- Modify: `../vertigo-sync/src/lib.rs`
- Modify: `../vertigo-sync/src/server.rs`
- Modify: `../vertigo-sync/tests/readiness_contract_test.rs`
- Test: `../vertigo-sync/src/mcp.rs`

- [ ] **Step 1: Write the failing command tests**

Cover:
- target-sensitive commands must include:

```json
{
  "expected_target": "preview",
  "expected_epoch": 42,
  "expected_incarnation_id": "inc-7"
}
```

- commands are rejected when the current authoritative record is no longer `ready=true`
- stale queued commands are rejected after incarnation rollover
- commands that do not depend on synchronized Studio state remain unaffected

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml plugin_command_enqueue_and_drain -- --nocapture
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test::action_preconditions -- --nocapture
```

Expected: FAIL because plugin/MCP commands are not yet readiness-bound.

- [ ] **Step 3: Extend command envelopes**

Add optional readiness expectations to target-sensitive commands only:

```rust
pub struct PluginCommand {
    pub id: String,
    pub kind: String,
    pub payload: serde_json::Value,
    pub readiness: Option<ReadinessExpectation>,
}
```

Reject the command before execution if:
- target mismatches
- epoch mismatches
- incarnation mismatches
- current authoritative record is `ready=false`

- [ ] **Step 4: Keep non-readiness-sensitive tools simple**

Do not force readiness expectations onto read-only or detached tooling that does not depend on a synchronized Studio session.

- [ ] **Step 5: Run the tests to verify pass**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml plugin_command_enqueue_and_drain -- --nocapture
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test::action_preconditions -- --nocapture
```

Expected: PASS

- [ ] **Step 6: Profile action-precondition validation**

Measure:
- per-command validation cost
- queue rejection cost for stale commands
- any added latency on normal MCP/plugin command paths

This path belongs in Rust. If any check is still happening in shell or Python after this task, move it down.

- [ ] **Step 7: Commit**

```bash
git -C ../vertigo-sync add src/mcp.rs src/lib.rs src/server.rs tests/readiness_contract_test.rs
git -C ../vertigo-sync commit -m "feat: enforce readiness action preconditions"
```

## Task 5: Publish Project Facts From `arnis-roblox` Without Competing Readiness Logic

**Files:**
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewTelemetry.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewRequest.lua`
- Modify: `roblox/src/ServerScriptService/Tests/AustinPreviewTelemetry.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/AustinPreviewTimeTravel.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/AustinPreviewTelemetry.spec.lua`

- [ ] **Step 1: Write the failing Studio tests**

Cover:
- project telemetry exports preview facts, not final readiness
- fact payload distinguishes:
  - `preview_build_active`
  - `preview_state_apply_pending`
  - `preview_sync_idle`
  - `full_bake_active`
  - `full_bake_last_result`
- preview and full-bake facts remain separate

- [ ] **Step 2: Run the tests to verify failure**

Run: the focused Studio spec surface for preview telemetry and time-travel behavior.
Expected: FAIL because the current payload is telemetry-oriented but not shaped explicitly as readiness inputs.

- [ ] **Step 3: Add compact project fact serialization**

Emit a compact transport value like:

```lua
{
    preview = {
        build_active = false,
        state_apply_pending = false,
        sync_state = "idle",
    },
    full_bake = {
        active = false,
        last_result = "success",
    },
}
```

Keep it bounded and stable. Do not put giant event logs or scene data into this attribute.

- [ ] **Step 4: Keep final readiness out of `arnis-roblox`**

Do not add:
- `preview_ready`
- `edit_sync_ready`
- `full_bake_result_ready`

Those belong only in `vertigo-sync`.

- [ ] **Step 5: Run the tests to verify pass**

Run: the same focused Studio specs.
Expected: PASS

- [ ] **Step 6: Profile project fact gathering**

Measure:
- time spent in `AustinPreviewBuilder` fact updates
- size and cadence of `VertigoPreviewTelemetryJson`
- whether world-state churn causes repeated full serialization

If project fact shaping becomes a visible hot loop, reduce churn first. If it still stays hot and the logic is broadly reusable, move the heavy transform out of Luau.

- [ ] **Step 7: Commit**

```bash
git add roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua roblox/src/ServerScriptService/StudioPreview/AustinPreviewTelemetry.lua roblox/src/ServerScriptService/StudioPreview/AustinPreviewRequest.lua roblox/src/ServerScriptService/Tests/AustinPreviewTelemetry.spec.lua roblox/src/ServerScriptService/Tests/AustinPreviewTimeTravel.spec.lua
git commit -m "refactor(preview): publish project facts for vsync readiness"
```

## Task 6: Merge Project Facts Into Authoritative `vertigo-sync` Readiness

**Files:**
- Modify: `../vertigo-sync/src/lib.rs`
- Modify: `../vertigo-sync/src/server.rs`
- Modify: `../vertigo-sync/tests/readiness_contract_test.rs`
- Test: `../vertigo-sync/tests/readiness_contract_test.rs`

- [ ] **Step 1: Write the failing merge tests**

Cover:
- project fact payload from `arnis-roblox` can drive `preview` readiness transitions
- `full_bake_start` and `full_bake_result` are derived from project facts plus server/plugin prerequisites
- prerequisite invalidation forces dependent targets back to `ready=false` even if project facts are stale
- state-only preview churn does not spuriously advance `preview_epoch`

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test::project_fact_merge -- --nocapture
```

Expected: FAIL because `vertigo-sync` does not yet translate project facts into public readiness records.

- [ ] **Step 3: Parse project facts from the latest plugin-state payload**

Add a focused merge layer in Rust that consumes:
- server-owned facts
- plugin-owned local facts
- project-owned facts from `preview_project`

Shape the merge around the approved targets:
- `edit_sync`
- `preview`
- `full_bake_start`
- `full_bake_result`

- [ ] **Step 4: Apply authoritative merge and invalidation rules**

Implement:
- `preview.ready` requires satisfied `edit_sync` plus settled preview project facts
- `full_bake_start.ready` requires satisfied `edit_sync` plus no conflicting full-bake activity
- `full_bake_result.ready` requires a successful full-bake result for the current incarnation
- project fact staleness cannot keep a target ready after prerequisite invalidation

- [ ] **Step 5: Run the tests to verify pass**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test::project_fact_merge -- --nocapture
```

Expected: PASS

- [ ] **Step 6: Profile the merge path**

Measure:
- merge cost per `/plugin/state` update
- allocations caused by project fact decoding
- any redundant recomputation of unchanged target records

If repeated fact decoding or merge logic becomes hot, keep the merge path entirely in Rust and avoid extra intermediate representations.

- [ ] **Step 7: Commit**

```bash
git -C ../vertigo-sync add src/lib.rs src/server.rs tests/readiness_contract_test.rs
git -C ../vertigo-sync commit -m "feat: derive readiness from project facts"
```

## Task 7: Convert The Studio Harness To The Authoritative Readiness Contract

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/studio_harness_policy.py`
- Modify: `scripts/tests/test_run_studio_harness.py`
- Test: `scripts/tests/test_run_studio_harness.py`

- [ ] **Step 1: Write the failing harness tests**

Cover:
- edit-mode setup waits on `GET /readiness?target=preview` before MCP actions
- `edit_sync` may be used instead when the flow does not require preview state
- MCP action envelopes include `expected_target`, `expected_epoch`, and `expected_incarnation_id`
- harness no longer treats raw log matches or MCP reachability as sufficient readiness truth

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
python3 -m unittest scripts.tests.test_run_studio_harness.RunStudioHarnessTests.test_edit_mode_waits_for_vsync_readiness_before_mcp_actions -v
python3 -m unittest scripts.tests.test_run_studio_harness -v
```

Expected: FAIL because the harness still uses weak readiness signals.

- [ ] **Step 3: Add readiness polling and envelope construction**

In `studio_harness_policy.py`, add helpers shaped like:

```python
def fetch_readiness(base_url: str, target: str) -> dict: ...
def wait_for_readiness(base_url: str, target: str, timeout_seconds: int) -> dict: ...
def build_readiness_expectation(record: dict) -> dict: ...
```

In `run_studio_harness.sh`, call those helpers before:
- edit-mode MCP actions
- preview assertions
- future full-bake/export entrypoints

- [ ] **Step 4: Demote old heuristics to diagnostics**

Keep:
- UI state checks
- log markers
- MCP reachability probes

Only as diagnostics and failure context. Do not use them as the final go/no-go gate.

- [ ] **Step 5: Run the tests and one real harness pass**

Run:

```bash
python3 -m unittest scripts.tests.test_run_studio_harness -v
ARNIS_PREVIEW_TELEMETRY_DIR=/tmp/arnis-preview-telemetry bash scripts/run_studio_harness.sh --hard-restart --takeover --no-play --skip-plugin-smoke --edit-wait 30 --pattern-wait 120
```

Expected:
- tests PASS
- harness waits on authoritative readiness
- MCP actions carry readiness expectations
- no edit-mode action runs against an unsynced clean place

- [ ] **Step 6: Profile the harness path and lower hot loops**

Measure:
- readiness poll frequency and wall time
- JSON parsing cost in Python
- repeated shell/Python work per harness loop
- memory growth during one full edit-mode run

If repeated parsing or envelope construction is measurably hot, move that logic into Rust rather than stacking more shell/Python glue.

- [ ] **Step 7: Commit**

```bash
git add scripts/run_studio_harness.sh scripts/studio_harness_policy.py scripts/tests/test_run_studio_harness.py
git commit -m "test(harness): gate edit actions on vsync readiness"
```

## Task 8: Documentation, Regression Coverage, And Export-Plan Unblock

**Files:**
- Modify: `../vertigo-sync/docs/configuration.md`
- Modify: `docs/superpowers/plans/2026-03-25-roblox-3d-export.md`
- Modify: `scripts/tests/test_run_studio_harness.py`
- Modify: `../vertigo-sync/tests/readiness_contract_test.rs`

- [ ] **Step 1: Write the failing doc/assertion tests**

Cover:
- docs mention target names exactly as implemented
- docs explain `incarnation_id`, `status_class`, and action preconditions
- export/full-bake work is explicitly blocked on `target=full_bake_start` and `target=full_bake_result`

- [ ] **Step 2: Run the tests to verify failure**

Run the relevant Rust/Python doc-contract tests or string assertions.
Expected: FAIL until docs and assertions match shipped behavior.

- [ ] **Step 3: Update docs and unblock the export plan**

Document:
- readiness query endpoint
- readiness event endpoint
- command preconditions
- target semantics
- client usage rules

Then mark the export plan ready to consume `full_bake_*` targets instead of heuristic bake readiness.

- [ ] **Step 4: Run the full focused verification set**

Run:

```bash
cargo test --manifest-path ../vertigo-sync/Cargo.toml readiness_contract_test -- --nocapture
cargo test --manifest-path ../vertigo-sync/Cargo.toml --bin vsync embedded_plugin_contains_edit_preview_runtime_contract plugin_source_module_contains_preview_runtime_telemetry -- --nocapture
python3 -m unittest scripts.tests.test_run_studio_harness -v
```

Expected: PASS

- [ ] **Step 5: Capture the profiling summary**

Write a short summary into the plan or handoff notes:
- what was measured
- what stayed cheap enough in Luau/Python
- what was lowered to Rust
- any remaining hotspots that should block further export work

- [ ] **Step 6: Commit**

```bash
git -C ../vertigo-sync add docs/configuration.md tests/readiness_contract_test.rs src/main.rs
git -C ../vertigo-sync commit -m "docs: publish readiness contract usage"
git add docs/superpowers/plans/2026-03-25-roblox-3d-export.md scripts/tests/test_run_studio_harness.py
git commit -m "docs: align arnis plans with vsync readiness contract"
```

## Execution Notes

- Keep this work split by ownership boundary. Do not move final readiness decisions into `arnis-roblox`.
- Prefer adding the readiness engine and query surface before modifying the harness. The harness test should stay red until the server contract exists.
- Keep the current memory guardrails and telemetry in place during implementation. This plan is about correctness and race elimination, not rolling back the OOM protections.
- Use profiling to decide when to lower hot loops to Rust. Do not guess.
- Treat the approved spec as fixed contract input during implementation. If a true contract erratum appears, stop and run a new spec-review loop instead of silently editing the spec in implementation work.
- Do not start the 3D export/full-bake implementation until `Task 7` is complete and the harness is proven to wait on authoritative readiness.
