# Play/Preview/Export Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Converge edit preview, play mode, baked Roblox place export, and `vsync export-3d` onto one canonical full-bake world contract so the same world truth drives preview, runtime, and both `.glb` and `.fbx` export outputs.

**Architecture:** Treat the full-bake Austin manifest family as the only canonical world source in `arnis-roblox`. Make preview and play derived policy modes on top of that same world contract, keep gameplay systems isolated from world-fidelity validation, and make `vertigo-sync` orchestrate full-bake/export while emitting both `.glb` and `.fbx` from one canonical scene IR.

**Tech Stack:** Luau, Roblox Studio importer/builders, Rust (`arbx_cli`, `arbx_pipeline`, `arbx_roblox_export`), SQLite manifest store, `vertigo-sync`, Studio harness, `TestEZ`, Python harness tooling.

---

## File Structure

### Canonical world contract and parity

- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
  - Stop treating preview/runtime manifest families as separate world-definition sources in local-dev parity paths.
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
  - Consume the canonical full-bake world contract in local-dev parity mode instead of the preview-only manifest family.
- Modify: `roblox/src/ServerScriptService/ImportService/AustinSpawn.lua`
  - Keep preview/runtime policy differences explicit while preserving one canonical anchor contract.
- Create: `roblox/src/ServerScriptService/ImportService/CanonicalWorldContract.lua`
  - Small adapter for manifest-family selection, canonical anchor resolution, and envelope derivation.
- Create: `roblox/src/ServerScriptService/Tests/CanonicalWorldContract.spec.lua`
  - Contract tests for canonical manifest family, anchor parity, and bounded-slice derivation.
- Modify: `roblox/src/ServerScriptService/Tests/RunAustinManifestSelection.spec.lua`
  - Lock new manifest-family rules.
- Modify: `roblox/src/ServerScriptService/Tests/AustinPreviewTimeTravel.spec.lua`
  - Keep full-bake vs preview policy coverage aligned with the new contract.
- Create: `roblox/src/ServerScriptService/Tests/CanonicalWorldParity.spec.lua`
  - Hard anti-drift parity assertions for preview/play/full-bake over the same envelope.

### Runtime bootstrap and world-truth stabilization

- Modify: `roblox/src/ServerScriptService/BootstrapAustin.server.lua`
  - Enforce a monotonic bootstrap state machine with unique attempt identity and no duplicate entry.
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
  - Preserve startup chunk identity/signatures and keep startup residency compatible with streaming reconciliation.
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/WorldProbe.client.lua`
  - Surface canonical runtime world evidence for parity checks.
- Create: `roblox/src/ServerScriptService/Tests/BootstrapAustinStateMachine.spec.lua`
  - Runtime state/transition contract tests.
- Modify: `scripts/tests/test_austin_runtime_contract.py`
  - Assert bootstrap phases, retry identity, and world-ready semantics.
- Modify: `scripts/run_studio_harness.sh`
  - Gate observation on authoritative runtime readiness hooks only.
- Modify: `scripts/tests/test_run_studio_harness.py`
  - Reject pre-ready screenshots/assertions as non-authoritative.

### Minimap canonicalization

- Modify: `roblox/src/ServerScriptService/ImportService/CanonicalWorldContract.lua`
  - Expose canonical anchor/basis values to minimap and export consumers.
- Modify: `roblox/src/ServerScriptService/ImportService/MinimapService.lua`
  - Move static-layer payload generation onto canonical transform inputs.
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/MinimapController.client.lua`
  - Consume precomputed/static payloads with north-up canonical transform and incremental redraw only.
- Create: `roblox/src/ServerScriptService/Tests/MinimapCanonicalTransform.spec.lua`
  - Luau-side transform parity tests.
- Modify: `scripts/tests/test_minimap_runtime_contract.py`
  - Runtime harness assertions for canonical transforms and non-janky refresh behavior.

### Baked place + scene IR export

- Create: `docs/superpowers/specs/2026-03-25-roblox-3d-export-contract.md`
  - Required cross-repo export contract prerequisite for implementation.
- Create: `rust/crates/arbx_roblox_export/src/scene_ir.rs`
  - Canonical scene IR types shared by `.glb` and `.fbx` backends.
- Create: `rust/crates/arbx_roblox_export/src/place_export.rs`
  - Baked Roblox place/export metadata helpers.
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs`
  - Export scene IR/place export modules.
- Modify: `rust/crates/arbx_cli/src/main.rs`
  - Add or extend low-level helpers only; do not become the user-facing 3D export/full-bake orchestration entrypoint.
- Modify: `../vertigo-sync/src/main.rs`
  - Add the sole user-facing `export-3d` orchestration entrypoint that requests full bake and emits both formats.
- Modify: `../vertigo-sync/assets/plugin_src/00_main.lua`
  - Add full-bake/export orchestration path on top of existing readiness contract.
- Create: `scripts/tests/test_scene_export_contract.py`
  - High-level contract coverage for place/scene IR/export output expectations.

### Anti-drift ownership and guardrails

- Modify: `docs/vertigo-sync-boundary.md`
  - Make ownership boundaries explicit and non-overlapping.
- Modify: `AGENTS.md`
  - Add anti-drift implementation guardrails for canonical world truth and export parity.
- Modify: `CLAUDE.md`
  - Mirror the anti-drift guardrails for future agents.
- Create: `scripts/tests/test_convergence_guardrails.py`
  - Static guard tests for canonical source ownership and prohibited parallel world-definition paths.

### Gameplay isolation and separate validation

- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua`
  - Split or clearly isolate car / jetpack / parachute behavior from world-fidelity checks.
- Modify: `scripts/run_studio_harness.sh`
  - Add distinct world-fidelity play lane and gameplay-validation lane.
- Modify: `scripts/tests/test_run_studio_harness.py`
  - Lock lane separation and readiness gating.
- Modify: `scripts/tests/test_vehicle_controller_contract.py`
  - Add failing car behavior tests first.

---

### Task 1: Lock the canonical full-bake world contract

**Files:**
- Create: `roblox/src/ServerScriptService/ImportService/CanonicalWorldContract.lua`
- Create: `roblox/src/ServerScriptService/Tests/CanonicalWorldContract.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/CanonicalWorldParity.spec.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/AustinSpawn.lua`
- Modify: `roblox/src/ServerScriptService/Tests/RunAustinManifestSelection.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/AustinPreviewTimeTravel.spec.lua`

- [ ] **Step 1: Write the failing canonical-world contract tests**

Cover:
- preview and play local-dev parity paths do not pick different manifest families as world truth
- the canonical source is the full-bake Austin manifest family
- bounded preview/runtime slices are derived accelerators only
- preview/play for the same shared envelope resolve the same canonical anchor contract
- future code cannot silently introduce a second world-definition path for preview/play/full-bake

- [ ] **Step 2: Run the focused tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_run_studio_harness scripts.tests.test_austin_runtime_contract -v
```

Run in Studio:
```bash
bash scripts/run_studio_harness.sh --no-play --edit-tests --spec-filter CanonicalWorldContract.spec.lua --takeover --hard-restart
bash scripts/run_studio_harness.sh --no-play --edit-tests --spec-filter CanonicalWorldParity.spec.lua --takeover --hard-restart
```

Expected: FAIL because preview and play still use different manifest-family selection logic and separate anchor semantics.

- [ ] **Step 3: Implement the canonical world contract adapter**

Implement:
- one helper that resolves canonical manifest family for local-dev parity and full-bake flows
- one helper that resolves canonical anchor values from the canonical artifact family
- one helper that derives bounded preview/runtime envelopes without redefining world truth

- [ ] **Step 4: Route preview and play through the canonical contract**

Update:
- `AustinPreviewBuilder` to use canonical manifest/anchor resolution in local-dev parity mode
- `RunAustin` to use the same canonical world contract in local-dev parity mode
- keep explicit policy-mode differences small and documented

- [ ] **Step 5: Re-run the focused tests and verify pass**

Run the same commands from Step 2.
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/CanonicalWorldContract.lua \
  roblox/src/ServerScriptService/Tests/CanonicalWorldContract.spec.lua \
  roblox/src/ServerScriptService/Tests/CanonicalWorldParity.spec.lua \
  roblox/src/ServerScriptService/ImportService/RunAustin.lua \
  roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua \
  roblox/src/ServerScriptService/ImportService/AustinSpawn.lua \
  roblox/src/ServerScriptService/Tests/RunAustinManifestSelection.spec.lua \
  roblox/src/ServerScriptService/Tests/AustinPreviewTimeTravel.spec.lua
git commit -m "feat: converge preview and play on canonical world contract"
```

### Task 1.5: Encode anti-drift ownership guardrails

**Files:**
- Modify: `docs/vertigo-sync-boundary.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Create: `scripts/tests/test_convergence_guardrails.py`

- [ ] **Step 1: Write the failing ownership and anti-drift guard tests**

Cover:
- `arnis-roblox` is the only owner of canonical world truth, manifest semantics, and scene extraction adapters
- `vertigo-sync` is the only owner of edit/full-bake orchestration and `export-3d` transport/format orchestration
- no new preview-only or play-only world-definition source may be introduced without tripping tests/docs

- [ ] **Step 2: Run the tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_convergence_guardrails -v
```

Expected: FAIL because these guardrails are not yet encoded explicitly enough.

- [ ] **Step 3: Implement the minimal docs and static guardrails**

Implement:
- explicit ownership notes in `docs/vertigo-sync-boundary.md`
- explicit anti-drift instructions in `AGENTS.md` and `CLAUDE.md`
- one static guard test that fails if new parallel world-definition paths are introduced in the expected entrypoints

- [ ] **Step 4: Re-run the tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add docs/vertigo-sync-boundary.md AGENTS.md CLAUDE.md scripts/tests/test_convergence_guardrails.py
git commit -m "docs: encode convergence ownership guardrails"
```

### Task 2: Enforce bootstrap attempt identity and monotonic phase ordering

**Files:**
- Create: `roblox/src/ServerScriptService/Tests/BootstrapAustinStateMachine.spec.lua`
- Modify: `roblox/src/ServerScriptService/BootstrapAustin.server.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Modify: `scripts/tests/test_austin_runtime_contract.py`

- [ ] **Step 1: Write the failing bootstrap state-machine tests**

Cover:
- bootstrap phases are monotonic for one attempt
- `failed` has a stable observable semantic
- retry produces a new bootstrap-attempt identity
- duplicate bootstrap entry is rejected as a bug

- [ ] **Step 2: Run the focused tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_austin_runtime_contract -v
```

Run in Studio:
```bash
bash scripts/run_studio_harness.sh --play-wait 25 --takeover --hard-restart --spec-filter BootstrapAustinStateMachine.spec.lua
```

Expected: FAIL because duplicate bootstrap and/or incomplete bootstrap attempt identity semantics are still present.

- [ ] **Step 3: Implement the monotonic bootstrap contract**

Implement:
- unique bootstrap attempt identity
- monotonic state transitions
- explicit `failed` handling
- no silent re-entry into the same attempt

- [ ] **Step 4: Re-run the focused tests and verify pass**

Run the same commands from Step 2.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/Tests/BootstrapAustinStateMachine.spec.lua \
  roblox/src/ServerScriptService/BootstrapAustin.server.lua \
  roblox/src/ServerScriptService/ImportService/RunAustin.lua \
  scripts/tests/test_austin_runtime_contract.py
git commit -m "fix: enforce canonical runtime bootstrap state machine"
```

### Task 3: Make startup import and streaming use the same chunk truth

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/init.lua`
- Modify: `roblox/src/ServerScriptService/Tests/SubplanRegistrationChunkTruth.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/PreviewSubplanStateReconcile.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/BootstrapAustinStateMachine.spec.lua`
- Modify: `scripts/tests/test_austin_runtime_contract.py`

- [ ] **Step 1: Write the failing chunk-registration parity tests**

Cover:
- startup-imported chunks and later-streamed chunks carry the same signatures/identity
- streaming reconciliation does not unload or degrade just-imported startup chunks
- world-root truth remains stable through `streaming_ready`
- `world_ready` and `streaming_ready` semantics only pass when required startup chunks are registered and preserved

- [ ] **Step 2: Run the focused tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_austin_runtime_contract -v
```

Run in Studio:
```bash
bash scripts/run_studio_harness.sh --play-wait 25 --takeover --hard-restart --spec-filter SubplanRegistrationChunkTruth.spec.lua
bash scripts/run_studio_harness.sh --play-wait 25 --takeover --hard-restart --spec-filter PreviewSubplanStateReconcile.spec.lua
```

Expected: FAIL if startup and streaming still disagree on chunk identity.

- [ ] **Step 3: Implement the minimal chunk-registration fix**

Implement:
- one canonical chunk-signature path
- one canonical loaded-chunk identity path
- no special startup-vs-streaming interpretation drift
- complete `world_ready` / `streaming_ready` semantics on top of converged chunk-registration truth

- [ ] **Step 4: Re-run the focused tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/StreamingService.lua \
  roblox/src/ServerScriptService/ImportService/init.lua \
  roblox/src/ServerScriptService/Tests/SubplanRegistrationChunkTruth.spec.lua \
  roblox/src/ServerScriptService/Tests/PreviewSubplanStateReconcile.spec.lua \
  roblox/src/ServerScriptService/Tests/BootstrapAustinStateMachine.spec.lua \
  scripts/tests/test_austin_runtime_contract.py
git commit -m "fix: unify startup and streaming chunk registration"
```

### Task 4: Make runtime readiness hooks authoritative for harness observation

**Files:**
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/WorldProbe.client.lua`
- Modify: `roblox/src/ServerScriptService/BootstrapAustin.server.lua`
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/tests/test_run_studio_harness.py`
- Modify: `scripts/tests/test_austin_runtime_contract.py`

- [ ] **Step 1: Write the failing readiness-hook tests**

Cover:
- authoritative runtime-ready hooks exist for `world_ready` and `gameplay_ready`
- harness probes/screenshots before those hooks are rejected as non-authoritative
- harness waits on runtime readiness instead of inferring convergence from timing or incidental markers

- [ ] **Step 2: Run the focused tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_run_studio_harness scripts.tests.test_austin_runtime_contract -v
```

Expected: FAIL because harness observation is not yet fully tied to authoritative runtime readiness hooks.

- [ ] **Step 3: Implement the authoritative readiness hooks**

Implement:
- stable runtime hook publication in `BootstrapAustin.server.lua` and `WorldProbe.client.lua`
- harness gating only on authoritative runtime readiness
- explicit rejection path for pre-ready screenshots/assertions

- [ ] **Step 4: Re-run the focused tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add roblox/src/StarterPlayer/StarterPlayerScripts/WorldProbe.client.lua \
  roblox/src/ServerScriptService/BootstrapAustin.server.lua \
  scripts/run_studio_harness.sh \
  scripts/tests/test_run_studio_harness.py \
  scripts/tests/test_austin_runtime_contract.py
git commit -m "fix: gate harness observation on runtime readiness hooks"
```

### Task 5: Canonicalize building and terrain presentation

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/init.lua`
- Modify: `rust/crates/arbx_pipeline/src/lib.rs`
- Modify: `roblox/src/ServerScriptService/Tests/RoofOnlyRooftopAttachment.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/RoofTruth.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/TerrainAlignment.spec.lua`
- Modify: `scripts/tests/test_austin_runtime_contract.py`

- [ ] **Step 1: Write the failing visual-truth tests**

Cover:
- roof-only structures remain rooftop attachments, not full-height floating slabs
- shell walls/roofs and terrain materials match canonical import semantics in play
- no runtime path replaces imported world truth with checker placeholders or partial shells

- [ ] **Step 2: Run the tests and verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_austin_runtime_contract -v
```

Run in Studio:
```bash
bash scripts/run_studio_harness.sh --play-wait 25 --takeover --hard-restart --spec-filter RoofOnlyRooftopAttachment.spec.lua
bash scripts/run_studio_harness.sh --play-wait 25 --takeover --hard-restart --spec-filter RoofTruth.spec.lua
bash scripts/run_studio_harness.sh --play-wait 25 --takeover --hard-restart --spec-filter TerrainAlignment.spec.lua
```

Expected: FAIL where play still diverges visibly from preview for the same envelope.

- [ ] **Step 3: Implement the minimal importer/compiler fixes**

Implement only the code required to align play with canonical world truth.

- [ ] **Step 4: Re-run tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua \
  roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua \
  roblox/src/ServerScriptService/ImportService/init.lua \
  rust/crates/arbx_pipeline/src/lib.rs \
  roblox/src/ServerScriptService/Tests/RoofOnlyRooftopAttachment.spec.lua \
  roblox/src/ServerScriptService/Tests/RoofTruth.spec.lua \
  roblox/src/ServerScriptService/Tests/TerrainAlignment.spec.lua \
  scripts/tests/test_austin_runtime_contract.py
git commit -m "fix: align play building and terrain presentation with canonical world truth"
```

### Task 6: Canonicalize minimap transforms and static-layer redraw

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/CanonicalWorldContract.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/MinimapService.lua`
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/MinimapController.client.lua`
- Create: `roblox/src/ServerScriptService/Tests/MinimapCanonicalTransform.spec.lua`
- Modify: `scripts/tests/test_minimap_runtime_contract.py`

- [ ] **Step 1: Write the failing minimap transform tests**

Cover:
- all static layers share one north-up canonical transform
- no static layer uses a separate rotation basis
- static background/landuse layers are not rerastered every frame
- minimap transform inputs come from `CanonicalWorldContract`, not a minimap-specific reinterpretation

- [ ] **Step 2: Run the focused tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_minimap_runtime_contract -v
```

Run in Studio:
```bash
bash scripts/run_studio_harness.sh --no-play --edit-tests --spec-filter MinimapCanonicalTransform.spec.lua --takeover --hard-restart
```

Expected: FAIL if static layers still drift or refresh jankily.

- [ ] **Step 3: Implement the minimal canonical-transform path**

Implement:
- precomputed/static payload consumption
- one transform for all layers
- incremental redraw only
- no minimap-specific anchor/basis drift

- [ ] **Step 4: Re-run tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/MinimapService.lua \
  roblox/src/ServerScriptService/ImportService/CanonicalWorldContract.lua \
  roblox/src/StarterPlayer/StarterPlayerScripts/MinimapController.client.lua \
  roblox/src/ServerScriptService/Tests/MinimapCanonicalTransform.spec.lua \
  scripts/tests/test_minimap_runtime_contract.py
git commit -m "fix: canonicalize minimap transforms and redraw path"
```

### Task 7: Separate world-fidelity validation from gameplay validation

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/tests/test_run_studio_harness.py`
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua`
- Modify: `scripts/tests/test_vehicle_controller_contract.py`

- [ ] **Step 1: Write the failing harness-lane and car tests**

Cover:
- world-fidelity play lane runs without abilities/vehicle pollution
- gameplay-validation lane remains available separately
- car mode can enter, stay active, and respond to seat/control state
- vehicle/gameplay systems remain inert or isolated during world-fidelity validation

- [ ] **Step 2: Run the focused tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_run_studio_harness scripts.tests.test_vehicle_controller_contract -v
```

Expected: FAIL because the harness still conflates world and gameplay validation, and car behavior is currently broken.

- [ ] **Step 3: Implement the lane split and minimal car fix**

Implement:
- separate play modes in the harness
- minimal isolated gameplay-path fixes in `VehicleController.client.lua`
- no changes to canonical world-import code in this task

- [ ] **Step 4: Re-run tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/run_studio_harness.sh \
  scripts/tests/test_run_studio_harness.py \
  roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua \
  scripts/tests/test_vehicle_controller_contract.py
git commit -m "fix: separate world fidelity from gameplay validation"
```

### Task 7.5: Add dedicated gameplay-system validation for jetpack, parachute, audio, and camera

**Files:**
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua`
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/AmbientSoundscape.client.lua`
- Modify: `scripts/tests/test_vehicle_controller_contract.py`
- Modify: `scripts/tests/test_play_audio_assets.py`
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/tests/test_run_studio_harness.py`

- [ ] **Step 1: Write the failing gameplay-system tests**

Cover:
- jetpack, parachute, audio, and camera behavior run only in the gameplay-validation lane
- those systems are gated on readiness and do not destabilize world-fidelity validation
- blocked/forbidden assets remain rejected in gameplay validation

- [ ] **Step 2: Run the focused tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_vehicle_controller_contract \
  scripts.tests.test_play_audio_assets \
  scripts.tests.test_run_studio_harness -v
```

Expected: FAIL because gameplay-system validation is not yet fully separated and locked down.

- [ ] **Step 3: Implement the minimal gameplay validation path**

Implement:
- explicit gameplay-validation lane behavior in the harness
- readiness-gated jetpack/parachute/camera behavior
- audio validation that stays outside the world-fidelity lane

- [ ] **Step 4: Re-run the focused tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua \
  roblox/src/StarterPlayer/StarterPlayerScripts/AmbientSoundscape.client.lua \
  scripts/tests/test_vehicle_controller_contract.py \
  scripts/tests/test_play_audio_assets.py \
  scripts/run_studio_harness.sh \
  scripts/tests/test_run_studio_harness.py
git commit -m "fix: isolate gameplay systems from world-fidelity validation"
```

### Task 8: Write the cross-repo export contract before code

**Files:**
- Create: `docs/superpowers/specs/2026-03-25-roblox-3d-export-contract.md`
- Modify: `docs/chunk_schema.md`
- Modify: `docs/vertigo-sync-boundary.md`

- [ ] **Step 1: Write the failing contract gaps as explicit TODO coverage**

Cover:
- canonical scene IR ownership
- canonical full-bake/export entrypoint ownership
- canonical anchor/basis requirements for export alignment
- baked Roblox place / `.glb` / `.fbx` parity rules

- [ ] **Step 2: Save the export contract doc**

Write:
`docs/superpowers/specs/2026-03-25-roblox-3d-export-contract.md`

Expected: the contract exists and is explicit before export implementation begins.

- [ ] **Step 3: Update boundary docs**

Clarify:
- `vsync export-3d` is the sole user-facing 3D export/full-bake orchestration entrypoint
- `arbx_cli` is limited to low-level helpers and internal place-export support

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-03-25-roblox-3d-export-contract.md \
  docs/chunk_schema.md \
  docs/vertigo-sync-boundary.md
git commit -m "docs: define canonical export contract"
```

### Task 9: Add canonical baked Roblox place export

**Files:**
- Modify: `rust/crates/arbx_cli/src/main.rs`
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs`
- Create: `rust/crates/arbx_roblox_export/src/place_export.rs`
- Modify: `scripts/tests/test_scene_export_contract.py`

- [ ] **Step 1: Write the failing baked-place export tests**

Cover:
- a canonical full-bake place export exists as a first-class output
- exported place metadata preserves canonical chunk ownership and source-feature identity or documented collapsed ownership
- place export consumes canonical anchor/basis values from the shared world contract or equivalent exported metadata

- [ ] **Step 2: Run the tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_scene_export_contract -v
```

Expected: FAIL because baked place export is not yet a first-class canonical output.

- [ ] **Step 3: Implement the minimal baked-place export path**

Implement:
- CLI surface
- canonical metadata emission
- no new parallel world-definition logic
- no separate user-facing export orchestration path outside `vertigo-sync`

- [ ] **Step 4: Re-run tests and verify pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/crates/arbx_cli/src/main.rs \
  rust/crates/arbx_roblox_export/src/lib.rs \
  rust/crates/arbx_roblox_export/src/place_export.rs \
  scripts/tests/test_scene_export_contract.py
git commit -m "feat: add canonical baked Roblox place export"
```

### Task 10: Add canonical scene IR and dual `.glb` + `.fbx` export

**Files:**
- Create: `rust/crates/arbx_roblox_export/src/scene_ir.rs`
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs`
- Modify: `rust/crates/arbx_cli/src/main.rs`
- Modify: `../vertigo-sync/src/main.rs`
- Modify: `../vertigo-sync/assets/plugin_src/00_main.lua`
- Modify: `scripts/tests/test_scene_export_contract.py`
- Modify: `docs/superpowers/specs/2026-03-25-roblox-3d-export-contract.md`

- [ ] **Step 1: Write the failing scene-IR/export tests**

Cover:
- one canonical scene IR drives both `.glb` and `.fbx`
- format outputs preserve canonical chunk ownership and source-feature identity or documented collapsed ownership
- `vsync export-3d` emits both formats in one run by default
- no format-specific world extraction path can diverge from the canonical baked-world IR population path
- export alignment consumes the canonical anchor/basis contract and fails if format-specific transforms drift

- [ ] **Step 2: Run the tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_scene_export_contract -v
```

Run:
```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_roblox_export -p arbx_cli -- --nocapture
```

Expected: FAIL because the canonical IR and default dual-export path do not exist yet.

- [ ] **Step 3: Implement the minimal shared scene IR**

Implement:
- scene IR types
- backend-neutral population path from the baked world/export adapters
- no format-specific world extraction drift
- canonical anchor/basis parity with the shared world contract

- [ ] **Step 4: Implement `vsync export-3d` dual export**

Implement:
- full-bake orchestration
- default `.glb` + `.fbx` emission in one run
- format-specific serialization after shared IR population
- `vsync export-3d` remains the only user-facing full-bake 3D export entrypoint

- [ ] **Step 5: Re-run tests and verify pass**

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git -C ../vertigo-sync add src/main.rs assets/plugin_src/00_main.lua
git -C ../vertigo-sync commit -m "feat: add canonical dual-format export orchestration"
git add rust/crates/arbx_roblox_export/src/scene_ir.rs \
  rust/crates/arbx_roblox_export/src/lib.rs \
  rust/crates/arbx_cli/src/main.rs \
  scripts/tests/test_scene_export_contract.py \
  docs/superpowers/specs/2026-03-25-roblox-3d-export-contract.md
git commit -m "feat: add canonical scene ir for glb and fbx export"
```

### Task 11: Final convergence verification

**Files:**
- Modify as needed based on any final contract drift uncovered

- [ ] **Step 1: Run the full relevant verification suite**

Run:
```bash
python3 -m unittest scripts.tests.test_generate_harness_projects \
  scripts.tests.test_refresh_runtime_harness_from_sample_data \
  scripts.tests.test_convergence_guardrails \
  scripts.tests.test_run_studio_harness \
  scripts.tests.test_austin_runtime_contract \
  scripts.tests.test_minimap_runtime_contract \
  scripts.tests.test_vehicle_controller_contract \
  scripts.tests.test_scene_export_contract -v
```

Run:
```bash
cargo test --manifest-path rust/Cargo.toml --workspace -- --nocapture
```

Run:
```bash
bash scripts/run_studio_harness.sh --takeover --hard-restart --skip-plugin-smoke
```

Expected: PASS

- [ ] **Step 2: Run formatting and diff hygiene checks**

Run:
```bash
stylua roblox/src
cargo fmt --manifest-path rust/Cargo.toml --all
git diff --check
git -C ../vertigo-sync diff --check
```

Expected: PASS

- [ ] **Step 3: Commit final cleanups**

```bash
git add -A
git commit -m "chore: finalize play preview export convergence"
git -C ../vertigo-sync add -A
git -C ../vertigo-sync commit -m "chore: finalize export orchestration convergence"
```
