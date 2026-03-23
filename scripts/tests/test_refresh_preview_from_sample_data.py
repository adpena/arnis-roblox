from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "refresh_preview_from_sample_data.py"
GENERATOR_SCRIPT = ROOT / "scripts" / "json_manifest_to_sharded_lua.py"


def load_module():
    scripts_dir = str(MODULE_PATH.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    spec = importlib.util.spec_from_file_location("refresh_preview_from_sample_data", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RefreshPreviewFromSampleDataTests(unittest.TestCase):
    def test_parse_source_index_preserves_streaming_metadata(self) -> None:
        module = load_module()
        schema, chunk_refs = module.parse_source_index(
            '\n'.join(
                [
                    'return {schemaVersion="0.4.0",chunkRefs={',
                    '{id="0_0",originStuds={x=0,y=1,z=2},featureCount=13,streamingCost=62,shards={"AustinManifestIndex_001","AustinManifestIndex_002"}},',
                    "}}",
                ]
            )
        )

        self.assertEqual(schema, "0.4.0")
        self.assertEqual(chunk_refs["0_0"]["x"], "0")
        self.assertEqual(chunk_refs["0_0"]["y"], "1")
        self.assertEqual(chunk_refs["0_0"]["z"], "2")
        self.assertEqual(chunk_refs["0_0"]["featureCount"], "13")
        self.assertEqual(chunk_refs["0_0"]["streamingCost"], "62")
        self.assertEqual(
            chunk_refs["0_0"]["shards"],
            ["AustinManifestIndex_001", "AustinManifestIndex_002"],
        )

    def test_parse_source_index_preserves_partition_version_and_subplans(self) -> None:
        module = load_module()
        schema, chunk_refs = module.parse_source_index(
            "\n".join(
                [
                    "return {schemaVersion=\"0.4.0\",chunkRefs={",
                    '{id="0_0",originStuds={x=0,y=1,z=2},partitionVersion="subplans.v1",subplans={{id="terrain",layer="terrain",featureCount=1,streamingCost=40.0,bounds={minX=0,minY=0,maxX=128,maxY=128}},{id="roads",layer="roads",featureCount=2,streamingCost=4.5}},featureCount=13,streamingCost=62,shards={"AustinManifestIndex_001","AustinManifestIndex_002"}},',
                    "}}",
                ]
            )
        )

        self.assertEqual(schema, "0.4.0")
        self.assertEqual(chunk_refs["0_0"]["partitionVersion"], "subplans.v1")
        self.assertEqual(
            chunk_refs["0_0"]["subplans"],
            [
                {
                    "id": "terrain",
                    "layer": "terrain",
                    "featureCount": "1",
                    "streamingCost": "40.0",
                    "bounds": {"minX": "0", "minY": "0", "maxX": "128", "maxY": "128"},
                },
                {
                    "id": "roads",
                    "layer": "roads",
                    "featureCount": "2",
                    "streamingCost": "4.5",
                },
            ],
        )

    def test_parse_source_index_reads_top_level_totals_not_subplan_counts(self) -> None:
        module = load_module()
        schema, chunk_refs = module.parse_source_index(
            "\n".join(
                [
                    "return {schemaVersion=\"0.4.0\",chunkRefs={",
                    '{id="0_0",originStuds={x=0,y=1,z=2},partitionVersion="subplans.v1",subplans={{id="terrain",layer="terrain",featureCount=1,streamingCost=40.0},{id="roads",layer="roads",featureCount=2,streamingCost=4.5}},featureCount=13,streamingCost=62,shards={"AustinManifestIndex_001","AustinManifestIndex_002"}},',
                    "}}",
                ]
            )
        )

        self.assertEqual(schema, "0.4.0")
        self.assertEqual(chunk_refs["0_0"]["featureCount"], "13")
        self.assertEqual(chunk_refs["0_0"]["streamingCost"], "62")
        self.assertEqual(chunk_refs["0_0"]["subplans"][0]["featureCount"], "1")
        self.assertEqual(chunk_refs["0_0"]["subplans"][0]["streamingCost"], "40.0")

    def test_parse_source_index_accepts_generator_emitted_chunk_refs(self) -> None:
        module = load_module()
        manifest = {
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "PreviewParseIntegrationTest",
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
                    "originStuds": {"x": 0, "y": 1, "z": 2},
                    "roads": [{}],
                }
            ],
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            manifest_path = temp_root / "manifest.json"
            out_dir = temp_root / "out"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            subprocess.run(
                [
                    "python3",
                    str(GENERATOR_SCRIPT),
                    "--json",
                    str(manifest_path),
                    "--output-dir",
                    str(out_dir),
                    "--index-name",
                    "TestManifestIndex",
                    "--shard-folder",
                    "TestManifestChunks",
                ],
                check=True,
                cwd=ROOT,
            )

            schema, chunk_refs = module.parse_source_index(
                (out_dir / "TestManifestIndex.lua").read_text(encoding="utf-8")
            )

        self.assertEqual(schema, "0.4.0")
        self.assertEqual(chunk_refs["0_0"]["shards"], ["TestManifestIndex_001"])
        self.assertEqual(chunk_refs["0_0"]["partitionVersion"], "subplans.v1")
        self.assertEqual(
            chunk_refs["0_0"]["subplans"],
            [
                {
                    "id": "terrain",
                    "layer": "terrain",
                    "featureCount": "1",
                    "streamingCost": "40.0",
                }
            ],
        )

    def test_write_preview_index_emits_streaming_metadata(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            preview_index = Path(temp_dir) / "AustinPreviewManifestIndex.lua"
            original_preview_index = module.PREVIEW_INDEX
            module.PREVIEW_INDEX = preview_index
            try:
                module.write_preview_index(
                    "0.4.0",
                    [
                        (
                            "0_0",
                            {
                                "x": "0",
                                "y": "1",
                                "z": "2",
                                "featureCount": "13",
                                "streamingCost": "62",
                                "shards": ["AustinPreviewManifestIndex_001"],
                            },
                        )
                    ],
                    ["AustinPreviewManifestIndex_001"],
                )
            finally:
                module.PREVIEW_INDEX = original_preview_index

            written = preview_index.read_text(encoding="utf-8")
            self.assertIn("featureCount = 13", written)
            self.assertIn("streamingCost = 62", written)

    def test_write_preview_index_emits_partition_version_and_subplans(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            preview_index = Path(temp_dir) / "AustinPreviewManifestIndex.lua"
            original_preview_index = module.PREVIEW_INDEX
            module.PREVIEW_INDEX = preview_index
            try:
                module.write_preview_index(
                    "0.4.0",
                    [
                        (
                            "0_0",
                            {
                                "x": "0",
                                "y": "1",
                                "z": "2",
                                "partitionVersion": "subplans.v1",
                                "subplans": [
                                    {
                                        "id": "terrain",
                                        "layer": "terrain",
                                        "featureCount": "1",
                                        "streamingCost": "40.0",
                                        "bounds": {
                                            "minX": "0",
                                            "minY": "0",
                                            "maxX": "128",
                                            "maxY": "128",
                                        },
                                    },
                                    {
                                        "id": "roads",
                                        "layer": "roads",
                                        "featureCount": "2",
                                        "streamingCost": "4.5",
                                    },
                                ],
                                "featureCount": "13",
                                "streamingCost": "62",
                                "shards": ["AustinPreviewManifestIndex_001"],
                            },
                        )
                    ],
                    ["AustinPreviewManifestIndex_001"],
                )
            finally:
                module.PREVIEW_INDEX = original_preview_index

            written = preview_index.read_text(encoding="utf-8")
            self.assertIn('partitionVersion = "subplans.v1"', written)
            self.assertIn('subplans = {', written)
            self.assertIn('id = "terrain"', written)
            self.assertIn('bounds = { minX = 0, minY = 0, maxX = 128, maxY = 128 }', written)
            self.assertIn('id = "roads"', written)

    def test_preview_shard_fragments_strip_index_only_subplan_metadata(self) -> None:
        module = load_module()

        fragments = module.fragment_preview_chunk(
            {
                "id": "0_0",
                "originStuds": {"x": 0, "y": 0, "z": 0},
                "partitionVersion": "subplans.v1",
                "subplans": [
                    {
                        "id": "terrain",
                        "layer": "terrain",
                        "featureCount": 1,
                        "streamingCost": 40.0,
                    }
                ],
                "roads": [{"id": "road_1"}],
            },
            50_000,
        )

        self.assertGreaterEqual(len(fragments), 1)
        self.assertNotIn("partitionVersion", fragments[0])
        self.assertNotIn("subplans", fragments[0])
        self.assertNotIn("partitionVersion", fragments[-1])
        self.assertNotIn("subplans", fragments[-1])

    def test_fragment_preview_chunk_splits_large_terrain_payloads(self) -> None:
        module = load_module()

        heights = list(range(128))
        materials = ["Grass"] * 128
        fragments = module.fragment_preview_chunk(
            {
                "id": "0_0",
                "originStuds": {"x": 0, "y": 0, "z": 0},
                "terrain": {
                    "cellSizeStuds": 4,
                    "width": 16,
                    "depth": 16,
                    "heights": heights,
                    "materials": materials,
                },
            },
            350,
        )

        self.assertGreater(len(fragments), 2)
        self.assertEqual(
            fragments[0]["terrain"],
            {
                "cellSizeStuds": 4,
                "width": 16,
                "depth": 16,
            },
        )

        height_fragments = [fragment["terrain"]["heights"] for fragment in fragments if "heights" in fragment.get("terrain", {})]
        material_fragments = [
            fragment["terrain"]["materials"] for fragment in fragments if "materials" in fragment.get("terrain", {})
        ]

        self.assertGreater(len(height_fragments), 1)
        self.assertGreater(len(material_fragments), 1)
        self.assertEqual([item for fragment in height_fragments for item in fragment], heights)
        self.assertEqual([item for fragment in material_fragments for item in fragment], materials)

    def test_main_keeps_canonical_chunk_origin_when_source_index_is_stale(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            source_index = temp_root / "AustinManifestIndex.lua"
            source_json = temp_root / "austin-manifest.json"
            preview_dir = temp_root / "StudioPreview"
            preview_index = preview_dir / "AustinPreviewManifestIndex.lua"
            preview_shards = preview_dir / "AustinPreviewManifestChunks"

            source_index.write_text(
                "\n".join(
                    [
                        'return {schemaVersion="0.4.0",chunkRefs={',
                        '{id="-1_-1",originStuds={x=999,y=888,z=777},shards={"AustinManifestIndex_001"}},',
                        '{id="0_-1",originStuds={x=999,y=888,z=777},shards={"AustinManifestIndex_001"}},',
                        '{id="-1_0",originStuds={x=999,y=888,z=777},shards={"AustinManifestIndex_001"}},',
                        '{id="0_0",originStuds={x=999,y=888,z=777},partitionVersion="subplans.v1",subplans={{id="terrain",layer="terrain",featureCount=1,streamingCost=40.0}},featureCount=13,streamingCost=62,shards={"AustinManifestIndex_001"}},',
                        "}}",
                    ]
                ),
                encoding="utf-8",
            )
            source_json.write_text(
                '{"schemaVersion":"0.4.0","chunks":['
                '{"id":"-1_-1","originStuds":{"x":-256,"y":1,"z":-256}},'
                '{"id":"0_-1","originStuds":{"x":0,"y":2,"z":-256}},'
                '{"id":"-1_0","originStuds":{"x":-256,"y":3,"z":0}},'
                '{"id":"0_0","originStuds":{"x":0,"y":4,"z":0},"roads":[{"id":"road_1"}]}'
                "]}",
                encoding="utf-8",
            )

            original_source_index = module.SOURCE_INDEX
            original_source_json = module.SOURCE_JSON
            original_preview_dir = module.PREVIEW_DIR
            original_preview_index = module.PREVIEW_INDEX
            original_preview_shards = module.PREVIEW_SHARDS
            original_max_preview_bytes = module.MAX_PREVIEW_BYTES
            module.SOURCE_INDEX = source_index
            module.SOURCE_JSON = source_json
            module.PREVIEW_DIR = preview_dir
            module.PREVIEW_INDEX = preview_index
            module.PREVIEW_SHARDS = preview_shards
            module.MAX_PREVIEW_BYTES = 50_000
            try:
                exit_code = module.main()
            finally:
                module.SOURCE_INDEX = original_source_index
                module.SOURCE_JSON = original_source_json
                module.PREVIEW_DIR = original_preview_dir
                module.PREVIEW_INDEX = original_preview_index
                module.PREVIEW_SHARDS = original_preview_shards
                module.MAX_PREVIEW_BYTES = original_max_preview_bytes

            self.assertEqual(exit_code, 0)
            written = preview_index.read_text(encoding="utf-8")
            self.assertIn("originStuds = { x = 0, y = 4, z = 0 }", written)
            self.assertNotIn("originStuds = { x = 999, y = 888, z = 777 }", written)
            self.assertIn('partitionVersion = "subplans.v1"', written)

    def test_main_uses_schema_version_from_source_json_when_runtime_index_is_stale(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            source_index = temp_root / "AustinManifestIndex.lua"
            source_json = temp_root / "austin-manifest.json"
            preview_dir = temp_root / "StudioPreview"
            preview_index = preview_dir / "AustinPreviewManifestIndex.lua"
            preview_shards = preview_dir / "AustinPreviewManifestChunks"

            source_index.write_text(
                "\n".join(
                    [
                        'return {schemaVersion="0.4.0",chunkRefs={',
                        '{id="-1_-1",originStuds={x=-256,y=1,z=-256},shards={"AustinManifestIndex_001"}},',
                        '{id="0_-1",originStuds={x=0,y=2,z=-256},shards={"AustinManifestIndex_001"}},',
                        '{id="-1_0",originStuds={x=-256,y=3,z=0},shards={"AustinManifestIndex_001"}},',
                        '{id="0_0",originStuds={x=0,y=4,z=0},featureCount=13,streamingCost=62,shards={"AustinManifestIndex_001"}},',
                        "}}",
                    ]
                ),
                encoding="utf-8",
            )
            source_json.write_text(
                '{"schemaVersion":"0.5.0","chunks":['
                '{"id":"-1_-1","originStuds":{"x":-256,"y":1,"z":-256}},'
                '{"id":"0_-1","originStuds":{"x":0,"y":2,"z":-256}},'
                '{"id":"-1_0","originStuds":{"x":-256,"y":3,"z":0}},'
                '{"id":"0_0","originStuds":{"x":0,"y":4,"z":0},"roads":[{"id":"road_1"}]}'
                "]}",
                encoding="utf-8",
            )

            original_source_index = module.SOURCE_INDEX
            original_source_json = module.SOURCE_JSON
            original_preview_dir = module.PREVIEW_DIR
            original_preview_index = module.PREVIEW_INDEX
            original_preview_shards = module.PREVIEW_SHARDS
            original_max_preview_bytes = module.MAX_PREVIEW_BYTES
            module.SOURCE_INDEX = source_index
            module.SOURCE_JSON = source_json
            module.PREVIEW_DIR = preview_dir
            module.PREVIEW_INDEX = preview_index
            module.PREVIEW_SHARDS = preview_shards
            module.MAX_PREVIEW_BYTES = 50_000
            try:
                exit_code = module.main()
            finally:
                module.SOURCE_INDEX = original_source_index
                module.SOURCE_JSON = original_source_json
                module.PREVIEW_DIR = original_preview_dir
                module.PREVIEW_INDEX = original_preview_index
                module.PREVIEW_SHARDS = original_preview_shards
                module.MAX_PREVIEW_BYTES = original_max_preview_bytes

            self.assertEqual(exit_code, 0)
            written = preview_index.read_text(encoding="utf-8")
            self.assertIn('schemaVersion = "0.5.0"', written)
            self.assertNotIn('schemaVersion = "0.4.0"', written)


if __name__ == "__main__":
    unittest.main()
