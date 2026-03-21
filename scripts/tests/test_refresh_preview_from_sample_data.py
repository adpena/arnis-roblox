from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "refresh_preview_from_sample_data.py"


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


if __name__ == "__main__":
    unittest.main()
