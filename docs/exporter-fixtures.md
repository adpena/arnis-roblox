## Rust exporter ⇄ Roblox fixture contract

This repository keeps a loose but intentional contract between the Rust exporter samples and the Roblox sample fixtures.

- **Rust side (source of truth for shape)**:
  - `rust/crates/arbx_roblox_export/src/lib.rs` exposes `build_sample_multi_chunk(count_x, count_z)`.
  - `rust/crates/arbx_cli/src/main.rs` wires the `sample` command:
    - `arbx_cli sample --grid X,Z` → emits a schema `0.3.0` manifest JSON with an `X × Z` grid of chunks.
  - `arbx_cli sample --grid 2,2` is the reference command for a small, multi-chunk sample manifest.

- **Roblox side (fixtures used by tests)**:
  - `ServerStorage.SampleData.SampleManifest`:
    - Single-chunk, hand-authored manifest used by `ImportService.spec.lua` and `ChunkSchema.spec.lua`.
  - `ServerStorage.SampleData.SampleMultiChunkManifest`:
    - Multi-chunk, hand-authored manifest that mirrors the **shape** of a `--grid 2,2` export (two adjacent chunks with a primary road spanning the boundary).
    - Used by `ServerScriptService.Tests.ImportServiceMultiChunk.spec.lua` to assert:
      - `ImportService.ImportManifest` imports multiple chunks (`stats.chunksImported == 2`).
      - Both chunk folders (`"0_0"` and `"1_0"`) are created under the world root.

### Using real OSM data (Overpass) with the full pipeline

For quick end-to-end tests with real OSM data, you can use the helper scripts under `scripts/`:

- `scripts/fetch_osm_overpass.py`:
  - Calls the public Overpass API with a bounding box and saves the JSON.
  - Example:
    - `python scripts/fetch_osm_overpass.py --bbox 30.26,-97.75,30.27,-97.74 --out rust/data/austin_overpass.json`
- `scripts/export_austin_from_osm.sh`:
  - Convenience wrapper that:
    1. Fetches OSM data for an Austin bbox via Overpass.
    2. Runs the full Rust pipeline + exporter using `arbx_cli compile`.
  - Usage (from repo root):
    - `bash scripts/export_austin_from_osm.sh`
  - Output:
    - `rust/out/austin-manifest.json` – ready to validate with `ChunkSchema` and import into Roblox.
- `scripts/export_austin_to_lua.sh`:
  - Converts `rust/out/austin-manifest.json` into sharded Roblox fixture modules.
  - It also refreshes the Studio preview shards from the current exported JSON manifest so edit-mode preview matches the latest runtime data contract without inheriting runtime shard sizing/layout directly.
  - The script now fails if generated runtime sample-data or preview shards drift back into stale fields, missing preview refs, or oversize VertigoSync shard modules.
  - Usage (from repo root):
    - `bash scripts/export_austin_to_lua.sh`
  - Output:
    - `roblox/src/ServerStorage/SampleData/AustinManifestIndex.lua`
    - `roblox/src/ServerStorage/SampleData/AustinManifestChunks/`
    - `roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua`
    - `roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/`
  - Each shard currently contains one chunk so no generated `ModuleScript` exceeds Roblox's `Source` size cap during sync.
- `scripts/build_austin_max_fidelity_place.sh`:
  - Builds a clean Austin `.rbxlx` for local Studio testing.
  - Output:
    - `exports/austin-max-fidelity-<UTCSTAMP>.rbxlx` - timestamped local snapshot
    - `exports/austin-max-fidelity-latest.rbxlx` - stable local latest copy
- `scripts/run_austin_fidelity.sh`:
  - Runs the bounded Austin Studio acceptance lane against the stable latest export.
  - Output:
    - `out/austin-fidelity/latest/arnis-scene-fidelity-edit.json`
    - `out/austin-fidelity/latest/arnis-scene-fidelity-edit.html`
    - `out/austin-fidelity/latest/arnis-scene-fidelity-play.json`
    - `out/austin-fidelity/latest/arnis-scene-fidelity-play.html`

You can swap the bbox or output paths in these scripts as needed, or use them as templates for other cities.

### Updating fixtures when the exporter changes

- If you change the Rust sample exporter or schema in a way that affects sample manifests:
  1. Run: `cd rust && cargo run -p arbx_cli -- sample --grid 2,2 > /tmp/sample-2x2.json`
  2. Inspect `/tmp/sample-2x2.json` and compare it to:
     - `roblox/src/ServerStorage/SampleData/SampleManifest.lua`
     - `roblox/src/ServerStorage/SampleData/SampleMultiChunkManifest.lua`
  3. Manually update the Lua fixtures to keep:
     - The same schema version (`0.3.0` unless bumped with migrations).
     - A compatible field layout for `ChunkSchema.validateManifest`.
     - A small but representative set of features (roads/buildings/terrain) that exercise importer behavior.
  4. Re-run:
     - `cd rust && cargo test`
     - Roblox test runner (`RunAll` in `ServerScriptService.Tests`) in Studio/CI.

This keeps the Rust sample exporter and Roblox fixtures aligned, while still allowing fixtures to remain small, readable, and hand-tuned for importer tests.
