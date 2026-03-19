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

## Current state (post-HD Pipeline)

The pipeline is complete and demo-ready. All builders are production-quality:

- **Schema 0.4.0** with full migration chain (0.1.0 → 0.4.0)
- **ElevationEnrichmentStage** — DEM-derived Y for all features
- **EditableMesh merging** for buildings and roads
- **26 surface physics types** with real-world friction coefficients
- **5-phase day/night cycle** with lerped atmospheric transitions
- **25+ prop types**, **20+ building materials**, **25+ tree species**
- **Car + jetpack + parachute** gameplay with full physics and sound
- **Live minimap**, **loading screen**, **ambient soundscape**
- **Worldwide support** — any lat/lon bbox, auto-downloads elevation

## Sequence of work for agents

1. Read `docs/chunk_schema.md` for the manifest contract.
2. Read `roblox/src/ReplicatedStorage/Shared/WorldConfig.lua` for all config knobs.
3. Use `arbx_cli explain` for the full pipeline architecture.
4. Use `arbx_cli compile --help` for CLI options.
5. Run `cargo test --workspace` in `rust/` to verify the pipeline.
6. Builders are in `roblox/src/ServerScriptService/ImportService/Builders/`.
7. Gameplay is in `roblox/src/StarterPlayer/StarterPlayerScripts/`.

## Change discipline

For every meaningful code change:

- update or add a test if there is a harness for that area
- update docs if the contract changed
- avoid introducing new dependencies without a concrete payoff
- prefer small, reviewable steps over giant speculative rewrites
- zero per-frame allocations in render loops
- all lerps must be dt-scaled (frame-rate independent)
- all sounds must fade (no audio pops)
- all UI transitions must use TweenService (no snaps)

## Roblox-specific guardrails

- Studio plugin code must remain optional.
- Runtime modules should not depend on plugin-only APIs.
- Keep anything that mutates `Workspace.GeneratedWorld` behind an importer or chunk loader service.
- When a feature is not ready, fail loudly with a TODO and a clear message.

## Rust-specific guardrails

- Keep exporter crates dependency-light until contracts settle.
- Avoid entangling domain types with source-adapter specifics.
- Keep upstream Arnis integration behind an adapter boundary instead of smearing it across the repo.

## Done criteria

A change is production-ready when all of the following are true:

- `cargo test --workspace` passes (31+ tests)
- the Roblox importer consumes the manifest without errors
- all features render correctly at the configured quality profile
- repeated imports are idempotent (no duplicate content)
- no per-frame allocations in any render loop
- all transitions smooth (TweenService, dt-scaled lerps)
- no TODO/placeholder comments in shipped code
