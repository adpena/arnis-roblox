# Hybrid Imagery Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the current Google-Maps-like hybrid pipeline so explicit semantic data survives export/import, edit and play mode share the same runtime truth, and VertigoSync integration is isolated from core world-generation behavior.

**Architecture:** Keep high geometric fidelity, but enforce a strict authority order: explicit manifest data first, semantic fallbacks second, visual enrichment last. Tighten exporter tests, importer tests, and harness tests around that contract before expanding detail. Treat VertigoSync as an adjacent integration boundary instead of a core in-repo dependency.

**Tech Stack:** Rust exporter crates, Roblox Luau importer/builders, bash/Python Studio harness scripts, VertigoSync-adjacent plugin workflow

---

### Task 1: Lock Exporter Authority Rules

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/chunker.rs`
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs`
- Test: `rust/crates/arbx_roblox_export/src/lib.rs`

- [ ] **Step 1: Write failing exporter tests for authority order**

Add regressions for:
- no synthetic whole-footprint rooms
- no forced facade styles
- usage-driven shell defaults
- explicit tags/colors surviving exporter defaults

- [ ] **Step 2: Run exporter tests to verify they fail**

Run: `cargo test -q -p arbx_roblox_export`
Expected: failing assertions for synthetic rooms and forced style/default flattening

- [ ] **Step 3: Implement minimal exporter fixes**

In `chunker.rs`:
- keep `rooms` empty unless real room topology exists
- never synthesize `facade_style`
- use explicit tags first, usage second, default last
- keep roof enrichment fallback-only

- [ ] **Step 4: Run exporter tests to verify they pass**

Run: `cargo test -q -p arbx_roblox_export`
Expected: PASS

- [ ] **Step 5: Format Rust changes**

Run: `cargo fmt --package arbx_roblox_export`
Expected: no diff noise beyond intended formatting

### Task 2: Preserve Explicit Terrain Semantics

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua`
- Modify: `roblox/src/ServerScriptService/Builders/LanduseBuilder.lua`
- Test: `roblox/src/ServerScriptService/Tests/TerrainExplicitMaterialPreservation.spec.lua`

- [ ] **Step 1: Write failing Luau regression for explicit terrain material preservation**

Test that explicit per-cell `Grass` survives prep even on steep cells.

- [ ] **Step 2: Verify the failure in code review / harness context**

Check the builder logic and confirm slope override currently applies even when `terrain.materials[idx]` exists.

- [ ] **Step 3: Implement minimal terrain fix**

In `TerrainBuilder.lua`:
- preserve explicit per-cell materials
- only apply slope-derived fallback when the cell is still using inferred/default terrain semantics

- [ ] **Step 4: Format Luau files**

Run: `stylua roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua roblox/src/ServerScriptService/Tests/TerrainExplicitMaterialPreservation.spec.lua`
Expected: PASS

- [ ] **Step 5: Diff sanity check**

Run: `git diff --check -- roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua roblox/src/ServerScriptService/Tests/TerrainExplicitMaterialPreservation.spec.lua`
Expected: no whitespace errors

### Task 3: Harden Play/Edit Evidence Collection

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/run_austin_stress.py`
- Test: `scripts/tests/test_austin_stress.py`

- [ ] **Step 1: Write failing script tests for runtime evidence detection**

Add tests proving:
- startup-only logs do not count as play evidence
- only logs containing real runtime markers count toward runtime evaluation

- [ ] **Step 2: Run Python tests to verify failure**

Run: `python3 -m unittest scripts.tests.test_austin_stress -v`
Expected: FAIL on missing runtime evidence classification

- [ ] **Step 3: Implement minimal harness/script fix**

In `run_studio_harness.sh` and/or `run_austin_stress.py`:
- gate runtime diagnosis on real play markers
- avoid treating generic startup warnings as play failures
- keep edit and play probes separated in output

- [ ] **Step 4: Run Python tests to verify pass**

Run: `python3 -m unittest scripts.tests.test_austin_stress -v`
Expected: PASS

- [ ] **Step 5: Shell syntax check**

Run: `bash -n scripts/run_studio_harness.sh`
Expected: PASS

### Task 4: Harden Built-Place Studio Harnessing

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/run_austin_stress.py`
- Test: `scripts/tests/test_austin_stress.py`

- [ ] **Step 1: Add coverage for built-place/runtime truth**

Add regressions for:
- attached sessions only count as play if real runtime markers exist
- startup-only logs do not count as runtime failures
- harness output keeps edit and play evidence separated

- [ ] **Step 2: Run Python tests to verify the harness contract**

Run: `python3 -m unittest scripts.tests.test_austin_stress -v`
Expected: PASS with explicit runtime-marker assertions

- [ ] **Step 3: Implement minimal harness hardening**

In `run_studio_harness.sh`:
- prefer an auto-built clean place over a blank Studio template
- enable `RunAllEntry.server.lua` before building the clean place
- sandbox Roblox plugins for the run so foreign Vertigo edit plugins cannot pollute Arnis evidence
- keep play detection gated on real runtime markers

- [ ] **Step 4: Run shell verification**

Run: `bash -n scripts/run_studio_harness.sh`
Expected: PASS

- [ ] **Step 5: Run a fresh Studio harness pass**

Run: `bash scripts/run_studio_harness.sh --takeover --hard-restart --edit-wait 20 --play-wait 25 --pattern-wait 120`
Expected:
- the harness opens the clean built place
- edit mode reaches `RunAll` or `AustinPreviewBuilder`
- play mode reaches `BootstrapAustin` / `RunAustin`
- no foreign Vertigo edit plugins pollute the log
### Task 5: Document VertigoSync Boundary

**Files:**
- Create or modify: `docs/vertigo-sync-boundary.md`
- Modify: `README.md`

- [ ] **Step 1: Write a short boundary document**

Document that:
- VertigoSync should live in an adjacent repo
- this repo consumes it as an optional integration
- world import/export correctness must not depend on plugin-only behavior

- [ ] **Step 2: Update README integration notes**

Add a concise section pointing to the boundary doc and clarifying optionality.

- [ ] **Step 3: Diff sanity check**

Run: `git diff --check -- docs/vertigo-sync-boundary.md README.md`
Expected: PASS
### Task 6: End-to-End Verification

**Files:**
- Verify existing touched files only

- [ ] **Step 1: Run Rust exporter tests**

Run: `cargo test -q -p arbx_roblox_export`
Expected: PASS

- [ ] **Step 2: Run Python harness tests**

Run: `python3 -m unittest scripts.tests.test_austin_stress -v`
Expected: PASS

- [ ] **Step 3: Run combined diff checks**

Run: `git diff --check -- rust/crates/arbx_roblox_export/src/chunker.rs rust/crates/arbx_roblox_export/src/lib.rs roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua scripts/run_austin_stress.py scripts/tests/test_austin_stress.py scripts/run_studio_harness.sh`
Expected: PASS

- [ ] **Step 4: Run a fresh Studio harness pass**

Run: `bash scripts/run_studio_harness.sh --takeover --hard-restart --edit-wait 20 --play-wait 25 --pattern-wait 120`
Expected:
- edit preview imports cleanly
- play mode reaches `BootstrapAustin` / `RunAustin`
- generated world exists in play mode
- no startup-only log is misreported as runtime failure
