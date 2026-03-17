# AGENTS.md

This file is the operating manual for coding agents working in this repository.

## Mission

Build a performant, chunked Roblox world importer/export pipeline inspired by Arnis, while keeping
the data compiler and the Roblox runtime/editor responsibilities separate.

## Non-negotiable architecture rules

1. **Offline compile, online import**
   - External geodata retrieval belongs in Rust-side tooling or a server-side pipeline.
   - Roblox runtime/editor code consumes already-compiled manifests.

2. **Schema before behavior**
   - Manifest and config schema changes must be reflected in `specs/` first.
   - Backward-compatibility changes must update the schema version and migration notes.

3. **Chunk everything**
   - New systems must identify their chunk ownership explicitly.
   - No global, unbounded scene generation helpers.

4. **Idempotent imports**
   - Importing the same manifest/chunk twice should overwrite or reconcile, not duplicate.

5. **Performance beats ornament**
   - Prefer terrain, merged representations, and pooled instances.
   - Delay high-detail assets and interiors until shell import is stable and benchmarked.

6. **Deterministic output**
   - The same source input and config should produce the same manifest and equivalent scene graph.

## Default sequence of work for Kodex

1. Stabilize the JSON schema in `specs/`.
2. Improve Rust manifest generation.
3. Improve Roblox schema validation.
4. Make chunk import deterministic and re-runnable.
5. Replace placeholder builders with optimized ones in this order:
   - terrain
   - roads
   - buildings
   - water
   - props
6. Add chunk unload/reload.
7. Add profiling and regression harnesses.
8. Only then expand art fidelity.

## Change discipline

For every meaningful code change:

- update or add a test if there is a harness for that area
- update docs if the contract changed
- avoid introducing new dependencies without a concrete payoff
- prefer small, reviewable steps over giant speculative rewrites

## Roblox-specific guardrails

- Studio plugin code must remain optional.
- Runtime modules should not depend on plugin-only APIs.
- Keep anything that mutates `Workspace.GeneratedWorld` behind an importer or chunk loader service.
- When a feature is not ready, fail loudly with a TODO and a clear message.

## Rust-specific guardrails

- Keep exporter crates dependency-light until contracts settle.
- Avoid entangling domain types with source-adapter specifics.
- Keep upstream Arnis integration behind an adapter boundary instead of smearing it across the repo.

## Done criteria for the first “real” milestone

A change is milestone-worthy when all of the following are true:

- the Rust sample exporter emits schema-valid chunk manifests
- the Roblox importer consumes them without manual hand-editing
- sample roads, terrain, and building shells appear in Studio
- repeated imports are clean
- smoke tests and repo checks pass
