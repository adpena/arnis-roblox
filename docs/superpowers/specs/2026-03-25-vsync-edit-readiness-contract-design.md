# Vertigo Sync Edit Readiness Contract Design

Date: 2026-03-25
Status: Draft
Primary goal: replace heuristic edit-session readiness checks with one authoritative `vertigo-sync` readiness contract that the Studio plugin, harness, and `arnis-roblox` all consume.

## Problem Statement

The current system has a deterministic core, but readiness is still inferred through multiple weaker signals:

- Studio UI state such as "editor ready"
- MCP reachability
- log markers such as plugin startup or snapshot reconciliation
- project-local facts such as preview builder idle state

That creates the exact failure mode we have been seeing:

1. `vsync` can be internally correct.
2. Another layer can act too early anyway.
3. The harness or MCP then runs against an unsynced or still-settling edit session.
4. Visible results include flicker, bounce, repeated rebuilds, and confusing failures that look nondeterministic.

The architecture problem is not just missing retries. It is the lack of one hard-to-misuse readiness contract.

## Goals

- Make `vertigo-sync` the sole owner of edit-session readiness truth.
- Expose one public readiness contract that is simple enough to block on and hard to misuse.
- Support distinct safe-to-act targets:
  - `edit_sync`
  - `preview`
  - `full_bake_start`
  - `full_bake_result`
- Keep internal state rich enough for debugging without forcing clients to interpret phase graphs.
- Advance readiness epochs only on meaningful invalidation, not on every diff.
- Eliminate harness and MCP readiness heuristics as correctness gates.
- Preserve deterministic behavior while reducing churn and race windows.

## Non-Goals

- No replacement of the underlying sync transport.
- No movement of world-import correctness into plugin-only APIs.
- No public API that requires clients to compare internal phases manually.
- No readiness design that depends on Studio UI state as canonical truth.
- No builder-specific scheduling hacks in the readiness layer.

## Recommended Approach

Implement one authoritative `vertigo-sync` readiness engine with:

1. target-based readiness queries
2. target-based readiness events
3. per-target epochs
4. one opaque incarnation token
5. a small public payload:
   - `target`
   - `ready`
   - `epoch`
   - `incarnation_id`
   - `status_class`
   - `code`
   - `reason`

Example:

```json
{
  "target": "preview",
  "ready": false,
  "epoch": 17,
  "incarnation_id": "studio-8f6f6d8c",
  "status_class": "transient",
  "code": "snapshot_reconciling",
  "reason": "snapshot_reconciling"
}
```

Clients must request the target they need and block until `ready=true` for that target, epoch, and incarnation.

This is the right design because it keeps the public contract brutally simple while allowing the internal engine to remain detailed and debuggable.

## Alternatives Considered

### 1. Standardize existing heuristics

Pros:

- smallest immediate change

Cons:

- multiple components still decide readiness independently
- preserves drift and race bugs
- still easy to misuse

Rejected.

### 2. Plugin-owned readiness with server relay

Pros:

- improves Studio-side consistency

Cons:

- still weakens server authority over target invalidation and epoch semantics
- makes reconnect and stale-session handling less clean

Rejected.

### 3. Server-owned readiness with target contracts

Pros:

- one source of truth
- hard to misuse
- clean separation between internal phases and public act-safety
- scalable to preview and full-bake

Cons:

- requires cross-repo contract work

Recommended.

## Contract

### Public Query Surface

Clients ask for a target explicitly:

- `edit_sync`
- `preview`
- `full_bake_start`
- `full_bake_result`

The authoritative response shape is:

```json
{
  "target": "preview",
  "ready": true,
  "epoch": 23,
  "incarnation_id": "studio-8f6f6d8c",
  "status_class": "ready",
  "code": "ready",
  "reason": null
}
```

Rules:

- `ready=true` means safe to act without races for that target.
- `ready=false` means the caller must not act yet.
- `incarnation_id` is an opaque token for one authoritative readiness universe. Callers must treat any incarnation change as invalidating cached readiness, even if the numeric epoch appears unchanged.
- `status_class` is the machine-readable compatibility layer. Initial classes are:
  - `ready`
  - `transient`
  - `blocked`
  - `failed`
- `code` is the stable machine-readable reason within a `status_class`.
- `reason` is diagnostic text for logs and debugging only. Clients must not branch on `reason`.
- clients must not derive readiness from UI state, raw logs, or phase ordering once this contract exists.

Compatibility rules:

- clients should always gate action on `ready`
- clients may branch on `status_class`
- clients may branch on known `code` values, but must treat unknown codes according to `status_class`
- adding a new `code` within an existing `status_class` is backward-compatible
- changing the meaning of an existing `code` is not backward-compatible

### Public Event Surface

Events use the exact same payload as the query API.

Rules:

- events are advisory wakeups
- queries are confirmation of current truth
- clients may react to events, but must confirm by query before taking action
- no separate event schema is allowed
- stale events are rejected on either `incarnation_id` mismatch or `epoch` mismatch

### Action Preconditions

Waiting for readiness is necessary but not sufficient. Any target-sensitive action that depends on synchronized Studio state must carry explicit preconditions:

- `expected_target`
- `expected_epoch`
- `expected_incarnation_id`

Examples:

- harness-triggered MCP evaluation against preview state
- export/bake commands
- mutating edit-session actions that assume a reconciled project tree

Rules:

- `vertigo-sync` must reject the action unless the current authoritative record for `expected_target` is still `ready=true`
- `vertigo-sync` must reject the action if any expected value does not match current authoritative state
- callers must re-query readiness after a rejection instead of retrying blindly
- a successful readiness wait does not authorize later actions against a newer or different incarnation

This closes the query-then-act race window. Without these preconditions, the readiness contract is still vulnerable to TOCTOU bugs.

## Targets

### `edit_sync`

Safe to run code against the synced project tree in Studio.

This means:

- the intended Studio session is connected
- the plugin is attached
- the project is mounted
- the current snapshot is reconciled for this target epoch

### `preview`

Safe to inspect or operate on the baked preview world without bounce, race, or rebuild churn.

This includes all `edit_sync` requirements, plus:

- preview-invalidating work for the current preview epoch is settled
- the visible preview world is coherent
- state-only updates required for correctness have been applied or are guaranteed not to make the world unsafe to inspect

### `full_bake_start`

Safe to start authoritative bake/export work for the current Studio-backed session and inputs.

This target exists because "safe to start" and "result is ready to inspect" are materially different states.

### `full_bake_result`

Safe to inspect or consume the authoritative bake/export result for the current full-bake epoch.

This target is intended to back `vsync export-3d` and similar workflows after bake completion.

## Internal State Machine

The public contract stays small. Internally, `vertigo-sync` tracks richer phases.

Representative internal phases:

- `studio_disconnected`
- `plugin_unavailable`
- `project_mount_pending`
- `snapshot_reconciling`
- `project_synced`
- `preview_build_pending`
- `preview_settling`
- `full_bake_pending`
- `full_bake_settling`
- `ready`

Rules:

- internal phases are implementation detail
- public callers must not compare or interpret them directly
- `status_class` and `code` are the machine-readable public summary of why a target is not ready
- `reason` remains diagnostic text only

## Epoch Model

Epochs are per-target, not global:

- `edit_sync_epoch`
- `preview_epoch`
- `full_bake_start_epoch`
- `full_bake_result_epoch`

This avoids false invalidation between unrelated surfaces.

Rules:

- epochs advance only when safety-to-act might change for that target
- epochs do not advance for irrelevant churn
- stale events or stale cached state are rejected by `incarnation_id` mismatch or epoch mismatch

## Target Dependency Invariants

The public contract must define prerequisite relationships explicitly.

Required invariants:

- `preview.ready=true` implies `edit_sync.ready=true` for the same `incarnation_id`
- `full_bake_start.ready=true` implies `edit_sync.ready=true` for the same `incarnation_id`
- `full_bake_result.ready=true` implies a successful `full_bake_start` occurred for the same `incarnation_id`

Non-invariants:

- `full_bake_result.ready=true` does not automatically imply `preview.ready=true`

This exception is intentional. Preview and authoritative bake may share some inputs, but they are not the same safety surface and may run with different isolation or staging rules.

Dependency rules:

- when a prerequisite target becomes not ready for an incarnation, dependent targets for that incarnation must also become not ready
- a target must never report `ready=true` for incarnation `I` if one of its prerequisites is only ready for a different incarnation
- a dependent target may keep its own epoch, but it may not remain ready across prerequisite invalidation

## Invalidation Rules

### `edit_sync_epoch`

Advance when the synced project tree materially changes in Studio.

Do not advance for:

- plugin reconnect noise with unchanged materialized state
- diagnostics-only telemetry updates

### `preview_epoch`

Advance when preview-safe act semantics change.

Advance for:

- geometry-invalidating source or manifest changes
- preview build cancellation or failure that invalidates the visible preview
- state changes that are part of preview correctness for the current target

Do not advance for:

- source churn that does not survive into preview semantics
- duplicate rebuild requests already converging toward the same result
- state-only updates that can be applied within the current safe preview epoch

### `full_bake_start_epoch`

Advance when the safety of starting an authoritative bake/export changes.

### `full_bake_result_epoch`

Advance when authoritative full-bake results change or become invalid for the current inputs/incarnation.

## Anti-Churn Rules

- single-flight work per target
- coalesced invalidations while work is in flight
- atomic visible-state commit at settle points
- explicit distinction between "fact changed" and "safe-to-act changed"
- no public `ready=true` while the target is half-applied

These rules are mandatory because the current visible flicker/bounce failures are symptoms of missing atomicity at the readiness layer.

## Repository Ownership

### `vertigo-sync` owns

- the authoritative readiness engine
- target definitions
- target epochs
- invalidation rules
- readiness event/query API
- merge logic from server facts, plugin facts, and project facts into one public answer
- harness-facing semantics for when actions may run

### Studio plugin owns

- reporting local facts upward, such as:
  - connected/disconnected
  - project mounted/not mounted
  - snapshot apply started/completed/failed
  - preview or full-bake request started/settled/failed

It is not the final readiness oracle.

### `arnis-roblox` owns

- project-specific readiness facts for `preview` and `full_bake`
- structured state such as:
  - preview sync active
  - preview sync idle
  - deferred state-only update pending
  - full-bake active/completed/failed

It does not publish a competing public readiness API.

### Harness owns

- waiting on the authoritative readiness contract
- verifying the target epoch before action

It must stop using the following as correctness gates:

- `wait_for_editor_ready`
- MCP reachability alone
- raw log markers alone
- Studio UI state alone

Those signals may remain as diagnostics, but not as truth.

## Migration Plan

### Phase 1

- add target-based readiness data model in `vertigo-sync`
- expose query and event payloads
- add `incarnation_id` issuance and invalidation rules
- define stable `status_class` and `code` taxonomy
- wire plugin fact reporting into that engine

### Phase 2

- add `arnis-roblox` preview/full-bake fact reporting
- map existing preview telemetry and state into structured readiness inputs

### Phase 3

- convert the Studio harness to block on `vertigo-sync` readiness instead of UI/log heuristics
- make MCP edit actions impossible before `target=preview` or `target=edit_sync` is ready, depending on requested workflow
- require action preconditions with `expected_target`, `expected_epoch`, and `expected_incarnation_id`

### Phase 4

- remove or demote obsolete readiness heuristics to diagnostics only

## Testing

Required verification surfaces:

- `vertigo-sync` unit tests for:
  - epoch advancement
  - incarnation rollover
  - stable `status_class` and `code` compatibility behavior
  - invalidation coalescing
  - stale event rejection
  - target-specific readiness evaluation
  - action precondition rejection on target, epoch, incarnation, or `ready=false` mismatch
- plugin/runtime integration tests for:
  - reconnect
  - delayed snapshot apply
  - duplicate invalidations
  - preview settle and state-only churn
  - incarnation change during queued client action
- harness tests proving:
  - edit-mode MCP actions cannot run before target readiness
  - stale readiness does not survive relaunch/reconnect
  - query success plus stale action precondition still fails safely
- `arnis-roblox` tests proving:
  - state-only preview churn does not spuriously invalidate geometry readiness
  - full-bake readiness remains separate from ordinary preview readiness

## Success Criteria

This design is successful when:

- there is one authoritative readiness contract
- clients request a target explicitly
- clients block on `ready=true` for that target, epoch, and incarnation
- target-sensitive actions are rejected if their expected target, epoch, or incarnation is stale, or if the current authoritative record is no longer ready
- preview actions do not run against unsynced or still-settling sessions
- visible flicker/bounce/rebuild churn from readiness races materially drops
- readiness debugging gets easier because every wait/failure has one `status_class`, one machine-readable `code`, one diagnostic `reason`, one target epoch, and one incarnation id
