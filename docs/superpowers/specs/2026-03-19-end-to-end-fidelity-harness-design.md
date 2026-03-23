# End-to-End Fidelity Harness — Design Spec

**Date:** 2026-03-19
**Status:** Draft
**Primary goal:** Measure `OSM -> manifest -> Studio scene` fidelity with deterministic metrics before adding more procedural detail.

## Problem Statement

The current pipeline can regress in multiple places without a single trustworthy source-of-truth check:

1. OSM extraction can lose topology or tags before export.
2. Manifest export can normalize or drop semantic detail.
3. Roblox import/build logic can distort or omit geometry.
4. Edit mode and play mode can diverge even when the manifest is identical.
5. Visual inspection alone is too noisy to distinguish true regressions from subjective ugliness.

We need an end-to-end fidelity harness that measures what the system actually produced against authoritative source data, not just what the manifest says it intended to produce.

## Goals

- Catch structural regressions such as:
  - missing walls
  - roof spill and fragmentation
  - courtyard / hole collapse
  - footprint loss
  - terrain cover loss
  - edit/play divergence
- Keep the first pass deterministic and CI-friendly.
- Make Austin the baseline city for repeated regression checks.
- Preserve separation of concerns:
  - Rust owns source extraction, normalization, and truth-pack generation.
  - Roblox owns observed-scene capture and scene-side metrics.
  - VertigoSync remains an optional integration path, not the correctness oracle.

## Non-Goals

- No LLM is the source of truth for pass/fail decisions.
- No image-only “looks good” scoring in the first pass.
- No large schema rewrite of the main chunk manifest just to support the harness.
- No attempt to solve photogrammetry or texture realism in this step.

## Recommended Approach

Build a two-pack comparator:

1. **Truth Pack**
   Generated from authoritative OSM-derived pipeline data after normalization but before Roblox import.

2. **Observed Pack**
   Captured from `Workspace.GeneratedWorld` after Studio import in both edit mode and play mode.

3. **Comparator**
   Computes deterministic metrics and emits a typed JSON report with hard failures, warnings, and trendable summary scores.

This is the right first step because it measures the actual product while still keeping the metrics explainable and debuggable.

## Review Findings Applied

This spec was tightened after an architectural review. The main corrections are:

1. The harness must not rely on model names as identity. Observed scene capture needs explicit source-id and chunk-id attribution on imported instances.
2. Building-hole / courtyard metrics cannot be hard-gated in phase one until building holes exist end-to-end in source, export, and import paths.
3. Terrain agreement must use a canonical shared sample grid in world space. Otherwise edit/play and source/scene comparisons will be noisy and non-repeatable.
4. Observed capture must run under a pinned LOD / detail state. Otherwise the same scene can appear to regress simply because detail groups were hidden.

## Alternatives Considered

### 1. Manifest-only fidelity checks

Pros:
- easiest to implement
- highly deterministic

Cons:
- misses importer/build/runtime regressions
- does not catch edit/play divergence

Rejected because current problems are explicitly end-to-end.

### 2. Vision-first LLM judging

Pros:
- useful for aesthetic triage later
- can detect “looks wrong” classes that are hard to encode

Cons:
- non-deterministic
- hard to make CI-safe
- prone to false confidence

Rejected as the primary correctness layer. It can be added later as a secondary reviewer.

### 3. End-to-end deterministic harness with optional AI triage

Pros:
- catches the real failures
- still debuggable
- extensible later

Cons:
- more plumbing work

Recommended.

## Architecture

### A. Truth Pack

Produced from Rust-side source and normalized pipeline data for a bounded region such as Austin preview or a selected bbox.

Contents:

- `meta`
  - city / bbox / source ids / schema versions / generator revision
- `buildings`
  - id
  - outer rings
  - inner rings / holes
  - centroid
  - base height
  - shell height
  - usage
  - roof shape / roof material / roof color
  - source tag presence flags
- `roads`
  - id
  - centerline
  - width
  - surface
  - sidewalk metadata
- `water`
  - id
  - polygon
  - holes
  - surfaceY
- `terrain`
  - sampled semantic ground-cover grid
  - explicit-vs-inferred material ownership

Important rule:
- The truth pack is not the manifest.
- It is a testing artifact designed for fidelity comparison.
- It should be additive so we do not destabilize the main runtime contract.

### B. Observed Pack

Captured from Studio after import/build completes.

Capture sources:

- `Workspace.GeneratedWorld`
- chunk folders / building models / shell folders / roof parts / terrain regions
- runtime markers from the harness to distinguish edit and play runs

Required observability contract:

- imported building models must expose stable source identity
- imported chunk roots must expose stable chunk identity
- capture must not infer identity from `Name` alone

Minimum required attributes / metadata:

- `ArnisSourceId`
- `ArnisChunkId`
- `ArnisImportRunId`
- existing height metadata such as `ArnisImportBuildingBaseY` and `ArnisImportBuildingHeight`

If those attributes are absent, the harness should fail the run as unobservable instead of silently guessing.

Contents:

- `meta`
  - mode: `edit` or `play`
  - Studio log id / run id / manifest id
- `buildings`
  - imported model id
  - authoritative source id
  - chunk id
  - shell footprint approximation
  - roof footprint approximation
  - wall segment coverage
  - overall height
  - support classification for roof-only structures
- `terrain`
  - sampled material grid aligned to truth-pack sample points
- `water`
  - observed coverage
- `runtime`
  - chunk counts
  - import timing
  - errors / warnings

### C. Comparator

Implemented in Python first, with strict typed models.

Recommended library usage:

- `Pydantic`: yes
  - typed truth-pack schema
  - typed observed-pack schema
  - typed metric report schema
- `PydanticAI`: optional later
  - only for narrative summarization or anomaly triage
- `DSPy`: optional later
  - only if we decide to optimize prompt-driven visual triage workflows

The comparator should remain deterministic even if optional AI helpers are added later.

## Metrics

### Structural hard-fail metrics

- `building_outer_iou`
  - overlap between source footprint outer ring and observed shell footprint
- `wall_coverage_ratio`
  - expected perimeter coverage vs observed wall coverage
- `roof_spill_ratio`
  - observed roof area outside source outer ring
- `roof_fragmentation_score`
  - penalizes jagged strip-like roof breakup
- `height_error`
  - expected shell height vs observed shell height

Phase-two structural metrics after building holes exist end-to-end:

- `building_hole_preservation`
  - checks whether source courtyards / holes remain open

### Semantic fidelity metrics

- `usage_retention`
- `roof_shape_retention`
- `terrain_material_agreement`
- `explicit_material_preservation`
- `water_hole_preservation`

### Runtime consistency metrics

- `edit_play_divergence`
  - compares observed edit pack vs observed play pack
- `idempotent_reimport_diff`
  - compares consecutive imports for duplicate / drift behavior

## Pass / Warn Policy

Hard failures:

- missing building shell
- wall coverage below threshold
- roof spill above threshold
- edit/play pack disagreement above threshold

Warnings:

- roof fragmentation above soft threshold
- terrain semantic drift in a minority of samples
- source-tag retention loss where fallback behavior still produced geometry

Report-only until building holes exist end-to-end:

- courtyard collapsed when source has holes

The exact thresholds should be versioned in the harness config so we can tighten them over time.

## Canonical Sampling Contract

The comparator must use shared world-space sample points so source and scene are measured on the same coordinates.

Rules:

- the truth pack defines the canonical sample grid
- the observed pack samples exactly those coordinates
- terrain and landuse use sparse fixed grids first
- footprint and roof checks use source-aligned polygon sampling plus perimeter sampling
- all tolerances are explicit and versioned

This is required for deterministic edit/play parity and for stable CI thresholds.

## LOD and Capture State

Observed capture must pin a deterministic scene state before sampling.

Required capture conditions:

- highest detail LOD enabled
- detail groups and shell groups visible
- no streaming-related hidden chunks in the selected comparison region
- import completion marker reached before capture starts

If the capture state cannot be guaranteed, the run should fail as invalid instead of recording noisy metrics.

## Output Artifacts

The harness should emit:

- `truth-pack.json`
- `observed-pack-edit.json`
- `observed-pack-play.json`
- `fidelity-report.json`
- `fidelity-summary.md`

Optional later:

- annotated PNG overlays
- AI-generated triage notes

## Austin Baseline

Austin should be the first golden baseline because:

- it is already the active stress dataset
- many current regressions were discovered there
- it exercises buildings, terrain, roads, and runtime paths together

We should keep:

- a compact preview baseline
- a runtime Austin baseline

Both should be regenerated intentionally, never implicitly.

## Integration Boundaries

### `arnis-roblox`

Owns:

- truth-pack generation hooks
- Studio observed-pack capture
- deterministic comparator
- fidelity reports
- edit/play harness execution

### `vertigo-sync`

Owns:

- source syncing and Studio iteration support

Does not own:

- fidelity truth
- scene correctness
- pass/fail semantics

This keeps VertigoSync useful without making it the authority on whether the world is correct.

## Implementation Slices

### Slice 1: Truth Pack

- add Rust-side export of a bounded truth pack for Austin
- include roof metadata, terrain semantics, water holes
- include building holes only where the source pipeline already carries them
- no main manifest schema break required

### Slice 2: Observed Pack Capture

- add Studio-side capture module for imported geometry and terrain samples
- support both edit and play mode
- keep it importer-adjacent, not plugin-dependent
- add explicit source-id / chunk-id attribution required by the comparator
- pin LOD / capture state before sampling

### Slice 3: Comparator

- add Python comparator with Pydantic models
- compute deterministic structural and semantic metrics
- emit machine-readable and human-readable reports

### Slice 4: Regression Wiring

- run against Austin in harness
- store baseline thresholds
- fail on hard regressions
- keep building-hole metrics report-only until end-to-end hole support lands

### Slice 5: Optional AI Triage

- only after deterministic harness is trusted
- AI summarizes suspicious areas; it does not decide correctness

## Testing Strategy

Rust:

- unit tests for truth-pack serialization
- topology tests for multi-outer and inner-ring building cases
- tag retention tests

Roblox:

- observed-pack capture specs for shell, roof, terrain, and water
- edit/play parity checks on known sample inputs
- attribution contract specs for `ArnisSourceId` / `ArnisChunkId`
- LOD-pinned capture-state specs

Python:

- comparator metric tests with hand-built fixtures
- threshold policy tests

Harness:

- Austin preview smoke
- Austin runtime end-to-end

## Risks

1. Footprint approximation from Roblox meshes may be lossy.
   Mitigation: use canonical shell metadata where possible and explicit sampling where not.

2. Terrain comparison can become too expensive.
   Mitigation: fixed sparse sampling grid first, denser sampling later.

3. Thresholds may be noisy at first.
   Mitigation: start with report-only mode, then promote stable metrics to hard gates.

4. Main manifest contract could be destabilized.
   Mitigation: keep truth-pack additive and separate.

5. Comparator could silently match the wrong building when names collide or models are merged.
   Mitigation: require explicit source-id attribution and fail closed when absent.

6. LOD or capture timing could create false regressions.
   Mitigation: pin capture state and fail invalid runs instead of sampling partial scenes.

## Recommendation

Proceed with the deterministic end-to-end harness first:

- additive truth-pack
- Studio observed-pack capture
- Pydantic-based comparator
- Austin baseline
- report-only first, then gated hard failures

Only after that is stable should we add `PydanticAI` or `DSPy` for qualitative triage and optimization.
