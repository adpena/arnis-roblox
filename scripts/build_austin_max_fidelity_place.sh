#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="$ROOT_DIR/exports"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_PLACE="$EXPORT_DIR/austin-max-fidelity-${STAMP}.rbxlx"

mkdir -p "$EXPORT_DIR"

echo "[build_austin_max_fidelity_place] Exporting Austin manifest/shards with YOLO fidelity..."
bash "$ROOT_DIR/scripts/export_austin_to_lua.sh" --yolo

echo "[build_austin_max_fidelity_place] Building clean place to $OUTPUT_PLACE"
python3 "$ROOT_DIR/scripts/bootstrap_arnis_studio.py" --output "$OUTPUT_PLACE"

echo "[build_austin_max_fidelity_place] Done: $OUTPUT_PLACE"
