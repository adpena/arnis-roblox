#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPT = ROOT / "scripts" / "build_austin_max_fidelity_place.sh"
E2E_SCRIPT = ROOT / "scripts" / "test_austin_max_fidelity_e2e.sh"
RUNNER_SCRIPT = ROOT / "scripts" / "run_austin_fidelity.sh"
EXPORT_FROM_OSM_SCRIPT = ROOT / "scripts" / "export_austin_from_osm.sh"
EXPORT_TO_LUA_SCRIPT = ROOT / "scripts" / "export_austin_to_lua.sh"


class AustinFidelityScriptTests(unittest.TestCase):
    def test_export_from_osm_defaults_to_bounded_dev_profile_and_allows_override(self) -> None:
        text = EXPORT_FROM_OSM_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('DEFAULT_PROFILE="${AUSTIN_EXPORT_DEFAULT_PROFILE:-balanced}"', text)
        self.assertIn("explicit_profile=0", text)
        self.assertIn('"--profile"|"--yolo"|"--terrain-cell-size")', text)
        self.assertIn('compile_args=("--profile" "$DEFAULT_PROFILE")', text)
        self.assertIn('compile_args+=("$@")', text)
        self.assertIn('using default dev fixture profile: $DEFAULT_PROFILE', text)
        self.assertIn('using explicit compile fidelity arguments', text)

    def test_export_to_lua_documents_bounded_dev_profile_default(self) -> None:
        text = EXPORT_TO_LUA_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("default bounded dev profile", text)
        self.assertIn('bash scripts/export_austin_to_lua.sh --profile high --satellite', text)
        self.assertIn('bash "$ROOT_DIR/scripts/export_austin_from_osm.sh" "$@"', text)

    def test_build_script_refreshes_stable_latest_export_copy(self) -> None:
        text = BUILD_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('LATEST_PLACE="$EXPORT_DIR/austin-max-fidelity-latest.rbxlx"', text)
        self.assertIn('TEMP_WORKSPACE="$(mktemp -d', text)
        self.assertIn('cleanup() {', text)
        self.assertIn('rsync -a --exclude "target" --exclude "out" "$ROOT_DIR/rust/" "$TEMP_WORKSPACE/rust/"', text)
        self.assertIn('rsync -a --exclude "out" "$ROOT_DIR/roblox/" "$TEMP_WORKSPACE/roblox/"', text)
        self.assertIn('bash "$TEMP_WORKSPACE/scripts/export_austin_to_lua.sh" --profile high --satellite', text)
        self.assertIn('python3 "$ROOT_DIR/scripts/bootstrap_arnis_studio.py" --roblox-root "$TEMP_WORKSPACE/roblox" --output "$OUTPUT_PLACE"', text)
        self.assertIn('cp "$OUTPUT_PLACE" "$LATEST_PLACE"', text)
        self.assertIn('echo "[build_austin_max_fidelity_place] Refreshed stable latest copy at $LATEST_PLACE"', text)
        self.assertIn("standard fidelity", text)
        self.assertNotIn("--yolo", text)

    def test_e2e_script_accepts_report_dir_and_defaults_to_stable_latest_place(self) -> None:
        text = E2E_SCRIPT.read_text(encoding="utf-8")

        self.assertIn('PLACE_PATH="$ROOT_DIR/exports/austin-max-fidelity-latest.rbxlx"', text)
        self.assertIn("PLACE_PATH_CUSTOM=0", text)
        self.assertIn('REPORT_DIR=""', text)
        self.assertIn("--report-dir)", text)
        self.assertIn("PLACE_PATH_CUSTOM=1", text)
        self.assertIn('if [[ $PLACE_PATH_CUSTOM -eq 0 && ! -f "$PLACE_PATH" ]]; then', text)
        self.assertIn('export ARNIS_SCENE_AUDIT_DIR="$REPORT_DIR"', text)
        self.assertIn('--skip-edit-tests', text)
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
