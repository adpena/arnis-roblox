import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SHARD_DIR = ROOT / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
PROJECT_FILE = ROOT / "roblox" / "default.project.json"
MAX_LUA_SOURCE_LENGTH = 199_999


class PreviewManifestShardTests(unittest.TestCase):
    def test_preview_shards_fit_vertigo_sync_source_limit(self) -> None:
        shard_paths = sorted(SHARD_DIR.glob("AustinPreviewManifestIndex_003*.lua"))
        self.assertTrue(shard_paths, "expected split preview shard modules to exist")

        oversized = []
        for path in shard_paths:
            size = path.stat().st_size
            if size >= MAX_LUA_SOURCE_LENGTH:
                oversized.append((path.name, size))

        self.assertEqual(
            oversized,
            [],
            f"expected preview shard modules to stay under VertigoSync's Lua source limit: {oversized}",
        )

    def test_vertigo_sync_ignores_hd_sample_data(self) -> None:
        project = json.loads(PROJECT_FILE.read_text())
        ignore_paths = set(project.get("globIgnorePaths", []))
        self.assertIn(
            "src/ServerStorage/SampleData/AustinHDManifestIndex.lua",
            ignore_paths,
        )
        self.assertIn(
            "src/ServerStorage/SampleData/AustinHDManifestChunks/**",
            ignore_paths,
        )


if __name__ == "__main__":
    unittest.main()
