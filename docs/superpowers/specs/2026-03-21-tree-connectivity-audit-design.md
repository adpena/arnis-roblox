# Tree Connectivity Audit Design

## Goal

Add first-class tree-structure diagnostics to the live scene audit so we can detect cases where canopies do not visibly connect to trunks, without tying the audit to the current tree art style.

## Scope

- Extend the live Roblox scene audit to classify tree props by structural evidence:
  - `connected_trunk_canopy`
  - `missing_trunk`
  - `missing_canopy`
  - `detached_canopy`
- Surface those metrics through the existing JSON and HTML scene fidelity reports.
- Keep the audit representation-based so it remains valid if we later replace procedural trees with higher-fidelity meshes.

## Design

### SceneAudit

- Detect tree roots from existing `ArnisPropKind == "tree"` tagging.
- Inspect descendants for trunk evidence:
  - part names containing `Trunk`
  - optionally later, trunk-tagged meshes if we add explicit attrs
- Inspect descendants for canopy evidence:
  - part names containing `Canopy`
- If both exist, evaluate simple structural overlap/vertical adjacency to classify:
  - `connected_trunk_canopy` when the top of a trunk intersects or nearly meets the bottom of a canopy volume
  - `detached_canopy` when both exist but are spatially separated
- Emit aggregate counts and per-species buckets.

### Scene Fidelity Report

- Add scene fields for aggregate tree connectivity counts.
- Add per-species connectivity buckets.
- Emit a finding when detached/missing structure exceeds a small threshold.

## Non-goals

- Changing tree art or geometry generation in this pass
- Introducing new runtime-only tags that the exporter must know about
- Making stylistic judgments about mesh quality

## Validation

- Red-green Luau spec for `SceneAudit` tree classification
- Python report test covering the new fields and finding logic
- Live Austin edit pass to confirm counts and species buckets flow through the harness
