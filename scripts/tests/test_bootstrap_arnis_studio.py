from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = ROOT / "scripts" / "bootstrap_arnis_studio.py"


def load_bootstrap_module():
    if not SCRIPT_PATH.exists():
        raise AssertionError(f"bootstrap script missing: {SCRIPT_PATH}")
    spec = importlib.util.spec_from_file_location("bootstrap_arnis_studio", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {SCRIPT_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BootstrapArnisStudioTests(unittest.TestCase):
    def test_help_mentions_supported_bootstrap_workflow(self) -> None:
        if not SCRIPT_PATH.exists():
            self.fail(f"bootstrap script missing: {SCRIPT_PATH}")

        result = subprocess.run(
            ["python3", str(SCRIPT_PATH), "--help"],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("default.project.json", result.stdout)
        self.assertIn("--open", result.stdout)
        self.assertIn("--roblox-root", result.stdout)

    def test_build_place_uses_default_project_and_repo_out_dir(self) -> None:
        module = load_bootstrap_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "custom.rbxlx"
            run = mock.Mock()
            module.build_place("vsync-bin", module.ROBLOX_DIR, output_path, run_command=run)

        run.assert_called_once_with(
            [
                "vsync-bin",
                "--root",
                str(module.ROBLOX_DIR),
                "build",
                "--project",
                "default.project.json",
                "--output",
                str(output_path),
            ],
            check=True,
        )

    def test_build_place_accepts_custom_project_name_and_roblox_root(self) -> None:
        module = load_bootstrap_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            roblox_root = Path(temp_dir) / "roblox-copy"
            output_path = Path(temp_dir) / "custom.rbxlx"
            run = mock.Mock()
            module.build_place(
                "vsync-bin",
                roblox_root,
                output_path,
                project_name="isolated.project.json",
                run_command=run,
            )

        run.assert_called_once_with(
            [
                "vsync-bin",
                "--root",
                str(roblox_root),
                "build",
                "--project",
                "isolated.project.json",
                "--output",
                str(output_path),
            ],
            check=True,
        )

    def test_default_output_path_lives_under_roblox_out(self) -> None:
        module = load_bootstrap_module()

        self.assertEqual(
            module.DEFAULT_OUTPUT_PLACE,
            module.ROBLOX_DIR / "out" / "arnis-test-clean.rbxlx",
        )

    def test_custom_output_path_is_accepted_for_export_copy(self) -> None:
        module = load_bootstrap_module()
        custom_output = ROOT / "exports" / "austin-max-fidelity-test.rbxlx"
        run = mock.Mock()

        module.build_place("vsync-bin", module.ROBLOX_DIR, custom_output, run_command=run)

        run.assert_called_once_with(
            [
                "vsync-bin",
                "--root",
                str(module.ROBLOX_DIR),
                "build",
                "--project",
                "default.project.json",
                "--output",
                str(custom_output),
            ],
            check=True,
        )


if __name__ == "__main__":
    unittest.main()
