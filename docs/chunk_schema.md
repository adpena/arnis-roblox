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
- optional `chunkRefs` scheduling metadata for compile/export artifacts

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
- Terrain resolution configurable: default `cellSizeStuds = 2` (128x128 grid, 16,384 cells), configurable 1-32 via CLI `--terrain-cell-size`. Voxel size configurable via WorldConfig (default 1).
- New road fields: `elevated` (bool), `tunnel` (bool), `sidewalk` (string).
- Building `color` renamed to `wallColor`; new fields: `roofColor`, `roofShape`, `roofMaterial`, `usage`, `minHeight`.
- New water field: `surfaceY` (authoritative surface elevation for polygon water).
- New prop fields: `height`, `leafType`.
- Lua builders no longer re-sample ground or apply snap thresholds — they read manifest values directly.
- Migration from 0.3.0 scales all stud-space coordinates by `oldMps / 0.3`.
- Index-side scheduling metadata is versioned separately via `partitionVersion`; changing the subplan contract does not require a manifest schema bump unless the manifest shape itself changes.

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

## Compile-time scheduling metadata

Compiled JSON artifacts may carry optional top-level `chunkRefs` metadata so the current Python
sharding pipeline can preserve Rust-authored scheduling hints into generated Lua indexes. These
entries are additive scheduling metadata only. They do not change manifest truth, schemaVersion
authority, or canonical chunk geometry/content in `chunks`.

Compile-time JSON `chunkRefs` carry scheduling metadata only and do not include shard names.
Generated Lua shard indexes carry the same metadata plus `shards` for lazy loading. In addition to
`id`, `originStuds`, and optional `shards`, generated indexes may include:

- `featureCount`: optional coarse aggregate hint for chunk-level authored content
- `streamingCost`: optional aggregate hint for weighted import cost used by chunk scheduling
- `partitionVersion`: scheduling-layer contract tag for the attached subplans
- `subplans`: ordered scheduling metadata with per-subplan `id`, `layer`, `featureCount`, `streamingCost`, and optional `bounds`

These fields do not change manifest truth or chunk contents. They exist so preview/runtime loaders
can choose a better import order without dropping any source geometry or metadata. `partitionVersion`
and `subplans` are additive index metadata only, not alternate manifest truth. When `subplans` are
present, top-level `featureCount` and `streamingCost` remain optional aggregate hints rather than
required fields. Those aggregate hints continue to reflect canonical authored chunk content at the
chunk level, even when a `subplans.v1` coarse plan omits explicit rails or barriers subplans.
The same `subplans.v1` contract may also emit multiple bounded siblings for a hot layer, such as
`buildings:nw` / `buildings:ne` / `buildings:sw` / `buildings:se`, while preserving the same
canonical chunk contents and aggregate chunk hints.

### Scheduling-layer migration notes

When the subplan scheduling contract changes:

- bump `partitionVersion`
- update the loader/verifier contract notes in this file
- keep the manifest `schemaVersion` unchanged unless the manifest structure itself changes
- treat subplan ordering, thresholds, and bounds semantics as scheduler policy, not manifest schema changes
- document any intentional gap between chunk-level aggregate hints and emitted coarse subplan layers

## Representation choices in this scaffold

### Terrain

A simple height grid with:
- `cellSizeStuds`
- `width`
- `depth`
- `heights`
- `material`
- optional per-cell `materials`

The optional `materials` array is populated from satellite imagery classification (SP-2). Each cell
receives a Roblox terrain material string derived from the satellite tile covering that grid cell,
allowing ground cover (grass, rock, sand, mud, etc.) to vary across the chunk rather than using a
single uniform material.

This is intentionally basic so the contract stabilizes before the representation gets fancy.

### Roads, rails, water, and barriers

Polyline-based ribbons with width and points. Roads carry `hasSidewalk`, `surface`, `elevated` (bridge),
`tunnel`, and `sidewalk` (both/left/right/no/separate) flags. `sidewalk=separate` means the source road
declares sidewalks nearby, but not attached to the road ribbon itself, so attached sidewalk/curb scene
geometry is not expected for that road ID. Additional optional OSM-derived road fields:
`maxspeed` (integer km/h speed limit), `lit` (boolean street lighting), `oneway` (boolean direction
constraint), and `layer` (integer vertical stacking level for overpasses/underpasses). Water polygons
carry `holes` for islands/cutouts, `surfaceY` for authoritative surface elevation, `width` (real-world
meters for river/stream features), and `intermittent` (boolean for seasonal water bodies).

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
- optional roofHeight (real-world meters for the roof portion above the eave)
- optional name (OSM `name` tag for labeled structures)

### Props

Point instances with:
- kind
- position (authoritative Y from DEM)
- yaw
- scale
- optional species hint for vegetation
- optional height (real-world meters, for trees)
- optional leafType (broadleaved/needleleaved)
- optional circumference (real-world meters trunk circumference, for tree scaling)

### Landuse

Polygon shells for broad ground-treatment ownership such as parks, grass, sand, or paved civic areas.

## Implemented extensions (from planned)

- [x] instance-merged road strips (EditableMesh merging in RoadBuilder)
- [x] instance-merged building geometry (EditableMesh merging in BuildingBuilder)
- [x] LOD metadata (CollectionService tagging: LOD_Detail, LOD_Interior, StreetLight, Road)
- [x] light sources (PointLights on street lamps, interior ceiling lights, car headlights)
- [x] power layers (power_tower, power_pole props from OSM)
- [x] satellite-derived material palettes (per-cell terrain, per-building roof)
- [x] surface physics properties (26 surface types with friction coefficients)
- [x] road AI metadata (Oneway, MaxSpeed, Lanes attributes on road Parts)

## Planned future extensions

- Mapbox Vector Tile integration (MVT geometry + OSM semantics fusion)
- Custom mesh tree models (replace procedural Part trees)
- SurfaceAppearance textures (normal maps for brick, asphalt, etc.)
- Traffic simulation (moving vehicles along road splines)
- Interior furniture generation (from room type inference)
- Real-time collaborative editing via Studio MCP
- Multiplayer chunk streaming
