# Fidelity, Streaming, and Preview Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize Studio preview/import behavior while improving building/material fidelity and expanding source-to-scene diagnostics for roofs, vegetation, roads, sidewalks, water, and streaming hot spots.

**Architecture:** Keep offline compile authority in Rust and additive diagnostics/scheduling metadata in manifests/indexes, while Roblox preview/runtime stays responsible for deterministic chunk/subplan loading, stable invalidation handling, and scene-side truth capture. Fix preview bounce first so audits observe stable geometry, then tighten the existing audit signal and finally improve material/roof fidelity plus streaming policy against that verified signal.

**Tech Stack:** Luau importer/preview/runtime modules, Python audit/harness scripts, Rust pipeline/export crates, Studio test harness.

---

### Task 1: Eliminate destructive preview bounce and rebuild flashes

**Files:**
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ManifestLoader.lua`
- Modify: `roblox/src/ServerScriptService/Tests/AustinPreviewTimeTravel.spec.lua`
- Modify: `scripts/tests/test_austin_stress.py`
- Modify: `scripts/run_austin_stress.py`

- [ ] Trace the current preview invalidation/build-token path and write a failing spec or stress assertion for the “state-only sync churn causes full visible rebuild” case.
- [ ] Keep active preview builds coherent when `PREVIEW_INVALIDATION_EPOCH_ATTR` or hard-pause time-travel state changes mid-import.
- [ ] Tighten dirty-chunk detection so source-only/module-only churn does not trigger destructive chunk reimports when semantic chunk content is unchanged.
- [ ] Add harness/stress assertions for “no flash/full rebuild on state-only invalidation”.
- [ ] Verify with focused Luau specs and one stress/harness run.

### Task 2: Make roof/material/tree/road/water diagnostics trustworthy and more granular

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/SceneAudit.lua`
- Modify: `scripts/scene_fidelity_audit.py`
- Modify: `scripts/manifest_quality_audit.py`
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/tests/test_scene_fidelity_audit.py`
- Modify: `scripts/tests/test_manifest_quality_audit.py`
- Modify: `scripts/tests/test_run_studio_harness.py`

- [ ] Add failing tests for edge cases where current roof coverage, scene-bucket reassembly, or tree connectivity metrics can overstate fidelity.
- [ ] Tighten the existing scene-side telemetry so closure decks, direct roofs, merged roofs, road surface buckets, water buckets, and vegetation connectivity are reported without stale-bucket leakage.
- [ ] Extend manifest-side auditing with stronger OSM/Overture material and roof mismatch reporting for suspicious landmark/civic cases.
- [ ] Update the harness parser/export path only where existing bucket streams need correction.
- [ ] Verify the Python audit suites and confirm the new metrics catch known Austin cases.

### Task 3: Improve building material and roof fidelity without reintroducing stylized regressions

**Files:**
- Modify: `rust/crates/arbx_pipeline/src/lib.rs`
- Modify: `rust/crates/arbx_pipeline/src/overture.rs`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/SceneAudit.lua`
- Modify: `roblox/src/ServerScriptService/Tests/GlassWallOpaqueRoof.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/OpaqueCivicFacadeTruth.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/FlatShellMeshRoofTruth.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/RoofTruth.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/SceneAudit.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/BuildingMaterialTruth.spec.lua`

- [ ] Write failing tests around high-identity civic/stone/copper buildings and glass-walled buildings that still need opaque roofs and non-fabricated facade styling.
- [ ] Preserve compile-time material truth from both OSM and Overture when explicit facade/roof metadata already exists.
- [ ] Tighten importer-side material/roof defaults so offices can still be glazed while civic/landmark shells remain opaque and roof materials stay believable.
- [ ] Keep roof geometry explicit wherever scene truth depends on it, and prevent closure-deck fallbacks from being misreported as direct shaped roofs.
- [ ] Verify with focused Rust tests plus the Luau roof/material truth specs.

### Task 4: Harden chunk/subplan scheduling for hotspot-heavy world streaming

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ChunkPriority.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ManifestLoader.lua`
- Modify: `rust/crates/arbx_roblox_export/src/subplans.rs`
- Modify: `rust/crates/arbx_roblox_export/tests/subplans.rs`
- Modify: `roblox/src/ServerScriptService/Tests/ChunkSubplanPriority.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/SubplanImportEquivalence.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/StreamingPriorityHotspot.spec.lua`

- [ ] Add failing tests for deterministic hotspot ordering/splitting and for preserving scene equivalence between staged and full chunk import.
- [ ] Improve chunk/subplan prioritization so observed hotspot cost, authored `streamingCost`, and coarse layer ordering all participate in stable scheduling.
- [ ] Prefer additive hotspot splitting/ordering policy instead of coarse threshold-only behavior, keeping canonical manifest truth unchanged.
- [ ] Keep scheduler state reusable across runs without introducing nondeterministic import order for the same authored input.
- [ ] Verify with Rust subplan tests and focused Luau scheduling specs.

### Task 5: End-to-end validation and artifact export discipline

**Files:**
- Modify: `scripts/build_austin_max_fidelity_place.sh`
- Modify: `scripts/test_austin_max_fidelity_e2e.sh`
- Modify: `scripts/bootstrap_arnis_studio.py`
- Modify: `scripts/bootstrap_vsync_place.py`
- Modify: `scripts/tests/test_bootstrap_arnis_studio.py`
- Modify: `scripts/tests/test_bootstrap_vsync_place.py`

- [ ] Run the full Rust workspace tests and relevant Python/Luau/harness suites after the fixes land.
- [ ] Keep the max-fidelity Austin export/build path deterministic and reusable for cross-project testing.
- [ ] Update docs only where the implementation contract actually changes.
- [ ] Record residual risks separately from completed fixes so future fidelity work starts from measured gaps instead of screenshots alone.
