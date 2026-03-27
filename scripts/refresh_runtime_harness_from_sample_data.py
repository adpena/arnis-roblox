#!/usr/bin/env python3
"""
Refresh a bounded runtime harness manifest from the current exported Austin manifest artifacts.

This keeps play-mode harness runs on a dev-sized runtime fixture instead of embedding the
full balanced Austin runtime sample-data tree into every clean play place.
"""

from __future__ import annotations

import json
import math
import sqlite3
import shutil
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from refresh_preview_from_sample_data import (  # noqa: E402
    MAX_PREVIEW_BYTES,
    PREVIEW_SELECTION_GUTTER_STUDS,
    SOURCE_INDEX,
    SOURCE_JSON,
    TARGET_CHUNK_IDS,
    _coerce_feature_count,
    _format_lua_value,
    count_chunk_features,
    derive_preview_chunk_ids,
    fragment_preview_chunk,
    load_source_manifest_subset,
    parse_source_chunk_size_studs,
    parse_source_index,
    resolve_source_sqlite_path,
    write_lua_module,
)


RUNTIME_HARNESS_DIR = ROOT / "roblox" / "src" / "ServerStorage" / "SampleData"
RUNTIME_HARNESS_INDEX = RUNTIME_HARNESS_DIR / "AustinHarnessManifestIndex.lua"
RUNTIME_HARNESS_SHARDS = RUNTIME_HARNESS_DIR / "AustinHarnessManifestChunks"
RUNTIME_HARNESS_SHARD_FOLDER = "AustinHarnessManifestChunks"
RUNTIME_HARNESS_LOAD_RADIUS_STUDS = 896
RUNTIME_HARNESS_GUTTER_STUDS = PREVIEW_SELECTION_GUTTER_STUDS
RUNTIME_HARNESS_FALLBACK_CANONICAL_POSITION_STUDS = {"x": 53.8972, "y": 0.0, "z": -578.1390}
RUNTIME_HARNESS_EXCLUDED_SPAWN_KINDS = {"motorway", "motorway_link", "trunk"}
RUNTIME_HARNESS_ROAD_PRIORITY = {
    "service": 10,
    "living_street": 12,
    "residential": 16,
    "unclassified": 20,
    "tertiary": 36,
    "secondary": 52,
    "primary": 80,
    "footway": 120,
    "pedestrian": 130,
    "cycleway": 140,
    "path": 150,
    "trunk": 220,
    "motorway_link": 260,
    "motorway": 300,
    "track": 320,
}
RUNTIME_HARNESS_BUILDING_CLEARANCE_STUDS = 72
RUNTIME_HARNESS_BUILDING_CLEARANCE_SCORE_SCALE = 1000
RUNTIME_HARNESS_BUILDING_NEIGHBORHOOD_STUDS = 140
RUNTIME_HARNESS_BUILDING_NEIGHBORHOOD_SCORE_SCALE = 10
RUNTIME_HARNESS_ROOF_ONLY_NEIGHBORHOOD_WEIGHT = 20
RUNTIME_HARNESS_INSIDE_FOOTPRINT_PENALTY = 1_000_000_000


def _parse_chunk_grid(chunk_id: str) -> tuple[int, int] | None:
    try:
        chunk_x, chunk_z = chunk_id.split("_", 1)
        return int(chunk_x), int(chunk_z)
    except ValueError:
        return None


def _point_in_polygon_2d(px: float, pz: float, polygon: list[tuple[float, float]]) -> bool:
    inside = False
    count = len(polygon)
    if count < 3:
        return False

    for index, current in enumerate(polygon):
        next_point = polygon[(index + 1) % count]
        current_above = current[1] > pz
        next_above = next_point[1] > pz
        if current_above == next_above:
            continue
        edge_cross_x = current[0] + (next_point[0] - current[0]) * ((pz - current[1]) / (next_point[1] - current[1]))
        if px < edge_cross_x:
            inside = not inside

    return inside


def _distance_to_segment_2d(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
    ab_x = bx - ax
    ab_z = bz - az
    ap_x = px - ax
    ap_z = pz - az
    denom = ab_x * ab_x + ab_z * ab_z
    t = 0.0 if denom <= 0 else max(0.0, min(1.0, (ap_x * ab_x + ap_z * ab_z) / denom))
    closest_x = ax + ab_x * t
    closest_z = az + ab_z * t
    return math.hypot(px - closest_x, pz - closest_z)


def _runtime_building_penalty(
    px: float, pz: float, building_footprints: list[dict[str, Any]]
) -> float:
    if not building_footprints:
        return 0.0

    nearest_distance = math.inf
    neighborhood_penalty = 0.0
    for footprint_entry in building_footprints:
        footprint = footprint_entry["points"]
        neighborhood_weight = footprint_entry["neighborhood_weight"]
        if _point_in_polygon_2d(px, pz, footprint):
            return float(RUNTIME_HARNESS_INSIDE_FOOTPRINT_PENALTY)

        footprint_nearest_distance = math.inf
        for index, point_a in enumerate(footprint):
            point_b = footprint[(index + 1) % len(footprint)]
            edge_distance = _distance_to_segment_2d(px, pz, point_a[0], point_a[1], point_b[0], point_b[1])
            footprint_nearest_distance = min(footprint_nearest_distance, edge_distance)

        nearest_distance = min(nearest_distance, footprint_nearest_distance)
        if footprint_nearest_distance < RUNTIME_HARNESS_BUILDING_NEIGHBORHOOD_STUDS:
            deficiency = RUNTIME_HARNESS_BUILDING_NEIGHBORHOOD_STUDS - footprint_nearest_distance
            neighborhood_penalty += (
                deficiency
                * deficiency
                * RUNTIME_HARNESS_BUILDING_NEIGHBORHOOD_SCORE_SCALE
                * neighborhood_weight
            )

    if nearest_distance >= RUNTIME_HARNESS_BUILDING_CLEARANCE_STUDS:
        return neighborhood_penalty

    deficiency = RUNTIME_HARNESS_BUILDING_CLEARANCE_STUDS - nearest_distance
    return deficiency * deficiency * RUNTIME_HARNESS_BUILDING_CLEARANCE_SCORE_SCALE + neighborhood_penalty


def select_runtime_harness_seed_chunk_ids(source_sqlite: Path) -> tuple[list[str], tuple[float, float, float]]:
    connection = sqlite3.connect(source_sqlite)
    try:
        chunk_rows = connection.execute(
            """
            SELECT chunk_id, origin_x, origin_y, origin_z, feature_count, chunk_json
            FROM manifest_chunks
            """
        ).fetchall()
    finally:
        connection.close()

    chunk_records: dict[str, dict[str, Any]] = {}
    road_candidates: list[dict[str, Any]] = []
    building_footprints_by_chunk: dict[str, list[dict[str, Any]]] = {}

    for chunk_id, origin_x, origin_y, origin_z, feature_count, chunk_json in chunk_rows:
        chunk = json.loads(chunk_json)
        chunk_grid = _parse_chunk_grid(chunk_id)
        if chunk_grid is None:
            continue

        chunk_records[chunk_id] = {
            "grid": chunk_grid,
            "feature_count": feature_count,
        }
        chunk_building_footprints: list[dict[str, Any]] = []
        for building in chunk.get("buildings", []):
            footprint = building.get("footprint")
            if not isinstance(footprint, list) or len(footprint) < 3:
                continue
            world_points = [
                (origin_x + float(point.get("x", 0.0)), origin_z + float(point.get("z", 0.0)))
                for point in footprint
                if isinstance(point, dict)
            ]
            if len(world_points) < 3:
                continue
            usage = str(building.get("usage") or building.get("kind") or "unknown").lower()
            chunk_building_footprints.append(
                {
                    "points": world_points,
                    "neighborhood_weight": (
                        RUNTIME_HARNESS_ROOF_ONLY_NEIGHBORHOOD_WEIGHT if usage == "roof" else 1
                    ),
                }
            )
        building_footprints_by_chunk[chunk_id] = chunk_building_footprints

        for road in chunk.get("roads", []):
            road_kind = str(road.get("kind") or "unknown")
            if road_kind in RUNTIME_HARNESS_EXCLUDED_SPAWN_KINDS:
                continue
            priority = RUNTIME_HARNESS_ROAD_PRIORITY.get(road_kind, 65)
            points = road.get("points") or []
            for index in range(len(points) - 1):
                point_a = points[index]
                point_b = points[index + 1]
                if not isinstance(point_a, dict) or not isinstance(point_b, dict):
                    continue
                mid_x = origin_x + (float(point_a.get("x", 0.0)) + float(point_b.get("x", 0.0))) * 0.5
                mid_y = origin_y + (float(point_a.get("y", 0.0)) + float(point_b.get("y", 0.0))) * 0.5
                mid_z = origin_z + (float(point_a.get("z", 0.0)) + float(point_b.get("z", 0.0))) * 0.5
                road_candidates.append(
                    {
                        "chunk_id": chunk_id,
                        "grid": chunk_grid,
                        "priority": priority,
                        "midpoint": (mid_x, mid_y, mid_z),
                    }
                )

    best_candidate: dict[str, Any] | None = None
    best_score: float | None = None
    for candidate in road_candidates:
        chunk_x, chunk_z = candidate["grid"]
        nearby_buildings: list[dict[str, Any]] = []
        nearby_feature_cost = 0
        for neighbor_x in range(chunk_x - 1, chunk_x + 2):
            for neighbor_z in range(chunk_z - 1, chunk_z + 2):
                neighbor_chunk_id = f"{neighbor_x}_{neighbor_z}"
                nearby_buildings.extend(building_footprints_by_chunk.get(neighbor_chunk_id, []))
                nearby_feature_cost += chunk_records.get(neighbor_chunk_id, {}).get("feature_count", 0)
        mid_x, _, mid_z = candidate["midpoint"]
        score = (
            candidate["priority"] * 100_000_000
            + _runtime_building_penalty(mid_x, mid_z, nearby_buildings)
            + nearby_feature_cost
        )
        if best_score is None or score < best_score:
            best_score = score
            best_candidate = candidate

    if best_candidate is None:
        fallback = RUNTIME_HARNESS_FALLBACK_CANONICAL_POSITION_STUDS
        return TARGET_CHUNK_IDS, (fallback["x"], fallback["y"], fallback["z"])

    midpoint = best_candidate["midpoint"]
    return [best_candidate["chunk_id"]], midpoint


def compute_total_features(
    chunk_refs: list[tuple[str, dict[str, Any]]], source_chunks: dict[str, dict[str, Any]]
) -> int:
    total_features = 0
    for chunk_id, chunk_ref in chunk_refs:
        feature_count = _coerce_feature_count(chunk_ref.get("featureCount"))
        if feature_count is None:
            source_chunk = source_chunks.get(chunk_id)
            if source_chunk is None:
                raise SystemExit(f"missing chunk {chunk_id} in {SOURCE_JSON}")
            feature_count = count_chunk_features(source_chunk)
        total_features += feature_count
    return total_features


def write_runtime_harness_index(
    schema_version: str,
    total_features: int,
    chunk_refs: list[tuple[str, dict[str, Any]]],
    shard_names: list[str],
    *,
    canonical_anchor_position: tuple[float, float, float],
    chunk_size_studs: float,
) -> None:
    anchor_x, anchor_y, anchor_z = canonical_anchor_position
    lines = [
        "return {",
        f'    schemaVersion = "{schema_version}",',
        "    meta = {",
        '        worldName = "AustinHarnessRuntime",',
        '        generator = "arbx_roblox_export",',
        '        source = "pipeline-export",',
        "        metersPerStud = 1,",
        f"        chunkSizeStuds = {_format_lua_value(chunk_size_studs)},",
        "        bbox = { minLat = 30.245, minLon = -97.765, maxLat = 30.305, maxLon = -97.715 },",
        f"        totalFeatures = {total_features},",
        "        canonicalAnchor = {",
        "            positionStuds = { "
        f"x = {_format_lua_value(round(anchor_x, 4))}, "
        f"y = {_format_lua_value(round(anchor_y, 4))}, "
        f"z = {_format_lua_value(round(anchor_z, 4))} "
        "},",
        "            lookDirectionStuds = { x = 0, y = 0, z = 1 },",
        "        },",
        "        notes = {",
        '            "runtime harness subset derived from rust/out/austin-manifest.json",',
        '            "used only for bounded Studio play harness runs; full Austin manifests remain runtime fallbacks",',
        "        },",
        "    },",
        f'    shardFolder = "{RUNTIME_HARNESS_SHARD_FOLDER}",',
        "    shards = {",
    ]

    for shard_name in shard_names:
        lines.append(f'        "{shard_name}",')

    lines.extend(
        [
            "    },",
            f"    chunkCount = {len(chunk_refs)},",
            f"    fragmentCount = {len(shard_names)},",
            "    chunksPerShard = 1,",
            "    chunkRefs = {",
        ]
    )

    for chunk_id, chunk_ref in chunk_refs:
        lines.append("        {")
        lines.append(f'            id = "{chunk_id}",')
        lines.append(
            "            originStuds = { "
            f'x = {chunk_ref["x"]}, y = {chunk_ref["y"]}, z = {chunk_ref["z"]} '
            "},"
        )
        if chunk_ref.get("partitionVersion") is not None:
            lines.append(f'            partitionVersion = {_format_lua_value(chunk_ref["partitionVersion"])},')
        if "featureCount" in chunk_ref:
            lines.append(f'            featureCount = {chunk_ref["featureCount"]},')
        if "streamingCost" in chunk_ref:
            lines.append(f'            streamingCost = {chunk_ref["streamingCost"]},')
        if chunk_ref.get("subplans") is not None:
            lines.append(f'            subplans = {_format_lua_value(chunk_ref["subplans"])},')
        shard_list = ", ".join(f'"{shard_name}"' for shard_name in chunk_ref["shards"])
        lines.append(f"            shards = {{ {shard_list} }},")
        lines.append("        },")

    lines.extend(["    },", "}", ""])
    RUNTIME_HARNESS_INDEX.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    source_text = SOURCE_INDEX.read_text(encoding="utf-8")
    _, source_chunk_refs = parse_source_index(source_text)
    chunk_size_studs = parse_source_chunk_size_studs(source_text)
    source_sqlite = resolve_source_sqlite_path(SOURCE_JSON)
    seed_chunk_ids = TARGET_CHUNK_IDS
    canonical_anchor_position = (
        RUNTIME_HARNESS_FALLBACK_CANONICAL_POSITION_STUDS["x"],
        RUNTIME_HARNESS_FALLBACK_CANONICAL_POSITION_STUDS["y"],
        RUNTIME_HARNESS_FALLBACK_CANONICAL_POSITION_STUDS["z"],
    )
    if source_sqlite.exists():
        seed_chunk_ids, canonical_anchor_position = select_runtime_harness_seed_chunk_ids(source_sqlite)
    harness_chunk_ids = derive_preview_chunk_ids(
        source_chunk_refs,
        seed_chunk_ids=seed_chunk_ids,
        chunk_size_studs=chunk_size_studs,
        load_radius_studs=RUNTIME_HARNESS_LOAD_RADIUS_STUDS,
        gutter_studs=RUNTIME_HARNESS_GUTTER_STUDS,
    )
    schema_version, source_chunks = load_source_manifest_subset(
        SOURCE_JSON,
        harness_chunk_ids,
        source_sqlite=source_sqlite,
    )
    harness_chunk_refs: list[tuple[str, dict[str, Any]]] = []
    for chunk_id in harness_chunk_ids:
        source_chunk = source_chunks.get(chunk_id)
        chunk_ref = source_chunk_refs.get(chunk_id)
        if source_chunk is None or chunk_ref is None:
            raise SystemExit(f"missing chunk {chunk_id} while building runtime harness subset")
        origin_studs = source_chunk.get("originStuds")
        if not isinstance(origin_studs, dict) or any(axis not in origin_studs for axis in ("x", "y", "z")):
            raise SystemExit(f"missing canonical originStuds for chunk {chunk_id} in {SOURCE_JSON}")
        harness_chunk_ref: dict[str, Any] = {
            "x": origin_studs["x"],
            "y": origin_studs["y"],
            "z": origin_studs["z"],
            "shards": [],
        }
        for key in ("featureCount", "streamingCost", "partitionVersion", "subplans"):
            if chunk_ref.get(key) is not None:
                harness_chunk_ref[key] = chunk_ref[key]
        harness_chunk_refs.append((chunk_id, harness_chunk_ref))

    shutil.rmtree(RUNTIME_HARNESS_SHARDS, ignore_errors=True)
    RUNTIME_HARNESS_SHARDS.mkdir(parents=True, exist_ok=True)

    shard_names: list[str] = []
    shard_index = 1
    for chunk_id, chunk_ref in harness_chunk_refs:
        chunk = source_chunks[chunk_id]
        fragments = fragment_preview_chunk(chunk, MAX_PREVIEW_BYTES)
        for fragment in fragments:
            shard_name = f"AustinHarnessManifestIndex_{shard_index:03d}"
            write_lua_module(RUNTIME_HARNESS_SHARDS / f"{shard_name}.lua", {"chunks": [fragment]})
            chunk_ref["shards"].append(shard_name)
            shard_names.append(shard_name)
            shard_index += 1

    total_features = compute_total_features(harness_chunk_refs, source_chunks)
    write_runtime_harness_index(
        schema_version,
        total_features,
        harness_chunk_refs,
        shard_names,
        canonical_anchor_position=canonical_anchor_position,
        chunk_size_studs=chunk_size_studs,
    )

    print(f"Refreshed runtime harness sample-data from {SOURCE_JSON}")
    print(f"Selected {len(harness_chunk_ids)} runtime harness chunks from AustinManifestIndex.lua")
    print(f"Wrote {len(shard_names)} runtime harness shards to {RUNTIME_HARNESS_SHARDS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
