from __future__ import annotations

import importlib.util
import json
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
from unittest import mock


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

    def test_derive_preview_chunk_ids_expands_seed_chunks_to_preview_radius_with_gutter(self) -> None:
        module = load_module()
        chunk_refs = {
            "-1_-1": {"x": "-256", "y": "0", "z": "-256", "shards": ["s1"]},
            "0_-1": {"x": "0", "y": "0", "z": "-256", "shards": ["s2"]},
            "-1_0": {"x": "-256", "y": "0", "z": "0", "shards": ["s3"]},
            "0_0": {"x": "0", "y": "0", "z": "0", "shards": ["s4"]},
            "4_1": {"x": "1024", "y": "0", "z": "256", "shards": ["s5"]},
            "5_0": {"x": "1280", "y": "0", "z": "0", "shards": ["s6"]},
        }

        selected = module.derive_preview_chunk_ids(chunk_refs, chunk_size_studs=256)

        self.assertIn("4_1", selected)
        self.assertNotIn("5_0", selected)
        for chunk_id in module.TARGET_CHUNK_IDS:
            self.assertIn(chunk_id, selected)

    def test_parse_source_chunk_size_studs_uses_meta_value_when_present(self) -> None:
        module = load_module()

        chunk_size = module.parse_source_chunk_size_studs(
            'return {schemaVersion="0.4.0",meta={chunkSizeStuds=512},chunkRefs={}}'
        )

        self.assertEqual(chunk_size, 512.0)

    def test_write_preview_index_emits_streaming_metadata(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            preview_index = Path(temp_dir) / "AustinPreviewManifestIndex.lua"
            original_preview_index = module.PREVIEW_INDEX
            module.PREVIEW_INDEX = preview_index
            try:
                module.write_preview_index(
                    "0.4.0",
                    13,
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
                    canonical_anchor_position=(10.5, 20.25, -30.75),
                    chunk_size_studs=256,
                )
            finally:
                module.PREVIEW_INDEX = original_preview_index

            written = preview_index.read_text(encoding="utf-8")
            self.assertIn("featureCount = 13", written)
            self.assertIn("streamingCost = 62", written)
            self.assertIn("positionStuds = { x = 10.5, y = 20.25, z = -30.75 }", written)

    def test_write_preview_index_emits_total_features_sum(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            preview_index = Path(temp_dir) / "AustinPreviewManifestIndex.lua"
            original_preview_index = module.PREVIEW_INDEX
            module.PREVIEW_INDEX = preview_index
            try:
                module.write_preview_index(
                    "0.4.0",
                    91,
                    [
                        (
                            "-1_-1",
                            {
                                "x": "-256",
                                "y": "1",
                                "z": "-256",
                                "featureCount": "53",
                                "streamingCost": "222",
                                "shards": ["AustinPreviewManifestIndex_001"],
                            },
                        ),
                        (
                            "0_-1",
                            {
                                "x": "0",
                                "y": "2",
                                "z": "-256",
                                "featureCount": "38",
                                "streamingCost": "147",
                                "shards": ["AustinPreviewManifestIndex_002"],
                            },
                        ),
                    ],
                    ["AustinPreviewManifestIndex_001", "AustinPreviewManifestIndex_002"],
                    canonical_anchor_position=(0, 0, -192),
                    chunk_size_studs=256,
                )
            finally:
                module.PREVIEW_INDEX = original_preview_index

            written = preview_index.read_text(encoding="utf-8")
            self.assertIn("totalFeatures = 91", written)

    def test_write_preview_index_emits_partition_version_and_subplans(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            preview_index = Path(temp_dir) / "AustinPreviewManifestIndex.lua"
            original_preview_index = module.PREVIEW_INDEX
            module.PREVIEW_INDEX = preview_index
            try:
                module.write_preview_index(
                    "0.4.0",
                    13,
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
                    canonical_anchor_position=(0, 0, -192),
                    chunk_size_studs=256,
                )
            finally:
                module.PREVIEW_INDEX = original_preview_index

            written = preview_index.read_text(encoding="utf-8")
            self.assertIn('partitionVersion = "subplans.v1"', written)
            self.assertIn('subplans = {', written)
            self.assertIn('id = "terrain"', written)
            self.assertIn('bounds = { minX = 0, minY = 0, maxX = 128, maxY = 128 }', written)
            self.assertIn('id = "roads"', written)

    def test_clone_chunk_ref_entries_deep_copies_shard_lists(self) -> None:
        module = load_module()

        original = [("0_0", {"shards": ["AustinPreviewManifestIndex_001"], "featureCount": "1"})]
        cloned = module.clone_chunk_ref_entries(original)
        cloned[0][1]["shards"].append("AustinCanonicalManifestIndex_001")

        self.assertEqual(original[0][1]["shards"], ["AustinPreviewManifestIndex_001"])
        self.assertEqual(
            cloned[0][1]["shards"],
            ["AustinPreviewManifestIndex_001", "AustinCanonicalManifestIndex_001"],
        )

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
            canonical_dir = temp_root / "SampleData"
            canonical_index = canonical_dir / "AustinCanonicalManifestIndex.lua"
            canonical_shards = canonical_dir / "AustinCanonicalManifestChunks"

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
            original_canonical_sample_data_dir = module.CANONICAL_SAMPLE_DATA_DIR
            original_canonical_index = module.CANONICAL_INDEX
            original_canonical_shards = module.CANONICAL_SHARDS
            original_max_preview_bytes = module.MAX_PREVIEW_BYTES
            module.SOURCE_INDEX = source_index
            module.SOURCE_JSON = source_json
            module.PREVIEW_DIR = preview_dir
            module.PREVIEW_INDEX = preview_index
            module.PREVIEW_SHARDS = preview_shards
            module.CANONICAL_SAMPLE_DATA_DIR = canonical_dir
            module.CANONICAL_INDEX = canonical_index
            module.CANONICAL_SHARDS = canonical_shards
            module.MAX_PREVIEW_BYTES = 50_000
            try:
                exit_code = module.main()
            finally:
                module.SOURCE_INDEX = original_source_index
                module.SOURCE_JSON = original_source_json
                module.PREVIEW_DIR = original_preview_dir
                module.PREVIEW_INDEX = original_preview_index
                module.PREVIEW_SHARDS = original_preview_shards
                module.CANONICAL_SAMPLE_DATA_DIR = original_canonical_sample_data_dir
                module.CANONICAL_INDEX = original_canonical_index
                module.CANONICAL_SHARDS = original_canonical_shards
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
            canonical_dir = temp_root / "SampleData"
            canonical_index = canonical_dir / "AustinCanonicalManifestIndex.lua"
            canonical_shards = canonical_dir / "AustinCanonicalManifestChunks"

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
            original_canonical_sample_data_dir = module.CANONICAL_SAMPLE_DATA_DIR
            original_canonical_index = module.CANONICAL_INDEX
            original_canonical_shards = module.CANONICAL_SHARDS
            original_max_preview_bytes = module.MAX_PREVIEW_BYTES
            module.SOURCE_INDEX = source_index
            module.SOURCE_JSON = source_json
            module.PREVIEW_DIR = preview_dir
            module.PREVIEW_INDEX = preview_index
            module.PREVIEW_SHARDS = preview_shards
            module.CANONICAL_SAMPLE_DATA_DIR = canonical_dir
            module.CANONICAL_INDEX = canonical_index
            module.CANONICAL_SHARDS = canonical_shards
            module.MAX_PREVIEW_BYTES = 50_000
            try:
                exit_code = module.main()
            finally:
                module.SOURCE_INDEX = original_source_index
                module.SOURCE_JSON = original_source_json
                module.PREVIEW_DIR = original_preview_dir
                module.PREVIEW_INDEX = original_preview_index
                module.PREVIEW_SHARDS = original_preview_shards
                module.CANONICAL_SAMPLE_DATA_DIR = original_canonical_sample_data_dir
                module.CANONICAL_INDEX = original_canonical_index
                module.CANONICAL_SHARDS = original_canonical_shards
                module.MAX_PREVIEW_BYTES = original_max_preview_bytes

            self.assertEqual(exit_code, 0)
            written = preview_index.read_text(encoding="utf-8")
            self.assertIn('schemaVersion = "0.5.0"', written)
            self.assertNotIn('schemaVersion = "0.4.0"', written)

    def test_main_streams_source_manifest_without_reading_entire_file(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            source_index = temp_root / "AustinManifestIndex.lua"
            source_json = temp_root / "austin-manifest.json"
            preview_dir = temp_root / "StudioPreview"
            preview_index = preview_dir / "AustinPreviewManifestIndex.lua"
            preview_shards = preview_dir / "AustinPreviewManifestChunks"
            canonical_dir = temp_root / "SampleData"
            canonical_index = canonical_dir / "AustinCanonicalManifestIndex.lua"
            canonical_shards = canonical_dir / "AustinCanonicalManifestChunks"

            source_index.write_text(
                "\n".join(
                    [
                        'return {schemaVersion="0.4.0",chunkRefs={',
                        '{id="-1_-1",originStuds={x=-256,y=1,z=-256},featureCount=1,streamingCost=8,shards={"AustinManifestIndex_001"}},',
                        '{id="0_-1",originStuds={x=0,y=2,z=-256},featureCount=1,streamingCost=8,shards={"AustinManifestIndex_001"}},',
                        '{id="-1_0",originStuds={x=-256,y=3,z=0},featureCount=1,streamingCost=8,shards={"AustinManifestIndex_001"}},',
                        '{id="0_0",originStuds={x=0,y=4,z=0},featureCount=2,streamingCost=12,shards={"AustinManifestIndex_001"}},',
                        "}}",
                    ]
                ),
                encoding="utf-8",
            )
            source_json.write_text(
                '{"schemaVersion":"0.5.0","chunks":['
                '{"id":"-2_-2","originStuds":{"x":-512,"y":0,"z":-512},"roads":[{"id":"ignore_me"}]},'
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
            original_canonical_sample_data_dir = module.CANONICAL_SAMPLE_DATA_DIR
            original_canonical_index = module.CANONICAL_INDEX
            original_canonical_shards = module.CANONICAL_SHARDS
            original_max_preview_bytes = module.MAX_PREVIEW_BYTES
            module.SOURCE_INDEX = source_index
            module.SOURCE_JSON = source_json
            module.PREVIEW_DIR = preview_dir
            module.PREVIEW_INDEX = preview_index
            module.PREVIEW_SHARDS = preview_shards
            module.CANONICAL_SAMPLE_DATA_DIR = canonical_dir
            module.CANONICAL_INDEX = canonical_index
            module.CANONICAL_SHARDS = canonical_shards
            module.MAX_PREVIEW_BYTES = 50_000

            original_read_text = Path.read_text

            def guarded_read_text(path: Path, *args, **kwargs):
                if path == source_json:
                    raise AssertionError("SOURCE_JSON.read_text should not be used for preview refresh")
                return original_read_text(path, *args, **kwargs)

            try:
                with mock.patch("pathlib.Path.read_text", new=guarded_read_text):
                    exit_code = module.main()
            finally:
                module.SOURCE_INDEX = original_source_index
                module.SOURCE_JSON = original_source_json
                module.PREVIEW_DIR = original_preview_dir
                module.PREVIEW_INDEX = original_preview_index
                module.PREVIEW_SHARDS = original_preview_shards
                module.CANONICAL_SAMPLE_DATA_DIR = original_canonical_sample_data_dir
                module.CANONICAL_INDEX = original_canonical_index
                module.CANONICAL_SHARDS = original_canonical_shards
                module.MAX_PREVIEW_BYTES = original_max_preview_bytes

            self.assertEqual(exit_code, 0)
            written = preview_index.read_text(encoding="utf-8")
            self.assertIn('schemaVersion = "0.5.0"', written)
            self.assertIn("originStuds = { x = 0, y = 4, z = 0 }", written)

    def test_load_source_manifest_subset_prefers_sqlite_store_when_present(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            source_json = temp_root / "austin-manifest.json"
            source_sqlite = temp_root / "austin-manifest.sqlite"

            source_json.write_text("{ this is not valid json", encoding="utf-8")

            connection = sqlite3.connect(source_sqlite)
            connection.executescript(
                """
                CREATE TABLE manifest_meta (
                    singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
                    schema_version TEXT NOT NULL,
                    world_name TEXT NOT NULL,
                    generator TEXT NOT NULL,
                    source TEXT NOT NULL,
                    meters_per_stud REAL NOT NULL,
                    chunk_size_studs INTEGER NOT NULL,
                    bbox_min_lat REAL NOT NULL,
                    bbox_min_lon REAL NOT NULL,
                    bbox_max_lat REAL NOT NULL,
                    bbox_max_lon REAL NOT NULL,
                    total_features INTEGER NOT NULL,
                    notes_json TEXT NOT NULL
                );
                CREATE TABLE manifest_chunks (
                    chunk_id TEXT PRIMARY KEY,
                    origin_x REAL NOT NULL,
                    origin_y REAL NOT NULL,
                    origin_z REAL NOT NULL,
                    feature_count INTEGER NOT NULL,
                    streaming_cost REAL NOT NULL,
                    partition_version TEXT NOT NULL,
                    subplans_json TEXT NOT NULL,
                    chunk_json TEXT NOT NULL
                );
                """
            )
            connection.execute(
                """
                INSERT INTO manifest_meta (
                    singleton_id, schema_version, world_name, generator, source,
                    meters_per_stud, chunk_size_studs,
                    bbox_min_lat, bbox_min_lon, bbox_max_lat, bbox_max_lon,
                    total_features, notes_json
                ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "0.5.0",
                    "SqliteManifest",
                    "test",
                    "test",
                    0.3,
                    256,
                    0.0,
                    0.0,
                    1.0,
                    1.0,
                    5,
                    '["sqlite-first"]',
                ),
            )
            for chunk_id, origin_y in (("-1_-1", 1.0), ("0_-1", 2.0), ("-1_0", 3.0), ("0_0", 4.0)):
                connection.execute(
                    """
                    INSERT INTO manifest_chunks (
                        chunk_id, origin_x, origin_y, origin_z,
                        feature_count, streaming_cost, partition_version,
                        subplans_json, chunk_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        chunk_id,
                        0.0,
                        origin_y,
                        0.0,
                        1,
                        8.0,
                        "subplans.v1",
                        "[]",
                        json.dumps({"id": chunk_id, "originStuds": {"x": 0, "y": origin_y, "z": 0}, "roads": []}),
                    ),
                )
            connection.commit()
            connection.close()

            schema_version, source_chunks = module.load_source_manifest_subset(
                source_json,
                module.TARGET_CHUNK_IDS,
                source_sqlite=source_sqlite,
            )

            self.assertEqual(schema_version, "0.5.0")
            self.assertEqual(set(source_chunks.keys()), set(module.TARGET_CHUNK_IDS))
            self.assertEqual(source_chunks["0_0"]["originStuds"]["y"], 4.0)


if __name__ == "__main__":
    unittest.main()
