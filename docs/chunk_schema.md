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
- `chunks`

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

`originStuds` is the world-space anchor for the chunk.

All geometry nested inside a chunk is treated as **chunk-local** unless the schema is later revised to
say otherwise. That means:

- terrain samples are addressed relative to the chunk origin
- road and water points are local to the chunk origin
- building footprints are local to the chunk origin
- prop positions are local to the chunk origin

This keeps chunk moves, reloads, and local editing much cleaner.

## Schema Versions

### 0.2.0 (Current)
- Adds `meta.totalFeatures`: an integer count of all features across all chunks.
- Mandatory for all new manifests.

### 0.1.0
- Initial scaffold version.
- Automatically migrated to 0.2.0 by the Roblox importer.

## Migration Mechanism

The Roblox importer includes a `Migrations` module (`roblox/src/ReplicatedStorage/Shared/Migrations.lua`) that automatically upgrades older manifests to the current `Version.SchemaVersion` before validation. This ensures backward compatibility as the schema evolves.

## Chunk section

Each chunk carries:

- `id`
- `originStuds`
- optional terrain grid
- roads
- buildings
- water
- props

## Representation choices in this scaffold

### Terrain

A simple height grid with:
- `cellSizeStuds`
- `width`
- `depth`
- `heights`
- `material`

This is intentionally basic so the contract stabilizes before the representation gets fancy.

### Roads and water

Polyline-based ribbons with width and points.

### Buildings

Shell-oriented footprints with:
- polygon footprint
- base height
- shell height
- roof kind

### Props

Minimal point instances with:
- kind
- position
- yaw
- scale

## Planned future extensions

- chunk-local material palettes
- instance-merged road strips
- mesh references
- LOD metadata
- instancing/prefab keys
- light sources and POIs
- rail / power / landuse layers
- migration metadata
