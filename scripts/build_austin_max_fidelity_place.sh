#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="$ROOT_DIR/exports"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_PLACE="$EXPORT_DIR/austin-max-fidelity-${STAMP}.rbxlx"
LATEST_PLACE="$EXPORT_DIR/austin-max-fidelity-latest.rbxlx"
TEMP_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/arnis-austin-max-fidelity.XXXXXX")"

mkdir -p "$EXPORT_DIR"

cleanup() {
  rm -rf "$TEMP_WORKSPACE"
}
trap cleanup EXIT

mkdir -p "$TEMP_WORKSPACE/scripts" "$TEMP_WORKSPACE/rust" "$TEMP_WORKSPACE/roblox"
rsync -a "$ROOT_DIR/scripts/" "$TEMP_WORKSPACE/scripts/"
rsync -a --exclude "target" --exclude "out" "$ROOT_DIR/rust/" "$TEMP_WORKSPACE/rust/"
rsync -a --exclude "out" "$ROOT_DIR/roblox/" "$TEMP_WORKSPACE/roblox/"

echo "[build_austin_max_fidelity_place] Exporting Austin manifest/shards with standard fidelity..."
bash "$TEMP_WORKSPACE/scripts/export_austin_to_lua.sh" --profile high --satellite

echo "[build_austin_max_fidelity_place] Building clean place to $OUTPUT_PLACE"
python3 "$ROOT_DIR/scripts/bootstrap_arnis_studio.py" --roblox-root "$TEMP_WORKSPACE/roblox" --output "$OUTPUT_PLACE"
cp "$OUTPUT_PLACE" "$LATEST_PLACE"
echo "[build_austin_max_fidelity_place] Refreshed stable latest copy at $LATEST_PLACE"

echo "[build_austin_max_fidelity_place] Done: $OUTPUT_PLACE"
