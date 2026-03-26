# Play/Preview Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make play mode converge toward edit preview by enforcing one canonical world contract, a deterministic runtime bootstrap, and stable building/terrain/minimap/runtime presentation.

**Architecture:** Keep one canonical content truth in `arnis-roblox` and vary only consumer policy after shared-envelope selection has been resolved. Fix the system in layers: parity contract first, then runtime bootstrap ordering, then building/terrain truth, then minimap/runtime gameplay isolation. Keep `vertigo-sync` and MCP as external orchestration/observation surfaces rather than part of world correctness.

**Tech Stack:** Luau (Roblox runtime/tests), Python harness utilities, Rust manifest/compiler pipeline, existing Studio harness and Vertigo integration

---

### Task 1: Canonical Preview/Play Parity Contract

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `scripts/refresh_preview_from_sample_data.py`
- Modify: `scripts/refresh_runtime_harness_from_sample_data.py`
- Test: `roblox/src/ServerScriptService/Tests/RunAustinManifestSelection.spec.lua`
- Test: `scripts/tests/test_refresh_runtime_harness_from_sample_data.py`
- Test: `scripts/tests/test_generated_austin_assets.py`
- Create or modify: `scripts/tests/test_preview_play_parity_contract.py`

- [ ] **Step 1: Write the failing parity tests**

Add tests that assert a shared envelope contract `(manifest source, anchor, radius, allowed layers/subplans)` produces:
- the same chunk IDs for preview and bounded play fixtures
- the same source-feature identity set for overlapping chunks
- the same minimap payload identity set before runtime policy differences

Use the same explicit radius on both sides for this task. Do not compare envelopes with different radii.

- [ ] **Step 2: Run the parity tests to confirm they fail**

Run:
```bash
python3 -m unittest scripts.tests.test_preview_play_parity_contract -v
```

Expected: failure showing preview/runtime fixture derivation still diverges.

- [ ] **Step 3: Implement the minimal convergence changes**

Make preview and bounded-play fixture generation share the same deterministic selection contract for this task, including the same explicit anchor, radius, and allowed layers/subplans. Runtime-only policy differences happen only after that shared envelope is resolved.

- [ ] **Step 4: Rebuild generated fixtures**

Run:
```bash
python3 scripts/refresh_preview_from_sample_data.py
python3 scripts/refresh_runtime_harness_from_sample_data.py
```

- [ ] **Step 5: Re-run the parity tests**

Run:
```bash
python3 -m unittest \
  scripts.tests.test_preview_play_parity_contract \
  scripts.tests.test_refresh_runtime_harness_from_sample_data \
  scripts.tests.test_generated_austin_assets -v
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/RunAustin.lua \
  roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua \
  scripts/refresh_preview_from_sample_data.py \
  scripts/refresh_runtime_harness_from_sample_data.py \
  scripts/tests/test_preview_play_parity_contract.py \
  scripts/tests/test_refresh_runtime_harness_from_sample_data.py \
  scripts/tests/test_generated_austin_assets.py \
  roblox/src/ServerScriptService/Tests/RunAustinManifestSelection.spec.lua
git commit -m "test: enforce preview play parity contract"
```

### Task 2: Runtime Bootstrap State Machine

**Files:**
- Modify: `roblox/src/ServerScriptService/BootstrapAustin.server.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Modify: `scripts/run_studio_harness.sh`
- Test: `scripts/tests/test_austin_runtime_contract.py`
- Test: `scripts/tests/test_run_studio_harness.py`

- [ ] **Step 1: Write failing bootstrap-contract tests**

Add tests for observable runtime states:
- `loading_manifest`
- `importing_startup`
- `world_ready`
- `streaming_ready`
- `minimap_ready`
- `gameplay_ready`
- `failed`

Also assert duplicate bootstrap entry is treated as a test failure.

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
python3 -m unittest \
  scripts.tests.test_austin_runtime_contract \
  scripts.tests.test_run_studio_harness -v
```

- [ ] **Step 3: Implement explicit bootstrap sequencing**

Refactor `BootstrapAustin.server.lua` so startup import, spawn placement, streaming start, minimap start, and gameplay enablement are separate ordered phases with stable workspace attributes.

- [ ] **Step 4: Re-run targeted tests**

Run:
```bash
python3 -m unittest \
  scripts.tests.test_austin_runtime_contract \
  scripts.tests.test_run_studio_harness -v
```

Expected: state transitions are visible and duplicate bootstrap no longer occurs.

- [ ] **Step 5: Verify in Studio harness**

Run:
```bash
HARNESS_MEMORY_LIMIT_MB=4096 bash scripts/run_studio_harness.sh \
  --hard-restart --takeover --skip-plugin-smoke --play --edit-wait 30 --pattern-wait 120
```

Expected: no duplicate bootstrap warning, non-empty `GeneratedWorld_Austin`, stable runtime-ready marker.

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/BootstrapAustin.server.lua \
  roblox/src/ServerScriptService/ImportService/RunAustin.lua \
  scripts/run_studio_harness.sh \
  scripts/tests/test_austin_runtime_contract.py \
  scripts/tests/test_run_studio_harness.py
git commit -m "fix: add deterministic Austin runtime bootstrap state machine"
```

### Task 3: Building And Terrain Truth In Play

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/init.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ImportSignatures.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Test: `roblox/src/ServerScriptService/Tests/RoofOnlyRooftopAttachment.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/OpaqueCivicFacadeTruth.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/TerrainSurfaceHeightTruth.spec.lua`
- Create or modify: `scripts/tests/test_play_render_truth.py`

- [ ] **Step 1: Write failing render-truth tests**

Cover:
- no full-height roof-only shells when rooftop base is known
- wall/facade closure stays opaque in shell-mesh path
- startup-imported chunks retain the same signatures and survive streaming reconciliation
- play runtime does not report pathological overhead-roof counts at canonical spawn

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_play_render_truth -v
```

- [ ] **Step 3: Implement minimal fixes**

Use existing shell-mesh and registration paths. Do not introduce a new building mode. Fix:
- roof-only base derivation
- runtime chunk registration/signature parity
- terrain/material continuity across startup import and streaming

- [ ] **Step 4: Run Luau and Python tests**

Run:
```bash
python3 -m unittest scripts.tests.test_play_render_truth -v
HARNESS_MEMORY_LIMIT_MB=4096 bash scripts/run_studio_harness.sh \
  --hard-restart --takeover --skip-plugin-smoke --edit-tests --no-play \
  --spec-filter RoofOnlyRooftopAttachment.spec.lua --edit-wait 30 --pattern-wait 120
HARNESS_MEMORY_LIMIT_MB=4096 bash scripts/run_studio_harness.sh \
  --hard-restart --takeover --skip-plugin-smoke --edit-tests --no-play \
  --spec-filter OpaqueCivicFacadeTruth.spec.lua --edit-wait 30 --pattern-wait 120
HARNESS_MEMORY_LIMIT_MB=4096 bash scripts/run_studio_harness.sh \
  --hard-restart --takeover --skip-plugin-smoke --edit-tests --no-play \
  --spec-filter TerrainSurfaceHeightTruth.spec.lua --edit-wait 30 --pattern-wait 120
stylua roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua \
  roblox/src/ServerScriptService/ImportService/init.lua \
  roblox/src/ServerScriptService/ImportService/ImportSignatures.lua \
  roblox/src/ServerScriptService/ImportService/StreamingService.lua
```

- [ ] **Step 5: Verify in live play**

Run:
```bash
HARNESS_MEMORY_LIMIT_MB=4096 bash scripts/run_studio_harness.sh \
  --hard-restart --takeover --skip-plugin-smoke --play --edit-wait 30 --pattern-wait 120
```

Expected: no spawn-under-roof corruption, terrain/materials present, world root remains loaded after streaming start.

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua \
  roblox/src/ServerScriptService/ImportService/init.lua \
  roblox/src/ServerScriptService/ImportService/ImportSignatures.lua \
  roblox/src/ServerScriptService/ImportService/StreamingService.lua \
  roblox/src/ServerScriptService/Tests/RoofOnlyRooftopAttachment.spec.lua \
  roblox/src/ServerScriptService/Tests/OpaqueCivicFacadeTruth.spec.lua \
  roblox/src/ServerScriptService/Tests/TerrainSurfaceHeightTruth.spec.lua \
  scripts/tests/test_play_render_truth.py
git commit -m "fix: converge play building and terrain truth with preview"
```

### Task 4: Canonical Minimap Transform And Runtime Stability

**Files:**
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/MinimapController.client.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/MinimapService.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ChunkLoader.lua`
- Test: `scripts/tests/test_minimap_runtime_contract.py`

- [ ] **Step 1: Expand failing minimap tests**

Add assertions for:
- north-up transform
- same transform basis for roads, landuse, and background polygons
- no static-layer full reraster every frame
- stable incremental refresh under player rotation
- a measurable redraw counter or elapsed-cost metric proving static layers are not fully regenerated on each update

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_minimap_runtime_contract -v
```

- [ ] **Step 3: Implement canonical transform/compositing changes**

Keep static chunk payloads stable and only update visibility/compositing and dynamic markers at runtime.

- [ ] **Step 4: Re-run tests**

Run:
```bash
python3 -m unittest scripts.tests.test_minimap_runtime_contract -v
```

Expected: test output includes an execution-level assertion that static-layer redraw counters stay flat across dynamic updates while dynamic marker updates continue.

- [ ] **Step 5: Verify in live play**

Run the Studio harness play lane and confirm the minimap remains aligned and smooth.

- [ ] **Step 6: Commit**

```bash
git add roblox/src/StarterPlayer/StarterPlayerScripts/MinimapController.client.lua \
  roblox/src/ServerScriptService/ImportService/MinimapService.lua \
  roblox/src/ServerScriptService/ImportService/ChunkLoader.lua \
  scripts/tests/test_minimap_runtime_contract.py
git commit -m "fix: canonicalize minimap transform and runtime refresh"
```

### Task 5: Gameplay Isolation And Asset Hygiene

**Files:**
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua`
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/AmbientSoundscape.client.lua`
- Modify: gameplay scripts that still reference forbidden IDs (search-driven)
- Test: `scripts/tests/test_play_audio_assets.py`
- Test: `scripts/tests/test_vehicle_controller_contract.py`

- [ ] **Step 1: Write or tighten failing tests**

Assert:
- no forbidden asset IDs in standard play systems
- default humanoid camera is restored outside explicit vehicle/jetpack modes
- gameplay failures do not change world-ready state

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
python3 -m unittest \
  scripts.tests.test_play_audio_assets \
  scripts.tests.test_vehicle_controller_contract -v
```

- [ ] **Step 3: Implement minimal fixes**

Remove or replace blocked sounds and enforce explicit camera-ownership transitions.

- [ ] **Step 4: Re-run tests**

Run:
```bash
python3 -m unittest \
  scripts.tests.test_play_audio_assets \
  scripts.tests.test_vehicle_controller_contract -v
```

- [ ] **Step 5: Verify in live play**

Run the play harness and confirm no blocked asset errors in the log and stable camera mode transitions.

- [ ] **Step 6: Commit**

```bash
git add roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua \
  roblox/src/StarterPlayer/StarterPlayerScripts/AmbientSoundscape.client.lua \
  scripts/tests/test_play_audio_assets.py \
  scripts/tests/test_vehicle_controller_contract.py
git commit -m "fix: isolate gameplay systems from world readiness"
```

### Task 6: Readiness Hooks And Runtime Proof Signals

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `roblox/src/StarterPlayer/StarterPlayerScripts/WorldProbe.client.lua`
- Modify only repo-local readiness hook consumption needed for verification
- Test: `scripts/tests/test_run_studio_harness.py`

- [ ] **Step 1: Write failing observation tests**

Add assertions that:
- screenshots are captured only after authoritative runtime-ready/edit-ready signals
- `WorldProbe.client.lua` emits world-truth markers (spawn, nearby buildings, overhead roofs, minimap alignment)
- capture payloads consume those emitted markers only after readiness
- bootstrap state transitions are observed in order

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
python3 -m unittest scripts.tests.test_run_studio_harness -v
```

- [ ] **Step 3: Implement minimal observation fixes**

Keep this repo limited to readiness hooks and harness consumption. If MCP backend changes are required, track them in the adjacent repo/tooling rather than smearing them here.

- [ ] **Step 4: Re-run tests**

Run:
```bash
python3 -m unittest scripts.tests.test_run_studio_harness -v
```

Expected: the test suite asserts ordered bootstrap states from runtime-ready hooks rather than only checking source text or log presence.

- [ ] **Step 5: Verify with real capture**

Run the harness and confirm the saved screenshot matches the settled play or preview state rather than a torn-down session.

- [ ] **Step 6: Commit**

```bash
git add scripts/run_studio_harness.sh \
  roblox/src/StarterPlayer/StarterPlayerScripts/WorldProbe.client.lua \
  scripts/tests/test_run_studio_harness.py
git commit -m "test: make runtime proof signals readiness-safe"
```

### Task 7: Bounded Streaming Hardening Follow-On

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/ChunkPriority.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/MemoryGuardrail.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Modify: `docs/exporter-fixtures.md`
- Test: `roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua`

- [ ] **Step 1: Write failing bounded-streaming tests**

Add tests that assert:
- stable chunk/tile identity is preserved across startup import and streaming updates
- bounded-memory telemetry remains populated during convergence runs
- priority scheduling remains deterministic for the same input and focal point

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
HARNESS_MEMORY_LIMIT_MB=4096 bash scripts/run_studio_harness.sh \
  --hard-restart --takeover --skip-plugin-smoke --edit-tests --no-play \
  --spec-filter MemoryGuardrail.spec.lua --edit-wait 30 --pattern-wait 120
HARNESS_MEMORY_LIMIT_MB=4096 bash scripts/run_studio_harness.sh \
  --hard-restart --takeover --skip-plugin-smoke --edit-tests --no-play \
  --spec-filter StreamingPriority.spec.lua --edit-wait 30 --pattern-wait 120
```

- [ ] **Step 3: Implement minimal hardening**

Do only the bounded follow-on needed by the spec:
- preserve stable chunk identity
- keep memory/priority telemetry authoritative
- avoid changing world truth or fixture semantics

- [ ] **Step 4: Re-run tests**

Run the same targeted spec commands again and expect them to pass.

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/ChunkPriority.lua \
  roblox/src/ServerScriptService/ImportService/MemoryGuardrail.lua \
  roblox/src/ServerScriptService/ImportService/StreamingService.lua \
  docs/exporter-fixtures.md \
  roblox/src/ServerScriptService/Tests/MemoryGuardrail.spec.lua \
  roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua
git commit -m "fix: harden bounded streaming identity and telemetry"
```

### Final Verification

- [ ] Run targeted Python harness suite:

```bash
python3 -m unittest \
  scripts.tests.test_preview_play_parity_contract \
  scripts.tests.test_refresh_runtime_harness_from_sample_data \
  scripts.tests.test_generated_austin_assets \
  scripts.tests.test_austin_runtime_contract \
  scripts.tests.test_run_studio_harness \
  scripts.tests.test_play_render_truth \
  scripts.tests.test_minimap_runtime_contract -v
```

- [ ] Run targeted Luau formatting and diff checks:

```bash
stylua roblox/src/ServerScriptService/ImportService/AustinSpawn.lua \
  roblox/src/ServerScriptService/ImportService/RunAustin.lua \
  roblox/src/ServerScriptService/BootstrapAustin.server.lua \
  roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua \
  roblox/src/ServerScriptService/ImportService/StreamingService.lua \
  roblox/src/StarterPlayer/StarterPlayerScripts/MinimapController.client.lua \
  roblox/src/StarterPlayer/StarterPlayerScripts/WorldProbe.client.lua
git diff --check
```

- [ ] Run Rust verification because parity and manifest selection depend on the compiler/runtime boundary:

```bash
cd rust && cargo test --workspace
```

- [ ] Run one clean edit preview harness pass and one clean play harness pass under the 4 GB guardrail.

- [ ] Only after those pass, request final review and integration.
