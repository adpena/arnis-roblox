#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "run_all_checks.py"
LUAU_SOURCE_ROOTS = [
    ROOT / "roblox" / "src" / "ReplicatedStorage",
    ROOT / "roblox" / "src" / "ServerScriptService",
    ROOT / "roblox" / "src" / "StarterPlayer",
]


def load_module():
    spec = importlib.util.spec_from_file_location("run_all_checks", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RunAllChecksTests(unittest.TestCase):
    def test_main_runs_python_luau_rust_and_fuzz_checks_when_tools_exist(self) -> None:
        module = load_module()
        calls: list[list[str]] = []

        def fake_run(cmd: list[str]) -> int:
            calls.append(cmd)
            return 0

        def fake_which(name: str) -> str | None:
            return {
                "cargo": "/usr/bin/cargo",
                "selene": "/usr/local/bin/selene",
                "stylua": "/usr/local/bin/stylua",
            }.get(name)

        original_run = module.run
        original_which = module.shutil.which
        module.run = fake_run
        module.shutil.which = fake_which
        try:
            exit_code = module.main()
        finally:
            module.run = original_run
            module.shutil.which = original_which

        self.assertEqual(exit_code, 0)
        self.assertEqual(
            calls,
            [
                [module.sys.executable, str(ROOT / "scripts" / "check_scaffold.py")],
                [
                    module.sys.executable,
                    "-m",
                    "unittest",
                    "discover",
                    "-s",
                    str(ROOT / "scripts" / "tests"),
                    "-p",
                    "test_*.py",
                    "-v",
                ],
                [module.sys.executable, str(ROOT / "scripts" / "verify_generated_austin_assets.py")],
                [module.sys.executable, str(ROOT / "scripts" / "manifest_quality_audit.py")],
                [
                    "/usr/local/bin/selene",
                    "--config",
                    str(ROOT / "roblox" / "selene.toml"),
                    *[str(path) for path in LUAU_SOURCE_ROOTS],
                ],
                [
                    "/usr/local/bin/stylua",
                    "--check",
                    "--config-path",
                    str(ROOT / "roblox" / "stylua.toml"),
                    *[str(path) for path in LUAU_SOURCE_ROOTS],
                ],
                [
                    "/usr/bin/cargo",
                    "test",
                    "--locked",
                    "--manifest-path",
                    str(ROOT / "rust" / "Cargo.toml"),
                ],
                [
                    "/usr/bin/cargo",
                    "fmt",
                    "--manifest-path",
                    str(ROOT / "rust" / "Cargo.toml"),
                    "--all",
                    "--",
                    "--check",
                ],
                [
                    "/usr/bin/cargo",
                    "clippy",
                    "--locked",
                    "--manifest-path",
                    str(ROOT / "rust" / "Cargo.toml"),
                    "--all-targets",
                    "--all-features",
                    "--",
                    "-D",
                    "warnings",
                ],
                [module.sys.executable, str(ROOT / "scripts" / "run_rust_fuzz.py"), "--check-config"],
                [module.sys.executable, str(ROOT / "scripts" / "repo_audit.py"), "--strict"],
            ],
        )

    def test_main_skips_optional_local_tool_checks_when_tools_are_missing(self) -> None:
        module = load_module()
        calls: list[list[str]] = []

        def fake_run(cmd: list[str]) -> int:
            calls.append(cmd)
            return 0

        original_run = module.run
        original_which = module.shutil.which
        module.run = fake_run
        module.shutil.which = lambda _name: None
        output = io.StringIO()
        try:
            with redirect_stdout(output):
                exit_code = module.main()
        finally:
            module.run = original_run
            module.shutil.which = original_which

        self.assertEqual(exit_code, 0)
        self.assertIn("selene not found; skipping Luau lint.", output.getvalue())
        self.assertIn("stylua not found; skipping Luau format check.", output.getvalue())
        self.assertIn("cargo not found; skipping Rust tests/lints and fuzz config check.", output.getvalue())
        self.assertEqual(
            calls,
            [
                [module.sys.executable, str(ROOT / "scripts" / "check_scaffold.py")],
                [
                    module.sys.executable,
                    "-m",
                    "unittest",
                    "discover",
                    "-s",
                    str(ROOT / "scripts" / "tests"),
                    "-p",
                    "test_*.py",
                    "-v",
                ],
                [module.sys.executable, str(ROOT / "scripts" / "verify_generated_austin_assets.py")],
                [module.sys.executable, str(ROOT / "scripts" / "manifest_quality_audit.py")],
                [module.sys.executable, str(ROOT / "scripts" / "repo_audit.py"), "--strict"],
            ],
        )


if __name__ == "__main__":
    unittest.main()
