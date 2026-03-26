from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _import_generator_module():
    scripts_dir = str(ROOT / "scripts")
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    import generate_harness_projects

    return generate_harness_projects


class GenerateHarnessProjectsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.tmp_path = Path(self.tmpdir.name)
        self.default_project_path = self.tmp_path / "default.project.json"
        self.build_project_path = self.tmp_path / ".harness.build.project.json"
        self.serve_project_path = self.tmp_path / ".harness.serve.project.json"
        self.default_project_path.write_text(
            json.dumps(
                {
                    "name": "ArnisRoblox",
                    "globIgnorePaths": [
                        "**/*.md",
                        "**/.DS_Store",
                        "src/ServerStorage/SampleData/AustinHDManifestIndex.lua",
                        "src/ServerStorage/SampleData/AustinHDManifestChunks/**",
                    ],
                    "vertigoSync": {"editPreview": {"enabled": True}},
                }
            ),
            encoding="utf-8",
        )

    def test_edit_build_ignores_runtime_sample_data_but_keeps_preview_fixture(self) -> None:
        module = _import_generator_module()

        module.generate_harness_projects(
            default_project=self.default_project_path,
            build_project=self.build_project_path,
            serve_project=self.serve_project_path,
            include_runtime_sample_data=False,
        )

        build_data = json.loads(self.build_project_path.read_text(encoding="utf-8"))
        ignores = set(build_data["globIgnorePaths"])

        self.assertIn("src/ServerStorage/SampleData/AustinManifestIndex.lua", ignores)
        self.assertIn("src/ServerStorage/SampleData/AustinManifestChunks/**", ignores)
        self.assertNotIn("src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua", ignores)
        self.assertNotIn("src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/**", ignores)
        self.assertNotIn("vertigoSync", build_data)

    def test_play_build_keeps_runtime_sample_data_visible(self) -> None:
        module = _import_generator_module()

        module.generate_harness_projects(
            default_project=self.default_project_path,
            build_project=self.build_project_path,
            serve_project=self.serve_project_path,
            include_runtime_sample_data=True,
        )

        build_data = json.loads(self.build_project_path.read_text(encoding="utf-8"))
        ignores = set(build_data["globIgnorePaths"])

        self.assertNotIn("src/ServerStorage/SampleData/AustinManifestIndex.lua", ignores)
        self.assertNotIn("src/ServerStorage/SampleData/AustinManifestChunks/**", ignores)
        self.assertNotIn("src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua", ignores)
        self.assertNotIn("src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/**", ignores)

    def test_serve_project_always_ignores_compiled_fixture_trees(self) -> None:
        module = _import_generator_module()

        module.generate_harness_projects(
            default_project=self.default_project_path,
            build_project=self.build_project_path,
            serve_project=self.serve_project_path,
            include_runtime_sample_data=False,
        )

        serve_data = json.loads(self.serve_project_path.read_text(encoding="utf-8"))
        ignores = set(serve_data["globIgnorePaths"])

        self.assertIn("src/ServerStorage/SampleData/AustinManifestIndex.lua", ignores)
        self.assertIn("src/ServerStorage/SampleData/AustinManifestChunks/**", ignores)
        self.assertIn("src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua", ignores)
        self.assertIn("src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/**", ignores)


if __name__ == "__main__":
    unittest.main()
