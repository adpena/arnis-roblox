# Architecture

## Core thesis

Treat the Roblox port as a **compiler + importer system**, not as a giant in-Studio rewrite of Arnis.

```text
Upstream geodata / Arnis adapter
            │
            ▼
   Rust pipeline + chunk export
            │
            ▼
   versioned manifest + config
            │
            ▼
 Roblox Studio importer/plugin/runtime
            │
            ▼
 streamed chunked world in Workspace
```

## Why this split exists

Roblox and Minecraft have very different scene representations.

- Minecraft output can be thought of as chunk/block data.
- Roblox output is a mix of terrain, parts, meshes, models, packages, and streamed instances.
- Studio/editor concerns are different from runtime concerns.
- Agent workflows are much better when the data contract is explicit.

## Bounded contexts

### 1) Rust export side

Lives under `rust/`.

Responsibilities:

- receive normalized source geometry from an adapter boundary
- classify world objects
- assign chunk ownership
- emit deterministic manifests
- eventually own schema migrations and offline validation

It should **not** know about Studio widgets, toolbar buttons, or edit-time UX.

### 2) Roblox import/runtime side

Lives under `roblox/`.

Responsibilities:

- validate manifests
- build/import chunk content into `Workspace.GeneratedWorld`
- load/unload chunks cleanly
- expose predictable entry points for Studio MCP and plugin automation
- collect runtime/editor profiling signals

It should **not** fetch external map data directly.

### 3) Plugin/editor side

Also under `roblox/`, but kept optional.

Responsibilities:

- toolbar buttons
- import sample/test data into the current place
- run smoke tests from Studio
- accelerate iteration

It must remain a thin layer over shared services.

## Directory ownership

```text
rust/crates/arbx_geo            foundational coordinate + bbox types
rust/crates/arbx_pipeline       source adapter and stage contracts
rust/crates/arbx_roblox_export  manifest types + export logic
rust/crates/arbx_cli            developer-facing commands

roblox/src/ReplicatedStorage    shared contracts and config
roblox/src/ServerScriptService  importer, builders, test runner
roblox/src/ServerStorage        sample manifests and test data
roblox/src/Workspace            generated-world anchor folders
roblox/plugin                   optional plugin model sources
```

## Runtime import flow

1. `ManifestLoader` returns a manifest table.
2. `ChunkSchema` validates the manifest.
3. `ImportService` prepares or clears the world root.
4. Each chunk is imported by specialized builders.
5. `ChunkLoader` records ownership and supports future unload/reload logic.
6. `Profiler` captures timing for visibility during optimization.

## First major upgrade targets

- replace placeholder terrain fill with a voxel-grid writer
- deduplicate or merge road/building geometry where useful
- add authoritative chunk overwrite semantics
- move decorative props behind budget-aware toggles
- add asset-backed prefabs/packages for repeated content

## Explicit anti-patterns

- direct Overpass or elevation HTTP calls from runtime scripts
- giant monolithic “generate the whole city now” functions
- plugin code that contains the real importer logic
- hidden schema changes without version updates
