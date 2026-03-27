#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper to:
#  1) Fetch real OSM data for an Austin bbox via Overpass
#  2) Run the full Rust pipeline + exporter
#  3) Convert the JSON manifest into sharded Roblox Lua ModuleScripts
#
# Usage (from repo root):
#   bash scripts/export_austin_to_lua.sh
#   bash scripts/export_austin_to_lua.sh --yolo
#   bash scripts/export_austin_to_lua.sh --profile high --satellite
#
# Default behavior:
#   Uses the default bounded dev profile from export_austin_from_osm.sh unless explicit
#   fidelity arguments are supplied on the command line.
#
# Outputs:
#   rust/data/austin_overpass.json
#   rust/out/austin-manifest.json
#   rust/out/austin-manifest.sqlite
#   roblox/src/ServerStorage/SampleData/AustinManifestIndex.lua
#   roblox/src/ServerStorage/SampleData/AustinManifestChunks/
#   roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua
#   roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
DATA_DIR="$RUST_DIR/data"
OUT_DIR="$RUST_DIR/out"
SAMPLE_DATA_DIR="$ROOT_DIR/roblox/src/ServerStorage/SampleData"
PREVIEW_DIR="$ROOT_DIR/roblox/src/ServerScriptService/StudioPreview"

mkdir -p "$DATA_DIR" "$OUT_DIR" "$SAMPLE_DATA_DIR" "$PREVIEW_DIR"

echo "=== Fetching Overture building footprints ==="
python3 "$ROOT_DIR/scripts/fetch_overture_buildings.py" || echo "Warning: Overture fetch failed, continuing with OSM only"

echo "[export_austin_to_lua] Fetching OSM + exporting manifest with the default bounded dev profile unless explicitly overridden..."
bash "$ROOT_DIR/scripts/export_austin_from_osm.sh" "$@"

echo "[export_austin_to_lua] Converting SQLite manifest store to sharded Lua modules..."
python3 "$ROOT_DIR/scripts/json_manifest_to_sharded_lua.py" \
  --sqlite "$OUT_DIR/austin-manifest.sqlite" \
  --output-dir "$SAMPLE_DATA_DIR" \
  --index-name "AustinManifestIndex" \
  --shard-folder "AustinManifestChunks" \
  --chunks-per-shard 1

echo "[export_austin_to_lua] Refreshing Studio preview from current Austin sample-data shards..."
python3 "$ROOT_DIR/scripts/refresh_preview_from_sample_data.py"

echo "[export_austin_to_lua] Refreshing bounded runtime harness sample-data from current Austin shards..."
python3 "$ROOT_DIR/scripts/refresh_runtime_harness_from_sample_data.py"

echo "[export_austin_to_lua] Verifying generated Austin sample-data + preview assets..."
python3 "$ROOT_DIR/scripts/verify_generated_austin_assets.py"

echo "[export_austin_to_lua] Done. Sharded manifests written to $SAMPLE_DATA_DIR and $PREVIEW_DIR"
