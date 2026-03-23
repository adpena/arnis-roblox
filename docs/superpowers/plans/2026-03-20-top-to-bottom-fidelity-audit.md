# Top-To-Bottom Fidelity Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic top-to-bottom fidelity/profiling loop that identifies where source truth is lost between canonical geodata, manifest compilation, and Roblox scene generation.

**Architecture:** Add a second-stage scene auditor that captures runtime/edit-mode GeneratedWorld facts and compares them against manifest truth for a local focus zone. Use that instrumentation to drive targeted fixes in building, road, sidewalk, terrain, elevation, and scaling logic, while keeping VertigoSync and the harness fail-closed and production-safe.

**Tech Stack:** Python audit tooling, Rust pipeline metrics, Luau importer instrumentation/specs, Bash harness scripts, VertigoSync smoke validation

---

### Task 1: Capture Scene-vs-Manifest Truth

**Files:**
- Create: `scripts/scene_fidelity_audit.py`
- Create: `scripts/tests/test_scene_fidelity_audit.py`
- Modify: `scripts/run_studio_harness.sh`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`

- [ ] Write failing tests for scene-audit parsing and report structure.
- [ ] Add runtime/edit-mode instrumentation to emit machine-readable scene summaries for the loaded Austin focus zone.
- [ ] Implement the Python auditor to compare scene summaries against manifest truth and produce JSON/HTML artifacts.
- [ ] Wire the harness to collect those artifacts automatically.
- [ ] Verify with focused unit tests and one live harness run.

### Task 2: Profile Builder Loss Points

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua`
- Modify: `roblox/src/ServerScriptService/Tests/*.spec.lua`

- [ ] Add low-overhead counters/timers for dropped geometry, merged geometry, imprinted terrain, and fallback paths.
- [ ] Add or tighten specs around walls, sidewalks, roof truth, and terrain preservation.
- [ ] Use scene-audit results to fix the highest-signal fidelity regressions one subsystem at a time.

### Task 3: Tighten Pipeline Semantics

**Files:**
- Modify: `rust/crates/arbx_pipeline/src/*.rs`
- Modify: `rust/crates/arbx_roblox_export/src/*.rs`
- Modify: `scripts/manifest_quality_audit.py`

- [ ] Extend canonical source-vs-manifest comparison to richer topology/material/elevation semantics.
- [ ] Fix any compile-stage duplication, clipping, or simplification regressions uncovered by the scene audit.
- [ ] Regenerate Austin artifacts and re-run audits.

### Task 4: Production Hardening

**Files:**
- Modify: `scripts/run_all_checks.py`
- Modify: `scripts/run_studio_harness.sh`
- Modify: `../vertigo-sync/src/*.rs` as needed
- Modify: docs as needed

- [ ] Keep the harness fail-closed on foreign plugins and stale assets.
- [ ] Keep DX simple: one command path for validate/build/run with rich artifacts generated automatically.
- [ ] Document the audit/profiling workflow and thresholds.
