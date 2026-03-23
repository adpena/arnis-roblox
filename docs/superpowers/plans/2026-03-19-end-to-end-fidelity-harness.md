# End-to-End Fidelity Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic Austin-first end-to-end fidelity harness that compares authoritative source truth against the imported Studio scene in edit mode and play mode.

**Architecture:** Add an additive Rust-side truth-pack export, a Roblox observed-pack capture path with explicit source attribution and pinned capture state, and a Python comparator with typed reports. Wire the harness into Austin runs in report-only mode first, then promote stable structural metrics to hard regression gates.

**Tech Stack:** Rust (`arbx_pipeline`, `arbx_cli`), Luau importer/runtime capture modules, Python 3 with `pydantic`, existing Studio harness scripts.

---

### Task 1: Lock the observability contract in Roblox

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ChunkLoader.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Create: `roblox/src/ServerScriptService/Tests/FidelityAttribution.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/FidelityAttribution.spec.lua`

- [ ] **Step 1: Write the failing Roblox attribution spec**

Add a spec that imports a small building set and asserts:
- each imported building model has `ArnisSourceId`
- each imported building model has `ArnisChunkId`
- each imported building model has `ArnisImportRunId`
- existing height attributes remain present

- [ ] **Step 2: Run the spec to verify it fails**

Run: Studio test harness focused on the new spec
Expected: FAIL because the new attributes do not exist yet

- [ ] **Step 3: Add explicit source/chunk/run attribution**

In `BuildingBuilder.lua`, when creating each building model:
- set `ArnisSourceId` from `building.id`
- set `ArnisChunkId` from importer context or chunk parent name
- set `ArnisImportRunId` from the current import session

In importer/runtime entrypoints:
- ensure a deterministic run id is created for each import
- propagate it down to builders

- [ ] **Step 4: Make attribution fail closed**

If required attribution inputs are absent:
- fail loudly in capture-facing code paths
- do not silently fall back to `Name`-only matching

- [ ] **Step 5: Re-run the attribution spec**

Run: Studio test harness focused on `FidelityAttribution.spec.lua`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua roblox/src/ServerScriptService/ImportService/ChunkLoader.lua roblox/src/ServerScriptService/ImportService/RunAustin.lua roblox/src/ServerScriptService/Tests/FidelityAttribution.spec.lua
git commit -m "feat: add fidelity attribution contract"
```

### Task 2: Add pinned capture-state support for deterministic observed packs

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/ChunkLoader.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Modify: `scripts/run_studio_harness.sh`
- Create: `roblox/src/ServerScriptService/Tests/FidelityCaptureState.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/FidelityCaptureState.spec.lua`

- [ ] **Step 1: Write the failing capture-state spec**

Add a spec that asserts the fidelity capture path:
- forces highest-detail LOD for the target region
- waits for import completion before capture
- records invalid capture if required scene state is not reached

- [ ] **Step 2: Run the spec to verify it fails**

Run: Studio test harness focused on `FidelityCaptureState.spec.lua`
Expected: FAIL because capture-state orchestration does not exist yet

- [ ] **Step 3: Implement a capture-state helper**

Add helper logic that:
- pins detail groups visible
- confirms target chunks are materialized
- confirms import-complete markers are present
- returns structured invalid-state reasons instead of noisy partial samples

- [ ] **Step 4: Expose capture-state control to the harness**

Update `run_studio_harness.sh` so Austin fidelity runs can:
- trigger capture only after completion markers
- reject stale attached sessions
- record invalid-capture outcomes distinctly from importer failures

- [ ] **Step 5: Re-run the capture-state spec**

Run: Studio test harness focused on `FidelityCaptureState.spec.lua`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/ChunkLoader.lua roblox/src/ServerScriptService/ImportService/RunAustin.lua scripts/run_studio_harness.sh roblox/src/ServerScriptService/Tests/FidelityCaptureState.spec.lua
git commit -m "feat: pin fidelity capture state"
```

### Task 3: Add Rust truth-pack export for Austin

**Files:**
- Modify: `rust/crates/arbx_pipeline/src/lib.rs`
- Modify: `rust/crates/arbx_cli/src/main.rs`
- Create: `rust/crates/arbx_pipeline/src/fidelity_truth.rs`
- Create: `rust/crates/arbx_pipeline/tests/fidelity_truth.rs`
- Test: `rust/crates/arbx_pipeline/tests/fidelity_truth.rs`
- Docs: `docs/superpowers/specs/2026-03-19-end-to-end-fidelity-harness-design.md`

- [ ] **Step 1: Write the failing Rust truth-pack tests**

Add tests that assert truth-pack export includes:
- stable meta
- building outer rings
- building source metadata
- water holes
- terrain semantic sample grid

Do not require building holes yet unless they already exist upstream.

- [ ] **Step 2: Run the truth-pack tests to verify they fail**

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_pipeline fidelity_truth -- --nocapture
```

Expected: FAIL because truth-pack export does not exist yet

- [ ] **Step 3: Implement additive truth-pack types**

Create `fidelity_truth.rs` with serializable models for:
- meta
- buildings
- roads
- water
- terrain sample grid

Keep these separate from the main manifest contract.

- [ ] **Step 4: Add CLI export support**

Extend `arbx_cli` with a command or flag that emits:
- `truth-pack.json` for a bounded Austin region

Keep the command deterministic and script-friendly.

- [ ] **Step 5: Re-run the Rust truth-pack tests**

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_pipeline fidelity_truth -- --nocapture
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/crates/arbx_pipeline/src/lib.rs rust/crates/arbx_pipeline/src/fidelity_truth.rs rust/crates/arbx_pipeline/tests/fidelity_truth.rs rust/crates/arbx_cli/src/main.rs docs/superpowers/specs/2026-03-19-end-to-end-fidelity-harness-design.md
git commit -m "feat: export additive fidelity truth pack"
```

### Task 4: Add Studio observed-pack capture

**Files:**
- Create: `roblox/src/ServerScriptService/ImportService/FidelityCapture.lua`
- Create: `roblox/src/ServerScriptService/Tests/FidelityCapture.spec.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ManifestLoader.lua`
- Test: `roblox/src/ServerScriptService/Tests/FidelityCapture.spec.lua`

- [ ] **Step 1: Write the failing observed-pack capture spec**

Add a spec that:
- imports a known mini-scene
- runs capture after import completion
- asserts observed-pack output includes attributed buildings, terrain samples, runtime metadata, and mode

- [ ] **Step 2: Run the spec to verify it fails**

Run: Studio test harness focused on `FidelityCapture.spec.lua`
Expected: FAIL because `FidelityCapture.lua` does not exist yet

- [ ] **Step 3: Implement the capture module**

Create `FidelityCapture.lua` with functions to:
- enumerate building models using `ArnisSourceId`
- record shell/roof approximations
- sample terrain materials at canonical coordinates
- capture runtime metadata for edit/play modes

Return plain tables suitable for JSON encoding.

- [ ] **Step 4: Add capture hooks to Austin runtime paths**

Expose a way for harness runs to request:
- observed-pack capture after edit import
- observed-pack capture after play import

- [ ] **Step 5: Re-run the capture spec**

Run: Studio test harness focused on `FidelityCapture.spec.lua`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/FidelityCapture.lua roblox/src/ServerScriptService/ImportService/RunAustin.lua roblox/src/ServerScriptService/ImportService/ManifestLoader.lua roblox/src/ServerScriptService/Tests/FidelityCapture.spec.lua
git commit -m "feat: add observed scene fidelity capture"
```

### Task 5: Build the Python comparator with Pydantic

**Files:**
- Create: `scripts/fidelity_models.py`
- Create: `scripts/compare_fidelity.py`
- Create: `scripts/tests/test_compare_fidelity.py`
- Create: `scripts/tests/fixtures/fidelity/`
- Test: `scripts/tests/test_compare_fidelity.py`

- [ ] **Step 1: Write the failing Python comparator tests**

Add tests for:
- truth-pack validation
- observed-pack validation
- `building_outer_iou`
- `wall_coverage_ratio`
- `roof_spill_ratio`
- `terrain_material_agreement`
- invalid observed-pack rejection when attribution is missing

- [ ] **Step 2: Run the comparator tests to verify they fail**

Run:

```bash
python3 -m unittest scripts.tests.test_compare_fidelity -v
```

Expected: FAIL because comparator modules do not exist yet

- [ ] **Step 3: Implement typed models with Pydantic**

In `fidelity_models.py`:
- define models for truth pack, observed pack, report, and threshold config

In `compare_fidelity.py`:
- load and validate JSON
- compute deterministic metrics
- emit JSON and markdown summaries

- [ ] **Step 4: Keep building-hole metrics gated**

Implement hole/courtyard handling as:
- report-only when holes are unavailable in buildings
- hard metrics only once end-to-end support exists

- [ ] **Step 5: Re-run the comparator tests**

Run:

```bash
python3 -m unittest scripts.tests.test_compare_fidelity -v
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/fidelity_models.py scripts/compare_fidelity.py scripts/tests/test_compare_fidelity.py scripts/tests/fixtures/fidelity
git commit -m "feat: add deterministic fidelity comparator"
```

### Task 6: Wire Austin edit/play harness runs to emit fidelity reports

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/run_all_checks.py`
- Create: `scripts/run_austin_fidelity.sh`
- Create: `scripts/tests/test_austin_fidelity.py`
- Docs: `docs/exporter-fixtures.md`
- Test: `scripts/tests/test_austin_fidelity.py`

- [ ] **Step 1: Write the failing harness orchestration tests**

Add tests that assert the Austin fidelity runner:
- creates truth-pack and observed-pack outputs
- invokes the comparator
- distinguishes invalid capture from importer failure
- stays report-only in the first phase

- [ ] **Step 2: Run the harness tests to verify they fail**

Run:

```bash
python3 -m unittest scripts.tests.test_austin_fidelity -v
```

Expected: FAIL because the new runner does not exist yet

- [ ] **Step 3: Implement the Austin fidelity runner**

Create `run_austin_fidelity.sh` that:
- regenerates Austin artifacts when requested
- exports a truth pack
- runs Studio in edit mode and play mode
- captures observed packs
- runs the comparator
- writes outputs to a stable report directory

- [ ] **Step 4: Integrate with checks**

Update `run_all_checks.py` to support:
- optional Austin fidelity report mode
- non-blocking report-only execution at first

- [ ] **Step 5: Re-run the harness tests**

Run:

```bash
python3 -m unittest scripts.tests.test_austin_fidelity -v
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add scripts/run_studio_harness.sh scripts/run_all_checks.py scripts/run_austin_fidelity.sh scripts/tests/test_austin_fidelity.py docs/exporter-fixtures.md
git commit -m "feat: wire Austin end-to-end fidelity harness"
```

### Task 7: Promote stable metrics and document thresholds

**Files:**
- Create: `scripts/fidelity_thresholds.json`
- Modify: `scripts/compare_fidelity.py`
- Modify: `docs/performance-budget.md`
- Modify: `docs/superpowers/specs/2026-03-19-end-to-end-fidelity-harness-design.md`
- Test: `scripts/tests/test_compare_fidelity.py`

- [ ] **Step 1: Write threshold policy tests**

Add tests for:
- hard-fail metrics
- warning-only metrics
- report-only metrics for unsupported building-hole comparisons

- [ ] **Step 2: Run the threshold tests to verify they fail**

Run:

```bash
python3 -m unittest scripts.tests.test_compare_fidelity -v
```

Expected: FAIL because threshold policy is not externalized yet

- [ ] **Step 3: Externalize and document thresholds**

Add `fidelity_thresholds.json` and wire the comparator to:
- read thresholds by metric
- mark unsupported metrics explicitly
- distinguish hard fail vs warn vs report-only

- [ ] **Step 4: Re-run comparator tests**

Run:

```bash
python3 -m unittest scripts.tests.test_compare_fidelity -v
```

Expected: PASS

- [ ] **Step 5: Run the Austin report once end-to-end**

Run:

```bash
bash scripts/run_austin_fidelity.sh
```

Expected:
- truth pack generated
- edit observed pack generated
- play observed pack generated
- fidelity report emitted without silent fallback

- [ ] **Step 6: Commit**

```bash
git add scripts/fidelity_thresholds.json scripts/compare_fidelity.py docs/performance-budget.md docs/superpowers/specs/2026-03-19-end-to-end-fidelity-harness-design.md
git commit -m "feat: add fidelity threshold policy"
```

### Final Verification

**Files:**
- Verify all files touched in Tasks 1-7

- [ ] **Step 1: Run targeted Rust tests**

```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_pipeline
```

- [ ] **Step 2: Run targeted Python tests**

```bash
python3 -m unittest scripts.tests.test_generated_austin_assets scripts.tests.test_preview_manifest_shards scripts.tests.test_compare_fidelity scripts.tests.test_austin_fidelity -v
```

- [ ] **Step 3: Run Roblox Studio harness tests**

Run the Studio harness with the new fidelity specs enabled.
Expected: all fidelity-related specs pass in edit mode, and report capture is valid.

- [ ] **Step 4: Run formatting and diff hygiene**

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
stylua roblox/src/ServerScriptService/ImportService roblox/src/ServerScriptService/Tests
git diff --check
```

- [ ] **Step 5: Record the first Austin baseline report**

Save the first stable report artifacts and note any report-only metrics that still require end-to-end building-hole support.

