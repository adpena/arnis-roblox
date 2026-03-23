from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "bootstrap_vsync_place.py"


def load_module():
    scripts_dir = str(MODULE_PATH.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    spec = importlib.util.spec_from_file_location("bootstrap_vsync_place", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BootstrapVsyncPlaceTests(unittest.TestCase):
    def test_script_exists(self) -> None:
        self.assertTrue(MODULE_PATH.is_file(), f"missing bootstrap script at {MODULE_PATH}")

    def test_default_plan_targets_repo_project_and_clean_place(self) -> None:
        module = load_module()
        plan = module.build_bootstrap_plan(ROOT, open_studio=False)
        self.assertEqual(plan.project_path, ROOT / "roblox" / "default.project.json")
        self.assertEqual(plan.output_place_path, ROOT / "roblox" / "out" / "arnis-test-clean.rbxlx")
        self.assertIn("vsync serve --project default.project.json", plan.next_steps)

    def test_build_command_uses_vsync_build_project_output(self) -> None:
        module = load_module()
        plan = module.build_bootstrap_plan(ROOT, open_studio=False)
        command = module.build_place_command(plan, "/tmp/vsync")
        self.assertEqual(
            command,
            [
                "/tmp/vsync",
                "--root",
                str(ROOT / "roblox"),
                "build",
                "--project",
                "default.project.json",
                "--output",
                "out/arnis-test-clean.rbxlx",
            ],
        )

    def test_serve_command_uses_vsync_serve_project(self) -> None:
        module = load_module()
        plan = module.build_bootstrap_plan(ROOT, open_studio=False)
        command = module.build_serve_command(plan, "/tmp/vsync")
        self.assertEqual(
            command,
            [
                "/tmp/vsync",
                "serve",
                "--project",
                "default.project.json",
            ],
        )


if __name__ == "__main__":
    unittest.main()
