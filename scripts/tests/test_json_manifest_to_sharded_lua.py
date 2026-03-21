from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "json_manifest_to_sharded_lua.py"


class JsonManifestToShardedLuaTests(unittest.TestCase):
    def test_chunk_refs_include_streaming_metadata(self) -> None:
        manifest = {
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "StreamingMetaTest",
                "generator": "test",
                "source": "test",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256,
                "bbox": {"minLat": 0, "minLon": 0, "maxLat": 1, "maxLon": 1},
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": {"x": 0, "y": 0, "z": 0},
                    "terrain": {"cellSizeStuds": 4, "width": 1, "depth": 1, "heights": [0], "material": "Grass"},
                    "roads": [{}, {}],
                    "rails": [{}],
                    "buildings": [{}, {}],
                    "water": [{}],
                    "props": [{}, {}, {}],
                    "landuse": [{}, {}],
                    "barriers": [{}],
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
                    str(SCRIPT),
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

            index_text = (out_dir / "TestManifestIndex.lua").read_text(encoding="utf-8")
            self.assertIn("featureCount=13", index_text)
            self.assertIn("streamingCost=62", index_text)

    def test_chunk_refs_include_partition_version_and_subplans(self) -> None:
        manifest = {
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SubplanMetaTest",
                "generator": "test",
                "source": "test",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256,
                "bbox": {"minLat": 0, "minLon": 0, "maxLat": 1, "maxLon": 1},
            },
            "chunkRefs": [
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
                            "bounds": {"minX": 0, "minY": 0, "maxX": 128, "maxY": 128},
                        },
                        {
                            "id": "roads",
                            "layer": "roads",
                            "featureCount": 2,
                            "streamingCost": 4.5,
                        },
                    ],
                }
            ],
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": {"x": 0, "y": 0, "z": 0},
                    "roads": [{}, {}],
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
                    str(SCRIPT),
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

            index_text = (out_dir / "TestManifestIndex.lua").read_text(encoding="utf-8")
            self.assertIn('partitionVersion="subplans.v1"', index_text)
            self.assertIn('subplans={{id="terrain",layer="terrain"', index_text)
            self.assertIn('featureCount=1,streamingCost=40.0,bounds={minX=0,minY=0,maxX=128,maxY=128}', index_text)
            self.assertIn('{id="roads",layer="roads",featureCount=2,streamingCost=4.5}', index_text)

    def test_chunk_refs_do_not_derive_top_level_counts_when_subplans_exist(self) -> None:
        manifest = {
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SubplanFallbackTest",
                "generator": "test",
                "source": "test",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256,
                "bbox": {"minLat": 0, "minLon": 0, "maxLat": 1, "maxLon": 1},
            },
            "chunkRefs": [
                {
                    "id": "0_0",
                    "originStuds": {"x": 0, "y": 0, "z": 0},
                    "partitionVersion": "subplans.v1",
                    "subplans": [
                        {
                            "id": "terrain",
                            "layer": "terrain",
                            "featureCount": 7,
                            "streamingCost": 40.0,
                        },
                        {
                            "id": "roads",
                            "layer": "roads",
                            "featureCount": 8,
                            "streamingCost": 4.5,
                        },
                    ],
                }
            ],
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": {"x": 0, "y": 0, "z": 0},
                    "roads": [{}],
                    "buildings": [{}],
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
                    str(SCRIPT),
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

            index_text = (out_dir / "TestManifestIndex.lua").read_text(encoding="utf-8")
            self.assertIn('partitionVersion="subplans.v1"', index_text)
            self.assertIn('subplans={{id="terrain",layer="terrain",featureCount=7,streamingCost=40.0}', index_text)
            self.assertNotIn("featureCount=2", index_text)
            self.assertNotIn("streamingCost=16", index_text)

    def test_chunk_level_subplan_fields_are_ignored_without_index_chunk_ref_metadata(self) -> None:
        manifest = {
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "BoundaryTest",
                "generator": "test",
                "source": "test",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256,
                "bbox": {"minLat": 0, "minLon": 0, "maxLat": 1, "maxLon": 1},
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": {"x": 0, "y": 0, "z": 0},
                    "partitionVersion": "subplans.v1",
                    "subplans": [
                        {
                            "id": "roads",
                            "layer": "roads",
                            "featureCount": 2,
                            "streamingCost": 4.5,
                        }
                    ],
                    "roads": [{}, {}],
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
                    str(SCRIPT),
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

            index_text = (out_dir / "TestManifestIndex.lua").read_text(encoding="utf-8")
            shard_text = (out_dir / "TestManifestChunks" / "TestManifestIndex_001.lua").read_text(encoding="utf-8")
            self.assertNotIn('partitionVersion="subplans.v1"', index_text)
            self.assertNotIn("subplans={{", index_text)
            self.assertIn("featureCount=2", index_text)
            self.assertIn("streamingCost=8", index_text)
            self.assertNotIn('partitionVersion="subplans.v1"', shard_text)
            self.assertNotIn("subplans={{", shard_text)


if __name__ == "__main__":
    unittest.main()
