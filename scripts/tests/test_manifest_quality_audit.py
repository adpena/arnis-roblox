from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "manifest_quality_audit.py"


def load_module():
    spec = importlib.util.spec_from_file_location("manifest_quality_audit", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ManifestQualityAuditTests(unittest.TestCase):
    maxDiff = None

    def test_fixture_report_flags_semantic_collapse_and_renders_html(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"
            html_path = root / "report.html"
            html_path = root / "report.html"

            buildings = []
            for index in range(12):
                buildings.append(
                    {
                        "id": f"building_{index}",
                        "usage": "yes",
                        "material": "Concrete",
                        "wallColor": {"r": 170, "g": 170, "b": 170},
                        "roof": "flat",
                        "height": 8,
                        "footprint": [
                            {"x": index * 120, "z": 0},
                            {"x": index * 120 + 80, "z": 0},
                            {"x": index * 120 + 80, "z": 80},
                            {"x": index * 120, "z": 80},
                        ],
                    }
                )

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "FixtureWorld",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 0.3,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.245,
                        "minLon": -97.765,
                        "maxLat": 30.305,
                        "maxLon": -97.715,
                    },
                    "totalFeatures": len(buildings) + 2,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 5000, "y": 0, "z": 5000},
                        "terrain": {
                            "cellSizeStuds": 2,
                            "width": 4,
                            "depth": 4,
                            "heights": [0] * 16,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "road_1",
                                "kind": "residential",
                                "widthStuds": 8,
                                "surface": None,
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 32, "y": 0, "z": 0}],
                            }
                        ],
                        "buildings": buildings,
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {
                                "type": "relation",
                                "id": 42,
                                "tags": {"type": "multipolygon", "building": "university"},
                                "members": [{"type": "way", "ref": 7, "role": "inner"}],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("roof_shape_collapse", codes)
            self.assertIn("building_hole_absence", codes)
            self.assertIn("building_usage_collapse", codes)
            self.assertNotIn("source_to_manifest_topology_loss", codes)
            self.assertIn("terrain_material_monotony", codes)
            self.assertEqual(report["summary"]["building_count"], 12)
            self.assertEqual(report["summary"]["roof_distribution"]["flat"], 12)
            self.assertIn("quality_scores", report["summary"])
            self.assertIn("hotspots", report["summary"])
            self.assertIn("building_height", report["summary"]["stats"])
            self.assertEqual(report["summary"]["stats"]["building_height"]["max"], 8.0)
            self.assertTrue(report["location"]["openstreetmap_url"].startswith("https://www.openstreetmap.org/"))
            self.assertEqual(len(report["data_sources"]), 1)
            self.assertIn("multipolygon", report["data_sources"][0]["snippet"])
            self.assertEqual(report["osm_summary"]["element_count"], 1)
            self.assertEqual(report["osm_summary"]["type_counts"]["relation"], 1)
            self.assertEqual(report["osm_summary"]["inner_role_member_count"], 1)
            self.assertEqual(report["osm_summary"]["building_relation_count"], 1)
            self.assertIn("scale_alignment", report["summary"])
            self.assertIn("source_summary", report)
            self.assertIn("glass_material_by_usage", report["summary"])

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("FixtureWorld", html)
            self.assertIn("roof_shape_collapse", html)
            self.assertIn("OpenStreetMap", html)
            self.assertIn("OSM Source Summary", html)
            self.assertIn("Scale Alignment", html)
            self.assertNotIn('class="card"', html)
            self.assertIn("metric-strip", html)
            self.assertIn('id="report-data"', html)
            self.assertIn('id="finding-filter"', html)
            self.assertIn('id="hotspot-table"', html)
            self.assertIn("Usage Drift", html)
            self.assertIn('data-finding-code="roof_shape_collapse"', html)
            self.assertIn("const report =", html)

    def test_report_flags_suspicious_glass_landmark_assignments(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "MaterialAuditTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 2,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_capitol",
                                "name": "Texas State Capitol Annex",
                                "usage": "civic",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 12,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 10, "z": 0},
                                    {"x": 10, "z": 10},
                                    {"x": 0, "z": 10},
                                ],
                            },
                            {
                                "id": "osm_exec",
                                "name": "Executive Office Building",
                                "usage": "office",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 20,
                                "footprint": [
                                    {"x": 40, "z": 0},
                                    {"x": 55, "z": 0},
                                    {"x": 55, "z": 12},
                                    {"x": 40, "z": 12},
                                ],
                            },
                            {
                                "id": "osm_tower",
                                "name": "Downtown Tower",
                                "usage": "office",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 30,
                                "footprint": [
                                    {"x": 20, "z": 0},
                                    {"x": 30, "z": 0},
                                    {"x": 30, "z": 10},
                                    {"x": 20, "z": 10},
                                ],
                            },
                            {
                                "id": "osm_counties",
                                "name": "Texas Association of Counties",
                                "usage": "office",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 18,
                                "footprint": [
                                    {"x": 60, "z": 0},
                                    {"x": 72, "z": 0},
                                    {"x": 72, "z": 12},
                                    {"x": 60, "z": 12},
                                ],
                            },
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

            report = audit.build_report(manifest_path, [])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("implausible_building_material_assignments", codes)
            suspicious = report["summary"]["suspicious_material_assignments"]
            self.assertEqual(len(suspicious), 3)
            self.assertEqual([entry["id"] for entry in suspicious], ["osm_capitol", "osm_exec", "osm_counties"])
            self.assertEqual(suspicious[0]["signals"], ["usage:civic", "name:capitol"])
            self.assertEqual(suspicious[1]["signals"], ["name:executive office", "name:office building"])
            self.assertEqual(suspicious[2]["signals"], ["name:counties"])
            self.assertEqual(suspicious[2]["reason"], "name:counties")
            self.assertEqual(report["summary"]["suspicious_material_assignment_count"], 3)
            self.assertEqual(report["summary"]["suspicious_material_assignment_by_signal"]["name:counties"], 1)
            self.assertEqual(report["summary"]["suspicious_material_assignment_by_signal"]["name:office building"], 1)
            self.assertEqual(report["summary"]["suspicious_material_assignment_by_signal"]["usage:civic"], 1)

    def test_report_flags_source_to_manifest_usage_drift(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            cases = [
                {
                    "id": "osm_1",
                    "name": "Neighborhood Church",
                    "usage": "church",
                    "tags": {
                        "building": "yes",
                        "amenity": "place_of_worship",
                        "name": "Neighborhood Church",
                    },
                },
                {
                    "id": "osm_2",
                    "name": "Cafe Blue",
                    "usage": "cafe",
                    "tags": {
                        "building": "yes",
                        "amenity": "restaurant",
                        "name": "Cafe Blue",
                    },
                },
                {
                    "id": "osm_3",
                    "name": "State Office Annex",
                    "usage": "office",
                    "tags": {
                        "building": "office",
                        "office": "government",
                        "government": "yes",
                        "name": "State Office Annex",
                    },
                },
                {
                    "id": "osm_4",
                    "name": "Nori",
                    "usage": "retail",
                    "tags": {
                        "building": "yes",
                        "amenity": "restaurant",
                        "name": "Nori",
                    },
                },
                {
                    "id": "osm_5",
                    "name": "PD Thai",
                    "usage": "commercial",
                    "tags": {
                        "building": "yes",
                        "amenity": "restaurant",
                        "name": "PD Thai",
                    },
                },
                {
                    "id": "osm_6",
                    "name": "Wheatsville Food Co-op",
                    "usage": "commercial",
                    "tags": {
                        "building": "yes",
                        "shop": "supermarket",
                        "name": "Wheatsville Food Co-op",
                    },
                },
                {
                    "id": "osm_7",
                    "name": "Exxon",
                    "usage": "roof",
                    "tags": {
                        "building": "yes",
                        "amenity": "fuel",
                        "name": "Exxon",
                    },
                },
            ]

            nodes = []
            buildings = []
            elements = []
            for index, case in enumerate(cases, start=1):
                lat = 30.0 + (index * 0.0002)
                lon = -97.0 + (index * 0.0002)
                node_base = index * 10
                nodes.extend(
                    [
                        {"type": "node", "id": node_base + 1, "lat": lat, "lon": lon},
                        {"type": "node", "id": node_base + 2, "lat": lat, "lon": lon + 0.0001},
                        {"type": "node", "id": node_base + 3, "lat": lat + 0.0001, "lon": lon + 0.0001},
                        {"type": "node", "id": node_base + 4, "lat": lat + 0.0001, "lon": lon},
                    ]
                )
                elements.append(
                    {
                        "type": "way",
                        "id": index,
                        "nodes": [node_base + 1, node_base + 2, node_base + 3, node_base + 4, node_base + 1],
                        "tags": case["tags"],
                    }
                )
                buildings.append(
                    {
                        "id": case["id"],
                        "name": case["name"],
                        "usage": case["usage"],
                        "material": "Glass" if case["usage"] == "office" else "Cobblestone",
                        "roof": "flat" if case["usage"] != "church" else "gabled",
                        "height": 20,
                        "footprint": [
                            {"x": (index - 1) * 12, "z": 0},
                            {"x": (index - 1) * 12 + 10, "z": 0},
                            {"x": (index - 1) * 12 + 10, "z": 10},
                            {"x": (index - 1) * 12, "z": 10},
                        ],
                    }
                )

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "UsageDriftTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": len(cases),
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": buildings,
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": nodes + elements,
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])

            codes = {finding["code"] for finding in report["findings"]}
            self.assertIn("source_to_manifest_usage_drift", codes)
            self.assertEqual(report["summary"]["source_usage_mismatch_count"], 5)
            self.assertEqual(report["summary"]["source_usage_refinement_count"], 2)
            self.assertCountEqual(
                [
                    (row["source_usage_signal"], row["manifest_usage"])
                    for row in report["summary"]["source_usage_refinements"]
                ],
                [("religious", "church"), ("restaurant", "cafe")],
            )
            self.assertCountEqual(
                [
                    (row["source_usage_signal"], row["manifest_usage"])
                    for row in report["summary"]["source_usage_mismatches"]
                ],
                [
                    ("government", "office"),
                    ("restaurant", "retail"),
                    ("restaurant", "commercial"),
                    ("supermarket", "commercial"),
                    ("garage", "roof"),
                ],
            )
            self.assertEqual(report["summary"]["source_usage_confusion"]["government->office"], 1)
            self.assertEqual(report["summary"]["source_usage_confusion"]["restaurant->retail"], 1)
            self.assertEqual(report["summary"]["source_usage_confusion"]["restaurant->commercial"], 1)
            self.assertEqual(report["summary"]["source_usage_confusion"]["supermarket->commercial"], 1)
            self.assertEqual(report["summary"]["source_usage_confusion"]["garage->roof"], 1)
            self.assertEqual(report["summary"]["source_usage_signal_distribution"]["government"], 1)
            usage_breakdown = report["summary"]["source_usage_diagnostics"]
            self.assertEqual(usage_breakdown["government"]["source_count"], 1)
            self.assertEqual(usage_breakdown["government"]["mismatch_count"], 1)
            self.assertEqual(usage_breakdown["government"]["identity_loss_count"], 0)
            self.assertEqual(usage_breakdown["religious"]["refinement_count"], 1)
            self.assertEqual(usage_breakdown["restaurant"]["source_count"], 3)
            self.assertEqual(usage_breakdown["restaurant"]["mismatch_count"], 2)
            self.assertEqual(usage_breakdown["restaurant"]["refinement_count"], 1)
            self.assertEqual(usage_breakdown["supermarket"]["mismatch_count"], 1)
            self.assertEqual(usage_breakdown["garage"]["mismatch_count"], 1)
            self.assertEqual(
                report["summary"]["source_usage_diagnostics_top_mismatch_types"][0]["source_usage_signal"],
                "restaurant",
            )

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("Usage Drift", html)
            self.assertIn("Neighborhood Church", html)
            self.assertIn("source→manifest", html)
            self.assertIn("government-&gt;office", html)
            self.assertIn("restaurant-&gt;commercial", html)
            self.assertIn("usage diag", html)

    def test_report_flags_source_to_manifest_material_drift_from_explicit_tags(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            cases = [
                {
                    "id": "osm_1",
                    "name": "Brick Hall",
                    "manifest_material": "Glass",
                    "tags": {
                        "building": "school",
                        "building:material": "brick",
                        "name": "Brick Hall",
                    },
                },
                {
                    "id": "osm_2",
                    "name": "Glass Pavilion",
                    "manifest_material": "Concrete",
                    "tags": {
                        "building": "commercial",
                        "building:material": "glass",
                        "name": "Glass Pavilion",
                    },
                },
                {
                    "id": "osm_3",
                    "name": "Stone Chapel",
                    "manifest_material": "Cobblestone",
                    "tags": {
                        "building": "church",
                        "building:material": "stone",
                        "name": "Stone Chapel",
                    },
                },
                {
                    "id": "osm_4",
                    "name": "Timber Cabin",
                    "manifest_material": "WoodPlanks",
                    "tags": {
                        "building": "house",
                        "material": "wood",
                        "name": "Timber Cabin",
                    },
                },
            ]

            nodes = []
            ways = []
            buildings = []
            for index, case in enumerate(cases, start=1):
                lat = 30.0 + (index * 0.0002)
                lon = -97.0 + (index * 0.0002)
                node_base = index * 10
                nodes.extend(
                    [
                        {"type": "node", "id": node_base + 1, "lat": lat, "lon": lon},
                        {"type": "node", "id": node_base + 2, "lat": lat, "lon": lon + 0.0001},
                        {"type": "node", "id": node_base + 3, "lat": lat + 0.0001, "lon": lon + 0.0001},
                        {"type": "node", "id": node_base + 4, "lat": lat + 0.0001, "lon": lon},
                    ]
                )
                ways.append(
                    {
                        "type": "way",
                        "id": index,
                        "nodes": [node_base + 1, node_base + 2, node_base + 3, node_base + 4, node_base + 1],
                        "tags": case["tags"],
                    }
                )
                buildings.append(
                    {
                        "id": case["id"],
                        "name": case["name"],
                        "usage": "school" if index == 1 else "commercial",
                        "material": case["manifest_material"],
                        "roof": "flat",
                        "height": 16,
                        "footprint": [
                            {"x": (index - 1) * 12, "z": 0},
                            {"x": (index - 1) * 12 + 10, "z": 0},
                            {"x": (index - 1) * 12 + 10, "z": 10},
                            {"x": (index - 1) * 12, "z": 10},
                        ],
                    }
                )

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "MaterialDriftTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": len(cases),
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": buildings,
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": nodes + ways,
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("source_to_manifest_material_drift", codes)
            self.assertEqual(report["summary"]["source_material_mismatch_count"], 2)
            self.assertEqual(report["summary"]["source_material_confusion"]["brick_masonry->glass"], 1)
            self.assertEqual(report["summary"]["source_material_confusion"]["glass->concrete"], 1)
            self.assertEqual(report["summary"]["source_material_signal_distribution"]["brick_masonry"], 2)
            self.assertEqual(report["summary"]["source_material_signal_distribution"]["glass"], 1)
            self.assertEqual(report["summary"]["source_material_signal_distribution"]["wood"], 1)
            self.assertCountEqual(
                [row["id"] for row in report["summary"]["source_material_mismatches"]],
                ["osm_1", "osm_2"],
            )
            self.assertEqual(
                [row["source_material_signal"] for row in report["summary"]["source_material_mismatches"]],
                ["brick_masonry", "glass"],
            )

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("brick_masonry-&gt;glass", html)
            self.assertIn("Glass Pavilion", html)

    def test_report_surfaces_source_water_signal_distribution(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "WaterSignalsTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 2,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [],
                        "water": [
                            {
                                "id": "pool_1",
                                "kind": "swimming_pool",
                                "type": "polygon",
                                "footprint": [{"x": 0, "z": 0}, {"x": 4, "z": 0}, {"x": 4, "z": 4}],
                                "holes": [],
                            },
                            {
                                "id": "fountain_1",
                                "kind": "fountain",
                                "type": "polygon",
                                "footprint": [{"x": 8, "z": 0}, {"x": 10, "z": 0}, {"x": 10, "z": 2}],
                                "holes": [],
                            },
                        ],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {
                                "type": "way",
                                "id": 1,
                                "nodes": [101, 102, 103, 101],
                                "tags": {"natural": "water"},
                            },
                            {
                                "type": "way",
                                "id": 2,
                                "nodes": [201, 202, 203, 201],
                                "tags": {"leisure": "swimming_pool"},
                            },
                            {
                                "type": "node",
                                "id": 3,
                                "lat": 30.005,
                                "lon": -96.995,
                                "tags": {"amenity": "fountain"},
                            },
                            {
                                "type": "way",
                                "id": 4,
                                "nodes": [301, 302],
                                "tags": {"waterway": "stream"},
                            },
                            {"type": "node", "id": 101, "lat": 30.001, "lon": -96.999},
                            {"type": "node", "id": 102, "lat": 30.001, "lon": -96.998},
                            {"type": "node", "id": 103, "lat": 30.002, "lon": -96.998},
                            {"type": "node", "id": 201, "lat": 30.003, "lon": -96.999},
                            {"type": "node", "id": 202, "lat": 30.003, "lon": -96.998},
                            {"type": "node", "id": 203, "lat": 30.004, "lon": -96.998},
                            {"type": "node", "id": 301, "lat": 30.006, "lon": -96.999},
                            {"type": "node", "id": 302, "lat": 30.007, "lon": -96.998},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])

            self.assertEqual(report["summary"]["water_kind_distribution"]["swimming_pool"], 1)
            self.assertEqual(report["summary"]["water_kind_distribution"]["fountain"], 1)
            self.assertEqual(report["summary"]["source_water_signal_distribution"]["natural:water"], 1)
            self.assertEqual(report["summary"]["source_water_signal_distribution"]["leisure:swimming_pool"], 1)
            self.assertEqual(report["summary"]["source_water_signal_distribution"]["amenity:fountain"], 1)
            self.assertEqual(report["summary"]["source_water_signal_distribution"]["waterway:stream"], 1)

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("manifest water", html)
            self.assertIn("source water", html)
            self.assertIn("swimming_pool", html)
            self.assertIn("amenity:fountain", html)

    def test_report_surfaces_water_signal_and_geometry_drift(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "WaterDriftTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 4,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [],
                        "water": [
                            {
                                "id": "river_1",
                                "kind": "river",
                                "type": "ribbon",
                                "material": "Water",
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 16, "y": 0, "z": 0}],
                            },
                            {
                                "id": "fountain_1",
                                "kind": "fountain",
                                "type": "ribbon",
                                "material": "Water",
                                "points": [{"x": 24, "y": 0, "z": 0}, {"x": 28, "y": 0, "z": 2}],
                            },
                            {
                                "id": "pool_1",
                                "kind": "swimming_pool",
                                "type": "polygon",
                                "material": "Water",
                                "footprint": [
                                    {"x": 40, "z": 0},
                                    {"x": 50, "z": 0},
                                    {"x": 50, "z": 8},
                                    {"x": 40, "z": 8},
                                ],
                            },
                            {
                                "id": "pond_1",
                                "kind": "pond",
                                "type": "polygon",
                                "material": "Water",
                                "footprint": [
                                    {"x": 60, "z": 0},
                                    {"x": 72, "z": 0},
                                    {"x": 72, "z": 10},
                                    {"x": 60, "z": 10},
                                ],
                            },
                        ],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {
                                "type": "way",
                                "id": 1,
                                "nodes": [101, 102],
                                "tags": {"waterway": "stream"},
                            },
                            {
                                "type": "node",
                                "id": 2,
                                "lat": 30.004,
                                "lon": -96.996,
                                "tags": {"amenity": "fountain"},
                            },
                            {
                                "type": "way",
                                "id": 3,
                                "nodes": [201, 202, 203, 201],
                                "tags": {"leisure": "swimming_pool"},
                            },
                            {
                                "type": "way",
                                "id": 4,
                                "nodes": [301, 302, 303, 301],
                                "tags": {"natural": "water"},
                            },
                            {"type": "node", "id": 101, "lat": 30.001, "lon": -96.999},
                            {"type": "node", "id": 102, "lat": 30.001, "lon": -96.998},
                            {"type": "node", "id": 201, "lat": 30.003, "lon": -96.999},
                            {"type": "node", "id": 202, "lat": 30.003, "lon": -96.998},
                            {"type": "node", "id": 203, "lat": 30.004, "lon": -96.998},
                            {"type": "node", "id": 301, "lat": 30.006, "lon": -96.999},
                            {"type": "node", "id": 302, "lat": 30.007, "lon": -96.998},
                            {"type": "node", "id": 303, "lat": 30.006, "lon": -96.997},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("source_to_manifest_water_signal_drift", codes)
            self.assertIn("source_to_manifest_water_geometry_drift", codes)
            self.assertEqual(report["summary"]["water_signal_mismatch_count"], 2)
            self.assertEqual(report["summary"]["water_geometry_mismatch_count"], 1)
            self.assertCountEqual(
                [row["source_water_signal"] for row in report["summary"]["water_signal_mismatches"]],
                ["waterway:river", "waterway:stream"],
            )
            self.assertEqual(report["summary"]["water_geometry_mismatch_records"][0]["kind"], "fountain")
            self.assertEqual(report["summary"]["water_geometry_mismatch_records"][0]["expected_geometry_type"], "polygon")

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("source_to_manifest_water_signal_drift", html)
            self.assertIn("source_to_manifest_water_geometry_drift", html)
            self.assertIn("waterway:stream", html)
            self.assertIn("fountain", html)

    def test_report_surfaces_pedestrian_signal_drift(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "PedestrianDriftTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 2,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "way_101",
                                "kind": "footway",
                                "subkind": "footway",
                                "widthStuds": 8,
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 20, "y": 0, "z": 0}],
                            }
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
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {"type": "way", "id": 101, "nodes": [1, 2], "tags": {"highway": "footway"}},
                            {"type": "way", "id": 102, "nodes": [3, 4], "tags": {"highway": "path"}},
                            {
                                "type": "way",
                                "id": 103,
                                "nodes": [5, 6],
                                "tags": {"highway": "residential", "sidewalk": "both"},
                            },
                            {"type": "node", "id": 1, "lat": 30.001, "lon": -96.999},
                            {"type": "node", "id": 2, "lat": 30.001, "lon": -96.998},
                            {"type": "node", "id": 3, "lat": 30.002, "lon": -96.999},
                            {"type": "node", "id": 4, "lat": 30.002, "lon": -96.998},
                            {"type": "node", "id": 5, "lat": 30.003, "lon": -96.999},
                            {"type": "node", "id": 6, "lat": 30.003, "lon": -96.998},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("source_to_manifest_pedestrian_drift", codes)
            self.assertEqual(report["summary"]["pedestrian_signal_mismatch_count"], 2)
            self.assertCountEqual(
                [row["pedestrian_signal"] for row in report["summary"]["pedestrian_signal_mismatches"]],
                ["highway:path", "sidewalk:present"],
            )

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("source_to_manifest_pedestrian_drift", html)
            self.assertIn("sidewalk:present", html)
            self.assertIn("highway:path", html)

    def test_report_surfaces_tree_species_drift_by_source_id(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "TreeDriftTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 3,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [],
                        "water": [],
                        "props": [
                            {"id": "tree_10", "kind": "tree", "species": "oak", "position": {"x": 0, "y": 0, "z": 0}},
                            {"id": "tree_11", "kind": "tree", "position": {"x": 4, "y": 0, "z": 4}},
                            {"id": "tree_12", "kind": "tree", "species": "maple", "position": {"x": 8, "y": 0, "z": 8}},
                        ],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {"type": "node", "id": 10, "lat": 30.0010, "lon": -96.9990, "tags": {"natural": "tree", "species": "oak"}},
                            {"type": "node", "id": 11, "lat": 30.0011, "lon": -96.9989, "tags": {"natural": "tree", "genus": "quercus"}},
                            {"type": "node", "id": 12, "lat": 30.0012, "lon": -96.9988, "tags": {"natural": "tree", "taxon": "acer rubrum"}},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("source_to_manifest_tree_species_drift", codes)
            self.assertEqual(report["summary"]["tree_species_mismatch_count"], 2)
            self.assertCountEqual(
                [row["id"] for row in report["summary"]["tree_species_mismatches"]],
                ["tree_11", "tree_12"],
            )
            self.assertCountEqual(
                [(row["id"], row["source_species"], row["manifest_species"]) for row in report["summary"]["tree_species_mismatches"]],
                [
                    ("tree_11", "quercus", ""),
                    ("tree_12", "acer rubrum", "maple"),
                ],
            )

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("source_to_manifest_tree_species_drift", html)
            self.assertIn("source tree species", html)
            self.assertIn("acer rubrum", html)
            self.assertIn("quercus", html)

    def test_report_surfaces_rail_signal_drift(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "RailDriftTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 2,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [
                            {
                                "id": "osm_rail_101",
                                "kind": "rail",
                                "widthStuds": 4,
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 32, "y": 0, "z": 0}],
                            }
                        ],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {"type": "way", "id": 101, "nodes": [1, 2], "tags": {"railway": "rail"}},
                            {"type": "way", "id": 102, "nodes": [3, 4], "tags": {"railway": "tram"}},
                            {"type": "node", "id": 1, "lat": 30.001, "lon": -96.999},
                            {"type": "node", "id": 2, "lat": 30.001, "lon": -96.998},
                            {"type": "node", "id": 3, "lat": 30.002, "lon": -96.999},
                            {"type": "node", "id": 4, "lat": 30.002, "lon": -96.998},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("source_to_manifest_rail_drift", codes)
            self.assertEqual(report["summary"]["rail_signal_mismatch_count"], 1)
            self.assertEqual(
                report["summary"]["source_rail_signal_distribution"],
                {"railway:rail": 1, "railway:tram": 1},
            )
            self.assertEqual(report["summary"]["manifest_rail_signal_distribution"], {"railway:rail": 1})
            self.assertEqual(
                report["summary"]["rail_signal_mismatches"],
                [
                    {
                        "rail_signal": "railway:tram",
                        "source_count": 1,
                        "manifest_count": 0,
                    }
                ],
            )
            self.assertEqual(report["summary"]["rail_signal_record_mismatch_count"], 1)
            self.assertEqual(
                report["summary"]["rail_signal_record_mismatches"],
                [
                    {
                        "id": "osm_rail_102",
                        "source_rail_signal": "railway:tram",
                        "manifest_rail_signal": "",
                    }
                ],
            )

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("source_to_manifest_rail_drift", html)
            self.assertIn("source rail", html)
            self.assertIn("manifest rail", html)
            self.assertIn("osm_rail_102", html)
            self.assertIn("railway:tram", html)

    def test_report_flags_broad_suspicious_material_usage_combinations(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "BroadMaterialRiskTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 4,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_hospital",
                                "name": "Saint Mercy Hospital",
                                "usage": "hospital",
                                "material": "SmoothPlastic",
                                "roof": "flat",
                                "height": 24,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 12, "z": 0},
                                    {"x": 12, "z": 12},
                                    {"x": 0, "z": 12},
                                ],
                            },
                            {
                                "id": "osm_house",
                                "name": "Glass Cottage",
                                "usage": "detached",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 10,
                                "footprint": [
                                    {"x": 20, "z": 0},
                                    {"x": 30, "z": 0},
                                    {"x": 30, "z": 10},
                                    {"x": 20, "z": 10},
                                ],
                            },
                            {
                                "id": "osm_warehouse",
                                "name": "East Warehouse",
                                "usage": "warehouse",
                                "material": "Metal",
                                "roof": "flat",
                                "height": 14,
                                "footprint": [
                                    {"x": 40, "z": 0},
                                    {"x": 56, "z": 0},
                                    {"x": 56, "z": 12},
                                    {"x": 40, "z": 12},
                                ],
                            },
                            {
                                "id": "osm_school",
                                "name": "Brick School",
                                "usage": "school",
                                "material": "Brick",
                                "roof": "flat",
                                "height": 18,
                                "footprint": [
                                    {"x": 64, "z": 0},
                                    {"x": 78, "z": 0},
                                    {"x": 78, "z": 12},
                                    {"x": 64, "z": 12},
                                ],
                            },
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

            report = audit.build_report(manifest_path, [])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertIn("implausible_building_material_assignments", codes)
            suspicious = report["summary"]["suspicious_material_assignments"]
            self.assertEqual(len(suspicious), 2)
            self.assertEqual([entry["id"] for entry in suspicious], ["osm_hospital", "osm_house"])
            self.assertEqual(suspicious[0]["signals"], ["usage:hospital", "family:plastic"])
            self.assertEqual(suspicious[1]["signals"], ["usage:detached"])
            self.assertEqual(report["summary"]["suspicious_material_assignment_by_signal"]["family:plastic"], 1)
            self.assertEqual(report["summary"]["suspicious_material_assignment_by_signal"]["usage:hospital"], 1)
            self.assertEqual(report["summary"]["suspicious_material_assignment_by_signal"]["usage:detached"], 1)

    def test_report_treats_religious_subtype_refinement_as_benign(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "SubtypeTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 1,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_9",
                                "name": "Neighborhood Church",
                                "usage": "church",
                                "material": "Cobblestone",
                                "roof": "gabled",
                                "height": 18,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 10, "z": 0},
                                    {"x": 10, "z": 10},
                                    {"x": 0, "z": 10},
                                ],
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
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.0, "lon": -97.0},
                            {"type": "node", "id": 2, "lat": 30.0, "lon": -96.9999},
                            {"type": "node", "id": 3, "lat": 30.0001, "lon": -96.9999},
                            {"type": "node", "id": 4, "lat": 30.0001, "lon": -97.0},
                            {
                                "type": "way",
                                "id": 9,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {
                                    "building": "yes",
                                    "amenity": "place_of_worship",
                                    "name": "Neighborhood Church",
                                },
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])

            codes = {finding["code"] for finding in report["findings"]}
            self.assertNotIn("source_to_manifest_usage_drift", codes)
            self.assertEqual(report["summary"]["source_usage_mismatch_count"], 0)
            self.assertEqual(report["summary"]["source_usage_refinement_count"], 1)
            self.assertEqual(report["summary"]["source_usage_refinements"][0]["source_usage_signal"], "religious")
            self.assertEqual(report["summary"]["source_usage_refinements"][0]["manifest_usage"], "church")

    def test_report_aggregates_multiple_sources_and_flags_geometry_bloat_and_scale_mismatch(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            overpass_path = root / "fixture-overpass.json"
            overture_path = root / "fixture-overture.geojson"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "ScaleDriftTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 0.5,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 3,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 2,
                            "width": 4,
                            "depth": 4,
                            "heights": [0] * 16,
                            "materials": ["Grass"] * 16,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_1",
                                "usage": "yes",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 12,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 400, "z": 0},
                                    {"x": 400, "z": 400},
                                    {"x": 0, "z": 400},
                                ],
                            },
                            {
                                "id": "ov_1",
                                "usage": "building",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 10,
                                "footprint": [
                                    {"x": 500, "z": 0},
                                    {"x": 700, "z": 0},
                                    {"x": 700, "z": 200},
                                    {"x": 500, "z": 200},
                                ],
                            },
                            {
                                "id": "ov_2",
                                "usage": "building",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 10,
                                "footprint": [
                                    {"x": 800, "z": 0},
                                    {"x": 1000, "z": 0},
                                    {"x": 1000, "z": 200},
                                    {"x": 800, "z": 200},
                                ],
                            },
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
            overpass_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.004, "lon": -96.996},
                            {"type": "node", "id": 2, "lat": 30.004, "lon": -96.9955},
                            {"type": "node", "id": 3, "lat": 30.0045, "lon": -96.9955},
                            {"type": "node", "id": 4, "lat": 30.0045, "lon": -96.996},
                            {
                                "type": "way",
                                "id": 100,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {"building": "yes"},
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            overture_path.write_text(
                json.dumps(
                    {
                        "type": "FeatureCollection",
                        "features": [
                            {
                                "type": "Feature",
                                "geometry": {
                                    "type": "Polygon",
                                    "coordinates": [
                                        [
                                            [-96.994, 30.004],
                                            [-96.9935, 30.004],
                                            [-96.9935, 30.0045],
                                            [-96.994, 30.0045],
                                            [-96.994, 30.004],
                                        ]
                                    ],
                                },
                                "properties": {"class": "commercial", "height": 9.0},
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [overpass_path, overture_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertEqual(len(report["data_sources"]), 2)
            self.assertEqual(report["summary"]["source_alignment"]["source_building_geometry_count"], 2)
            self.assertEqual(
                report["summary"]["source_alignment"]["manifest_building_source_breakdown"]["overture"],
                2,
            )
            self.assertEqual(report["source_summary"]["overture"]["building_geometry_count"], 1)
            self.assertIn("source_to_manifest_geometry_bloat", codes)
            self.assertIn("world_scale_mismatch", codes)

    def test_generic_usage_ratio_counts_building_and_yes_as_collapse(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "UsageAuditTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 2,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_1",
                                "usage": "yes",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 8,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 10, "z": 0},
                                    {"x": 10, "z": 10},
                                    {"x": 0, "z": 10},
                                ],
                            },
                            {
                                "id": "ov_1",
                                "usage": "building",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 8,
                                "footprint": [
                                    {"x": 20, "z": 0},
                                    {"x": 30, "z": 0},
                                    {"x": 30, "z": 10},
                                    {"x": 20, "z": 10},
                                ],
                            },
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
            report = audit.build_report(manifest_path, [])

            self.assertEqual(report["summary"]["generic_usage_ratio"], 1.0)

    def test_source_alignment_canonicalizes_overlapping_overture_gap_fill(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            overpass_path = root / "fixture-overpass.json"
            overture_path = root / "fixture-overture.geojson"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "CanonicalSourceTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 1,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_1",
                                "usage": "office",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 12,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 48, "z": 0},
                                    {"x": 48, "z": 36},
                                    {"x": 0, "z": 36},
                                ],
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
            overpass_path.write_text(
                json.dumps(
                    {
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.0040, "lon": -96.9960},
                            {"type": "node", "id": 2, "lat": 30.0040, "lon": -96.9956},
                            {"type": "node", "id": 3, "lat": 30.0043, "lon": -96.9956},
                            {"type": "node", "id": 4, "lat": 30.0043, "lon": -96.9960},
                            {
                                "type": "way",
                                "id": 100,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {"building": "office"},
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            overture_path.write_text(
                json.dumps(
                    {
                        "type": "FeatureCollection",
                        "features": [
                            {
                                "type": "Feature",
                                "geometry": {
                                    "type": "Polygon",
                                    "coordinates": [
                                        [
                                            [-96.99598, 30.00402],
                                            [-96.99558, 30.00402],
                                            [-96.99558, 30.00428],
                                            [-96.99598, 30.00428],
                                            [-96.99598, 30.00402],
                                        ]
                                    ],
                                },
                                "properties": {"class": "commercial", "height": 10.0},
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [overpass_path, overture_path])
            source_alignment = report["summary"]["source_alignment"]

            self.assertEqual(source_alignment["source_building_geometry_count"], 1)
            self.assertEqual(source_alignment["raw_source_building_geometry_count"], 2)
            self.assertEqual(
                source_alignment["canonical_source_building_source_breakdown"],
                {"osm": 1},
            )
            self.assertEqual(
                source_alignment["source_duplicate_overlap_counts"]["overture_dropped_as_duplicate"],
                1,
            )
            self.assertAlmostEqual(source_alignment["manifest_to_source_building_ratio"], 1.0, places=4)

    def test_report_flags_building_area_bloat_and_road_gap_against_source_geometry(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            overpass_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "AreaGapTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 4,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "road_1",
                                "kind": "residential",
                                "widthStuds": 8,
                                "surface": "asphalt",
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 24, "y": 0, "z": 0}],
                            }
                        ],
                        "buildings": [
                            {
                                "id": "osm_1",
                                "usage": "office",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 10,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 400, "z": 0},
                                    {"x": 400, "z": 400},
                                    {"x": 0, "z": 400},
                                ],
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
            overpass_path.write_text(
                json.dumps(
                    {
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.0040, "lon": -96.9960},
                            {"type": "node", "id": 2, "lat": 30.0040, "lon": -96.9957},
                            {"type": "node", "id": 3, "lat": 30.0043, "lon": -96.9957},
                            {"type": "node", "id": 4, "lat": 30.0043, "lon": -96.9960},
                            {
                                "type": "way",
                                "id": 100,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {"building": "office"},
                            },
                            {"type": "node", "id": 11, "lat": 30.0035, "lon": -96.9965},
                            {"type": "node", "id": 12, "lat": 30.0036, "lon": -96.9962},
                            {
                                "type": "way",
                                "id": 200,
                                "nodes": [11, 12],
                                "tags": {"highway": "residential"},
                            },
                            {"type": "node", "id": 21, "lat": 30.0038, "lon": -96.9958},
                            {"type": "node", "id": 22, "lat": 30.0041, "lon": -96.9954},
                            {
                                "type": "way",
                                "id": 201,
                                "nodes": [21, 22],
                                "tags": {"highway": "residential"},
                            },
                            {"type": "node", "id": 31, "lat": 30.0042, "lon": -96.9964},
                            {"type": "node", "id": 32, "lat": 30.0045, "lon": -96.9961},
                            {
                                "type": "way",
                                "id": 202,
                                "nodes": [31, 32],
                                "tags": {"highway": "service"},
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [overpass_path])
            codes = {finding["code"] for finding in report["findings"]}
            source_alignment = report["summary"]["source_alignment"]

            self.assertEqual(source_alignment["source_building_geometry_count"], 1)
            self.assertEqual(source_alignment["source_road_geometry_count"], 3)
            self.assertGreater(source_alignment["source_building_footprint_area"], 0.0)
            self.assertGreater(source_alignment["manifest_building_footprint_area"], 100000.0)
            self.assertLess(source_alignment["building_footprint_area_alignment_ratio"], 0.5)
            self.assertAlmostEqual(source_alignment["manifest_to_source_road_ratio"], 1.0 / 3.0, places=4)
            self.assertIn("source_to_manifest_building_area_bloat", codes)
            self.assertIn("source_to_manifest_road_gap", codes)

    def test_source_bounds_include_full_overpass_way_geometry_not_just_in_bbox_nodes(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            overpass_path = root / "fixture-overpass.json"
            overpass_path.write_text(
                json.dumps(
                    {
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.0000, "lon": -97.0000},
                            {"type": "node", "id": 2, "lat": 30.0000, "lon": -96.9880},
                            {"type": "node", "id": 3, "lat": 30.0020, "lon": -96.9880},
                            {"type": "node", "id": 4, "lat": 30.0020, "lon": -97.0000},
                            {
                                "type": "way",
                                "id": 10,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {"building": "yes"},
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            source_summary, bounds, _ = audit._build_source_summary(
                [overpass_path],
                bbox={
                    "minLat": 29.9990,
                    "minLon": -96.9980,
                    "maxLat": 30.0015,
                    "maxLon": -96.9900,
                },
                center_lat=30.0000,
                center_lon=-96.9940,
                meters_per_stud=1.0,
            )

            self.assertIn("osm", source_summary)
            self.assertIsNotNone(bounds["max_x"])
            self.assertGreater(
                bounds["max_x"],
                500.0,
                "source bounds should preserve the full way geometry even when some member nodes extend beyond the bbox"
            )

    def test_scale_alignment_uses_in_bbox_source_bounds_not_full_geometry_extensions(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            overpass_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "BoundaryTruthTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 29.9990,
                        "minLon": -96.9980,
                        "maxLat": 30.0015,
                        "maxLon": -96.9900,
                    },
                    "totalFeatures": 1,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": -192.64995, "y": 0.0, "z": -139.14937},
                        "terrain": None,
                        "roads": [],
                        "rails": [],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "buildings": [
                            {
                                "id": "osm_10",
                                "material": "Concrete",
                                "footprint": [
                                    {"x": 0.0, "z": 0.0},
                                    {"x": 500.0, "z": 0.0},
                                    {"x": 500.0, "z": 200.0},
                                    {"x": 0.0, "z": 200.0},
                                ],
                                "baseY": 0.0,
                                "height": 20.0,
                                "roof": "flat",
                            }
                        ],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            overpass_path.write_text(
                json.dumps(
                    {
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.0000, "lon": -97.0000},
                            {"type": "node", "id": 2, "lat": 30.0000, "lon": -96.9880},
                            {"type": "node", "id": 3, "lat": 30.0020, "lon": -96.9880},
                            {"type": "node", "id": 4, "lat": 30.0020, "lon": -97.0000},
                            {
                                "type": "way",
                                "id": 10,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {"building": "yes"},
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [overpass_path])
            codes = {finding["code"] for finding in report["findings"]}

            self.assertNotIn(
                "world_scale_mismatch",
                codes,
                "scale alignment should use in-bbox source bounds so large intersecting geometries do not look like global world scaling regressions",
            )
            self.assertIn("source_full_geometry_bounds", report["summary"]["scale_alignment"])
            self.assertGreater(
                report["summary"]["scale_alignment"]["source_full_geometry_bounds"]["max_x"],
                report["summary"]["scale_alignment"]["source_bounds"]["max_x"],
            )

    def test_road_source_alignment_uses_unique_manifest_ids_not_chunk_split_count(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            overpass_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "RoadSplitTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 2,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "osm_200",
                                "kind": "residential",
                                "widthStuds": 8,
                                "surface": "asphalt",
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 20, "y": 0, "z": 0}],
                            }
                        ],
                        "buildings": [],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    },
                    {
                        "id": "1_0",
                        "originStuds": {"x": 256, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "osm_200",
                                "kind": "residential",
                                "widthStuds": 8,
                                "surface": "asphalt",
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 20, "y": 0, "z": 0}],
                            }
                        ],
                        "buildings": [],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    },
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            overpass_path.write_text(
                json.dumps(
                    {
                        "elements": [
                            {"type": "node", "id": 11, "lat": 30.0035, "lon": -96.9965},
                            {"type": "node", "id": 12, "lat": 30.0036, "lon": -96.9962},
                            {
                                "type": "way",
                                "id": 200,
                                "nodes": [11, 12],
                                "tags": {"highway": "residential"},
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [overpass_path])
            source_alignment = report["summary"]["source_alignment"]
            codes = {finding["code"] for finding in report["findings"]}

            self.assertEqual(source_alignment["manifest_unique_road_geometry_count"], 1)
            self.assertEqual(source_alignment["source_road_geometry_count"], 1)
            self.assertEqual(source_alignment["manifest_to_source_road_ratio"], 1.0)
            self.assertEqual(source_alignment["road_chunk_split_factor"], 2.0)
            self.assertNotIn("source_to_manifest_road_bloat", codes)

    def test_report_can_focus_on_local_zone(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            overpass_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "ZoneTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 4,
                },
                "chunks": [
                    {
                        "id": "near",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "osm_200",
                                "kind": "residential",
                                "widthStuds": 8,
                                "surface": "asphalt",
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 20, "y": 0, "z": 0}],
                            }
                        ],
                        "buildings": [
                            {
                                "id": "osm_near",
                                "usage": "office",
                                "material": "Glass",
                                "roof": "flat",
                                "height": 10,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 20, "z": 0},
                                    {"x": 20, "z": 20},
                                    {"x": 0, "z": 20},
                                ],
                            }
                        ],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    },
                    {
                        "id": "far",
                        "originStuds": {"x": 1000, "y": 0, "z": 1000},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "osm_201",
                                "kind": "service",
                                "widthStuds": 8,
                                "surface": "asphalt",
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 20, "y": 0, "z": 0}],
                            }
                        ],
                        "buildings": [
                            {
                                "id": "osm_far",
                                "usage": "warehouse",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 10,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 20, "z": 0},
                                    {"x": 20, "z": 20},
                                    {"x": 0, "z": 20},
                                ],
                            }
                        ],
                        "water": [],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    },
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            overpass_path.write_text(
                json.dumps(
                    {
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.0040, "lon": -96.9960},
                            {"type": "node", "id": 2, "lat": 30.0040, "lon": -96.9958},
                            {"type": "node", "id": 3, "lat": 30.0042, "lon": -96.9958},
                            {"type": "node", "id": 4, "lat": 30.0042, "lon": -96.9960},
                            {
                                "type": "way",
                                "id": 100,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {"building": "office"},
                            },
                            {"type": "node", "id": 11, "lat": 30.0041, "lon": -96.9962},
                            {"type": "node", "id": 12, "lat": 30.0041, "lon": -96.9960},
                            {
                                "type": "way",
                                "id": 200,
                                "nodes": [11, 12],
                                "tags": {"highway": "residential"},
                            },
                            {"type": "node", "id": 21, "lat": 30.0098, "lon": -96.9902},
                            {"type": "node", "id": 22, "lat": 30.0098, "lon": -96.9900},
                            {"type": "node", "id": 23, "lat": 30.0100, "lon": -96.9900},
                            {"type": "node", "id": 24, "lat": 30.0100, "lon": -96.9902},
                            {
                                "type": "way",
                                "id": 101,
                                "nodes": [21, 22, 23, 24, 21],
                                "tags": {"building": "warehouse"},
                            },
                            {"type": "node", "id": 31, "lat": 30.0099, "lon": -96.9904},
                            {"type": "node", "id": 32, "lat": 30.0099, "lon": -96.9902},
                            {
                                "type": "way",
                                "id": 201,
                                "nodes": [31, 32],
                                "tags": {"highway": "service"},
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            full_report = audit.build_report(manifest_path, [overpass_path])
            zone_report = audit.build_report(manifest_path, [overpass_path], focus_x=0.0, focus_z=0.0, radius=200.0)

            self.assertEqual(full_report["summary"]["building_count"], 2)
            self.assertEqual(zone_report["summary"]["building_count"], 1)
            self.assertEqual(zone_report["summary"]["roads_count"], 1)
            self.assertEqual(zone_report["summary"]["source_alignment"]["source_building_geometry_count"], 1)
            self.assertEqual(zone_report["summary"]["source_alignment"]["source_road_geometry_count"], 1)
            self.assertEqual(zone_report["summary"]["source_alignment"]["source_building_source_breakdown"]["osm"], 1)
            self.assertEqual(zone_report["summary"]["source_alignment"]["manifest_building_source_breakdown"]["osm"], 1)
            self.assertIn("zone", zone_report)
            self.assertEqual(zone_report["zone"]["radius"], 200.0)
            self.assertEqual(zone_report["zone"]["focus_x"], 0.0)
            self.assertEqual(zone_report["zone"]["focus_z"], 0.0)

    def test_current_austin_manifest_surfaces_known_quality_risks(self) -> None:
        audit = load_module()
        manifest_path = ROOT / "rust" / "out" / "austin-manifest.json"
        source_paths = [
            ROOT / "rust" / "data" / "austin_overpass.json",
            ROOT / "rust" / "data" / "overture_buildings.geojson",
        ]

        report = audit.build_report(manifest_path, source_paths)
        codes = {finding["code"] for finding in report["findings"]}

        self.assertNotIn("roof_shape_collapse", codes)
        self.assertNotIn("terrain_material_monotony", codes)
        self.assertNotIn("building_usage_collapse", codes)
        self.assertNotIn("building_material_collapse", codes)
        self.assertIn("road_surface_metadata_sparse", codes)
        self.assertNotIn("source_to_manifest_road_bloat", codes)
        self.assertNotIn("world_scale_mismatch", codes)
        self.assertNotIn("building_height_scale_mismatch", codes)
        self.assertGreater(report["summary"]["building_count"], 1000)
        self.assertGreater(report["summary"]["building_hole_count"], 0)
        self.assertLess(report["summary"]["generic_usage_ratio"], 0.05)
        self.assertLess(report["summary"]["flat_roof_ratio"], 0.9)
        self.assertLess(report["summary"]["dominant_building_material_ratio"], 0.5)
        self.assertGreater(report["osm_summary"]["element_count"], 1000)
        self.assertGreater(report["osm_summary"]["type_counts"]["relation"], 100)
        self.assertGreater(report["osm_summary"]["building_relation_with_inner_count"], 0)
        self.assertGreaterEqual(report["summary"]["source_alignment"]["topology_alignment_ratio"], 1.0)
        self.assertGreater(report["summary"]["scale_alignment"]["world_alignment_ratio"], 0.99)
        self.assertGreater(report["summary"]["source_alignment"]["road_chunk_split_factor"], 1.0)
        self.assertLess(
            report["summary"]["source_alignment"]["manifest_building_source_breakdown"]["overture"],
            1500,
        )
        self.assertGreater(
            report["summary"]["source_alignment"]["source_duplicate_overlap_counts"]["overture_dropped_as_duplicate"],
            1000,
        )
        self.assertIn("quality_scores", report["summary"])
        self.assertIn("hotspots", report["summary"])
        self.assertIn("chunk_building_density", report["summary"]["hotspots"])

    def test_report_flags_strong_source_identity_loss_and_transform(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "IdentityLossTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 1,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "proxy_capitol_shell",
                                "name": "Capitol Complex Annex",
                                "usage": "government",
                                "material": "Limestone",
                                "roof": "flat",
                                "height": 24,
                                "footprint": [
                                    {"x": -557, "z": 627},
                                    {"x": -543, "z": 627},
                                    {"x": -543, "z": 643},
                                    {"x": -557, "z": 643},
                                ],
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

            elements = [
                {"type": "node", "id": 1, "lat": 30.00000, "lon": -97.00000},
                {"type": "node", "id": 2, "lat": 30.00000, "lon": -96.99988},
                {"type": "node", "id": 3, "lat": 30.00012, "lon": -96.99988},
                {"type": "node", "id": 4, "lat": 30.00012, "lon": -97.00000},
                {
                    "type": "way",
                    "id": 25758443,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {
                        "building": "government",
                        "name": "Texas State Capitol",
                        "building:material": "stone",
                    },
                },
                {"type": "node", "id": 11, "lat": 30.00100, "lon": -97.00100},
                {"type": "node", "id": 12, "lat": 30.00100, "lon": -97.00088},
                {"type": "node", "id": 13, "lat": 30.00112, "lon": -97.00088},
                {"type": "node", "id": 14, "lat": 30.00112, "lon": -97.00100},
                {
                    "type": "way",
                    "id": 4001,
                    "nodes": [11, 12, 13, 14, 11],
                    "tags": {
                        "building": "yes",
                        "amenity": "courthouse",
                        "name": "Travis County Courthouse",
                        "building:material": "stone",
                    },
                },
            ]
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": elements,
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])

            codes = {finding["code"] for finding in report["findings"]}
            self.assertIn("source_to_manifest_identity_loss", codes)
            self.assertIn("source_to_manifest_identity_transform", codes)
            self.assertEqual(report["summary"]["strong_source_building_count"], 2)
            self.assertEqual(report["summary"]["source_identity_loss_count"], 1)
            self.assertEqual(report["summary"]["source_identity_transform_count"], 1)
            self.assertEqual(report["summary"]["source_identity_loss_by_usage"]["courthouse"], 1)
            self.assertEqual(report["summary"]["source_identity_transform_by_usage"]["government"], 1)
            self.assertEqual(report["summary"]["source_identity_loss_by_reason"]["name:courthouse"], 1)
            self.assertEqual(report["summary"]["source_identity_transform_by_reason"]["name:capitol"], 1)
            self.assertEqual(
                report["summary"]["source_identity_transform_records"][0]["name"],
                "Texas State Capitol",
            )
            self.assertEqual(
                report["summary"]["source_identity_loss_records"][0]["name"],
                "Travis County Courthouse",
            )
            self.assertEqual(
                report["summary"]["source_identity_transform_records"][0]["manifest_matches"][0]["id"],
                "proxy_capitol_shell",
            )

    def test_report_flags_named_building_way_lost_inside_non_building_relation(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "InnerLossTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 0,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
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

            elements = [
                {"type": "node", "id": 1, "lat": 30.00000, "lon": -97.00000},
                {"type": "node", "id": 2, "lat": 30.00000, "lon": -96.99988},
                {"type": "node", "id": 3, "lat": 30.00012, "lon": -96.99988},
                {"type": "node", "id": 4, "lat": 30.00012, "lon": -97.00000},
                {
                    "type": "way",
                    "id": 25758443,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {
                        "building": "government",
                        "name": "Texas State Capitol",
                        "building:material": "stone",
                    },
                },
                {"type": "node", "id": 11, "lat": 29.9999, "lon": -97.0001},
                {"type": "node", "id": 12, "lat": 29.9999, "lon": -96.9997},
                {"type": "node", "id": 13, "lat": 30.0002, "lon": -96.9997},
                {"type": "node", "id": 14, "lat": 30.0002, "lon": -97.0001},
                {
                    "type": "way",
                    "id": 5000,
                    "nodes": [11, 12, 13, 14, 11],
                    "tags": {"leisure": "park", "name": "Capitol Square"},
                },
                {
                    "type": "relation",
                    "id": 13105661,
                    "tags": {"type": "multipolygon", "leisure": "park", "name": "Capitol Square"},
                    "members": [
                        {"type": "way", "ref": 5000, "role": "outer"},
                        {"type": "way", "ref": 25758443, "role": "inner"},
                    ],
                },
            ]
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": elements,
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}
            self.assertIn("source_to_manifest_inner_building_identity_loss", codes)
            self.assertEqual(report["summary"]["inner_non_building_relation_identity_loss_count"], 1)
            row = report["summary"]["inner_non_building_relation_identity_loss_records"][0]
            self.assertEqual(row["source_id"], "osm_25758443")
            self.assertEqual(row["name"], "Texas State Capitol")
            self.assertEqual(row["relation_contexts"], ["Capitol Square"])

    def test_overture_identity_audit_uses_source_record_id_when_present(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overture.geojson"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "OvertureIdentityTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 1,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "ov_w25758443@23",
                                "name": "Texas State Capitol",
                                "usage": "government",
                                "material": "Limestone",
                                "roof": "flat",
                                "height": 24,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 12, "z": 0},
                                    {"x": 12, "z": 12},
                                    {"x": 0, "z": 12},
                                ],
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

            source = {
                "type": "FeatureCollection",
                "features": [
                    {
                        "type": "Feature",
                        "geometry": {
                            "type": "Polygon",
                            "coordinates": [[
                                [-97.0, 30.0],
                                [-96.99988, 30.0],
                                [-96.99988, 30.00012],
                                [-97.0, 30.00012],
                                [-97.0, 30.0],
                            ]],
                        },
                        "properties": {
                            "id": "0f5209b1-5016-43f0-b85c-8c5b972c3382",
                            "names": {"primary": "Texas State Capitol"},
                            "sources": [{"record_id": "w25758443@23"}],
                            "class": "government",
                            "facade_material": "stone",
                            "has_parts": True,
                        },
                    }
                ],
            }
            source_path.write_text(json.dumps(source), encoding="utf-8")

            report = audit.build_report(manifest_path, [source_path])
            codes = {finding["code"] for finding in report["findings"]}
            self.assertNotIn("source_to_manifest_identity_loss", codes)
            self.assertEqual(report["summary"]["source_identity_loss_count"], 0)
            self.assertEqual(report["summary"]["source_identity_transform_count"], 0)

    def test_zone_identity_audit_uses_global_manifest_id_match(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "ZoneIdentityTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 1,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 1000, "y": 0, "z": 1000},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_42807246",
                                "name": "Robert E. Johnson State Legislative Office Building",
                                "usage": "government",
                                "material": "Limestone",
                                "roof": "flat",
                                "height": 20,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 12, "z": 0},
                                    {"x": 12, "z": 12},
                                    {"x": 0, "z": 12},
                                ],
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

            elements = [
                {"type": "node", "id": 1, "lat": 30.00000, "lon": -97.00000},
                {"type": "node", "id": 2, "lat": 30.00000, "lon": -96.99988},
                {"type": "node", "id": 3, "lat": 30.00012, "lon": -96.99988},
                {"type": "node", "id": 4, "lat": 30.00012, "lon": -97.00000},
                {
                    "type": "way",
                    "id": 42807246,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {
                        "building": "yes",
                        "office": "government",
                        "government": "legislative",
                        "name": "Robert E. Johnson State Legislative Office Building",
                    },
                },
            ]
            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": elements,
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(
                manifest_path,
                [source_path],
                focus_x=5000.0,
                focus_z=5000.0,
                radius=100.0,
            )
            codes = {finding["code"] for finding in report["findings"]}
            self.assertNotIn("source_to_manifest_identity_loss", codes)
            self.assertEqual(report["summary"]["source_identity_loss_count"], 0)

    def test_zone_topology_loss_uses_zone_scoped_inner_ring_count(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "ZoneTopologyTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.1,
                        "maxLon": -96.9,
                    },
                    "totalFeatures": 1,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_local",
                                "name": "Local Shell",
                                "usage": "office",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 16,
                                "footprint": [
                                    {"x": -20, "z": -20},
                                    {"x": 20, "z": -20},
                                    {"x": 20, "z": 20},
                                    {"x": -20, "z": 20},
                                ],
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

            source_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "osm3s": {"timestamp_osm_base": "2026-03-20T02:00:19Z"},
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.20, "lon": -96.80},
                            {"type": "node", "id": 2, "lat": 30.20, "lon": -96.799},
                            {"type": "node", "id": 3, "lat": 30.199, "lon": -96.799},
                            {"type": "node", "id": 4, "lat": 30.199, "lon": -96.80},
                            {"type": "node", "id": 5, "lat": 30.1997, "lon": -96.7997},
                            {"type": "node", "id": 6, "lat": 30.1997, "lon": -96.7993},
                            {"type": "node", "id": 7, "lat": 30.1993, "lon": -96.7993},
                            {"type": "node", "id": 8, "lat": 30.1993, "lon": -96.7997},
                            {"type": "way", "id": 101, "nodes": [1, 2, 3, 4, 1]},
                            {"type": "way", "id": 102, "nodes": [5, 6, 7, 8, 5]},
                            {
                                "type": "relation",
                                "id": 201,
                                "tags": {"type": "multipolygon", "building": "yes", "name": "Far Courtyard"},
                                "members": [
                                    {"type": "way", "ref": 101, "role": "outer"},
                                    {"type": "way", "ref": 102, "role": "inner"},
                                ],
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(
                manifest_path,
                [source_path],
                focus_x=0.0,
                focus_z=0.0,
                radius=100.0,
            )
            codes = {finding["code"] for finding in report["findings"]}
            self.assertEqual(report["summary"]["source_alignment"]["source_building_relations_with_inner"], 0)
            self.assertNotIn("source_to_manifest_topology_loss", codes)

    def test_report_disaggregates_roof_and_water_slices_in_json_and_html(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            overpass_path = root / "fixture-overpass.json"
            overture_path = root / "fixture-overture.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "RoofWaterAuditTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 6,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [],
                        "buildings": [
                            {
                                "id": "osm_10",
                                "name": "City Hall",
                                "usage": "civic",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 14,
                                "footprint": [
                                    {"x": 0, "z": 0},
                                    {"x": 10, "z": 0},
                                    {"x": 10, "z": 10},
                                    {"x": 0, "z": 10},
                                ],
                            },
                            {
                                "id": "osm_11",
                                "name": "First Church",
                                "usage": "church",
                                "material": "Brick",
                                "roof": "gabled",
                                "height": 18,
                                "footprint": [
                                    {"x": 20, "z": 0},
                                    {"x": 30, "z": 0},
                                    {"x": 30, "z": 10},
                                    {"x": 20, "z": 10},
                                ],
                            },
                            {
                                "id": "ov_1",
                                "name": "Commerce Tower",
                                "usage": "office",
                                "material": "Glass",
                                "roof": "sawtooth",
                                "height": 24,
                                "footprint": [
                                    {"x": 40, "z": 0},
                                    {"x": 50, "z": 0},
                                    {"x": 50, "z": 10},
                                    {"x": 40, "z": 10},
                                ],
                            },
                            {
                                "id": "local_1",
                                "name": "Corner Shops",
                                "usage": "retail",
                                "material": "Concrete",
                                "roof": "flat",
                                "height": 12,
                                "footprint": [
                                    {"x": 60, "z": 0},
                                    {"x": 72, "z": 0},
                                    {"x": 72, "z": 12},
                                    {"x": 60, "z": 12},
                                ],
                            },
                        ],
                        "water": [
                            {
                                "id": "osm_water_1",
                                "kind": "river",
                                "material": "Water",
                                "points": [{"x": 0, "y": 0, "z": 40}, {"x": 50, "y": 0, "z": 40}],
                                "widthStuds": 8,
                            },
                            {
                                "id": "water_2",
                                "kind": "pond",
                                "material": "Water",
                                "type": "polygon",
                                "footprint": [
                                    {"x": 60, "z": 40},
                                    {"x": 76, "z": 40},
                                    {"x": 76, "z": 56},
                                    {"x": 60, "z": 56},
                                ],
                            },
                        ],
                        "props": [],
                        "landuse": [],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            overpass_path.write_text(
                json.dumps(
                    {
                        "generator": "Overpass API",
                        "elements": [
                            {"type": "node", "id": 1, "lat": 30.0000, "lon": -97.0000},
                            {"type": "node", "id": 2, "lat": 30.0000, "lon": -96.9999},
                            {"type": "node", "id": 3, "lat": 30.0001, "lon": -96.9999},
                            {"type": "node", "id": 4, "lat": 30.0001, "lon": -97.0000},
                            {"type": "node", "id": 5, "lat": 30.0000, "lon": -96.9997},
                            {"type": "node", "id": 6, "lat": 30.0000, "lon": -96.9996},
                            {"type": "node", "id": 7, "lat": 30.0001, "lon": -96.9996},
                            {"type": "node", "id": 8, "lat": 30.0001, "lon": -96.9997},
                            {
                                "type": "way",
                                "id": 10,
                                "nodes": [1, 2, 3, 4, 1],
                                "tags": {
                                    "building": "yes",
                                    "office": "government",
                                    "name": "City Hall",
                                },
                            },
                            {
                                "type": "way",
                                "id": 11,
                                "nodes": [5, 6, 7, 8, 5],
                                "tags": {
                                    "building": "church",
                                    "amenity": "place_of_worship",
                                    "name": "First Church",
                                },
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            overture_path.write_text(
                json.dumps(
                    {
                        "type": "FeatureCollection",
                        "features": [
                            {
                                "type": "Feature",
                                "geometry": {
                                    "type": "Polygon",
                                    "coordinates": [
                                        [
                                            [-96.9994, 30.0000],
                                            [-96.9993, 30.0000],
                                            [-96.9993, 30.0001],
                                            [-96.9994, 30.0001],
                                            [-96.9994, 30.0000],
                                        ]
                                    ],
                                },
                                "properties": {
                                    "id": "1",
                                    "class": "commercial",
                                    "names": {"primary": "Commerce Tower"},
                                    "height": 24.0,
                                },
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = audit.build_report(manifest_path, [overpass_path, overture_path])

            self.assertEqual(report["summary"]["roof_distribution_by_usage"]["civic"]["flat"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_usage"]["church"]["gabled"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_usage"]["office"]["sawtooth"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_source_usage"]["government"]["flat"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_source_usage"]["religious"]["gabled"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_source_usage"]["commercial"]["sawtooth"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_source_type"]["osm"]["flat"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_source_type"]["osm"]["gabled"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_source_type"]["overture"]["sawtooth"], 1)
            self.assertEqual(report["summary"]["roof_distribution_by_source_type"]["unknown"]["flat"], 1)
            self.assertEqual(report["summary"]["water_kind_distribution_by_type"]["ribbon"]["river"], 1)
            self.assertEqual(report["summary"]["water_kind_distribution_by_type"]["polygon"]["pond"], 1)
            self.assertEqual(report["summary"]["water_kind_distribution_by_source_type"]["osm"]["river"], 1)
            self.assertEqual(report["summary"]["water_kind_distribution_by_source_type"]["unknown"]["pond"], 1)

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("roof by usage", html)
            self.assertIn("roof by source usage", html)
            self.assertIn("roof by source", html)
            self.assertIn("water by type", html)
            self.assertIn("water by source", html)
            self.assertIn("civic / flat", html)
            self.assertIn("government / flat", html)
            self.assertIn("polygon / pond", html)
            self.assertIn("osm / river", html)

    def test_report_emits_non_building_osm_type_diagnostics(self) -> None:
        audit = load_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            manifest_path = root / "fixture-manifest.json"
            source_path = root / "fixture-overpass.json"
            html_path = root / "report.html"

            manifest = {
                "schemaVersion": "0.4.0",
                "meta": {
                    "worldName": "BroadAuditTown",
                    "generator": "test",
                    "source": "pipeline-export",
                    "metersPerStud": 1.0,
                    "chunkSizeStuds": 256,
                    "bbox": {
                        "minLat": 30.0,
                        "minLon": -97.0,
                        "maxLat": 30.01,
                        "maxLon": -96.99,
                    },
                    "totalFeatures": 8,
                },
                "chunks": [
                    {
                        "id": "0_0",
                        "originStuds": {"x": 0, "y": 0, "z": 0},
                        "terrain": {
                            "cellSizeStuds": 4,
                            "width": 2,
                            "depth": 2,
                            "heights": [0, 0, 0, 0],
                            "materials": ["Grass"] * 4,
                            "material": "Grass",
                        },
                        "roads": [
                            {
                                "id": "osm_road_footway",
                                "kind": "footway",
                                "subkind": "sidewalk",
                                "widthStuds": 4,
                                "surface": "PavingStones",
                                "points": [{"x": 0, "y": 0, "z": 0}, {"x": 24, "y": 0, "z": 0}],
                            },
                            {
                                "id": "osm_road_path",
                                "kind": "path",
                                "subkind": "trail",
                                "widthStuds": 5,
                                "surface": "Grass",
                                "points": [{"x": 0, "y": 0, "z": 16}, {"x": 24, "y": 0, "z": 16}],
                            },
                            {
                                "id": "osm_road_residential",
                                "kind": "residential",
                                "subkind": "default",
                                "widthStuds": 10,
                                "surface": "Asphalt",
                                "points": [{"x": 0, "y": 0, "z": 32}, {"x": 24, "y": 0, "z": 32}],
                            },
                        ],
                        "buildings": [],
                        "water": [
                            {
                                "id": "osm_pool",
                                "kind": "swimming_pool",
                                "type": "polygon",
                                "footprint": [
                                    {"x": 40, "z": 0},
                                    {"x": 54, "z": 0},
                                    {"x": 54, "z": 12},
                                    {"x": 40, "z": 12},
                                ],
                            }
                        ],
                        "props": [
                            {
                                "id": "osm_tree_1",
                                "kind": "tree",
                                "species": "oak",
                                "position": {"x": 64, "y": 0, "z": 16},
                            },
                            {
                                "id": "osm_fountain_1",
                                "kind": "fountain",
                                "position": {"x": 72, "y": 0, "z": 24},
                            },
                        ],
                        "landuse": [
                            {
                                "id": "osm_park_1",
                                "kind": "park",
                                "footprint": [
                                    {"x": 80, "z": 0},
                                    {"x": 112, "z": 0},
                                    {"x": 112, "z": 24},
                                    {"x": 80, "z": 24},
                                ],
                            }
                        ],
                        "barriers": [],
                        "rails": [],
                    }
                ],
            }
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            source = {
                "generator": "Overpass API",
                "osm3s": {"timestamp_osm_base": "2026-03-21T00:00:00Z"},
                "elements": [
                    {"type": "node", "id": 1, "lat": 30.0001, "lon": -96.9999},
                    {"type": "node", "id": 2, "lat": 30.0001, "lon": -96.9997},
                    {"type": "node", "id": 3, "lat": 30.0001, "lon": -96.9995},
                    {"type": "node", "id": 4, "lat": 30.0003, "lon": -96.9999},
                    {"type": "node", "id": 5, "lat": 30.0003, "lon": -96.9997},
                    {"type": "node", "id": 6, "lat": 30.0003, "lon": -96.9995},
                    {"type": "node", "id": 7, "lat": 30.0005, "lon": -96.9999},
                    {"type": "node", "id": 8, "lat": 30.0005, "lon": -96.9997},
                    {"type": "node", "id": 9, "lat": 30.0005, "lon": -96.9995},
                    {"type": "node", "id": 10, "lat": 30.0007, "lon": -96.9999, "tags": {"natural": "tree"}},
                    {"type": "node", "id": 11, "lat": 30.0008, "lon": -96.9998, "tags": {"amenity": "fountain"}},
                    {"type": "way", "id": 101, "nodes": [1, 2], "tags": {"highway": "footway"}},
                    {"type": "way", "id": 102, "nodes": [4, 5], "tags": {"highway": "path"}},
                    {"type": "way", "id": 103, "nodes": [7, 8], "tags": {"highway": "residential", "sidewalk": "both"}},
                    {
                        "type": "way",
                        "id": 104,
                        "nodes": [1, 2, 5, 4, 1],
                        "tags": {"leisure": "park"},
                    },
                    {
                        "type": "way",
                        "id": 105,
                        "nodes": [2, 3, 6, 5, 2],
                        "tags": {"leisure": "swimming_pool"},
                    },
                ],
            }
            source_path.write_text(json.dumps(source), encoding="utf-8")

            report = audit.build_report(manifest_path, [source_path])

            self.assertEqual(report["osm_summary"]["source_highway_signal_distribution"]["highway:footway"], 1)
            self.assertEqual(report["osm_summary"]["source_highway_signal_distribution"]["highway:path"], 1)
            self.assertEqual(
                report["osm_summary"]["source_pedestrian_signal_distribution"]["highway:footway"],
                1,
            )
            self.assertEqual(
                report["osm_summary"]["source_pedestrian_signal_distribution"]["highway:path"],
                1,
            )
            self.assertEqual(
                report["osm_summary"]["source_pedestrian_signal_distribution"]["sidewalk:both"],
                1,
            )
            self.assertEqual(
                report["osm_summary"]["source_vegetation_signal_distribution"]["natural:tree"],
                1,
            )
            self.assertEqual(
                report["osm_summary"]["source_vegetation_signal_distribution"]["leisure:park"],
                1,
            )
            self.assertEqual(report["summary"]["road_subkind_distribution"]["sidewalk"], 1)
            self.assertEqual(report["summary"]["pedestrian_way_distribution"]["footway"], 1)
            self.assertEqual(report["summary"]["pedestrian_way_distribution"]["path"], 1)
            self.assertEqual(report["summary"]["prop_kind_distribution"]["tree"], 1)
            self.assertEqual(report["summary"]["prop_kind_distribution"]["fountain"], 1)
            self.assertEqual(report["summary"]["tree_species_distribution"]["oak"], 1)
            self.assertEqual(report["summary"]["vegetation_signal_distribution"]["tree"], 1)
            self.assertEqual(report["summary"]["vegetation_signal_distribution"]["park"], 1)

            audit.write_html_report(report, html_path)
            html = html_path.read_text(encoding="utf-8")
            self.assertIn("Pedestrian Diagnostics", html)
            self.assertIn("Vegetation Diagnostics", html)
            self.assertIn("source highway", html)
            self.assertIn("source pedestrian", html)
            self.assertIn("source vegetation", html)
            self.assertIn("manifest props", html)
            self.assertIn("tree species", html)


if __name__ == "__main__":
    unittest.main()
