# Build Pipeline

## Pipeline stages

The intended long-term pipeline is:

1. **Acquire**
   - upstream adapter obtains normalized source data
2. **Normalize**
   - resolve missing values, tag aliases, and geometry cleanup
3. **Classify**
   - roads, buildings, terrain patches, water, props, rail, etc.
4. **Chunk**
   - assign authoritative chunk ownership
5. **Export**
   - emit Roblox manifest(s)
6. **Import**
   - Studio/runtime consumes manifests and builds scene content

## What belongs where

### Rust-side

- acquisition
- normalization
- classification
- chunk assignment
- manifest writing
- offline validation and migration

### Roblox-side

- manifest validation
- content instantiation
- chunk lifecycle
- performance telemetry
- editor UX

## Recommended adapter boundary for future Arnis integration

Instead of pasting Arnis logic everywhere, create a single adapter layer that can translate upstream
data structures into project-owned domain structures.

```text
Arnis / source-specific types
            │
            ▼
     adapter conversion
            │
            ▼
   project-owned domain types
            │
            ▼
   project-owned manifest export
```

This preserves freedom to:
- swap in direct OSM/elevation tooling later
- compare Arnis-derived output against custom adapters
- test without the full upstream toolchain

## Expected artifact types

### Canonical artifacts

- `chunk-manifest.json`
- `world-config.json`
- material palette / style config
- migration notes when schema changes

### Developer artifacts

- sample manifests
- profiling snapshots
- chunk-diff regression fixtures
