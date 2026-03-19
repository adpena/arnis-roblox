# Chunk Schema

The schema lives in `specs/chunk-manifest.schema.json`.

## Design goals

- readable by humans
- easy for Rust to emit
- easy for Luau to validate
- versioned explicitly
- chunk ownership is obvious
- representation choices are swappable over time

## Top-level fields

- `schemaVersion`
- `meta`
- `chunks` (must contain at least one chunk)

## Meta section

The meta section defines:

- world name
- source description
- manifest generator identity
- `metersPerStud`
- `chunkSizeStuds`
- bounding box
- optional notes

## Coordinate convention

`originStuds` is the world-space anchor for the chunk. `metersPerStud` (0.3) defines the canonical scale.

All geometry nested inside a chunk is treated as **chunk-local** unless the schema is later revised to
say otherwise. That means:

- terrain samples are addressed relative to the chunk origin
- road and water points are local to the chunk origin
- building footprints are local to the chunk origin
- prop positions are local to the chunk origin

**Elevation authority:** The Rust exporter samples elevation from the DEM at export time and writes authoritative Y values for all features. Roblox builders consume these directly — no re-sampling, no snap thresholds, no heuristic delta checks. GroundSampler remains available for runtime queries (player placement) but is not used during chunk import.

This keeps chunk moves, reloads, and local editing much cleaner.

## Schema Versions

### 0.4.0 (Current)
- Canonical scale: `metersPerStud = 0.3` (1 stud ≈ 0.3m, matching Roblox humanoid proportions).
- Rust exporter is the single elevation authority — all Y positions are authoritative from DEM sampling.
- Terrain resolution increased: `cellSizeStuds = 4`, grid 64x64 (4,096 cells per chunk), voxel size 2.
- New road fields: `elevated` (bool), `tunnel` (bool), `sidewalk` (string).
- Building `color` renamed to `wallColor`; new fields: `roofColor`, `roofShape`, `roofMaterial`, `usage`, `minHeight`.
- New water field: `surfaceY` (authoritative surface elevation for polygon water).
- New prop fields: `height`, `leafType`.
- Lua builders no longer re-sample ground or apply snap thresholds — they read manifest values directly.
- Migration from 0.3.0 scales all stud-space coordinates by `oldMps / 0.3`.

### 0.3.0
- Documents the richer manifest surface already supported by the exporter and importer.
- Adds schema support for:
  - `terrain.materials`
  - `roads.hasSidewalk`
  - `roads.surface`
  - `buildings.height_m`
  - `buildings.levels`
  - `buildings.roofLevels`
  - `buildings.facadeStyle`
  - `water.holes`
  - `props.species`
  - chunk-level `landuse`
  - chunk-level `barriers`
- Automatically migrated to `0.4.0` by the Roblox importer.

### 0.2.0
- Adds `meta.totalFeatures`: an integer count of all features across all chunks.
- Automatically migrated to `0.4.0` by the Roblox importer.

### 0.1.0
- Initial scaffold version.
- Automatically migrated to `0.4.0` by the Roblox importer.

## Migration Mechanism

The Roblox importer includes a `Migrations` module (`roblox/src/ReplicatedStorage/Shared/Migrations.lua`) that automatically upgrades older manifests to the current `Version.SchemaVersion` before validation. This ensures backward compatibility as the schema evolves.

## Chunk section

Each chunk carries:

- `id`
- `originStuds`
- optional terrain grid
- roads
- rails
- buildings
- water
- props
- landuse
- barriers

## Representation choices in this scaffold

### Terrain

A simple height grid with:
- `cellSizeStuds`
- `width`
- `depth`
- `heights`
- `material`
- optional per-cell `materials`

This is intentionally basic so the contract stabilizes before the representation gets fancy.

### Roads, rails, water, and barriers

Polyline-based ribbons with width and points. Roads carry `hasSidewalk`, `surface`, `elevated` (bridge),
`tunnel`, and `sidewalk` (both/left/right/no) flags. Water polygons carry `holes` for islands/cutouts
and `surfaceY` for authoritative surface elevation.

### Buildings

Shell-oriented footprints with:
- polygon footprint
- base height (authoritative Y from DEM)
- shell height (in studs at canonical scale)
- optional measured height and level counts
- roof kind, shape, material, and color
- wall color (from OSM or satellite)
- optional facade style hints
- optional usage (OSM building tag)
- optional minHeight (for stilted/elevated structures)

### Props

Point instances with:
- kind
- position (authoritative Y from DEM)
- yaw
- scale
- optional species hint for vegetation
- optional height (real-world meters, for trees)
- optional leafType (broadleaved/needleleaved)

### Landuse

Polygon shells for broad ground-treatment ownership such as parks, grass, sand, or paved civic areas.

## Planned future extensions

- chunk-local material palettes
- instance-merged road strips
- mesh references
- LOD metadata
- instancing/prefab keys
- light sources and POIs
- power layers
- migration metadata
