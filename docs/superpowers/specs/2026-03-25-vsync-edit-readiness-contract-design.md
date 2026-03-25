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
  - `full_bake`
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
4. a minimal public payload:
   - `target`
   - `ready`
   - `epoch`
   - `reason`

Example:

```json
{
  "target": "preview",
  "ready": false,
  "epoch": 17,
  "reason": "snapshot_reconciling"
}
```

Clients must request the target they need and block until `ready=true` for that target and epoch.

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
- `full_bake`

The authoritative response shape is:

```json
{
  "target": "preview",
  "ready": true,
  "epoch": 23,
  "reason": null
}
```

Rules:

- `ready=true` means safe to act without races for that target.
- `ready=false` means the caller must not act yet.
- `reason` is human-readable and stable enough for logs and debugging.
- clients must not derive readiness from UI state, raw logs, or phase ordering once this contract exists.

### Public Event Surface

Events use the exact same payload as the query API.

Rules:

- events are advisory wakeups
- queries are confirmation of current truth
- clients may react to events, but must confirm by query before taking action
- no separate event schema is allowed

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

### `full_bake`

Safe to start or inspect authoritative bake/export work.

This target is stricter than preview and is intended to back `vsync export-3d` and similar workflows.

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
- `reason` is the only public summary of why a target is not ready

## Epoch Model

Epochs are per-target, not global:

- `edit_sync_epoch`
- `preview_epoch`
- `full_bake_epoch`

This avoids false invalidation between unrelated surfaces.

Rules:

- epochs advance only when safety-to-act might change for that target
- epochs do not advance for irrelevant churn
- stale events or stale cached state are rejected by epoch mismatch

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

### `full_bake_epoch`

Advance when authoritative full-bake inputs or results change.

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
- wire plugin fact reporting into that engine

### Phase 2

- add `arnis-roblox` preview/full-bake fact reporting
- map existing preview telemetry and state into structured readiness inputs

### Phase 3

- convert the Studio harness to block on `vertigo-sync` readiness instead of UI/log heuristics
- make MCP edit actions impossible before `target=preview` or `target=edit_sync` is ready, depending on requested workflow

### Phase 4

- remove or demote obsolete readiness heuristics to diagnostics only

## Testing

Required verification surfaces:

- `vertigo-sync` unit tests for:
  - epoch advancement
  - invalidation coalescing
  - stale event rejection
  - target-specific readiness evaluation
- plugin/runtime integration tests for:
  - reconnect
  - delayed snapshot apply
  - duplicate invalidations
  - preview settle and state-only churn
- harness tests proving:
  - edit-mode MCP actions cannot run before target readiness
  - stale readiness does not survive relaunch/reconnect
- `arnis-roblox` tests proving:
  - state-only preview churn does not spuriously invalidate geometry readiness
  - full-bake readiness remains separate from ordinary preview readiness

## Success Criteria

This design is successful when:

- there is one authoritative readiness contract
- clients request a target explicitly
- clients block on `ready=true` for that target and epoch
- preview actions do not run against unsynced or still-settling sessions
- visible flicker/bounce/rebuild churn from readiness races materially drops
- readiness debugging gets easier because every wait/failure has one `reason` and one target epoch
