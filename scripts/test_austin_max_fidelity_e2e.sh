#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLACE_PATH="${1:-}"

if [[ -z "$PLACE_PATH" ]]; then
  echo "[test_austin_max_fidelity_e2e] No place path supplied; building a fresh max-fidelity Austin place first..."
  bash "$ROOT_DIR/scripts/build_austin_max_fidelity_place.sh"
  PLACE_PATH="$(ls -1t "$ROOT_DIR"/exports/austin-max-fidelity-*.rbxlx | head -n 1)"
fi

if [[ -z "$PLACE_PATH" || ! -f "$PLACE_PATH" ]]; then
  echo "[test_austin_max_fidelity_e2e] place file not found: $PLACE_PATH" >&2
  exit 1
fi

echo "[test_austin_max_fidelity_e2e] Running Studio harness against $PLACE_PATH"
bash "$ROOT_DIR/scripts/run_studio_harness.sh" \
  --takeover \
  --hard-restart \
  --no-play \
  --edit-wait 35 \
  --pattern-wait 120 \
  --place "$PLACE_PATH"
