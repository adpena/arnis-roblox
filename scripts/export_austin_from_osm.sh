#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper to:
#  1) Fetch real OSM data for an Austin bbox via Overpass
#  2) Run the full Rust pipeline + exporter
#
# Usage (from repo root):
#   bash scripts/export_austin_from_osm.sh
#
# Outputs:
#   rust/data/austin_overpass.json
#   rust/out/austin-manifest.json

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
DATA_DIR="$RUST_DIR/data"
OUT_DIR="$RUST_DIR/out"

mkdir -p "$DATA_DIR" "$OUT_DIR"

echo "[export_austin_from_osm] Fetching OSM data via Overpass..."
python3 "$ROOT_DIR/scripts/fetch_osm_overpass.py" \
  --bbox "30.245,-97.765,30.305,-97.715" \
  --out "$DATA_DIR/austin_overpass.json"

echo "[export_austin_from_osm] Running full pipeline + exporter..."
cd "$RUST_DIR"
cargo run -p arbx_cli -- compile \
  --source "data/austin_overpass.json" \
  --bbox "30.245,-97.765,30.305,-97.715" \
  --out "out/austin-manifest.json"

echo "[export_austin_from_osm] Done. Manifest written to rust/out/austin-manifest.json"

