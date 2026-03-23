#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "run_rust_fuzz.py"


def load_module():
    spec = importlib.util.spec_from_file_location("run_rust_fuzz", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RunRustFuzzTests(unittest.TestCase):
    def test_discover_targets_lists_fuzz_target_stems(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp_dir:
            fuzz_dir = Path(tmp_dir)
            targets_dir = fuzz_dir / "fuzz_targets"
            targets_dir.mkdir()
            (targets_dir / "overpass_json.rs").write_text("// target")
            (targets_dir / "export_features.rs").write_text("// target")

            targets = module.discover_targets(fuzz_dir)

        self.assertEqual(targets, ["export_features", "overpass_json"])

    def test_main_check_config_succeeds_for_valid_layout(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp_dir:
            fuzz_dir = Path(tmp_dir)
            (fuzz_dir / "Cargo.toml").write_text("[package]\nname = 'arbx_fuzz'\n")
            targets_dir = fuzz_dir / "fuzz_targets"
            targets_dir.mkdir()
            (targets_dir / "subplan_chunk_ref.rs").write_text("// target")

            exit_code = module.main(["--fuzz-dir", str(fuzz_dir), "--check-config"])

        self.assertEqual(exit_code, 0)

    def test_main_smoke_build_requires_cargo(self) -> None:
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp_dir:
            fuzz_dir = Path(tmp_dir)
            (fuzz_dir / "Cargo.toml").write_text("[package]\nname = 'arbx_fuzz'\n")
            targets_dir = fuzz_dir / "fuzz_targets"
            targets_dir.mkdir()
            (targets_dir / "subplan_chunk_ref.rs").write_text("// target")

            original_which = module.shutil.which
            module.shutil.which = lambda _name: None
            output = io.StringIO()
            try:
                with redirect_stdout(output):
                    exit_code = module.main(["--fuzz-dir", str(fuzz_dir), "--smoke-build"])
            finally:
                module.shutil.which = original_which

        self.assertEqual(exit_code, 1)
        self.assertIn("cargo is required for fuzz smoke builds.", output.getvalue())


if __name__ == "__main__":
    unittest.main()
