#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper to:
#  1) Fetch real OSM data for an Austin bbox via Overpass
#  2) Run the full Rust pipeline + exporter
#  3) Convert the JSON manifest into sharded Roblox Lua ModuleScripts
#
# Usage (from repo root):
#   bash scripts/export_austin_to_lua.sh
#
# Outputs:
#   rust/data/austin_overpass.json
#   rust/out/austin-manifest.json
#   roblox/src/ServerStorage/SampleData/AustinManifestIndex.lua
#   roblox/src/ServerStorage/SampleData/AustinManifestChunks/
#   roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua
#   roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
DATA_DIR="$RUST_DIR/data"
OUT_DIR="$RUST_DIR/out"
SAMPLE_DATA_DIR="$ROOT_DIR/roblox/src/ServerStorage/SampleData"
PREVIEW_JSON="$ROOT_DIR/specs/generated/austin-preview-downtown.json"
PREVIEW_DIR="$ROOT_DIR/roblox/src/ServerScriptService/StudioPreview"

mkdir -p "$DATA_DIR" "$OUT_DIR" "$SAMPLE_DATA_DIR" "$PREVIEW_DIR"

echo "=== Fetching Overture building footprints ==="
python3 "$ROOT_DIR/scripts/fetch_overture_buildings.py" || echo "Warning: Overture fetch failed, continuing with OSM only"

echo "[export_austin_to_lua] Fetching OSM + exporting manifest..."
bash "$ROOT_DIR/scripts/export_austin_from_osm.sh"

echo "[export_austin_to_lua] Converting JSON manifest to sharded Lua modules..."
python3 "$ROOT_DIR/scripts/json_manifest_to_sharded_lua.py" \
  --json "$OUT_DIR/austin-manifest.json" \
  --output-dir "$SAMPLE_DATA_DIR" \
  --index-name "AustinManifestIndex" \
  --shard-folder "AustinManifestChunks" \
  --chunks-per-shard 1

if [[ -f "$PREVIEW_JSON" ]]; then
  echo "[export_austin_to_lua] Converting preview subset to sharded Lua modules..."
  python3 "$ROOT_DIR/scripts/json_manifest_to_sharded_lua.py" \
    --json "$PREVIEW_JSON" \
    --output-dir "$PREVIEW_DIR" \
    --index-name "AustinPreviewManifestIndex" \
    --shard-folder "AustinPreviewManifestChunks" \
    --chunks-per-shard 1
else
  echo "[export_austin_to_lua] Preview JSON not found at $PREVIEW_JSON; skipping preview shard generation"
fi

echo "[export_austin_to_lua] Done. Sharded manifests written to $SAMPLE_DATA_DIR and $PREVIEW_DIR"
