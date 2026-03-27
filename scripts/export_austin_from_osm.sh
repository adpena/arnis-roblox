#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper to:
#  1) Fetch real OSM data for an Austin bbox via Overpass
#  2) Run the full Rust pipeline + exporter
#
# Usage (from repo root):
#   bash scripts/export_austin_from_osm.sh
#   bash scripts/export_austin_from_osm.sh --yolo
#   bash scripts/export_austin_from_osm.sh --profile high --satellite
#
# Default behavior:
#   Uses a default bounded dev profile unless explicit fidelity arguments are supplied.
#   Override with AUSTIN_EXPORT_DEFAULT_PROFILE=fast|balanced|high|insane.
#
# Outputs:
#   rust/data/austin_overpass.json
#   rust/out/austin-manifest.json
#   rust/out/austin-manifest.sqlite

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
DATA_DIR="$RUST_DIR/data"
OUT_DIR="$RUST_DIR/out"
DEFAULT_PROFILE="${AUSTIN_EXPORT_DEFAULT_PROFILE:-balanced}"

mkdir -p "$DATA_DIR" "$OUT_DIR"

compile_args=()
explicit_profile=0
for arg in "$@"; do
  case "$arg" in
    "--profile"|"--yolo"|"--terrain-cell-size")
      explicit_profile=1
      ;;
  esac
done

if [[ $explicit_profile -eq 0 && -n "$DEFAULT_PROFILE" ]]; then
  echo "[export_austin_from_osm] using default dev fixture profile: $DEFAULT_PROFILE"
  compile_args=("--profile" "$DEFAULT_PROFILE")
else
  echo "[export_austin_from_osm] using explicit compile fidelity arguments"
fi

compile_args+=("$@")

echo "[export_austin_from_osm] Fetching OSM data via Overpass..."
python3 "$ROOT_DIR/scripts/fetch_osm_overpass.py" \
  --bbox "30.245,-97.765,30.305,-97.715" \
  --out "$DATA_DIR/austin_overpass.json"

echo "[export_austin_from_osm] Running full pipeline + exporter..."
cd "$RUST_DIR"
cargo run -p arbx_cli -- compile \
  --source "data/austin_overpass.json" \
  --bbox "30.245,-97.765,30.305,-97.715" \
  "${compile_args[@]}" \
  --out "out/austin-manifest.json" \
  --sqlite-out "out/austin-manifest.sqlite"

echo "[export_austin_from_osm] Done. Manifest written to rust/out/austin-manifest.json and rust/out/austin-manifest.sqlite"
