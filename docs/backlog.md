# Backlog

## Epic A — Contracts

- [x] finalize chunk schema (v0.2.0 stable)
- [x] finalize world config schema
- [x] add migration notes mechanism
- [x] add manifest version upgrade helper

## Epic B — Rust exporter

- [x] multi-chunk sample exporter
- [x] deterministic sort order
- [x] chunk ownership rules
- [x] adapter trait for upstream geodata
- [x] real geodata adapter (OSM/Overpass)
- [x] CLI commands for validate / diff / stats

## Epic C — Roblox importer

- [x] real terrain voxel writer
- [x] road strip batching or merging (EditableMesh)
- [x] building shell merge behavior (EditableMesh)
- [x] chunk unload/reload
- [x] per-chunk profiling summary
- [x] LOD / visibility distance selection (StreamingService)

## Epic D — Tooling

- [x] stronger repo checks (selene + cargo test)
- [x] optional TestEZ integration
- [x] CI workflow
- [x] serialized perf snapshots

## Epic E — Fidelity

- [x] water material strategy (EditableMesh merging)
- [x] tree/light prefab strategy (Pooling + Prefabs)
- [x] rail/power layers
- [x] interiors only after shell perf is stable
