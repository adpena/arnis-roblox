from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "verify_generated_austin_assets.py"
GENERATOR_SCRIPT = ROOT / "scripts" / "json_manifest_to_sharded_lua.py"


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

    def test_collect_errors_accepts_generator_emitted_runtime_chunk_refs_with_subplans(self) -> None:
        verifier = load_module()
        manifest = {
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "VerifierIntegrationTest",
                "generator": "test",
                "source": "test",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256,
                "bbox": {"minLat": 0, "minLon": 0, "maxLat": 1, "maxLon": 1},
            },
            "chunkRefs": [
                {
                    "id": "0_0",
                    "partitionVersion": "subplans.v1",
                    "subplans": [
                        {
                            "id": "terrain",
                            "layer": "terrain",
                            "featureCount": 1,
                            "streamingCost": 40.0,
                        }
                    ],
                }
            ],
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": {"x": 0, "y": 0, "z": 0},
                    "roads": [{}],
                }
            ],
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            runtime_output_dir = root / "roblox" / "src" / "ServerStorage" / "SampleData"
            preview_dir = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestChunks"
            preview_index = root / "roblox" / "src" / "ServerScriptService" / "StudioPreview" / "AustinPreviewManifestIndex.lua"
            manifest_path = root / "manifest.json"

            runtime_output_dir.mkdir(parents=True, exist_ok=True)
            preview_dir.mkdir(parents=True, exist_ok=True)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            subprocess.run(
                [
                    "python3",
                    str(GENERATOR_SCRIPT),
                    "--json",
                    str(manifest_path),
                    "--output-dir",
                    str(runtime_output_dir),
                    "--index-name",
                    "AustinManifestIndex",
                    "--shard-folder",
                    "AustinManifestChunks",
                ],
                check=True,
                cwd=ROOT,
            )

            preview_index.write_text(
                "\n".join(
                    [
                        "return {",
                        '    schemaVersion = "0.4.0",',
                        "    chunkCount = 4,",
                        "    fragmentCount = 1,",
                        "    chunkRefs = {",
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, streamingCost = 62, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 10, streamingCost = 20, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 9, streamingCost = 18, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 8, streamingCost = 16, shards = { "AustinPreviewManifestIndex_001" } },',
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

            self.assertEqual(errors, [], f"expected generator-emitted runtime chunkRefs to verify cleanly, got {errors}")

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

    def test_collect_errors_rejects_partial_preview_chunk_scheduling_metadata(self) -> None:
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
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, streamingCost = 62, shards = { "AustinManifestIndex_001" } },',
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
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 10, streamingCost = 20, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 9, streamingCost = 18, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 8, streamingCost = 16, shards = { "AustinPreviewManifestIndex_001" } },',
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
                any('chunk -1_-1 is missing streamingCost' in error for error in errors),
                f"expected per-chunk preview scheduling metadata error, got {errors}",
            )

    def test_collect_errors_rejects_partial_runtime_chunk_scheduling_metadata(self) -> None:
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
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, shards = { "AustinManifestIndex_001" } },',
                        '        { id = "1_0", originStuds = { x = 256, y = 0, z = 0 }, featureCount = 8, streamingCost = 16, shards = { "AustinManifestIndex_001" } },',
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
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, streamingCost = 62, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 10, streamingCost = 20, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 9, streamingCost = 18, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 8, streamingCost = 16, shards = { "AustinPreviewManifestIndex_001" } },',
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
                any('runtime chunk 0_0 is missing streamingCost' in error for error in errors),
                f"expected per-chunk runtime scheduling metadata error, got {errors}",
            )

    def test_collect_errors_rejects_malformed_subplan_bounds_shape(self) -> None:
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
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, streamingCost = 62, partitionVersion = "subplans.v1", subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0, bounds = { minX = 0, maxX = 128, maxY = 128 } } }, shards = { "AustinPreviewManifestIndex_001" } },',
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
                any("bounds" in error for error in errors),
                f"expected malformed bounds error, got {errors}",
            )

    def test_collect_errors_rejects_malformed_subplan_field_types(self) -> None:
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
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, streamingCost = 62, partitionVersion = "subplans.v1", subplans = { { id = { value = "terrain" }, layer = "terrain", featureCount = "many", streamingCost = "fast" } }, shards = { "AustinPreviewManifestIndex_001" } },',
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
                any("subplan" in error and ("id" in error or "featureCount" in error or "streamingCost" in error) for error in errors),
                f"expected malformed subplan field type error, got {errors}",
            )

    def test_collect_errors_accepts_subplans_without_top_level_aggregate_hints(self) -> None:
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
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, partitionVersion = "subplans.v1", subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0 } }, shards = { "AustinManifestIndex_001" } },',
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
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, partitionVersion = "subplans.v1", subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0 } }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, partitionVersion = "subplans.v1", subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0 } }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, partitionVersion = "subplans.v1", subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0 } }, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, partitionVersion = "subplans.v1", subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0 } }, shards = { "AustinPreviewManifestIndex_001" } },',
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

            self.assertEqual(errors, [], f"expected subplans to make top-level aggregate hints optional, got {errors}")

    def test_collect_errors_rejects_malformed_optional_aggregate_hints_with_subplans(self) -> None:
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
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = "many", partitionVersion = "subplans.v1", subplans = { { id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0 } }, shards = { "AustinManifestIndex_001" } },',
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
                        '        { id = "-1_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 13, streamingCost = 62, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_-1", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 10, streamingCost = 20, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "-1_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 9, streamingCost = 18, shards = { "AustinPreviewManifestIndex_001" } },',
                        '        { id = "0_0", originStuds = { x = 0, y = 0, z = 0 }, featureCount = 8, streamingCost = 16, shards = { "AustinPreviewManifestIndex_001" } },',
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
                any("runtime chunk 0_0 has malformed featureCount" in error for error in errors),
                f"expected malformed optional aggregate hint error, got {errors}",
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
                any("runtime chunk 0_0 is missing featureCount" in error for error in errors),
                f"expected runtime metadata error, got {errors}",
            )
            self.assertTrue(
                any("preview chunk -1_-1 is missing featureCount" in error for error in errors),
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
