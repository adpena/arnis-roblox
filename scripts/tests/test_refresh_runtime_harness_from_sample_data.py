from __future__ import annotations

import importlib.util
import json
import sqlite3
import sys
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "refresh_runtime_harness_from_sample_data.py"


def load_module():
    scripts_dir = str(MODULE_PATH.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    spec = importlib.util.spec_from_file_location("refresh_runtime_harness_from_sample_data", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RefreshRuntimeHarnessFromSampleDataTests(unittest.TestCase):
    def test_runtime_harness_radius_stays_bounded_for_dev_play(self) -> None:
        module = load_module()
        self.assertEqual(module.RUNTIME_HARNESS_LOAD_RADIUS_STUDS, 896)

    def test_select_runtime_harness_anchor_prefers_low_hazard_chunk(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            source_sqlite = temp_root / "austin-manifest.sqlite"
            connection = sqlite3.connect(source_sqlite)
            try:
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
                        singleton_id, schema_version, world_name, generator, source, meters_per_stud,
                        chunk_size_studs, bbox_min_lat, bbox_min_lon, bbox_max_lat, bbox_max_lon,
                        total_features, notes_json
                    ) VALUES (1, '0.4.0', 'AustinHarnessRuntime', 'test', 'test', 1.0, 256,
                              0, 0, 1, 1, 6, '[]')
                    """
                )

                dense_chunk = {
                    "id": "0_0",
                    "originStuds": {"x": 0, "y": 0, "z": 0},
                    "roads": [{"kind": "service", "points": [{"x": 0, "y": 0, "z": 0}, {"x": 64, "y": 0, "z": 0}]}],
                    "buildings": [
                        {
                            "id": "dense_a",
                            "usage": "apartments",
                            "footprint": [
                                {"x": 20, "z": -10},
                                {"x": 80, "z": -10},
                                {"x": 80, "z": 50},
                                {"x": 20, "z": 50},
                            ],
                        },
                        {
                            "id": "dense_roof",
                            "usage": "roof",
                            "footprint": [
                                {"x": -20, "z": -20},
                                {"x": 100, "z": -20},
                                {"x": 100, "z": 20},
                                {"x": -20, "z": 20},
                            ],
                        },
                    ],
                }
                open_chunk = {
                    "id": "2_0",
                    "originStuds": {"x": 512, "y": 0, "z": 0},
                    "roads": [{"kind": "service", "points": [{"x": 0, "y": 0, "z": 0}, {"x": 64, "y": 0, "z": 0}]}],
                    "buildings": [],
                }
                for chunk_id, origin_x, chunk in (
                    ("0_0", 0, dense_chunk),
                    ("2_0", 512, open_chunk),
                ):
                    connection.execute(
                        """
                        INSERT INTO manifest_chunks (
                            chunk_id, origin_x, origin_y, origin_z, feature_count, streaming_cost,
                            partition_version, subplans_json, chunk_json
                        ) VALUES (?, ?, 0, 0, 3, 12, 'subplans.v1', '[]', ?)
                        """,
                        (chunk_id, origin_x, json.dumps(chunk)),
                    )
                connection.commit()
            finally:
                connection.close()

            selected_chunk_ids, anchor_position = module.select_runtime_harness_seed_chunk_ids(source_sqlite)

            self.assertEqual(selected_chunk_ids, ["2_0"])
            self.assertAlmostEqual(anchor_position[0], 544.0, places=3)
            self.assertAlmostEqual(anchor_position[2], 0.0, places=3)

    def test_main_writes_bounded_runtime_harness_manifest(self) -> None:
        module = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            source_index = temp_root / "AustinManifestIndex.lua"
            source_json = temp_root / "austin-manifest.json"
            harness_dir = temp_root / "SampleData"
            harness_index = harness_dir / "AustinHarnessManifestIndex.lua"
            harness_shards = harness_dir / "AustinHarnessManifestChunks"

            source_index.write_text(
                "\n".join(
                    [
                        'return {schemaVersion="0.4.0",meta={chunkSizeStuds=256},chunkRefs={',
                        '{id="-1_-1",originStuds={x=-256,y=1,z=-256},featureCount=2,streamingCost=10,shards={"AustinManifestIndex_001"}},',
                        '{id="0_-1",originStuds={x=0,y=2,z=-256},featureCount=2,streamingCost=10,shards={"AustinManifestIndex_002"}},',
                        '{id="-1_0",originStuds={x=-256,y=3,z=0},featureCount=2,streamingCost=10,shards={"AustinManifestIndex_003"}},',
                        '{id="0_0",originStuds={x=0,y=4,z=0},featureCount=3,streamingCost=12,partitionVersion="subplans.v1",subplans={{id="terrain",layer="terrain",featureCount=1,streamingCost=8}},shards={"AustinManifestIndex_004"}},',
                        "}}",
                    ]
                ),
                encoding="utf-8",
            )
            source_json.write_text(
                '{"schemaVersion":"0.4.0","chunks":['
                '{"id":"-1_-1","originStuds":{"x":-256,"y":1,"z":-256},"roads":[{"points":[{"x":0,"y":0,"z":0},{"x":32,"y":0,"z":0}],"kind":"residential"}]},'
                '{"id":"0_-1","originStuds":{"x":0,"y":2,"z":-256},"roads":[{"points":[{"x":0,"y":0,"z":0},{"x":32,"y":0,"z":0}],"kind":"residential"}]},'
                '{"id":"-1_0","originStuds":{"x":-256,"y":3,"z":0},"roads":[{"points":[{"x":0,"y":0,"z":0},{"x":32,"y":0,"z":0}],"kind":"residential"}]},'
                '{"id":"0_0","originStuds":{"x":0,"y":4,"z":0},"terrain":{"cellSizeStuds":4,"width":2,"depth":2,"heights":[0,0,0,0],"materials":["Grass","Grass","Grass","Grass"]},"roads":[{"points":[{"x":0,"y":0,"z":0},{"x":32,"y":0,"z":0}],"kind":"residential"}]}'
                "]}",
                encoding="utf-8",
            )

            original_source_index = module.SOURCE_INDEX
            original_source_json = module.SOURCE_JSON
            original_runtime_dir = module.RUNTIME_HARNESS_DIR
            original_runtime_index = module.RUNTIME_HARNESS_INDEX
            original_runtime_shards = module.RUNTIME_HARNESS_SHARDS
            try:
                module.SOURCE_INDEX = source_index
                module.SOURCE_JSON = source_json
                module.RUNTIME_HARNESS_DIR = harness_dir
                module.RUNTIME_HARNESS_INDEX = harness_index
                module.RUNTIME_HARNESS_SHARDS = harness_shards
                exit_code = module.main()
            finally:
                module.SOURCE_INDEX = original_source_index
                module.SOURCE_JSON = original_source_json
                module.RUNTIME_HARNESS_DIR = original_runtime_dir
                module.RUNTIME_HARNESS_INDEX = original_runtime_index
                module.RUNTIME_HARNESS_SHARDS = original_runtime_shards

            self.assertEqual(exit_code, 0)
            written = harness_index.read_text(encoding="utf-8")
            self.assertIn('worldName = "AustinHarnessRuntime"', written)
            self.assertIn('shardFolder = "AustinHarnessManifestChunks"', written)
            self.assertIn("totalFeatures = 9", written)
            self.assertIn('partitionVersion = "subplans.v1"', written)
            self.assertIn("positionStuds =", written)
            self.assertNotIn("positionOffsetFromHeuristicStuds =", written)
            self.assertTrue(harness_shards.exists())
            self.assertGreaterEqual(len(list(harness_shards.glob("*.lua"))), 1)


if __name__ == "__main__":
    unittest.main()
