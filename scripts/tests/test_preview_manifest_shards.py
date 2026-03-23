import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SHARD_DIR = ROOT / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
SAMPLE_DATA_SHARD_DIR = ROOT / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestChunks"
PROJECT_FILE = ROOT / "roblox" / "default.project.json"
MAX_LUA_SOURCE_LENGTH = 199_999
STALE_ROOMS_PATTERN = re.compile(r"\brooms\s*=\s*\{")
STALE_FACADE_PATTERN = re.compile(r"\bfacadeStyle\s*=")


class PreviewManifestShardTests(unittest.TestCase):
    def test_preview_shards_fit_vertigo_sync_source_limit(self) -> None:
        shard_paths = sorted(SHARD_DIR.glob("AustinPreviewManifestIndex_*.lua"))
        self.assertTrue(shard_paths, "expected preview shard modules to exist")

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

    def test_runtime_sample_data_shards_do_not_include_stale_rooms_or_forced_facades(self) -> None:
        shard_paths = sorted(SAMPLE_DATA_SHARD_DIR.glob("AustinManifestIndex_*.lua"))
        self.assertTrue(shard_paths, "expected Austin sample-data shard modules to exist")

        stale_fields = []
        for path in shard_paths:
            text = path.read_text(encoding="utf-8")
            if STALE_ROOMS_PATTERN.search(text) or STALE_FACADE_PATTERN.search(text):
                stale_fields.append(path.name)

        self.assertEqual(
            stale_fields,
            [],
            f"expected Austin sample-data shards to avoid stale synthetic rooms/facade styling: {stale_fields}",
        )

    def test_preview_shards_do_not_include_stale_rooms_or_forced_facades(self) -> None:
        shard_paths = sorted(SHARD_DIR.glob("AustinPreviewManifestIndex_*.lua"))
        self.assertTrue(shard_paths, "expected preview shard modules to exist")

        stale_fields = []
        for path in shard_paths:
            text = path.read_text(encoding="utf-8")
            if STALE_ROOMS_PATTERN.search(text) or STALE_FACADE_PATTERN.search(text):
                stale_fields.append(path.name)

        self.assertEqual(
            stale_fields,
            [],
            f"expected preview shard modules to avoid stale synthetic rooms/facade styling: {stale_fields}",
        )

    def test_preview_shard_folder_does_not_mix_split_and_monolithic_layouts(self) -> None:
        split_paths = sorted(SHARD_DIR.glob("AustinPreviewManifestIndex_*_*.lua"))
        self.assertEqual(
            split_paths,
            [],
            f"expected preview shard folder to contain only one layout, found stale split files: {[path.name for path in split_paths]}",
        )


if __name__ == "__main__":
    unittest.main()
