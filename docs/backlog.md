# Backlog

## Epic A — Contracts

- [x] finalize chunk schema (v0.3.0 stable)
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

## Epic F — HD Pipeline

- [x] SP-1: Coordinate contract (meters_per_stud=0.3, schema 0.4.0, elevation authority, terrain 64x64)
- [x] SP-2: Data source fusion (z15 DEM, live Overpass tags, satellite tile classification, expanded OSM fields maxspeed/lit/oneway/layer/roofHeight/name/width/intermittent/circumference, Lua schema validation, JSON schema and docs updated)
- [x] SP-3: Builder fidelity (bilinear terrain interpolation, slope-aware materials, roof colors/materials from satellite, glass window panes, usage-aware window density, lane-aware road width, directional sidewalks, street lighting, water terrain carving, island preservation, height-based tree scaling, leaf type canopy shapes, palm tree rendering, 25+ tree species)
- [x] SP-4: Material & texture pipeline (integrated into SP-2 satellite classification + SP-3 builder consumption — roof materials from satellite, per-cell terrain materials, ground cover classification)
