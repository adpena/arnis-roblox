#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper to:
#  1) Fetch real OSM data for an Austin bbox via Overpass
#  2) Run the full Rust pipeline + exporter
#  3) Convert the JSON manifest into a Roblox Lua ModuleScript
#
# Usage (from repo root):
#   bash scripts/export_austin_to_lua.sh
#
# Outputs:
#   rust/data/austin_overpass.json
#   rust/out/austin-manifest.json
#   roblox/src/ServerStorage/SampleData/AustinManifest.lua

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
DATA_DIR="$RUST_DIR/data"
OUT_DIR="$RUST_DIR/out"
LUA_MODULE="$ROOT_DIR/roblox/src/ServerStorage/SampleData/AustinManifest.lua"

mkdir -p "$DATA_DIR" "$OUT_DIR" "$(dirname "$LUA_MODULE")"

echo "=== Fetching Overture building footprints ==="
python3 "$ROOT_DIR/scripts/fetch_overture_buildings.py" || echo "Warning: Overture fetch failed, continuing with OSM only"

echo "[export_austin_to_lua] Fetching OSM + exporting manifest..."
bash "$ROOT_DIR/scripts/export_austin_from_osm.sh"

echo "[export_austin_to_lua] Converting JSON manifest to Lua module..."
python3 "$ROOT_DIR/scripts/json_manifest_to_lua.py" \
  --json "$OUT_DIR/austin-manifest.json" \
  --module "$LUA_MODULE"

echo "[export_austin_to_lua] Done. Lua module written to $LUA_MODULE"

