#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLACE_PATH="$ROOT_DIR/exports/austin-max-fidelity-latest.rbxlx"
PLACE_PATH_CUSTOM=0
REPORT_DIR="$ROOT_DIR/out/austin-fidelity/latest"
FORCE_REBUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --place)
      PLACE_PATH="$2"
      PLACE_PATH_CUSTOM=1
      shift 2
      ;;
    --report-dir)
      REPORT_DIR="$2"
      shift 2
      ;;
    --rebuild)
      FORCE_REBUILD=1
      shift
      ;;
    *)
      echo "[run_austin_fidelity] unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ $FORCE_REBUILD -eq 1 && $PLACE_PATH_CUSTOM -eq 1 ]]; then
  echo "[run_austin_fidelity] --rebuild only supports the default latest export path" >&2
  exit 1
fi

if [[ ($FORCE_REBUILD -eq 1 || ! -f "$PLACE_PATH") && $PLACE_PATH_CUSTOM -eq 0 ]]; then
  bash "$ROOT_DIR/scripts/build_austin_max_fidelity_place.sh"
fi

mkdir -p "$REPORT_DIR"

bash "$ROOT_DIR/scripts/test_austin_max_fidelity_e2e.sh" \
  --place "$PLACE_PATH" \
  --report-dir "$REPORT_DIR"
