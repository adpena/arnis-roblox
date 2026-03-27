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
  - By default this now applies a bounded dev fixture profile (`balanced`) unless you explicitly pass `--profile`, `--yolo`, or `--terrain-cell-size`.
  - Override the default with `AUSTIN_EXPORT_DEFAULT_PROFILE=fast|balanced|high|insane` if you need a different non-explicit baseline.
  - Usage (from repo root):
    - `bash scripts/export_austin_from_osm.sh`
    - `bash scripts/export_austin_from_osm.sh --profile high --satellite`
  - Output:
    - `rust/out/austin-manifest.json` – ready to validate with `ChunkSchema` and import into Roblox.
    - `rust/out/austin-manifest.sqlite` – chunk-addressable SQLite sidecar for bounded-memory tooling.
- `scripts/export_austin_to_lua.sh`:
  - Converts `rust/out/austin-manifest.sqlite` into sharded Roblox fixture modules.
  - Like the exporter wrapper it now defaults to the bounded dev profile unless explicit fidelity arguments are supplied.
  - It also refreshes the Studio preview shards from the current exported manifest. The refresh path now prefers `rust/out/austin-manifest.sqlite` when present and falls back to bounded-memory JSON extraction otherwise, so edit-mode preview stays aligned without whole-file manifest loads.
  - The script now fails if generated runtime sample-data or preview shards drift back into stale fields, missing preview refs, or oversize VertigoSync shard modules.
  - Usage (from repo root):
    - `bash scripts/export_austin_to_lua.sh`
    - `bash scripts/export_austin_to_lua.sh --profile high --satellite`
  - Output:
    - `roblox/src/ServerStorage/SampleData/AustinManifestIndex.lua`
    - `roblox/src/ServerStorage/SampleData/AustinManifestChunks/`
    - `roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua`
    - `roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/`
  - Each shard currently contains one chunk so no generated `ModuleScript` exceeds Roblox's `Source` size cap during sync.
- `scripts/build_austin_max_fidelity_place.sh`:
  - Builds a clean Austin `.rbxlx` for local Studio testing.
  - This path now opts into explicit higher fidelity (`--profile high --satellite`) so the max-fidelity lane does not silently inherit the lighter dev default.
  - Canonical source compile command inside the wrapper:
    - `cd rust && cargo run --bin arbx_cli -- compile --source data/austin_overpass.json --bbox 30.245,-97.765,30.305,-97.715 --out out/austin-manifest.json --sqlite-out out/austin-manifest.sqlite`
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
