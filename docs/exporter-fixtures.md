## Rust exporter ⇄ Roblox fixture contract

This repository keeps a loose but intentional contract between the Rust exporter samples and the Roblox sample fixtures.

- **Rust side (source of truth for shape)**:
  - `rust/crates/arbx_roblox_export/src/lib.rs` exposes `build_sample_multi_chunk(count_x, count_z)`.
  - `rust/crates/arbx_cli/src/main.rs` wires the `sample` command:
    - `arbx_cli sample --grid X,Z` → emits a schema `0.2.0` manifest JSON with an `X × Z` grid of chunks.
  - `arbx_cli sample --grid 2,2` is the reference command for a small, multi-chunk sample manifest.

- **Roblox side (fixtures used by tests)**:
  - `ServerStorage.SampleData.SampleManifest`:
    - Single-chunk, hand-authored manifest used by `ImportService.spec.lua` and `ChunkSchema.spec.lua`.
  - `ServerStorage.SampleData.SampleMultiChunkManifest`:
    - Multi-chunk, hand-authored manifest that mirrors the **shape** of a `--grid 2,2` export (two adjacent chunks with a primary road spanning the boundary).
    - Used by `ServerScriptService.Tests.ImportServiceMultiChunk.spec.lua` to assert:
      - `ImportService.ImportManifest` imports multiple chunks (`stats.chunksImported == 2`).
      - Both chunk folders (`"0_0"` and `"1_0"`) are created under the world root.

### Updating fixtures when the exporter changes

- If you change the Rust sample exporter or schema in a way that affects sample manifests:
  1. Run: `cd rust && cargo run -p arbx_cli -- sample --grid 2,2 > /tmp/sample-2x2.json`
  2. Inspect `/tmp/sample-2x2.json` and compare it to:
     - `roblox/src/ServerStorage/SampleData/SampleManifest.lua`
     - `roblox/src/ServerStorage/SampleData/SampleMultiChunkManifest.lua`
  3. Manually update the Lua fixtures to keep:
     - The same schema version (`0.2.0` unless bumped with migrations).
     - A compatible field layout for `ChunkSchema.validateManifest`.
     - A small but representative set of features (roads/buildings/terrain) that exercise importer behavior.
  4. Re-run:
     - `cd rust && cargo test`
     - Roblox test runner (`RunAll` in `ServerScriptService.Tests`) in Studio/CI.

This keeps the Rust sample exporter and Roblox fixtures aligned, while still allowing fixtures to remain small, readable, and hand-tuned for importer tests.

