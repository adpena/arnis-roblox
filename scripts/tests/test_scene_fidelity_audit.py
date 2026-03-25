from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "scene_fidelity_audit.py"


def load_module():
    spec = importlib.util.spec_from_file_location("scene_fidelity_audit", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SceneFidelityAuditTests(unittest.TestCase):
    maxDiff = None

    def test_report_parses_latest_scene_marker_and_flags_missing_geometry(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"
            html_path = root / "scene-report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [
                            {"id": "road_1", "kind": "secondary", "subkind": "sidewalk"},
                            {"id": "road_2", "kind": "secondary", "subkind": "none"},
                        ],
                        "buildings": [
                            {
                                "id": "bldg_1",
                                "usage": "office",
                                "roof": "flat",
                                "material": "Concrete",
                                "roofMaterial": "Slate",
                            },
                            {
                                "id": "bldg_2",
                                "usage": "office",
                                "roof": "flat",
                                "material": "stone",
                                "roofMaterial": "copper",
                            },
                        ],
                        "water": [
                            {
                                "id": "water_poly_1",
                                "kind": "pond",
                                "material": "Water",
                                "type": "polygon",
                                "footprint": [
                                    {"x": 16, "z": 16},
                                    {"x": 48, "z": 16},
                                    {"x": 48, "z": 48},
                                    {"x": 16, "z": 48},
                                ],
                            },
                            {
                                "id": "water_ribbon_1",
                                "kind": "stream",
                                "material": "Water",
                                "points": [{"x": 96, "y": 0, "z": 32}, {"x": 144, "y": 0, "z": 48}],
                                "widthStuds": 8,
                            },
                        ],
                        "props": [
                            {
                                "id": "prop_tree_1",
                                "kind": "tree",
                                "species": "oak",
                                "position": {"x": 60, "y": 0, "z": 60},
                            },
                            {
                                "id": "prop_fountain_1",
                                "kind": "fountain",
                                "position": {"x": 84, "y": 0, "z": 72},
                            },
                        ],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    },
                    {
                        "id": "1_0",
                        "originStuds": {"x": 256, "y": 0, "z": 0},
                        "roads": [{"id": "road_3", "kind": "residential", "subkind": "sidewalk"}],
                        "buildings": [{"id": "bldg_3", "usage": "government", "roof": "gabled"}],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    },
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            stale_payload = {
                "phase": "play",
                "focus": {"x": 64.0, "z": 64.0},
                "radius": 350.0,
                "rootName": "GeneratedWorld_Austin",
                "scene": {
                    "chunkCount": 1,
                    "buildingModelCount": 1,
                    "chunksWithBuildingModels": 1,
                    "roadTaggedPartCount": 1,
                    "chunksWithRoadGeometry": 1,
                },
            }
            live_payload = {
                "phase": "play",
                "focus": {"x": 128.0, "z": 128.0},
                "radius": 400.0,
                "rootName": "GeneratedWorld_Austin",
                "scene": {
                    "chunkCount": 2,
                    "buildingModelCount": 1,
                    "buildingDetailPartCount": 0,
                    "buildingModelsWithRoof": 0,
                    "buildingModelsWithoutRoof": 1,
                    "buildingModelsWithDirectRoof": 0,
                    "buildingModelsWithMergedRoofOnly": 0,
                    "buildingModelsWithNoRoofEvidence": 1,
                    "buildingShellMeshPartCount": 0,
                    "chunksWithBuildingModels": 1,
                    "roadTaggedPartCount": 0,
                    "chunksWithRoadGeometry": 0,
                    "roadSurfacePartCountByKind": {
                        "secondary": {
                            "surfacePartCount": 1,
                            "featureCount": 1,
                            "sourceIds": ["road_1"],
                        }
                    },
                    "roadSurfacePartCountBySubkind": {
                        "sidewalk": {
                            "surfacePartCount": 1,
                            "featureCount": 1,
                            "sourceIds": ["road_1"],
                        }
                    },
                    "buildingRoofCoverageByUsage": {
                        "office": {
                            "buildingModelCount": 1,
                            "withRoofCount": 0,
                            "withoutRoofCount": 1,
                            "directRoofCount": 0,
                            "mergedRoofOnlyCount": 0,
                            "noRoofEvidenceCount": 1,
                        }
                    },
                    "buildingRoofCoverageByShape": {
                        "flat": {
                            "buildingModelCount": 1,
                            "withRoofCount": 0,
                            "withoutRoofCount": 1,
                            "directRoofCount": 0,
                            "mergedRoofOnlyCount": 0,
                            "noRoofEvidenceCount": 1,
                        }
                    },
                    "buildingModelCountByWallMaterial": {
                        "concrete": {"buildingModelCount": 1, "sourceIds": ["bldg_1"]},
                    },
                    "buildingModelCountByRoofMaterial": {
                        "slate": {"buildingModelCount": 1, "sourceIds": ["bldg_1"]},
                    },
                    "waterSurfacePartCount": 1,
                    "waterSurfacePartCountByType": {
                        "polygon": {"surfacePartCount": 1, "sourceIds": ["water_poly_1"]},
                    },
                    "waterSurfacePartCountByKind": {
                        "pond": {"surfacePartCount": 1, "sourceIds": ["water_poly_1"]},
                    },
                    "propInstanceCount": 1,
                    "propInstanceCountByKind": {
                        "tree": {"instanceCount": 1},
                    },
                    "ambientPropInstanceCount": 2,
                    "ambientPropInstanceCountByKind": {
                        "unknown": {"instanceCount": 2},
                    },
                    "treeInstanceCount": 1,
                    "treeInstanceCountBySpecies": {
                        "oak": {"instanceCount": 1},
                    },
                    "vegetationInstanceCount": 1,
                    "vegetationInstanceCountByKind": {
                        "tree": {"instanceCount": 1},
                    },
                    "chunksWithProps": 1,
                    "chunksWithVegetation": 1,
                    "chunksWithAmbientProps": 1,
                    "chunksWithWaterGeometry": 0,
                    "meshPartCount": 0,
                    "basePartCount": 0,
                },
            }
            live_chunks = {
                "phase": "play",
                "rootName": "GeneratedWorld_Austin",
                "chunkIds": ["0_0", "1_0"],
            }
            live_roof_usage = {
                "phase": "play",
                "rootName": "GeneratedWorld_Austin",
                "bucket": "office",
                "stats": live_payload["scene"]["buildingRoofCoverageByUsage"]["office"],
            }
            live_roof_shapes = {
                "phase": "play",
                "rootName": "GeneratedWorld_Austin",
                "buildingRoofCoverageByShape": live_payload["scene"]["buildingRoofCoverageByShape"],
            }
            trailing_scalar = {
                "phase": "play",
                "rootName": "GeneratedWorld_Austin",
                "key": "proceduralTreeInstanceCount",
                "value": 3,
            }
            log_path.write_text(
                "\n".join(
                    [
                        'ARNIS_SCENE_PLAY {"phase":"play","scene":{"buildingModelCount":1,"broken":"unterminated}',
                        "ARNIS_SCENE_PLAY " + json.dumps(stale_payload, separators=(",", ":")),
                        'ARNIS_SCENE_PLAY_ROOF_USAGE_BUCKET {"phase":"play","bucket":"broken"',
                        "other log noise",
                        "ARNIS_SCENE_PLAY_CHUNKS " + json.dumps(live_chunks, separators=(",", ":")),
                        "ARNIS_SCENE_PLAY_ROOF_USAGE_BUCKET "
                        + json.dumps(live_roof_usage, separators=(",", ":")),
                        "ARNIS_SCENE_PLAY_ROOF_SHAPES " + json.dumps(live_roof_shapes, separators=(",", ":")),
                        "ARNIS_SCENE_PLAY " + json.dumps(live_payload, separators=(",", ":")),
                        "ARNIS_SCENE_PLAY_SCALAR " + json.dumps(trailing_scalar, separators=(",", ":")),
                    ]
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_PLAY")
            codes = {finding["code"] for finding in report["findings"]}

            self.assertEqual(report["scene"]["chunkCount"], 2)
            self.assertEqual(report["scene"]["chunkIds"], ["0_0", "1_0"])
            self.assertEqual(report["scene"]["buildingModelCount"], 1)
            self.assertEqual(report["scene"]["buildingModelsWithRoof"], 0)
            self.assertEqual(report["scene"]["buildingModelsWithoutRoof"], 1)
            self.assertEqual(report["scene"]["buildingModelsWithDirectRoof"], 0)
            self.assertEqual(report["scene"]["buildingModelsWithMergedRoofOnly"], 0)
            self.assertEqual(report["scene"]["buildingModelsWithNoRoofEvidence"], 1)
            self.assertEqual(report["scene"]["roadSurfacePartCountByKind"]["secondary"]["surfacePartCount"], 1)
            self.assertEqual(report["scene"]["roadSurfacePartCountBySubkind"]["sidewalk"]["surfacePartCount"], 1)
            self.assertEqual(report["scene"]["buildingRoofCoverageByUsage"]["office"]["withoutRoofCount"], 1)
            self.assertEqual(report["scene"]["buildingRoofCoverageByUsage"]["office"]["noRoofEvidenceCount"], 1)
            self.assertEqual(report["scene"]["buildingRoofCoverageByShape"]["flat"]["withoutRoofCount"], 1)
            self.assertEqual(report["scene"]["buildingRoofCoverageByShape"]["flat"]["noRoofEvidenceCount"], 1)
            self.assertEqual(report["scene"]["waterSurfacePartCount"], 1)
            self.assertEqual(report["scene"]["waterSurfacePartCountByType"]["polygon"]["surfacePartCount"], 1)
            self.assertEqual(report["scene"]["waterSurfacePartCountByKind"]["pond"]["surfacePartCount"], 1)
            self.assertEqual(report["scene"]["propInstanceCount"], 1)
            self.assertEqual(report["scene"]["propInstanceCountByKind"]["tree"]["instanceCount"], 1)
            self.assertEqual(report["scene"]["ambientPropInstanceCount"], 2)
            self.assertEqual(report["scene"]["ambientPropInstanceCountByKind"]["unknown"]["instanceCount"], 2)
            self.assertEqual(report["scene"]["treeInstanceCount"], 1)
            self.assertEqual(report["scene"]["treeInstanceCountBySpecies"]["oak"]["instanceCount"], 1)
            self.assertEqual(report["scene"]["proceduralTreeInstanceCount"], 3)
            self.assertEqual(report["scene"]["vegetationInstanceCount"], 1)
            self.assertEqual(report["scene"]["vegetationInstanceCountByKind"]["tree"]["instanceCount"], 1)
            self.assertEqual(report["manifest"]["buildingCount"], 3)
            self.assertEqual(report["manifest"]["buildingCountByUsage"]["office"], 2)
            self.assertEqual(report["manifest"]["buildingCountByUsage"]["government"], 1)
            self.assertEqual(report["manifest"]["buildingCountByRoofShape"]["flat"], 2)
            self.assertEqual(report["manifest"]["buildingCountByRoofShape"]["gabled"], 1)
            self.assertEqual(report["manifest"]["buildingCountByExplicitWallMaterial"]["concrete"], 1)
            self.assertEqual(report["manifest"]["buildingCountByExplicitWallMaterial"]["cobblestone"], 1)
            self.assertEqual(report["manifest"]["buildingCountByExplicitRoofMaterial"]["slate"], 1)
            self.assertEqual(report["manifest"]["buildingCountByExplicitRoofMaterial"]["metal"], 1)
            self.assertEqual(report["manifest"]["roadCount"], 3)
            self.assertEqual(report["manifest"]["roadCountByKind"]["secondary"], 2)
            self.assertEqual(report["manifest"]["roadCountByKind"]["residential"], 1)
            self.assertEqual(report["manifest"]["roadCountBySubkind"]["sidewalk"], 2)
            self.assertEqual(report["manifest"]["roadCountBySubkind"]["none"], 1)
            self.assertEqual(report["manifest"]["waterCount"], 2)
            self.assertEqual(report["manifest"]["waterCountByKind"]["pond"], 1)
            self.assertEqual(report["manifest"]["waterCountByKind"]["stream"], 1)
            self.assertEqual(report["manifest"]["propCount"], 2)
            self.assertEqual(report["manifest"]["propCountByKind"]["tree"], 1)
            self.assertEqual(report["manifest"]["propCountByKind"]["fountain"], 1)
            self.assertEqual(report["manifest"]["treeCount"], 1)
            self.assertEqual(report["manifest"]["treeCountBySpecies"]["oak"], 1)
            self.assertEqual(report["manifest"]["vegetationCount"], 1)
            self.assertEqual(report["manifest"]["vegetationCountByKind"]["tree"], 1)
            self.assertEqual(report["manifest"]["chunksWithWater"], 1)
            self.assertEqual(report["manifest"]["waterCountByType"]["polygon"], 1)
            self.assertEqual(report["manifest"]["waterCountByType"]["ribbon"], 1)
            self.assertAlmostEqual(report["summary"]["building_model_ratio"], 1 / 3, places=4)
            self.assertAlmostEqual(report["summary"]["road_geometry_ratio"], 0.0, places=4)
            self.assertAlmostEqual(report["summary"]["water_geometry_ratio"], 0.0, places=4)
            self.assertEqual(report["scene"]["buildingModelCountByWallMaterial"]["concrete"]["sourceIds"], ["bldg_1"])
            self.assertEqual(report["scene"]["buildingModelCountByRoofMaterial"]["slate"]["sourceIds"], ["bldg_1"])
            self.assertIn("missing_building_models", codes)
            self.assertIn("missing_road_geometry", codes)
            self.assertIn("missing_water_geometry", codes)
            self.assertIn("roof_usage_scene_gap", codes)
            self.assertIn("roof_shape_scene_gap", codes)
            self.assertIn("road_kind_scene_gap", codes)
            self.assertIn("road_subkind_scene_gap", codes)
            self.assertIn("water_kind_scene_gap", codes)
            self.assertIn("prop_kind_scene_gap", codes)
            self.assertIn("explicit_wall_material_scene_gap", codes)
            self.assertIn("explicit_roof_material_scene_gap", codes)
            self.assertEqual(
                report["summary"]["roadKindGaps"],
                [
                    {
                        "bucket": "secondary",
                        "manifestCount": 2,
                        "sceneCount": 1,
                        "missingIds": ["road_2"],
                    },
                    {
                        "bucket": "residential",
                        "manifestCount": 1,
                        "sceneCount": 0,
                        "missingIds": ["road_3"],
                    },
                ],
            )
            self.assertEqual(
                report["summary"]["roadSubkindGaps"],
                [
                    {
                        "bucket": "sidewalk",
                        "manifestCount": 2,
                        "sceneCount": 1,
                        "missingIds": ["road_3"],
                    },
                    {
                        "bucket": "none",
                        "manifestCount": 1,
                        "sceneCount": 0,
                        "missingIds": ["road_2"],
                    },
                ],
            )
            self.assertEqual(
                report["summary"]["waterKindGaps"],
                [
                    {
                        "bucket": "stream",
                        "manifestCount": 1,
                        "sceneCount": 0,
                        "missingIds": ["water_ribbon_1"],
                    },
                ],
            )
            self.assertEqual(
                report["summary"]["propKindGaps"],
                [
                    {"bucket": "fountain", "manifestCount": 1, "sceneCount": 0, "missingIds": ["prop_fountain_1"]},
                ],
            )
            self.assertEqual(
                report["summary"]["explicitWallMaterialGaps"],
                [
                    {"bucket": "cobblestone", "manifestCount": 1, "sceneCount": 0, "missingIds": ["bldg_2"]},
                ],
            )
            self.assertEqual(
                report["summary"]["explicitRoofMaterialGaps"],
                [
                    {"bucket": "metal", "manifestCount": 1, "sceneCount": 0, "missingIds": ["bldg_2"]},
                ],
            )
            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("Scene Fidelity Audit", html)
            self.assertIn("building_model_ratio", html)
            self.assertIn("water_geometry_ratio", html)
            self.assertIn("building_models_with_roof", html)
            self.assertIn("building_models_without_roof", html)
            self.assertIn("building_models_with_direct_roof", html)
            self.assertIn("building_models_with_merged_roof_only", html)
            self.assertIn("building_models_with_no_roof_evidence", html)
            self.assertIn("water_surface_part_count", html)
            self.assertIn("prop_instance_count", html)
            self.assertIn("ambient_prop_instance_count", html)
            self.assertIn("tree_instance_count", html)
            self.assertIn("vegetation_instance_count", html)
            self.assertIn("chunks_with_water_geometry", html)
            self.assertIn("Roof Coverage By Usage", html)
            self.assertIn("Scene Roof Coverage By Shape", html)
            self.assertIn("Manifest Roof Expectations By Usage", html)
            self.assertIn("Manifest Roof Expectations By Shape", html)
            self.assertIn("Effective Building Wall Materials", html)
            self.assertIn("Effective Building Roof Materials", html)
            self.assertIn("Manifest Explicit Wall Materials", html)
            self.assertIn("Manifest Explicit Roof Materials", html)
            self.assertIn("Explicit Wall Material Gaps", html)
            self.assertIn("Explicit Roof Material Gaps", html)
            self.assertIn("Manifest Road Kinds", html)
            self.assertIn("Manifest Road Subkinds", html)
            self.assertIn("Water Surface Breakdown", html)
            self.assertIn("Manifest Water Kinds", html)
            self.assertIn("Water Surface By Kind", html)
            self.assertIn("Road Surface By Kind", html)
            self.assertIn("Road Surface By Subkind", html)
            self.assertIn("Road Kind Gaps", html)
            self.assertIn("Road Subkind Gaps", html)
            self.assertIn("Water Kind Gaps", html)
            self.assertIn("Prop Breakdown", html)
            self.assertIn("Manifest Props", html)
            self.assertIn("Prop Kind Gaps", html)
            self.assertIn("Ambient Props", html)
            self.assertIn("Tree Species", html)
            self.assertIn("Manifest Trees By Species", html)
            self.assertIn("Vegetation Breakdown", html)
            self.assertIn("Manifest Vegetation Kinds", html)
            self.assertIn("office", html)
            self.assertIn("government", html)
            self.assertIn("flat", html)
            self.assertIn("gabled", html)
            self.assertIn("polygon", html)
            self.assertIn("pond", html)
            self.assertIn("ribbon", html)
            self.assertIn("oak", html)
            self.assertIn("tree", html)
            self.assertIn("cobblestone", html)
            self.assertIn("slate", html)
            self.assertIn("secondary", html)
            self.assertIn("sidewalk", html)
            self.assertIn("residential", html)
            self.assertIn("ARNIS_SCENE_PLAY", html)
            self.assertNotIn('class=\"card\"', html)

    def test_main_can_render_html_from_precomputed_report_json(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report_path = root / "report.json"
            html_path = root / "report.html"
            report = {
                "summary": {
                    "marker": "ARNIS_SCENE_EDIT",
                    "building_model_ratio": 0.5,
                    "road_geometry_ratio": 1.0,
                    "chunk_ratio": 1.0,
                    "water_geometry_ratio": 0.5,
                },
                "scene": {
                    "chunkCount": 1,
                    "buildingModelsWithDirectShell": 7,
                    "buildingModelsMissingDirectShell": 2,
                    "buildingModelsWithRoof": 5,
                    "buildingModelsWithoutRoof": 2,
                    "buildingModelsWithDirectRoof": 3,
                    "buildingModelsWithMergedRoofOnly": 2,
                    "buildingModelsWithNoRoofEvidence": 2,
                    "buildingRoofCoverageByUsage": {
                        "office": {
                            "buildingModelCount": 4,
                            "withRoofCount": 3,
                            "withoutRoofCount": 1,
                            "directRoofCount": 2,
                            "mergedRoofOnlyCount": 1,
                            "noRoofEvidenceCount": 1,
                        }
                    },
                    "buildingRoofCoverageByShape": {
                        "flat": {
                            "buildingModelCount": 4,
                            "withRoofCount": 3,
                            "withoutRoofCount": 1,
                            "directRoofCount": 2,
                            "mergedRoofOnlyCount": 1,
                            "noRoofEvidenceCount": 1,
                        }
                    },
                    "waterSurfacePartCount": 3,
                    "waterSurfacePartCountByType": {
                        "polygon": {"surfacePartCount": 2},
                        "ribbon": {"surfacePartCount": 1},
                    },
                    "waterSurfacePartCountByKind": {
                        "pond": {"surfacePartCount": 2},
                        "stream": {"surfacePartCount": 1},
                    },
                    "propInstanceCount": 5,
                    "propInstanceCountByKind": {
                        "tree": {"instanceCount": 3},
                        "fountain": {"instanceCount": 2},
                    },
                    "ambientPropInstanceCount": 4,
                    "ambientPropInstanceCountByKind": {
                        "unknown": {"instanceCount": 4},
                    },
                    "treeInstanceCount": 3,
                    "treeInstanceCountBySpecies": {
                        "oak": {"instanceCount": 2},
                        "elm": {"instanceCount": 1},
                    },
                    "vegetationInstanceCount": 3,
                    "vegetationInstanceCountByKind": {
                        "tree": {"instanceCount": 3},
                    },
                    "chunksWithProps": 1,
                    "chunksWithVegetation": 1,
                    "chunksWithAmbientProps": 1,
                    "chunksWithWaterGeometry": 1,
                    "mergedBuildingMeshPartCount": 5,
                    "roadCrosswalkStripeCount": 9,
                },
                "manifest": {
                    "chunkCount": 2,
                    "buildingCountByUsage": {"office": 4},
                    "buildingCountByRoofShape": {"flat": 4},
                    "roadCountByKind": {"secondary": 2, "residential": 1},
                    "roadCountBySubkind": {"sidewalk": 2, "none": 1},
                    "propCount": 5,
                    "propCountByKind": {"tree": 3, "fountain": 2},
                    "treeCount": 3,
                    "treeCountBySpecies": {"oak": 2, "elm": 1},
                    "vegetationCount": 3,
                    "vegetationCountByKind": {"tree": 3},
                    "waterCountByKind": {"pond": 1, "stream": 1},
                    "waterCountByType": {"polygon": 1, "ribbon": 1},
                },
                "findings": [
                    {
                        "severity": "high",
                        "code": "missing_building_models",
                        "message": "scene built 1 building models but manifest expected 2",
                    }
                ],
            }
            report_path.write_text(json.dumps(report), encoding="utf-8")

            exit_code = audit.main(["--report-json", str(report_path), "--html-out", str(html_path)])

            self.assertEqual(exit_code, 0)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("ARNIS_SCENE_EDIT", html)
            self.assertIn("missing_building_models", html)
            self.assertIn("building_model_ratio", html)
            self.assertIn("building_models_with_direct_shell", html)
            self.assertIn("building_models_missing_direct_shell", html)
            self.assertIn("building_models_with_roof", html)
            self.assertIn("building_models_without_roof", html)
            self.assertIn("building_models_with_direct_roof", html)
            self.assertIn("building_models_with_merged_roof_only", html)
            self.assertIn("building_models_with_no_roof_evidence", html)
            self.assertIn("water_surface_part_count", html)
            self.assertIn("prop_instance_count", html)
            self.assertIn("ambient_prop_instance_count", html)
            self.assertIn("tree_instance_count", html)
            self.assertIn("vegetation_instance_count", html)
            self.assertIn("chunks_with_water_geometry", html)
            self.assertIn("Roof Coverage By Usage", html)
            self.assertIn("Scene Roof Coverage By Shape", html)
            self.assertIn("Manifest Roof Expectations By Usage", html)
            self.assertIn("Manifest Roof Expectations By Shape", html)
            self.assertIn("Water Surface Breakdown", html)
            self.assertIn("Water Surface By Kind", html)
            self.assertIn("Prop Breakdown", html)
            self.assertIn("Ambient Props", html)
            self.assertIn("Tree Species", html)
            self.assertIn("Vegetation Breakdown", html)
            self.assertIn("office", html)
            self.assertIn("flat", html)
            self.assertIn("polygon", html)
            self.assertIn("ribbon", html)
            self.assertIn("pond", html)
            self.assertIn("stream", html)
            self.assertIn("oak", html)
            self.assertIn("merged_building_mesh_part_count", html)
            self.assertIn("road_crosswalk_stripe_count", html)

    def test_report_reassembles_split_prop_and_vegetation_buckets(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [],
                        "water": [],
                        "props": [
                            {"id": "tree_1", "kind": "tree", "species": "oak", "position": {"x": 0, "y": 0, "z": 0}},
                            {
                                "id": "fountain_1",
                                "kind": "fountain",
                                "position": {"x": 4, "y": 0, "z": 4},
                            },
                        ],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            scene_payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "propInstanceCount": 2,
                    "ambientPropInstanceCount": 3,
                    "treeInstanceCount": 1,
                    "vegetationInstanceCount": 1,
                    "chunksWithProps": 1,
                    "chunksWithAmbientProps": 1,
                    "chunksWithVegetation": 1,
                    "chunksWithRoadGeometry": 0,
                    "chunksWithWaterGeometry": 0,
                    "buildingModelCount": 0,
                },
            }
            log_path.write_text(
                "\n".join(
                    [
                        "ARNIS_SCENE_EDIT_CHUNKS "
                        + json.dumps(
                            {"phase": "edit", "rootName": "GeneratedWorld_AustinPreview", "chunkIds": ["0_0"]},
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_PROP_KIND_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "tree",
                                "stats": {"instanceCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_PROP_KIND_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "tree",
                                "sourceIds": ["tree_1"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_PROP_KIND_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "fountain",
                                "stats": {"instanceCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_PROP_KIND_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "fountain",
                                "sourceIds": ["fountain_1"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_AMBIENT_PROP_KIND_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "unknown",
                                "stats": {"instanceCount": 3},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_TREE_SPECIES_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "oak",
                                "stats": {"instanceCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_TREE_SPECIES_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "oak",
                                "sourceIds": ["tree_1"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_VEGETATION_KIND_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "tree",
                                "stats": {"instanceCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_VEGETATION_KIND_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "tree",
                                "sourceIds": ["tree_1"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT " + json.dumps(scene_payload, separators=(",", ":")),
                    ]
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")

            self.assertEqual(report["scene"]["propInstanceCountByKind"]["tree"]["instanceCount"], 1)
            self.assertEqual(report["scene"]["propInstanceCountByKind"]["tree"]["sourceIds"], ["tree_1"])
            self.assertEqual(report["scene"]["propInstanceCountByKind"]["fountain"]["instanceCount"], 1)
            self.assertEqual(report["scene"]["propInstanceCountByKind"]["fountain"]["sourceIds"], ["fountain_1"])
            self.assertEqual(report["scene"]["ambientPropInstanceCountByKind"]["unknown"]["instanceCount"], 3)
            self.assertEqual(report["scene"]["treeInstanceCountBySpecies"]["oak"]["instanceCount"], 1)
            self.assertEqual(report["scene"]["treeInstanceCountBySpecies"]["oak"]["sourceIds"], ["tree_1"])
            self.assertEqual(report["scene"]["vegetationInstanceCountByKind"]["tree"]["instanceCount"], 1)
            self.assertEqual(report["scene"]["vegetationInstanceCountByKind"]["tree"]["sourceIds"], ["tree_1"])

    def test_report_reassembles_split_scalar_and_water_buckets(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [],
                        "water": [
                            {
                                "id": "water_1",
                                "kind": "pond",
                                "material": "Water",
                                "type": "polygon",
                                "footprint": [
                                    {"x": 16, "z": 16},
                                    {"x": 48, "z": 16},
                                    {"x": 48, "z": 48},
                                    {"x": 16, "z": 48},
                                ],
                            }
                        ],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            base_payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {},
            }
            log_path.write_text(
                "\n".join(
                    [
                        "ARNIS_SCENE_EDIT_SCALAR "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "key": "buildingModelCount",
                                "value": 2,
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_SCALAR "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "key": "waterSurfacePartCount",
                                "value": 1,
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_SCALAR "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "key": "chunksWithWaterGeometry",
                                "value": 1,
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_WATER_TYPE_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "polygon",
                                "stats": {"surfacePartCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_WATER_KIND_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "pond",
                                "stats": {"surfacePartCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_WATER_KIND_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "pond",
                                "sourceIds": ["water_1"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_ROAD_KIND_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "footway",
                                "stats": {"surfacePartCount": 2, "featureCount": 2},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_ROAD_KIND_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "footway",
                                "sourceIds": ["road_a", "road_b"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_ROAD_SUBKIND_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "sidewalk",
                                "stats": {"surfacePartCount": 1, "featureCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_ROAD_SUBKIND_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "sidewalk",
                                "sourceIds": ["road_a"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT " + json.dumps(base_payload, separators=(",", ":")),
                    ]
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")

            self.assertEqual(report["scene"]["buildingModelCount"], 2)
            self.assertEqual(report["scene"]["waterSurfacePartCount"], 1)
            self.assertEqual(report["scene"]["chunksWithWaterGeometry"], 1)
            self.assertEqual(report["scene"]["waterSurfacePartCountByType"]["polygon"]["surfacePartCount"], 1)
            self.assertEqual(report["scene"]["waterSurfacePartCountByKind"]["pond"]["surfacePartCount"], 1)
            self.assertEqual(report["scene"]["waterSurfacePartCountByKind"]["pond"]["sourceIds"], ["water_1"])
            self.assertEqual(report["scene"]["roadSurfacePartCountByKind"]["footway"]["surfacePartCount"], 2)
            self.assertEqual(report["scene"]["roadSurfacePartCountByKind"]["footway"]["sourceIds"], ["road_a", "road_b"])
            self.assertEqual(report["scene"]["roadSurfacePartCountBySubkind"]["sidewalk"]["surfacePartCount"], 1)
            self.assertEqual(report["scene"]["roadSurfacePartCountBySubkind"]["sidewalk"]["sourceIds"], ["road_a"])

    def test_merged_roof_finding_accepts_shell_mesh_support(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [{"id": "b1"}],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "buildingModelCount": 1,
                    "buildingModelsWithRoof": 1,
                    "buildingModelsWithoutRoof": 0,
                    "buildingModelsWithDirectRoof": 0,
                    "buildingModelsWithMergedRoofOnly": 1,
                    "buildingModelsWithNoRoofEvidence": 0,
                    "buildingShellMeshPartCount": 1,
                    "mergedBuildingMeshPartCount": 0,
                    "chunksWithBuildingModels": 1,
                },
            }
            log_path.write_text(
                "ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("merged_roof_only_coverage", codes)
            self.assertNotIn("merged_roof_claim_without_mesh_support", codes)

    def test_shaped_roof_closure_gap_is_reported(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [{"id": "b1"}],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "buildingModelCount": 1,
                    "buildingModelsWithRoof": 1,
                    "buildingModelsWithoutRoof": 0,
                    "buildingModelsWithDirectRoof": 1,
                    "buildingModelsWithMergedRoofOnly": 0,
                    "buildingModelsWithNoRoofEvidence": 0,
                    "buildingModelsWithRoofClosureDeck": 0,
                    "chunksWithBuildingModels": 1,
                    "buildingRoofCoverageByShape": {
                        "gabled": {
                            "buildingModelCount": 1,
                            "withRoofCount": 1,
                            "withoutRoofCount": 0,
                            "directRoofCount": 1,
                            "mergedRoofOnlyCount": 0,
                            "noRoofEvidenceCount": 0,
                            "closureDeckCount": 0,
                        }
                    },
                },
            }
            log_path.write_text(
                "ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("shaped_roof_closure_gap", codes)

    def test_roof_shape_gap_traces_direct_geometry_not_merged_only_evidence(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [{"id": "b1", "roof": "gabled"}],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "buildingModelCount": 1,
                    "buildingModelsWithRoof": 1,
                    "buildingModelsWithoutRoof": 0,
                    "buildingModelsWithDirectRoof": 0,
                    "buildingModelsWithMergedRoofOnly": 1,
                    "buildingModelsWithNoRoofEvidence": 0,
                    "chunksWithBuildingModels": 1,
                    "buildingRoofCoverageByShape": {
                        "gabled": {
                            "buildingModelCount": 1,
                            "withRoofCount": 1,
                            "withoutRoofCount": 0,
                            "directRoofCount": 0,
                            "mergedRoofOnlyCount": 1,
                            "noRoofEvidenceCount": 0,
                        }
                    },
                },
            }
            log_path.write_text(
                "ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")
            roof_shape_findings = [finding for finding in report["findings"] if finding["code"] == "roof_shape_scene_gap"]
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("merged_roof_only_coverage", codes)
            self.assertIn("roof_shape_scene_gap", codes)
            self.assertNotIn("missing_roof_evidence", codes)
            self.assertEqual(len(roof_shape_findings), 1)
            self.assertIn("direct roof geometries", roof_shape_findings[0]["message"])

    def test_road_gap_uses_unique_source_ids_when_available(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [
                            {"id": "road_a", "kind": "footway", "subkind": "none"},
                            {"id": "road_b", "kind": "footway", "subkind": "none"},
                        ],
                        "buildings": [],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 350.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "buildingModelCount": 0,
                    "chunksWithBuildingModels": 0,
                    "chunksWithRoadGeometry": 1,
                    "roadSurfacePartCountByKind": {
                        "footway": {
                            "surfacePartCount": 20,
                            "featureCount": 1,
                            "sourceIds": ["road_a", "road_b"],
                        }
                    },
                    "roadSurfacePartCountBySubkind": {
                        "none": {
                            "surfacePartCount": 20,
                            "featureCount": 1,
                            "sourceIds": ["road_a", "road_b"],
                        }
                    },
                },
            }
            chunks_payload = {
                "phase": "edit",
                "rootName": "GeneratedWorld_AustinPreview",
                "chunkIds": ["0_0"],
            }
            log_path.write_text(
                "\n".join(
                    [
                        "ARNIS_SCENE_EDIT_CHUNKS " + json.dumps(chunks_payload, separators=(",", ":")),
                        "ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")),
                    ]
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")

            self.assertEqual(report["summary"]["roadKindGaps"], [])
            self.assertEqual(report["summary"]["roadSubkindGaps"], [])
            codes = {finding["code"] for finding in report["findings"]}
            self.assertNotIn("road_kind_scene_gap", codes)
            self.assertNotIn("road_subkind_scene_gap", codes)

    def test_prop_and_vegetation_gaps_use_unique_source_ids_when_available(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [],
                        "water": [],
                        "props": [
                            {"id": "tree_a", "kind": "tree", "species": "oak", "position": {"x": 0, "y": 0, "z": 0}},
                            {"id": "tree_b", "kind": "tree", "species": "oak", "position": {"x": 4, "y": 0, "z": 4}},
                        ],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 350.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "propInstanceCountByKind": {
                        "tree": {"instanceCount": 1, "sourceIds": ["tree_a", "tree_b"]},
                    },
                    "treeInstanceCountBySpecies": {
                        "oak": {"instanceCount": 1, "sourceIds": ["tree_a", "tree_b"]},
                    },
                    "vegetationInstanceCountByKind": {
                        "tree": {"instanceCount": 1, "sourceIds": ["tree_a", "tree_b"]},
                    },
                },
            }
            chunks_payload = {
                "phase": "edit",
                "rootName": "GeneratedWorld_AustinPreview",
                "chunkIds": ["0_0"],
            }
            log_path.write_text(
                "\n".join(
                    [
                        "ARNIS_SCENE_EDIT_CHUNKS " + json.dumps(chunks_payload, separators=(",", ":")),
                        "ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")),
                    ]
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")

            self.assertEqual(report["summary"]["propKindGaps"], [])
            self.assertEqual(report["summary"]["treeSpeciesGaps"], [])
            self.assertEqual(report["summary"]["vegetationKindGaps"], [])
            codes = {finding["code"] for finding in report["findings"]}
            self.assertNotIn("prop_kind_scene_gap", codes)
            self.assertNotIn("tree_species_scene_gap", codes)
            self.assertNotIn("vegetation_kind_scene_gap", codes)

    def test_tree_connectivity_fields_and_finding(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [],
                        "water": [],
                        "props": [
                            {"id": "tree_1", "kind": "tree", "species": "oak", "position": {"x": 0, "y": 0, "z": 0}},
                            {"id": "tree_2", "kind": "tree", "species": "elm", "position": {"x": 12, "y": 0, "z": 0}},
                            {"id": "tree_3", "kind": "tree", "species": "cedar", "position": {"x": 24, "y": 0, "z": 0}},
                        ],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "propInstanceCount": 3,
                    "propInstanceCountByKind": {"tree": {"instanceCount": 3}},
                    "treeInstanceCount": 3,
                    "treeInstanceCountBySpecies": {
                        "oak": {"instanceCount": 1},
                        "elm": {"instanceCount": 1},
                        "cedar": {"instanceCount": 1},
                    },
                    "vegetationInstanceCount": 3,
                    "vegetationInstanceCountByKind": {"tree": {"instanceCount": 3}},
                    "treeModelsWithConnectedTrunkCanopy": 1,
                    "treeModelsMissingTrunk": 1,
                    "treeModelsMissingCanopy": 0,
                    "treeModelsWithDetachedCanopy": 1,
                    "treeConnectivityBySpecies": {
                        "oak": {
                            "treeInstanceCount": 1,
                            "connectedCount": 0,
                            "missingTrunkCount": 1,
                            "missingCanopyCount": 0,
                            "detachedCanopyCount": 0,
                        },
                        "elm": {
                            "treeInstanceCount": 1,
                            "connectedCount": 1,
                            "missingTrunkCount": 0,
                            "missingCanopyCount": 0,
                            "detachedCanopyCount": 0,
                        },
                        "cedar": {
                            "treeInstanceCount": 1,
                            "connectedCount": 0,
                            "missingTrunkCount": 0,
                            "missingCanopyCount": 0,
                            "detachedCanopyCount": 1,
                        },
                    },
                },
            }
            log_path.write_text("ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")), encoding="utf-8")

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")
            codes = {finding["code"] for finding in report["findings"]}

            self.assertEqual(report["scene"]["treeModelsWithConnectedTrunkCanopy"], 1)
            self.assertEqual(report["scene"]["treeModelsMissingTrunk"], 1)
            self.assertEqual(report["scene"]["treeModelsWithDetachedCanopy"], 1)
            self.assertEqual(report["scene"]["treeConnectivityBySpecies"]["oak"]["missingTrunkCount"], 1)
            self.assertEqual(report["scene"]["treeConnectivityBySpecies"]["elm"]["connectedCount"], 1)
            self.assertEqual(report["scene"]["treeConnectivityBySpecies"]["cedar"]["detachedCanopyCount"], 1)
            self.assertIn("tree_connectivity_gaps", codes)

    def test_report_reassembles_split_building_material_buckets(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SceneAuditTown",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "roads": [],
                        "buildings": [
                            {
                                "id": "bldg_1",
                                "usage": "office",
                                "roof": "flat",
                                "material": "Concrete",
                                "roofMaterial": "Slate",
                            }
                        ],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {
                    "chunkCount": 1,
                    "buildingModelCount": 1,
                    "chunksWithBuildingModels": 1,
                    "buildingModelsWithRoof": 1,
                    "buildingRoofCoverageByUsage": {
                        "office": {
                            "buildingModelCount": 1,
                            "withRoofCount": 1,
                            "withoutRoofCount": 0,
                            "directRoofCount": 1,
                            "mergedRoofOnlyCount": 0,
                            "noRoofEvidenceCount": 0,
                        }
                    },
                    "buildingRoofCoverageByShape": {
                        "flat": {
                            "buildingModelCount": 1,
                            "withRoofCount": 1,
                            "withoutRoofCount": 0,
                            "directRoofCount": 1,
                            "mergedRoofOnlyCount": 0,
                            "noRoofEvidenceCount": 0,
                        }
                    },
                },
            }
            log_path.write_text(
                "\n".join(
                    [
                        "ARNIS_SCENE_EDIT_BUILDING_WALL_MATERIAL_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "concrete",
                                "stats": {"buildingModelCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_BUILDING_WALL_MATERIAL_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "concrete",
                                "sourceIds": ["bldg_1"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_BUILDING_ROOF_MATERIAL_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "slate",
                                "stats": {"buildingModelCount": 1},
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT_BUILDING_ROOF_MATERIAL_IDS_BATCH "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_AustinPreview",
                                "bucket": "slate",
                                "sourceIds": ["bldg_1"],
                            },
                            separators=(",", ":"),
                        ),
                        "ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")),
                    ]
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")
            codes = {finding["code"] for finding in report["findings"]}

            self.assertEqual(report["scene"]["buildingModelCountByWallMaterial"]["concrete"]["buildingModelCount"], 1)
            self.assertEqual(report["scene"]["buildingModelCountByWallMaterial"]["concrete"]["sourceIds"], ["bldg_1"])
            self.assertEqual(report["scene"]["buildingModelCountByRoofMaterial"]["slate"]["buildingModelCount"], 1)
            self.assertEqual(report["scene"]["buildingModelCountByRoofMaterial"]["slate"]["sourceIds"], ["bldg_1"])
            self.assertEqual(report["summary"]["explicitWallMaterialGaps"], [])
            self.assertEqual(report["summary"]["explicitRoofMaterialGaps"], [])
            self.assertNotIn("explicit_wall_material_scene_gap", codes)
            self.assertNotIn("explicit_roof_material_scene_gap", codes)

    def test_report_ignores_trailing_fragments_from_other_run_key(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "manifest.json"
            log_path = root / "studio.log"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {"worldName": "SceneAuditTown", "metersPerStud": 0.3, "chunkSizeStuds": 256},
                "chunks": [{"id": "0_0", "originStuds": {"x": 0, "y": 0, "z": 0}, "roads": [], "buildings": [], "water": [], "props": [], "landuse": [], "barriers": [], "rails": []}],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            payload = {
                "phase": "edit",
                "focus": {"x": 32.0, "z": 32.0},
                "radius": 256.0,
                "rootName": "GeneratedWorld_AustinPreview",
                "scene": {"chunkCount": 1, "buildingModelCount": 0},
            }
            log_path.write_text(
                "\n".join(
                    [
                        "ARNIS_SCENE_EDIT " + json.dumps(payload, separators=(",", ":")),
                        "ARNIS_SCENE_EDIT_BUILDING_WALL_MATERIAL_BUCKET "
                        + json.dumps(
                            {
                                "phase": "edit",
                                "rootName": "GeneratedWorld_Stale",
                                "bucket": "glass",
                                "stats": {"buildingModelCount": 99},
                            },
                            separators=(",", ":"),
                        ),
                    ]
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, log_path, marker="ARNIS_SCENE_EDIT")
            self.assertNotIn("buildingModelCountByWallMaterial", report["scene"])


if __name__ == "__main__":
    unittest.main()
