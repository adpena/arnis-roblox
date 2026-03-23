#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPT = ROOT / "scripts" / "build_austin_max_fidelity_place.sh"
E2E_SCRIPT = ROOT / "scripts" / "test_austin_max_fidelity_e2e.sh"
RUNNER_SCRIPT = ROOT / "scripts" / "run_austin_fidelity.sh"


class AustinFidelityScriptTests(unittest.TestCase):
    def test_build_script_refreshes_stable_latest_export_copy(self) -> None:
        text = BUILD_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('LATEST_PLACE="$EXPORT_DIR/austin-max-fidelity-latest.rbxlx"', text)
        self.assertIn('cp "$OUTPUT_PLACE" "$LATEST_PLACE"', text)
        self.assertIn('echo "[build_austin_max_fidelity_place] Refreshed stable latest copy at $LATEST_PLACE"', text)

    def test_e2e_script_accepts_report_dir_and_defaults_to_stable_latest_place(self) -> None:
        text = E2E_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('PLACE_PATH="$ROOT_DIR/exports/austin-max-fidelity-latest.rbxlx"', text)
        self.assertIn("PLACE_PATH_CUSTOM=0", text)
        self.assertIn('REPORT_DIR=""', text)
        self.assertIn("--report-dir)", text)
        self.assertIn("PLACE_PATH_CUSTOM=1", text)
        self.assertIn('if [[ $PLACE_PATH_CUSTOM -eq 0 && ! -f "$PLACE_PATH" ]]; then', text)
        self.assertIn('export ARNIS_SCENE_AUDIT_DIR="$REPORT_DIR"', text)
        self.assertNotIn("--no-play", text)
        self.assertNotIn('ls -1t "$ROOT_DIR"/exports/austin-max-fidelity-*.rbxlx | head -n 1', text)

    def test_runner_script_exists_and_writes_stable_report_dir(self) -> None:
        self.assertTrue(RUNNER_SCRIPT.is_file(), f"missing Austin fidelity runner at {RUNNER_SCRIPT}")
        text = RUNNER_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('PLACE_PATH="$ROOT_DIR/exports/austin-max-fidelity-latest.rbxlx"', text)
        self.assertIn("PLACE_PATH_CUSTOM=0", text)
        self.assertIn('REPORT_DIR="$ROOT_DIR/out/austin-fidelity/latest"', text)
        self.assertIn("PLACE_PATH_CUSTOM=1", text)
        self.assertIn('if [[ $FORCE_REBUILD -eq 1 && $PLACE_PATH_CUSTOM -eq 1 ]]; then', text)
        self.assertIn('bash "$ROOT_DIR/scripts/build_austin_max_fidelity_place.sh"', text)
        self.assertIn('bash "$ROOT_DIR/scripts/test_austin_max_fidelity_e2e.sh"', text)
        self.assertIn('--report-dir "$REPORT_DIR"', text)


if __name__ == "__main__":
    unittest.main()
