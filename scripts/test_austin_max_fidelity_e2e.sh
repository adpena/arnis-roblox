#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLACE_PATH="$ROOT_DIR/exports/austin-max-fidelity-latest.rbxlx"
PLACE_PATH_CUSTOM=0
REPORT_DIR=""

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
    *)
      if [[ -z "$PLACE_PATH" || "$PLACE_PATH" == "$ROOT_DIR/exports/austin-max-fidelity-latest.rbxlx" ]]; then
        PLACE_PATH="$1"
        PLACE_PATH_CUSTOM=1
        shift
      else
        echo "[test_austin_max_fidelity_e2e] unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ $PLACE_PATH_CUSTOM -eq 0 && ! -f "$PLACE_PATH" ]]; then
  echo "[test_austin_max_fidelity_e2e] No place path supplied; building a fresh max-fidelity Austin place first..."
  bash "$ROOT_DIR/scripts/build_austin_max_fidelity_place.sh"
fi

if [[ -z "$PLACE_PATH" || ! -f "$PLACE_PATH" ]]; then
  echo "[test_austin_max_fidelity_e2e] place file not found: $PLACE_PATH" >&2
  exit 1
fi

if [[ -n "$REPORT_DIR" ]]; then
  mkdir -p "$REPORT_DIR"
  export ARNIS_SCENE_AUDIT_DIR="$REPORT_DIR"
fi

echo "[test_austin_max_fidelity_e2e] Running Studio harness against $PLACE_PATH"
bash "$ROOT_DIR/scripts/run_studio_harness.sh" \
  --takeover \
  --hard-restart \
  --skip-edit-tests \
  --edit-wait 35 \
  --pattern-wait 120 \
  --place "$PLACE_PATH"
