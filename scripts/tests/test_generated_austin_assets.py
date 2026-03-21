from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "verify_generated_austin_assets.py"


def load_module():
    spec = importlib.util.spec_from_file_location("verify_generated_austin_assets", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GeneratedAustinAssetsVerifierTests(unittest.TestCase):
    def test_parse_preview_chunk_refs_accepts_streaming_metadata(self) -> None:
        verifier = load_module()
        chunk_refs = verifier._parse_preview_chunk_refs(
            "\n".join(
                [
                    "return {",
                    "    chunkRefs = {",
                    '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, streamingCost = 62, shards = { "AustinPreviewManifestIndex_001", "AustinPreviewManifestIndex_002" } },',
                    "    },",
                    "}",
                    "",
                ]
            )
        )

        self.assertEqual(
            chunk_refs,
            {"0_0": ["AustinPreviewManifestIndex_001", "AustinPreviewManifestIndex_002"]},
        )

    def test_collect_errors_rejects_subplans_without_partition_version(self) -> None:
        verifier = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            preview_dir = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
            preview_index = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestIndex.lua"

            preview_dir.mkdir(parents=True, exist_ok=True)

            preview_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        "    chunkCount = 1,",
                        "    fragmentCount = 1,",
                        "    chunkRefs = {",
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0 } }, shards = { "AustinPreviewManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (preview_dir / "AustinPreviewManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            errors = verifier.collect_errors(root)

            self.assertTrue(
                any("partitionVersion" in error for error in errors),
                f"expected missing partitionVersion error, got {errors}",
            )

    def test_collect_errors_rejects_malformed_subplan_tables(self) -> None:
        verifier = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            preview_dir = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
            preview_index = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestIndex.lua"

            preview_dir.mkdir(parents=True, exist_ok=True)

            preview_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        "    chunkCount = 1,",
                        "    fragmentCount = 1,",
                        "    chunkRefs = {",
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, partitionVersion = "subplans.v1", subplans = { "not-a-table" }, shards = { "AustinPreviewManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (preview_dir / "AustinPreviewManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            errors = verifier.collect_errors(root)

            self.assertTrue(
                any("subplan" in error for error in errors),
                f"expected malformed subplan error, got {errors}",
            )

    def test_collect_errors_rejects_malformed_runtime_subplan_tables(self) -> None:
        verifier = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            runtime_dir = root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestChunks"
            preview_dir = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
            runtime_index = root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestIndex.lua"
            preview_index = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestIndex.lua"

            runtime_dir.mkdir(parents=True, exist_ok=True)
            preview_dir.mkdir(parents=True, exist_ok=True)

            runtime_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        '    shardFolder = "AustinManifestChunks",',
                        '    shards = { "AustinManifestIndex_001" },',
                        "    chunkRefs = {",
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, partitionVersion = "subplans.v1", subplans = { "not-a-table" }, shards = { "AustinManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (runtime_dir / "AustinManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            preview_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        "    chunkCount = 4,",
                        "    fragmentCount = 1,",
                        "    chunkRefs = {",
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (preview_dir / "AustinPreviewManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            errors = verifier.collect_errors(root)

            self.assertTrue(
                any("malformed subplan" in error for error in errors),
                f"expected runtime malformed subplan error, got {errors}",
            )

    def test_collect_errors_reports_missing_chunk_scheduling_metadata(self) -> None:
        verifier = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            runtime_dir = root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestChunks"
            preview_dir = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
            runtime_index = root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestIndex.lua"
            preview_index = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestIndex.lua"

            runtime_dir.mkdir(parents=True, exist_ok=True)
            preview_dir.mkdir(parents=True, exist_ok=True)

            runtime_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        '    shardFolder = "AustinManifestChunks",',
                        '    shards = { "AustinManifestIndex_001" },',
                        "    chunkRefs = {",
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (runtime_dir / "AustinManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            preview_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        "    chunkCount = 4,",
                        "    fragmentCount = 1,",
                        "    chunkRefs = {",
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (preview_dir / "AustinPreviewManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            errors = verifier.collect_errors(root)

            self.assertTrue(
                any("runtime index is missing chunk scheduling metadata" in error for error in errors),
                f"expected runtime metadata error, got {errors}",
            )
            self.assertTrue(
                any("preview index is missing chunk scheduling metadata" in error for error in errors),
                f"expected preview metadata error, got {errors}",
            )

    def test_collect_errors_accepts_current_repo_state(self) -> None:
        verifier = load_module()
        errors = verifier.collect_errors(ROOT)
        self.assertEqual(errors, [], f"expected generated Austin assets to verify cleanly: {errors}")

    def test_collect_errors_reports_stale_fields_and_missing_preview_shards(self) -> None:
        verifier = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            sample_dir = root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestChunks"
            preview_dir = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
            preview_index = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestIndex.lua"

            sample_dir.mkdir(parents=True, exist_ok=True)
            preview_dir.mkdir(parents=True, exist_ok=True)

            (sample_dir / "AustinManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",rooms={},facadeStyle="forced"}}}\n',
                encoding="utf-8",
            )
            preview_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        "    chunkRefs = {",
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            errors = verifier.collect_errors(root)

            self.assertTrue(
                any("stale synthetic rooms/facade styling" in error for error in errors),
                f"expected stale-field error, got {errors}",
            )
            self.assertTrue(
                any("missing preview shard modules" in error for error in errors),
                f"expected missing preview shard error, got {errors}",
            )

    def test_collect_errors_reports_unreferenced_runtime_shards(self) -> None:
        verifier = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            runtime_dir = root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestChunks"
            preview_dir = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
            runtime_index = root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestIndex.lua"
            preview_index = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestIndex.lua"

            runtime_dir.mkdir(parents=True, exist_ok=True)
            preview_dir.mkdir(parents=True, exist_ok=True)

            runtime_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        '    shardFolder = "AustinManifestChunks",',
                        '    shards = { "AustinManifestIndex_001" },',
                        "    chunkRefs = {",
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (runtime_dir / "AustinManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )
            (runtime_dir / "AustinManifestIndex_999.lua").write_text(
                'return {chunks={{id="stale",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            preview_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        "    chunkCount = 4,",
                        "    fragmentCount = 1,",
                        "    chunkRefs = {",
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, shards = { "AustinPreviewManifestIndex_001" } },',
                        "    },",
                        "}",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (preview_dir / "AustinPreviewManifestIndex_001.lua").write_text(
                'return {chunks={{id="0_0",originStuds={x=0,y=0,z=0}}}}\n',
                encoding="utf-8",
            )

            errors = verifier.collect_errors(root)

            self.assertTrue(
                any("unreferenced runtime shard modules" in error for error in errors),
                f"expected unreferenced runtime shard error, got {errors}",
            )


if __name__ == "__main__":
    unittest.main()
