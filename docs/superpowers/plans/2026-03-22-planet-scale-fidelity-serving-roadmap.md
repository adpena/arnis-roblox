# Planet-Scale Fidelity And Serving Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve ArnisRoblox from a high-fidelity regional exporter into a trustworthy planet-scale pipeline with deterministic chunk/subplan serving for local development and future hosted production, without regressing visible fidelity.

**Architecture:** Keep Roblox as a consumer of compiled chunk/subplan artifacts only. Move global data ownership, heavy preprocessing, and cache management into offline Rust/server-side systems, while making manifest-vs-scene audit the truth gate for fidelity work. Satellite projection remains deferred; satellite classification, DEM elevation, vector semantics, and exact-ID audit become the stable base layer.

**Tech Stack:** Rust (`arbx_cli`, `arbx_pipeline`, `arbx_roblox_export`), Luau import/runtime services, Vertigo Sync plugin/server, Overpass/OSM, Overture, Terrarium DEM, ESRI satellite classification, Roblox Studio harness.

---

## File Structure

**Roadmap / design docs**
- Create: `docs/superpowers/plans/2026-03-22-planet-scale-fidelity-serving-roadmap.md`
- Later spec follow-up: `docs/superpowers/specs/2026-03-22-planet-scale-serving-design.md`

**Primary code surfaces this roadmap depends on**
- Rust data ingest / compile:
  - `rust/crates/arbx_cli/src/main.rs`
  - `rust/crates/arbx_pipeline/src/lib.rs`
  - `rust/crates/arbx_pipeline/src/overture.rs`
  - `rust/crates/arbx_geo/src/lib.rs`
  - `rust/crates/arbx_geo/src/satellite.rs`
  - `rust/crates/arbx_roblox_export/src/subplans.rs`
- Asset/export scripts:
  - `scripts/export_austin_from_osm.sh`
  - `scripts/export_austin_to_lua.sh`
  - `scripts/build_austin_max_fidelity_place.sh`
  - `scripts/test_austin_max_fidelity_e2e.sh`
- Roblox runtime/import:
  - `roblox/src/ServerScriptService/ImportService/init.lua`
  - `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
  - `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
  - `roblox/src/ServerScriptService/ImportService/Builders/*.lua`
- Audit / verification:
  - `scripts/manifest_quality_audit.py`
  - `scripts/scene_fidelity_audit.py`
  - `roblox/src/ServerScriptService/ImportService/SceneAudit.lua`
- Preview/live sync control:
  - `scripts/run_studio_harness.sh`
  - `../vertigo-sync/src/lib.rs`
  - `../vertigo-sync/assets/plugin_src/00_main.lua`

## Current Truth Snapshot

- [ ] **Step 1: Treat current source coverage as explicit, not assumed**

Verify and document:
- OSM / Overpass are in active Austin export path via `scripts/export_austin_from_osm.sh`
- Overture building gap-fill is active via `scripts/fetch_overture_buildings.py` + `arbx_pipeline`
- Terrarium DEM is active in Rust elevation sampling
- Satellite classification exists and is only active when compile uses `--satellite`, `--profile high`, or `--yolo`
- Direct imagery projection is not currently implemented
- `aerialway` / gondola / ski-lift support is currently absent or negligible

Run:
```bash
cargo run --manifest-path rust/Cargo.toml -p arbx_cli -- explain
rg -n -- 'aerialway|gondola|chair_lift|ski|piste|cable_car' rust roblox docs scripts
```

Expected:
- explain output lists Overpass/OSM, Overture, Terrarium, and optional satellite classification
- search output shows no meaningful current aerialway implementation

## Milestone 1: Make Audit The Release Gate

### Task 1: Source Activation Audit

**Files:**
- Modify: `scripts/manifest_quality_audit.py`
- Modify: `scripts/tests/test_manifest_quality_audit.py`
- Reference: `rust/crates/arbx_cli/src/main.rs`
- Reference: `rust/crates/arbx_geo/src/satellite.rs`

- [ ] **Step 1: Add failing tests for source activation reporting**

Add tests asserting the audit can surface:
- whether satellite classification was enabled for the export
- whether Overture gap-fill was present
- whether DEM elevation authority is present

- [ ] **Step 2: Extend manifest metadata or audit heuristics minimally**

Preferred:
- add explicit metadata flags at export time for `satellite_enabled`, `dem_provider`, `overture_gapfill_enabled`

Fallback:
- derive conservatively from manifest shape, but only if unambiguous

- [ ] **Step 3: Render activation summary in HTML/JSON audit outputs**

Expected output:
- `source_activation`
- `fidelity_mode`
- warning if “max-fidelity” workflow is requested but satellite is off

- [ ] **Step 4: Verify**

Run:
```bash
python3 -m unittest scripts.tests.test_manifest_quality_audit -v
python3 -m py_compile scripts/manifest_quality_audit.py scripts/tests/test_manifest_quality_audit.py
```

### Task 2: Scene Gate Expansion

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/SceneAudit.lua`
- Modify: `scripts/scene_fidelity_audit.py`
- Modify: `roblox/src/ServerScriptService/Tests/SceneAudit.spec.lua`
- Modify: `scripts/tests/test_scene_fidelity_audit.py`

- [ ] **Step 1: Extend scene audit for remaining blind spots**

Add or strengthen first-class diagnostics for:
- terrain material coverage vs manifest terrain cells
- water subtype fidelity (fountain/lake/stream/river)
- building material/usage class mismatch buckets
- procedural vegetation class coverage by biome-like landuse category

- [ ] **Step 2: Keep exact-ID truth when possible**

If a feature has source IDs, compare unique source IDs, not raw part counts.

- [ ] **Step 3: Verify**

Run:
```bash
python3 -m unittest scripts.tests.test_scene_fidelity_audit -v
```

## Milestone 2: Finish Deterministic Streaming Contract

### Task 3: Landuse Subplan Execution Refinement

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/subplans.rs`
- Modify: `roblox/src/ServerScriptService/ImportService/init.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/LanduseBuilder.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`

- [ ] **Step 1: Use recursive landuse subplans as the runtime scheduling unit**

The exporter now emits bounded recursive landuse leaves. Ensure runtime scheduling exploits them before a giant polygon can dominate a single foreground slice.

- [ ] **Step 2: Add tests for deterministic landuse subplan execution order and clipping**

Write failing tests first for:
- subplan execution equivalence
- large-polygon clipping across recursive leaves
- no duplicate terrain fill side effects

- [ ] **Step 3: Verify against real Austin preview logs**

Use hard-restart harness and confirm the old giant `landuseTerrainFillMs` hotspots stay eliminated.

### Task 4: Props Hotspot Breakdown And Reduction

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/init.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/PropBuilder.lua`
- Modify: `roblox/src/ServerScriptService/Tests/ImportService.spec.lua`

- [ ] **Step 1: Keep the new per-kind prop timing in place and identify real offenders**

Use live Austin logs to determine whether tree, crossing, flagpole, prefab acquisition, or first-use pool cost dominates.

- [ ] **Step 2: Optimize only after measured proof**

Examples:
- lazily warm expensive prefab pools offline or during idle time
- collapse overly chatty tiny prop assemblies if they are visually equivalent
- preserve authored feature truth and exact-ID audit

- [ ] **Step 3: Verify with hard-restart preview logs**

## Milestone 3: Planet-Scale Data Service

### Task 5: Define Global Corpus Strategy

**Files:**
- Later spec/design doc
- Reference:
  - `rust/crates/arbx_pipeline/src/lib.rs`
  - `rust/crates/arbx_geo/src/lib.rs`
  - `rust/crates/arbx_geo/src/satellite.rs`

- [ ] **Step 1: Formalize storage tiers**

Define:
- global vector corpus: OSM + Overture
- global DEM tile corpus
- rolling regional satellite cache
- compiled chunk/subplan artifact store

- [ ] **Step 2: Separate raw sources from derived products**

Do not require full-world raw z19 imagery retention.
Prefer:
- classified products
- prewarmed regional caches
- rehydratable source fetch rules

- [ ] **Step 3: Define versioning contract**

Key by:
- source snapshot version
- compiler version
- schema version
- chunk partition version

### Task 6: Define Serving API

**Files:**
- Later spec/design doc

- [ ] **Step 1: Specify local/prod shared API shape**

API should support:
- resolve region by bbox / lat-lon / tile id
- fetch manifest index for region
- fetch chunk payloads
- fetch chunk subplans
- fetch audit summaries

- [ ] **Step 2: Keep Roblox runtime blind to raw sources**

Roblox receives only compiled chunk/subplan artifacts, never direct Overpass, DEM, or imagery calls.

## Milestone 4: Planet-Scale Domain Fidelity

### Task 7: Mountain / Alpine / Resort Domain Coverage

**Files:**
- Modify later:
  - `rust/crates/arbx_pipeline/src/lib.rs`
  - `roblox/src/ServerScriptService/ImportService/Builders/*`
  - `scripts/manifest_quality_audit.py`
  - `scripts/scene_fidelity_audit.py`

- [ ] **Step 1: Add domain matrix for unrepresented environment classes**

Explicitly track unsupported or weakly represented domains:
- snow / alpine terrain
- cliffs / rocky mountains
- ski pistes
- aerialway / gondola / ski lift / cable car
- mountain watercourses / waterfalls

- [ ] **Step 2: Add source extraction audit for those classes**

First prove whether the data exists in source and whether the pipeline drops it.

- [ ] **Step 3: Add implementation in dependency order**

Order:
1. source extraction / manifest schema
2. audit visibility
3. builder/runtime representation
4. performance/streaming integration

## Milestone 5: Max-Fidelity Workflow Validation

### Task 8: Make Highest-Fidelity Austin Export A Stable Regression Target

**Files:**
- Modify: `scripts/build_austin_max_fidelity_place.sh`
- Modify: `scripts/test_austin_max_fidelity_e2e.sh`
- Modify: `README.md`
- Possibly add: `scripts/tests/test_max_fidelity_workflow.py`

- [ ] **Step 1: Let max-fidelity export finish and persist**

The first run will be slow because it fills the z19 satellite cache.

- [ ] **Step 2: Run full Studio import against the exported place**

Run:
```bash
bash scripts/test_austin_max_fidelity_e2e.sh
```

- [ ] **Step 3: Record outputs**

Capture:
- output place path in `exports/`
- harness log path
- final scene audit artifact
- manifest audit artifact

- [ ] **Step 4: Add a smoke test or documented acceptance checklist**

Success criteria:
- export completes
- place builds cleanly
- Studio harness passes
- no preview full-rebuild regression
- audit doesn’t claim impossible green states

## Deferred On Purpose

- [ ] **Step 1: Keep direct imagery projection deferred**

Do not implement direct imagery projection until:
- source activation audit is trustworthy
- streaming/serving contract is stable
- regional cache policy is defined

It is a valid later milestone, but not the foundation.

## Final Verification Checklist

- [ ] **Step 1: Verify plan-linked scripts and docs are clean**

Run:
```bash
bash -n scripts/export_austin_from_osm.sh scripts/export_austin_to_lua.sh scripts/build_austin_max_fidelity_place.sh scripts/test_austin_max_fidelity_e2e.sh
python3 -m unittest scripts.tests.test_bootstrap_arnis_studio -v
git diff --check
```

- [ ] **Step 2: Keep one living proof artifact**

For every milestone, preserve:
- one manifest artifact
- one scene artifact
- one Studio log

Without those three, the milestone is not trustworthy enough to scale.
