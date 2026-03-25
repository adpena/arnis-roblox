#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from html import escape
from pathlib import Path
from typing import Any


def _load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path} did not contain a top-level JSON object")
    return data


def _safe_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _chunk_center(chunk: dict[str, Any], chunk_size: float) -> tuple[float, float]:
    origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
    origin_x = _safe_float(origin.get("x"))
    origin_z = _safe_float(origin.get("z"))
    return origin_x + chunk_size * 0.5, origin_z + chunk_size * 0.5


def _append_bucket_id(container: dict[str, list[str]], bucket: str, source_id: Any) -> None:
    if not isinstance(source_id, str) or source_id == "":
        return
    row = container.setdefault(bucket, [])
    if source_id not in row:
        row.append(source_id)


SOURCE_BUILDING_MATERIAL_TO_SCENE_BUCKET = {
    "asphalt": "asphalt",
    "brick": "brick",
    "bricks": "brick",
    "cladding": "diamondplate",
    "cobblestone": "cobblestone",
    "concrete": "concrete",
    "copper": "metal",
    "glass": "glass",
    "granite": "granite",
    "limestone": "limestone",
    "marble": "marble",
    "metal": "metal",
    "plaster": "smoothplastic",
    "render": "smoothplastic",
    "sandstone": "sandstone",
    "slate": "slate",
    "steel": "diamondplate",
    "stone": "cobblestone",
    "stucco": "smoothplastic",
    "thatch": "grass",
    "tile": "brick",
    "timber_framing": "woodplanks",
    "wood": "woodplanks",
}


def _normalize_manifest_explicit_material(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    if normalized == "":
        return None
    mapped = SOURCE_BUILDING_MATERIAL_TO_SCENE_BUCKET.get(normalized.lower())
    if mapped is not None:
        return mapped
    return normalized.lower()


def _append_stats_source_ids(stats: dict[str, Any], ids: Any) -> None:
    if not isinstance(ids, list):
        return
    current_ids = stats.setdefault("sourceIds", [])
    if not isinstance(current_ids, list):
        return
    seen = {source_id for source_id in current_ids if isinstance(source_id, str) and source_id}
    for source_id in ids:
        if isinstance(source_id, str) and source_id and source_id not in seen:
            current_ids.append(source_id)
            seen.add(source_id)


def _merge_pending_scene_fragments(
    payload: dict[str, Any],
    latest_chunks_payload: dict[str, Any] | None,
    latest_scalars: dict[str, Any],
    latest_roof_usage_payload: dict[str, Any] | None,
    latest_roof_usage_buckets: dict[str, dict[str, Any]],
    latest_roof_shapes_payload: dict[str, Any] | None,
    latest_prop_kind_buckets: dict[str, dict[str, Any]],
    latest_ambient_prop_kind_buckets: dict[str, dict[str, Any]],
    latest_tree_species_buckets: dict[str, dict[str, Any]],
    latest_vegetation_kind_buckets: dict[str, dict[str, Any]],
    latest_water_type_buckets: dict[str, dict[str, Any]],
    latest_water_kind_buckets: dict[str, dict[str, Any]],
    latest_road_kind_buckets: dict[str, dict[str, Any]],
    latest_road_subkind_buckets: dict[str, dict[str, Any]],
    latest_building_wall_material_buckets: dict[str, dict[str, Any]],
    latest_building_roof_material_buckets: dict[str, dict[str, Any]],
) -> None:
    scene = payload.get("scene")
    if not isinstance(scene, dict):
        scene = {}
        payload["scene"] = scene
    if isinstance(latest_chunks_payload, dict):
        chunk_ids = latest_chunks_payload.get("chunkIds")
        if isinstance(chunk_ids, list):
            scene["chunkIds"] = chunk_ids
    if latest_scalars:
        scene.update(latest_scalars)
    if isinstance(latest_roof_usage_payload, dict):
        coverage = latest_roof_usage_payload.get("buildingRoofCoverageByUsage")
        if isinstance(coverage, dict):
            scene["buildingRoofCoverageByUsage"] = coverage
    if latest_roof_usage_buckets:
        scene["buildingRoofCoverageByUsage"] = dict(latest_roof_usage_buckets)
    if isinstance(latest_roof_shapes_payload, dict):
        coverage = latest_roof_shapes_payload.get("buildingRoofCoverageByShape")
        if isinstance(coverage, dict):
            scene["buildingRoofCoverageByShape"] = coverage
    if latest_prop_kind_buckets:
        scene["propInstanceCountByKind"] = dict(latest_prop_kind_buckets)
    if latest_ambient_prop_kind_buckets:
        scene["ambientPropInstanceCountByKind"] = dict(latest_ambient_prop_kind_buckets)
    if latest_tree_species_buckets:
        scene["treeInstanceCountBySpecies"] = dict(latest_tree_species_buckets)
    if latest_vegetation_kind_buckets:
        scene["vegetationInstanceCountByKind"] = dict(latest_vegetation_kind_buckets)
    if latest_water_type_buckets:
        scene["waterSurfacePartCountByType"] = dict(latest_water_type_buckets)
    if latest_water_kind_buckets:
        scene["waterSurfacePartCountByKind"] = dict(latest_water_kind_buckets)
    if latest_road_kind_buckets:
        scene["roadSurfacePartCountByKind"] = dict(latest_road_kind_buckets)
    if latest_road_subkind_buckets:
        scene["roadSurfacePartCountBySubkind"] = dict(latest_road_subkind_buckets)
    if latest_building_wall_material_buckets:
        scene["buildingModelCountByWallMaterial"] = dict(latest_building_wall_material_buckets)
    if latest_building_roof_material_buckets:
        scene["buildingModelCountByRoofMaterial"] = dict(latest_building_roof_material_buckets)


def _new_fragment_state() -> dict[str, Any]:
    return {
        "chunks_payload": None,
        "roof_usage_payload": None,
        "roof_usage_buckets": {},
        "roof_shapes_payload": None,
        "scalars": {},
        "prop_kind_buckets": {},
        "ambient_prop_kind_buckets": {},
        "tree_species_buckets": {},
        "vegetation_kind_buckets": {},
        "water_type_buckets": {},
        "water_kind_buckets": {},
        "road_kind_buckets": {},
        "road_subkind_buckets": {},
        "building_wall_material_buckets": {},
        "building_roof_material_buckets": {},
    }


def _payload_run_key(payload: dict[str, Any]) -> tuple[str, str] | None:
    phase = payload.get("phase")
    root_name = payload.get("rootName")
    if isinstance(phase, str) and phase and isinstance(root_name, str) and root_name:
        return phase, root_name
    return None


def _merge_fragment_state(payload: dict[str, Any], state: dict[str, Any]) -> None:
    _merge_pending_scene_fragments(
        payload,
        state["chunks_payload"],
        state["scalars"],
        state["roof_usage_payload"],
        state["roof_usage_buckets"],
        state["roof_shapes_payload"],
        state["prop_kind_buckets"],
        state["ambient_prop_kind_buckets"],
        state["tree_species_buckets"],
        state["vegetation_kind_buckets"],
        state["water_type_buckets"],
        state["water_kind_buckets"],
        state["road_kind_buckets"],
        state["road_subkind_buckets"],
        state["building_wall_material_buckets"],
        state["building_roof_material_buckets"],
    )


def _parse_latest_marker(log_path: Path, marker: str) -> dict[str, Any]:
    latest_payload: dict[str, Any] | None = None
    latest_payload_key: tuple[str, str] | None = None
    fragment_states: dict[tuple[str, str], dict[str, Any]] = {}
    prefix = marker + " "
    chunk_prefix = marker + "_CHUNKS "
    roof_usage_prefix = marker + "_ROOF_USAGE "
    roof_usage_bucket_prefix = marker + "_ROOF_USAGE_BUCKET "
    roof_shapes_prefix = marker + "_ROOF_SHAPES "
    scalar_prefix = marker + "_SCALAR "
    prop_kind_bucket_prefix = marker + "_PROP_KIND_BUCKET "
    prop_kind_ids_batch_prefix = marker + "_PROP_KIND_IDS_BATCH "
    ambient_prop_kind_bucket_prefix = marker + "_AMBIENT_PROP_KIND_BUCKET "
    tree_species_bucket_prefix = marker + "_TREE_SPECIES_BUCKET "
    tree_species_ids_batch_prefix = marker + "_TREE_SPECIES_IDS_BATCH "
    vegetation_kind_bucket_prefix = marker + "_VEGETATION_KIND_BUCKET "
    vegetation_kind_ids_batch_prefix = marker + "_VEGETATION_KIND_IDS_BATCH "
    water_type_bucket_prefix = marker + "_WATER_TYPE_BUCKET "
    water_kind_bucket_prefix = marker + "_WATER_KIND_BUCKET "
    water_kind_ids_batch_prefix = marker + "_WATER_KIND_IDS_BATCH "
    road_kind_bucket_prefix = marker + "_ROAD_KIND_BUCKET "
    road_kind_ids_batch_prefix = marker + "_ROAD_KIND_IDS_BATCH "
    road_subkind_bucket_prefix = marker + "_ROAD_SUBKIND_BUCKET "
    road_subkind_ids_batch_prefix = marker + "_ROAD_SUBKIND_IDS_BATCH "
    building_wall_material_bucket_prefix = marker + "_BUILDING_WALL_MATERIAL_BUCKET "
    building_wall_material_ids_batch_prefix = marker + "_BUILDING_WALL_MATERIAL_IDS_BATCH "
    building_roof_material_bucket_prefix = marker + "_BUILDING_ROOF_MATERIAL_BUCKET "
    building_roof_material_ids_batch_prefix = marker + "_BUILDING_ROOF_MATERIAL_IDS_BATCH "
    with log_path.open(encoding="utf-8") as handle:
        for line in handle:
            matched_prefix = None
            if chunk_prefix in line:
                matched_prefix = chunk_prefix
            elif roof_usage_prefix in line:
                matched_prefix = roof_usage_prefix
            elif roof_usage_bucket_prefix in line:
                matched_prefix = roof_usage_bucket_prefix
            elif roof_shapes_prefix in line:
                matched_prefix = roof_shapes_prefix
            elif scalar_prefix in line:
                matched_prefix = scalar_prefix
            elif prop_kind_bucket_prefix in line:
                matched_prefix = prop_kind_bucket_prefix
            elif prop_kind_ids_batch_prefix in line:
                matched_prefix = prop_kind_ids_batch_prefix
            elif ambient_prop_kind_bucket_prefix in line:
                matched_prefix = ambient_prop_kind_bucket_prefix
            elif tree_species_bucket_prefix in line:
                matched_prefix = tree_species_bucket_prefix
            elif tree_species_ids_batch_prefix in line:
                matched_prefix = tree_species_ids_batch_prefix
            elif vegetation_kind_bucket_prefix in line:
                matched_prefix = vegetation_kind_bucket_prefix
            elif vegetation_kind_ids_batch_prefix in line:
                matched_prefix = vegetation_kind_ids_batch_prefix
            elif water_type_bucket_prefix in line:
                matched_prefix = water_type_bucket_prefix
            elif water_kind_bucket_prefix in line:
                matched_prefix = water_kind_bucket_prefix
            elif water_kind_ids_batch_prefix in line:
                matched_prefix = water_kind_ids_batch_prefix
            elif road_kind_bucket_prefix in line:
                matched_prefix = road_kind_bucket_prefix
            elif road_kind_ids_batch_prefix in line:
                matched_prefix = road_kind_ids_batch_prefix
            elif road_subkind_bucket_prefix in line:
                matched_prefix = road_subkind_bucket_prefix
            elif road_subkind_ids_batch_prefix in line:
                matched_prefix = road_subkind_ids_batch_prefix
            elif building_wall_material_bucket_prefix in line:
                matched_prefix = building_wall_material_bucket_prefix
            elif building_wall_material_ids_batch_prefix in line:
                matched_prefix = building_wall_material_ids_batch_prefix
            elif building_roof_material_bucket_prefix in line:
                matched_prefix = building_roof_material_bucket_prefix
            elif building_roof_material_ids_batch_prefix in line:
                matched_prefix = building_roof_material_ids_batch_prefix
            else:
                marker_index = line.find(prefix)
                if marker_index >= 0:
                    matched_prefix = prefix

            if matched_prefix is None:
                continue

            try:
                payload = json.loads(line[line.find(matched_prefix) + len(matched_prefix) :].strip())
            except json.JSONDecodeError:
                continue
            if not isinstance(payload, dict):
                continue

            run_key = _payload_run_key(payload)
            if run_key is None:
                continue

            state = fragment_states.setdefault(run_key, _new_fragment_state())

            if matched_prefix == prefix:
                _merge_fragment_state(payload, state)
                latest_payload = payload
                latest_payload_key = run_key
                fragment_states[run_key] = _new_fragment_state()
                continue
            if matched_prefix == chunk_prefix:
                state["chunks_payload"] = payload
                continue
            if matched_prefix == roof_usage_prefix:
                state["roof_usage_payload"] = payload
                continue
            if matched_prefix == roof_usage_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["roof_usage_buckets"][bucket] = stats
                continue
            if matched_prefix == roof_shapes_prefix:
                state["roof_shapes_payload"] = payload
                continue
            if matched_prefix == scalar_prefix:
                key = payload.get("key")
                if isinstance(key, str):
                    state["scalars"][key] = payload.get("value")
                continue
            if matched_prefix == prop_kind_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["prop_kind_buckets"][bucket] = stats
                continue
            if matched_prefix == prop_kind_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["prop_kind_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue
            if matched_prefix == ambient_prop_kind_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["ambient_prop_kind_buckets"][bucket] = stats
                continue
            if matched_prefix == tree_species_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["tree_species_buckets"][bucket] = stats
                continue
            if matched_prefix == tree_species_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["tree_species_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue
            if matched_prefix == vegetation_kind_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["vegetation_kind_buckets"][bucket] = stats
                continue
            if matched_prefix == vegetation_kind_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["vegetation_kind_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue
            if matched_prefix == water_type_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["water_type_buckets"][bucket] = stats
                continue
            if matched_prefix == water_kind_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["water_kind_buckets"][bucket] = stats
                continue
            if matched_prefix == water_kind_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["water_kind_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue
            if matched_prefix == road_kind_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["road_kind_buckets"][bucket] = stats
                continue
            if matched_prefix == road_kind_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["road_kind_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue
            if matched_prefix == road_subkind_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["road_subkind_buckets"][bucket] = stats
                continue
            if matched_prefix == road_subkind_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["road_subkind_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue
            if matched_prefix == building_wall_material_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["building_wall_material_buckets"][bucket] = stats
                continue
            if matched_prefix == building_wall_material_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["building_wall_material_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue
            if matched_prefix == building_roof_material_bucket_prefix:
                bucket = payload.get("bucket")
                stats = payload.get("stats")
                if isinstance(bucket, str) and isinstance(stats, dict):
                    state["building_roof_material_buckets"][bucket] = stats
                continue
            if matched_prefix == building_roof_material_ids_batch_prefix:
                bucket = payload.get("bucket")
                ids = payload.get("sourceIds")
                if isinstance(bucket, str) and isinstance(ids, list):
                    stats = state["building_roof_material_buckets"].setdefault(bucket, {})
                    _append_stats_source_ids(stats, ids)
                continue

    if latest_payload is None:
        raise ValueError(f"no {marker} marker found in {log_path}")
    if latest_payload_key is not None:
        trailing_state = fragment_states.get(latest_payload_key)
        if trailing_state is not None:
            _merge_fragment_state(latest_payload, trailing_state)
    return latest_payload


def _build_manifest_zone_summary(manifest: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
    meta = manifest.get("meta") if isinstance(manifest.get("meta"), dict) else {}
    chunk_size = _safe_float(meta.get("chunkSizeStuds"), 256.0)
    focus = payload.get("focus") if isinstance(payload.get("focus"), dict) else {}
    scene = payload.get("scene") if isinstance(payload.get("scene"), dict) else {}
    focus_x = _safe_float(focus.get("x"))
    focus_z = _safe_float(focus.get("z"))
    radius = _safe_float(payload.get("radius"), 0.0)
    radius_sq = radius * radius
    requested_chunk_ids = {
        str(chunk_id)
        for chunk_id in (scene.get("chunkIds") if isinstance(scene.get("chunkIds"), list) else [])
        if chunk_id is not None
    }

    chunk_count = 0
    road_count = 0
    building_count = 0
    prop_count = 0
    tree_count = 0
    vegetation_count = 0
    water_count = 0
    chunk_ids: list[str] = []
    chunks_with_roads = 0
    chunks_with_buildings = 0
    chunks_with_props = 0
    chunks_with_vegetation = 0
    chunks_with_water = 0
    prop_count_by_kind: dict[str, int] = {}
    prop_ids_by_kind: dict[str, list[str]] = {}
    tree_count_by_species: dict[str, int] = {}
    tree_ids_by_species: dict[str, list[str]] = {}
    vegetation_count_by_kind: dict[str, int] = {}
    vegetation_ids_by_kind: dict[str, list[str]] = {}
    water_count_by_type: dict[str, int] = {}
    water_count_by_kind: dict[str, int] = {}
    building_count_by_usage: dict[str, int] = {}
    building_count_by_roof_shape: dict[str, int] = {}
    building_count_by_explicit_wall_material: dict[str, int] = {}
    building_count_by_explicit_roof_material: dict[str, int] = {}
    building_ids_by_explicit_wall_material: dict[str, list[str]] = {}
    building_ids_by_explicit_roof_material: dict[str, list[str]] = {}
    road_count_by_kind: dict[str, int] = {}
    road_count_by_subkind: dict[str, int] = {}
    road_ids_by_kind: dict[str, list[str]] = {}
    road_ids_by_subkind: dict[str, list[str]] = {}
    water_ids_by_kind: dict[str, list[str]] = {}
    water_ids_by_type: dict[str, list[str]] = {}

    chunks = manifest.get("chunks")
    if not isinstance(chunks, list):
        chunks = []

    if requested_chunk_ids:
        chunk_lookup = {
            str(chunk.get("id")): chunk
            for chunk in chunks
            if isinstance(chunk, dict) and chunk.get("id") is not None
        }
        candidate_chunks = [chunk_lookup[chunk_id] for chunk_id in sorted(requested_chunk_ids) if chunk_id in chunk_lookup]
    else:
        candidate_chunks = [chunk for chunk in chunks if isinstance(chunk, dict)]

    for chunk in candidate_chunks:
        if not isinstance(chunk, dict):
            continue
        if not requested_chunk_ids:
            center_x, center_z = _chunk_center(chunk, chunk_size)
            dx = center_x - focus_x
            dz = center_z - focus_z
            if radius > 0 and dx * dx + dz * dz > radius_sq:
                continue

        chunk_count += 1
        chunk_id = str(chunk.get("id") or f"chunk_{chunk_count}")
        chunk_ids.append(chunk_id)

        roads = chunk.get("roads") if isinstance(chunk.get("roads"), list) else []
        buildings = chunk.get("buildings") if isinstance(chunk.get("buildings"), list) else []
        props = chunk.get("props") if isinstance(chunk.get("props"), list) else []
        waters = chunk.get("water") if isinstance(chunk.get("water"), list) else []

        road_count += len(roads)
        building_count += len(buildings)
        prop_count += len(props)
        water_count += len(waters)
        chunk_vegetation_count = 0
        if roads:
            chunks_with_roads += 1
            for road in roads:
                if not isinstance(road, dict):
                    continue
                kind = str(road.get("kind") or "unknown")
                subkind = str(road.get("subkind") or "none")
                road_count_by_kind[kind] = road_count_by_kind.get(kind, 0) + 1
                road_count_by_subkind[subkind] = road_count_by_subkind.get(subkind, 0) + 1
                _append_bucket_id(road_ids_by_kind, kind, road.get("id"))
                _append_bucket_id(road_ids_by_subkind, subkind, road.get("id"))
        if buildings:
            chunks_with_buildings += 1
            for building in buildings:
                if not isinstance(building, dict):
                    continue
                usage = str(building.get("usage") or building.get("kind") or "unknown")
                roof_shape = str(building.get("roof") or building.get("roofShape") or "unknown")
                building_count_by_usage[usage] = building_count_by_usage.get(usage, 0) + 1
                building_count_by_roof_shape[roof_shape] = building_count_by_roof_shape.get(roof_shape, 0) + 1
                wall_material = _normalize_manifest_explicit_material(building.get("material"))
                if wall_material is not None:
                    building_count_by_explicit_wall_material[wall_material] = (
                        building_count_by_explicit_wall_material.get(wall_material, 0) + 1
                    )
                    _append_bucket_id(building_ids_by_explicit_wall_material, wall_material, building.get("id"))
                roof_material = _normalize_manifest_explicit_material(building.get("roofMaterial"))
                if roof_material is not None:
                    building_count_by_explicit_roof_material[roof_material] = (
                        building_count_by_explicit_roof_material.get(roof_material, 0) + 1
                    )
                    _append_bucket_id(building_ids_by_explicit_roof_material, roof_material, building.get("id"))
        if props:
            chunks_with_props += 1
            for prop in props:
                if not isinstance(prop, dict):
                    continue
                kind = str(prop.get("kind") or "unknown")
                prop_count_by_kind[kind] = prop_count_by_kind.get(kind, 0) + 1
                _append_bucket_id(prop_ids_by_kind, kind, prop.get("id"))
                if kind == "tree":
                    tree_count += 1
                    species = str(prop.get("species") or "unknown")
                    tree_count_by_species[species] = tree_count_by_species.get(species, 0) + 1
                    _append_bucket_id(tree_ids_by_species, species, prop.get("id"))
                    vegetation_count += 1
                    chunk_vegetation_count += 1
                    vegetation_count_by_kind[kind] = vegetation_count_by_kind.get(kind, 0) + 1
                    _append_bucket_id(vegetation_ids_by_kind, kind, prop.get("id"))
                elif kind in {"hedge", "shrub"}:
                    vegetation_count += 1
                    chunk_vegetation_count += 1
                    vegetation_count_by_kind[kind] = vegetation_count_by_kind.get(kind, 0) + 1
                    _append_bucket_id(vegetation_ids_by_kind, kind, prop.get("id"))
        if chunk_vegetation_count > 0:
            chunks_with_vegetation += 1
        if waters:
            chunks_with_water += 1
            for water in waters:
                water_type = "unknown"
                water_kind = "unknown"
                if isinstance(water, dict):
                    water_kind = str(water.get("kind") or "unknown")
                    if isinstance(water.get("footprint"), list):
                        water_type = "polygon"
                    elif isinstance(water.get("points"), list):
                        water_type = "ribbon"
                water_count_by_type[water_type] = water_count_by_type.get(water_type, 0) + 1
                water_count_by_kind[water_kind] = water_count_by_kind.get(water_kind, 0) + 1
                _append_bucket_id(water_ids_by_type, water_type, water.get("id") if isinstance(water, dict) else None)
                _append_bucket_id(water_ids_by_kind, water_kind, water.get("id") if isinstance(water, dict) else None)

    return {
        "chunkCount": chunk_count,
        "chunkIds": chunk_ids,
        "roadCount": road_count,
        "roadCountByKind": road_count_by_kind,
        "roadCountBySubkind": road_count_by_subkind,
        "roadIdsByKind": road_ids_by_kind,
        "roadIdsBySubkind": road_ids_by_subkind,
        "buildingCount": building_count,
        "buildingCountByUsage": building_count_by_usage,
        "buildingCountByRoofShape": building_count_by_roof_shape,
        "buildingCountByExplicitWallMaterial": building_count_by_explicit_wall_material,
        "buildingCountByExplicitRoofMaterial": building_count_by_explicit_roof_material,
        "buildingIdsByExplicitWallMaterial": building_ids_by_explicit_wall_material,
        "buildingIdsByExplicitRoofMaterial": building_ids_by_explicit_roof_material,
        "propCount": prop_count,
        "propCountByKind": prop_count_by_kind,
        "propIdsByKind": prop_ids_by_kind,
        "treeCount": tree_count,
        "treeCountBySpecies": tree_count_by_species,
        "treeIdsBySpecies": tree_ids_by_species,
        "vegetationCount": vegetation_count,
        "vegetationCountByKind": vegetation_count_by_kind,
        "vegetationIdsByKind": vegetation_ids_by_kind,
        "waterCount": water_count,
        "chunksWithRoads": chunks_with_roads,
        "chunksWithBuildings": chunks_with_buildings,
        "chunksWithProps": chunks_with_props,
        "chunksWithVegetation": chunks_with_vegetation,
        "chunksWithWater": chunks_with_water,
        "waterCountByType": water_count_by_type,
        "waterCountByKind": water_count_by_kind,
        "waterIdsByType": water_ids_by_type,
        "waterIdsByKind": water_ids_by_kind,
    }


def _ratio(actual: float, expected: float) -> float:
    if expected <= 0:
        return 1.0 if actual <= 0 else 0.0
    return actual / expected


def _sorted_roof_coverage_rows(coverage: Any) -> list[tuple[str, dict[str, Any]]]:
    if not isinstance(coverage, dict):
        return []
    rows: list[tuple[str, dict[str, Any]]] = []
    for key, value in coverage.items():
        if isinstance(key, str) and isinstance(value, dict):
            rows.append((key, value))
    rows.sort(
        key=lambda item: (
            -int(item[1].get("buildingModelCount") or 0),
            -int(item[1].get("withoutRoofCount") or 0),
            item[0],
        )
    )
    return rows


def _sorted_manifest_count_rows(counts: Any) -> list[tuple[str, int]]:
    if not isinstance(counts, dict):
        return []
    rows: list[tuple[str, int]] = []
    for key, value in counts.items():
        if not isinstance(key, str):
            continue
        try:
            count = int(value)
        except (TypeError, ValueError):
            continue
        rows.append((key, count))
    rows.sort(key=lambda item: (-item[1], item[0]))
    return rows


def _scene_bucket_count(bucket_rows: Any, bucket: str, value_key: str) -> int:
    if not isinstance(bucket_rows, dict):
        return 0
    row = bucket_rows.get(bucket)
    if not isinstance(row, dict):
        return 0
    try:
        return int(row.get(value_key) or 0)
    except (TypeError, ValueError):
        return 0


def _scene_bucket_feature_truth_count(bucket_rows: Any, bucket: str, value_key: str) -> int:
    scene_ids = _scene_bucket_ids(bucket_rows, bucket)
    if scene_ids:
        return len(scene_ids)
    return _scene_bucket_count(bucket_rows, bucket, value_key)


def _manifest_bucket_feature_truth_count(
    manifest_counts: Any,
    manifest_ids_by_bucket: dict[str, list[str]] | None,
    bucket: str,
) -> int:
    if manifest_ids_by_bucket is not None:
        manifest_ids = manifest_ids_by_bucket.get(bucket) or []
        if manifest_ids:
            return len(manifest_ids)
    if not isinstance(manifest_counts, dict):
        return 0
    try:
        return int(manifest_counts.get(bucket) or 0)
    except (TypeError, ValueError):
        return 0


def _scene_bucket_ids(bucket_rows: Any, bucket: str) -> set[str]:
    if not isinstance(bucket_rows, dict):
        return set()
    row = bucket_rows.get(bucket)
    if not isinstance(row, dict):
        return set()
    values = row.get("sourceIds")
    if not isinstance(values, list):
        return set()
    return {value for value in values if isinstance(value, str) and value}


def _format_bucket_gap_summary(gaps: list[tuple[str, int, int]], label: str) -> str:
    preview = ", ".join(f"{bucket} {scene}/{expected}" for bucket, expected, scene in gaps[:5])
    if len(gaps) > 5:
        preview += f", +{len(gaps) - 5} more"
    return f"{label} scene gaps: {preview}"


def _gap_rows(
    gaps: list[tuple[str, int, int]], manifest_ids_by_bucket: dict[str, list[str]] | None = None, scene_buckets: Any = None
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for bucket, expected, scene in gaps:
        row: dict[str, Any] = {
            "bucket": bucket,
            "manifestCount": expected,
            "sceneCount": scene,
        }
        if manifest_ids_by_bucket is not None:
            manifest_ids = manifest_ids_by_bucket.get(bucket) or []
            scene_ids = _scene_bucket_ids(scene_buckets, bucket)
            missing_ids = [source_id for source_id in manifest_ids if source_id not in scene_ids]
            if missing_ids:
                row["missingIds"] = missing_ids
        rows.append(row)
    return rows


def build_report(manifest_path: Path, log_path: Path, *, marker: str) -> dict[str, Any]:
    manifest = _load_json(manifest_path)
    payload = _parse_latest_marker(log_path, marker)
    scene = payload.get("scene") if isinstance(payload.get("scene"), dict) else {}
    manifest_summary = _build_manifest_zone_summary(manifest, payload)

    scene_chunk_count = int(scene.get("chunkCount") or 0)
    scene_building_models = int(scene.get("buildingModelCount") or 0)
    scene_road_chunks = int(scene.get("chunksWithRoadGeometry") or 0)
    manifest_chunk_count = int(manifest_summary["chunkCount"])
    manifest_building_count = int(manifest_summary["buildingCount"])
    manifest_road_chunk_count = int(manifest_summary["chunksWithRoads"])
    manifest_prop_count = int(manifest_summary["propCount"])
    manifest_vegetation_count = int(manifest_summary["vegetationCount"])
    manifest_water_chunk_count = int(manifest_summary["chunksWithWater"])
    scene_water_chunks = int(scene.get("chunksWithWaterGeometry") or 0)
    scene_prop_count = int(scene.get("propInstanceCount") or 0)
    scene_vegetation_count = int(scene.get("vegetationInstanceCount") or 0)

    summary = {
        "marker": marker,
        "chunk_ratio": _ratio(scene_chunk_count, manifest_chunk_count),
        "building_model_ratio": _ratio(scene_building_models, manifest_building_count),
        "road_geometry_ratio": _ratio(scene_road_chunks, manifest_road_chunk_count),
        "prop_instance_ratio": _ratio(scene_prop_count, manifest_prop_count),
        "vegetation_instance_ratio": _ratio(scene_vegetation_count, manifest_vegetation_count),
        "water_geometry_ratio": _ratio(scene_water_chunks, manifest_water_chunk_count),
        "sceneRoadSurfaceKinds": scene.get("roadSurfacePartCountByKind") or {},
        "sceneRoadSurfaceSubkinds": scene.get("roadSurfacePartCountBySubkind") or {},
        "manifestRoadKinds": manifest_summary.get("roadCountByKind") or {},
        "manifestRoadSubkinds": manifest_summary.get("roadCountBySubkind") or {},
        "manifestWaterKinds": manifest_summary.get("waterCountByKind") or {},
        "manifestWaterTypes": manifest_summary.get("waterCountByType") or {},
        "manifestPropKinds": manifest_summary.get("propCountByKind") or {},
        "manifestTreeSpecies": manifest_summary.get("treeCountBySpecies") or {},
        "manifestVegetationKinds": manifest_summary.get("vegetationCountByKind") or {},
        "manifestExplicitBuildingWallMaterials": manifest_summary.get("buildingCountByExplicitWallMaterial") or {},
        "manifestExplicitBuildingRoofMaterials": manifest_summary.get("buildingCountByExplicitRoofMaterial") or {},
        "sceneBuildingWallMaterials": scene.get("buildingModelCountByWallMaterial") or {},
        "sceneBuildingRoofMaterials": scene.get("buildingModelCountByRoofMaterial") or {},
        "roadKindGaps": [],
        "roadSubkindGaps": [],
        "waterKindGaps": [],
        "propKindGaps": [],
        "treeSpeciesGaps": [],
        "vegetationKindGaps": [],
        "explicitWallMaterialGaps": [],
        "explicitRoofMaterialGaps": [],
    }

    findings: list[dict[str, Any]] = []
    if scene_chunk_count < manifest_chunk_count:
        findings.append(
            {
                "severity": "high",
                "code": "scene_chunk_gap",
                "message": f"scene built {scene_chunk_count} chunks but manifest expected {manifest_chunk_count}",
            }
        )
    if scene_building_models < manifest_building_count:
        findings.append(
            {
                "severity": "high",
                "code": "missing_building_models",
                "message": (
                    f"scene built {scene_building_models} building models but manifest expected {manifest_building_count}"
                ),
            }
        )
    if manifest_road_chunk_count > 0 and scene_road_chunks < manifest_road_chunk_count:
        findings.append(
            {
                "severity": "high",
                "code": "missing_road_geometry",
                "message": (
                    f"scene has road geometry in {scene_road_chunks} chunks but manifest expected {manifest_road_chunk_count}"
                ),
            }
        )
    if manifest_water_chunk_count > 0 and scene_water_chunks < manifest_water_chunk_count:
        findings.append(
            {
                "severity": "high",
                "code": "missing_water_geometry",
                "message": (
                    f"scene has water geometry in {scene_water_chunks} chunks but manifest expected {manifest_water_chunk_count}"
                ),
            }
        )
    if manifest_prop_count > 0 and scene_prop_count < manifest_prop_count:
        findings.append(
            {
                "severity": "medium",
                "code": "missing_prop_instances",
                "message": f"scene built {scene_prop_count} prop roots but manifest expected {manifest_prop_count}",
            }
        )
    if manifest_vegetation_count > 0 and scene_vegetation_count < manifest_vegetation_count:
        findings.append(
            {
                "severity": "medium",
                "code": "missing_vegetation_instances",
                "message": (
                    f"scene built {scene_vegetation_count} vegetation roots but manifest expected {manifest_vegetation_count}"
                ),
            }
        )
    building_model_count = int(scene.get("buildingModelCount") or 0)
    merged_roof_only_count = int(scene.get("buildingModelsWithMergedRoofOnly") or 0)
    no_roof_evidence_count = int(scene.get("buildingModelsWithNoRoofEvidence") or 0)
    roof_closure_deck_count = int(scene.get("buildingModelsWithRoofClosureDeck") or 0)
    connected_tree_count = int(scene.get("treeModelsWithConnectedTrunkCanopy") or 0)
    missing_trunk_tree_count = int(scene.get("treeModelsMissingTrunk") or 0)
    missing_canopy_tree_count = int(scene.get("treeModelsMissingCanopy") or 0)
    detached_canopy_tree_count = int(scene.get("treeModelsWithDetachedCanopy") or 0)
    procedural_tree_count = int(scene.get("proceduralTreeInstanceCount") or 0)
    procedural_connected_tree_count = int(scene.get("proceduralTreeModelsWithConnectedTrunkCanopy") or 0)
    procedural_missing_trunk_tree_count = int(scene.get("proceduralTreeModelsMissingTrunk") or 0)
    procedural_missing_canopy_tree_count = int(scene.get("proceduralTreeModelsMissingCanopy") or 0)
    procedural_detached_canopy_tree_count = int(scene.get("proceduralTreeModelsWithDetachedCanopy") or 0)
    if building_model_count > 0 and merged_roof_only_count > 0:
        findings.append(
            {
                "severity": "medium",
                "code": "merged_roof_only_coverage",
                "message": (
                    f"{merged_roof_only_count} buildings rely on merged-roof-only evidence; direct roof coverage may still be visually missing"
                ),
            }
        )
    merged_building_mesh_part_count = int(scene.get("mergedBuildingMeshPartCount") or 0)
    building_shell_mesh_part_count = int(scene.get("buildingShellMeshPartCount") or 0)
    if merged_roof_only_count > 0 and merged_building_mesh_part_count == 0 and building_shell_mesh_part_count == 0:
        findings.append(
            {
                "severity": "high",
                "code": "merged_roof_claim_without_mesh_support",
                "message": (
                    f"{merged_roof_only_count} buildings claim merged-roof-only coverage, but the scene reports no merged building mesh parts"
                ),
            }
        )
    if building_model_count > 0 and no_roof_evidence_count > 0:
        findings.append(
            {
                "severity": "high",
                "code": "missing_roof_evidence",
                "message": (
                    f"{no_roof_evidence_count} buildings have no direct or merged roof evidence in the scene"
                ),
            }
        )
    shaped_roof_coverage = scene.get("buildingRoofCoverageByShape") or {}
    shaped_roof_buckets = ("gabled", "hipped", "pyramidal", "skillion", "mansard", "dome", "onion", "cone", "gambrel")
    shaped_direct_roof_count = 0
    shaped_closure_deck_count = 0
    if isinstance(shaped_roof_coverage, dict):
        for bucket in shaped_roof_buckets:
            row = shaped_roof_coverage.get(bucket) or {}
            if isinstance(row, dict):
                shaped_direct_roof_count += int(row.get("directRoofCount") or 0)
                shaped_closure_deck_count += int(row.get("closureDeckCount") or 0)
    if shaped_direct_roof_count > shaped_closure_deck_count:
        findings.append(
            {
                "severity": "medium",
                "code": "shaped_roof_closure_gap",
                "message": (
                    f"scene reports {shaped_direct_roof_count} direct non-flat roofs but only "
                    f"{shaped_closure_deck_count} closure decks; some shaped roofs may still look open from above"
                ),
            }
        )
    if scene_vegetation_count > 0 and (
        missing_trunk_tree_count > 0 or missing_canopy_tree_count > 0 or detached_canopy_tree_count > 0
    ):
        findings.append(
            {
                "severity": "medium",
                "code": "tree_connectivity_gaps",
                "message": (
                    f"trees connected={connected_tree_count} missing_trunk={missing_trunk_tree_count} "
                    f"missing_canopy={missing_canopy_tree_count} detached_canopy={detached_canopy_tree_count}"
                ),
            }
        )
    if procedural_tree_count > 0 and (
        procedural_missing_trunk_tree_count > 0
        or procedural_missing_canopy_tree_count > 0
        or procedural_detached_canopy_tree_count > 0
    ):
        findings.append(
            {
                "severity": "medium",
                "code": "procedural_tree_connectivity_gaps",
                "message": (
                    f"{procedural_tree_count} procedural trees were audited, with "
                    f"{procedural_connected_tree_count} connected, "
                    f"{procedural_missing_trunk_tree_count} missing trunks, "
                    f"{procedural_missing_canopy_tree_count} missing canopies, and "
                    f"{procedural_detached_canopy_tree_count} detached canopies"
                ),
            }
        )

    manifest_roof_usage = manifest_summary.get("buildingCountByUsage") or {}
    scene_roof_usage = scene.get("buildingRoofCoverageByUsage") or {}
    for usage, expected_count in _sorted_manifest_count_rows(manifest_roof_usage):
        scene_row = scene_roof_usage.get(usage) if isinstance(scene_roof_usage, dict) else None
        scene_count = int(scene_row.get("withRoofCount") or 0) if isinstance(scene_row, dict) else 0
        if expected_count > 0 and scene_count < expected_count:
            findings.append(
                {
                    "severity": "medium",
                    "code": "roof_usage_scene_gap",
                    "message": (
                        f"roof usage bucket {usage} has {scene_count} buildings with roof coverage but manifest expected {expected_count}"
                    ),
                }
            )

    manifest_roof_shapes = manifest_summary.get("buildingCountByRoofShape") or {}
    scene_roof_shapes = scene.get("buildingRoofCoverageByShape") or {}
    for roof_shape, expected_count in _sorted_manifest_count_rows(manifest_roof_shapes):
        scene_row = scene_roof_shapes.get(roof_shape) if isinstance(scene_roof_shapes, dict) else None
        scene_count = int(scene_row.get("directRoofCount") or 0) if isinstance(scene_row, dict) else 0
        if expected_count > 0 and scene_count < expected_count:
            findings.append(
                {
                    "severity": "medium",
                    "code": "roof_shape_scene_gap",
                    "message": (
                        f"roof shape bucket {roof_shape} has {scene_count} direct roof geometries but manifest expected {expected_count}"
                    ),
                }
            )

    manifest_wall_materials = manifest_summary.get("buildingCountByExplicitWallMaterial") or {}
    manifest_wall_material_ids = manifest_summary.get("buildingIdsByExplicitWallMaterial")
    scene_wall_materials = scene.get("buildingModelCountByWallMaterial") or {}
    wall_material_gaps: list[tuple[str, int, int]] = []
    for material, expected_count in _sorted_manifest_count_rows(manifest_wall_materials):
        expected_feature_count = _manifest_bucket_feature_truth_count(
            manifest_wall_materials,
            manifest_wall_material_ids,
            material,
        )
        scene_count = _scene_bucket_feature_truth_count(scene_wall_materials, material, "buildingModelCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            wall_material_gaps.append((material, expected_feature_count, scene_count))
    if wall_material_gaps:
        summary["explicitWallMaterialGaps"] = _gap_rows(
            wall_material_gaps,
            manifest_wall_material_ids,
            scene_wall_materials,
        )
        findings.append(
            {
                "severity": "medium",
                "code": "explicit_wall_material_scene_gap",
                "message": _format_bucket_gap_summary(wall_material_gaps, "explicit wall material"),
            }
        )

    manifest_roof_materials = manifest_summary.get("buildingCountByExplicitRoofMaterial") or {}
    manifest_roof_material_ids = manifest_summary.get("buildingIdsByExplicitRoofMaterial")
    scene_roof_materials = scene.get("buildingModelCountByRoofMaterial") or {}
    roof_material_gaps: list[tuple[str, int, int]] = []
    for material, expected_count in _sorted_manifest_count_rows(manifest_roof_materials):
        expected_feature_count = _manifest_bucket_feature_truth_count(
            manifest_roof_materials,
            manifest_roof_material_ids,
            material,
        )
        scene_count = _scene_bucket_feature_truth_count(scene_roof_materials, material, "buildingModelCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            roof_material_gaps.append((material, expected_feature_count, scene_count))
    if roof_material_gaps:
        summary["explicitRoofMaterialGaps"] = _gap_rows(
            roof_material_gaps,
            manifest_roof_material_ids,
            scene_roof_materials,
        )
        findings.append(
            {
                "severity": "medium",
                "code": "explicit_roof_material_scene_gap",
                "message": _format_bucket_gap_summary(roof_material_gaps, "explicit roof material"),
            }
        )

    manifest_road_kinds = manifest_summary.get("roadCountByKind") or {}
    manifest_road_ids_by_kind = manifest_summary.get("roadIdsByKind")
    scene_road_kinds = scene.get("roadSurfacePartCountByKind") or {}
    road_kind_gaps: list[tuple[str, int, int]] = []
    for kind, expected_count in _sorted_manifest_count_rows(manifest_road_kinds):
        expected_feature_count = _manifest_bucket_feature_truth_count(manifest_road_kinds, manifest_road_ids_by_kind, kind)
        scene_count = _scene_bucket_feature_truth_count(scene_road_kinds, kind, "featureCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            road_kind_gaps.append((kind, expected_feature_count, scene_count))
    if road_kind_gaps:
        summary["roadKindGaps"] = _gap_rows(road_kind_gaps, manifest_road_ids_by_kind, scene_road_kinds)
        findings.append(
            {
                "severity": "medium",
                "code": "road_kind_scene_gap",
                "message": _format_bucket_gap_summary(road_kind_gaps, "road kind"),
            }
        )

    manifest_road_subkinds = manifest_summary.get("roadCountBySubkind") or {}
    manifest_road_ids_by_subkind = manifest_summary.get("roadIdsBySubkind")
    scene_road_subkinds = scene.get("roadSurfacePartCountBySubkind") or {}
    road_subkind_gaps: list[tuple[str, int, int]] = []
    for subkind, expected_count in _sorted_manifest_count_rows(manifest_road_subkinds):
        expected_feature_count = _manifest_bucket_feature_truth_count(
            manifest_road_subkinds,
            manifest_road_ids_by_subkind,
            subkind,
        )
        scene_count = _scene_bucket_feature_truth_count(scene_road_subkinds, subkind, "featureCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            road_subkind_gaps.append((subkind, expected_feature_count, scene_count))
    if road_subkind_gaps:
        summary["roadSubkindGaps"] = _gap_rows(
            road_subkind_gaps,
            manifest_road_ids_by_subkind,
            scene_road_subkinds,
        )
        findings.append(
            {
                "severity": "medium",
                "code": "road_subkind_scene_gap",
                "message": _format_bucket_gap_summary(road_subkind_gaps, "road subkind"),
            }
        )

    manifest_water_kinds = manifest_summary.get("waterCountByKind") or {}
    manifest_water_ids_by_kind = manifest_summary.get("waterIdsByKind")
    scene_water_kinds = scene.get("waterSurfacePartCountByKind") or {}
    water_kind_gaps: list[tuple[str, int, int]] = []
    for kind, expected_count in _sorted_manifest_count_rows(manifest_water_kinds):
        expected_feature_count = _manifest_bucket_feature_truth_count(manifest_water_kinds, manifest_water_ids_by_kind, kind)
        scene_count = _scene_bucket_feature_truth_count(scene_water_kinds, kind, "surfacePartCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            water_kind_gaps.append((kind, expected_feature_count, scene_count))
    if water_kind_gaps:
        summary["waterKindGaps"] = _gap_rows(water_kind_gaps, manifest_water_ids_by_kind, scene_water_kinds)
        findings.append(
            {
                "severity": "medium",
                "code": "water_kind_scene_gap",
                "message": _format_bucket_gap_summary(water_kind_gaps, "water kind"),
            }
        )

    manifest_props = manifest_summary.get("propCountByKind") or {}
    manifest_prop_ids_by_kind = manifest_summary.get("propIdsByKind")
    scene_props = scene.get("propInstanceCountByKind") or {}
    prop_kind_gaps: list[tuple[str, int, int]] = []
    for kind, expected_count in _sorted_manifest_count_rows(manifest_props):
        expected_feature_count = _manifest_bucket_feature_truth_count(manifest_props, manifest_prop_ids_by_kind, kind)
        scene_count = _scene_bucket_feature_truth_count(scene_props, kind, "instanceCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            prop_kind_gaps.append((kind, expected_feature_count, scene_count))
    if prop_kind_gaps:
        summary["propKindGaps"] = _gap_rows(prop_kind_gaps, manifest_prop_ids_by_kind, scene_props)
        findings.append(
            {
                "severity": "medium",
                "code": "prop_kind_scene_gap",
                "message": _format_bucket_gap_summary(prop_kind_gaps, "prop kind"),
            }
        )

    manifest_tree_species = manifest_summary.get("treeCountBySpecies") or {}
    manifest_tree_ids_by_species = manifest_summary.get("treeIdsBySpecies")
    scene_tree_species = scene.get("treeInstanceCountBySpecies") or {}
    tree_species_gaps: list[tuple[str, int, int]] = []
    for species, expected_count in _sorted_manifest_count_rows(manifest_tree_species):
        expected_feature_count = _manifest_bucket_feature_truth_count(
            manifest_tree_species,
            manifest_tree_ids_by_species,
            species,
        )
        scene_count = _scene_bucket_feature_truth_count(scene_tree_species, species, "instanceCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            tree_species_gaps.append((species, expected_feature_count, scene_count))
    if tree_species_gaps:
        summary["treeSpeciesGaps"] = _gap_rows(tree_species_gaps, manifest_tree_ids_by_species, scene_tree_species)
        findings.append(
            {
                "severity": "medium",
                "code": "tree_species_scene_gap",
                "message": _format_bucket_gap_summary(tree_species_gaps, "tree species"),
            }
        )

    manifest_vegetation = manifest_summary.get("vegetationCountByKind") or {}
    manifest_vegetation_ids_by_kind = manifest_summary.get("vegetationIdsByKind")
    scene_vegetation = scene.get("vegetationInstanceCountByKind") or {}
    vegetation_kind_gaps: list[tuple[str, int, int]] = []
    for kind, expected_count in _sorted_manifest_count_rows(manifest_vegetation):
        expected_feature_count = _manifest_bucket_feature_truth_count(
            manifest_vegetation,
            manifest_vegetation_ids_by_kind,
            kind,
        )
        scene_count = _scene_bucket_feature_truth_count(scene_vegetation, kind, "instanceCount")
        if expected_feature_count > 0 and scene_count < expected_feature_count:
            vegetation_kind_gaps.append((kind, expected_feature_count, scene_count))
    if vegetation_kind_gaps:
        summary["vegetationKindGaps"] = _gap_rows(
            vegetation_kind_gaps,
            manifest_vegetation_ids_by_kind,
            scene_vegetation,
        )
        findings.append(
            {
                "severity": "medium",
                "code": "vegetation_kind_scene_gap",
                "message": _format_bucket_gap_summary(vegetation_kind_gaps, "vegetation kind"),
            }
        )

    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "manifestPath": str(manifest_path),
        "logPath": str(log_path),
        "phase": payload.get("phase"),
        "rootName": payload.get("rootName"),
        "focus": payload.get("focus"),
        "radius": payload.get("radius"),
        "scene": scene,
        "manifest": manifest_summary,
        "summary": summary,
        "findings": findings,
    }


def write_html_report(report: dict[str, Any], html_path: Path) -> None:
    scene_metric_keys = [
        "buildingModelsWithDirectShell",
        "buildingModelsMissingDirectShell",
        "buildingModelsWithRoof",
        "buildingModelsWithoutRoof",
        "buildingModelsWithDirectRoof",
        "buildingModelsWithMergedRoofOnly",
        "buildingModelsWithNoRoofEvidence",
        "propInstanceCount",
        "ambientPropInstanceCount",
        "treeInstanceCount",
        "treeModelsWithConnectedTrunkCanopy",
        "treeModelsMissingTrunk",
        "treeModelsMissingCanopy",
        "treeModelsWithDetachedCanopy",
        "vegetationInstanceCount",
        "waterSurfacePartCount",
        "chunksWithWaterGeometry",
        "mergedBuildingMeshPartCount",
        "roadCrosswalkStripeCount",
    ]
    scene_metrics_html = "".join(
        (
            f"<div class=\"metric\"><div class=\"metric-label\">{escape(_to_metric_label(key))}</div>"
            f"<div class=\"metric-value\">{escape(str(report['scene'][key]))}</div></div>"
        )
        for key in scene_metric_keys
        if key in report["scene"]
    )

    findings_html = "".join(
        (
            f"<tr data-finding-code=\"{escape(str(finding['code']))}\">"
            f"<td>{escape(str(finding['severity']))}</td>"
            f"<td>{escape(str(finding['code']))}</td>"
            f"<td>{escape(str(finding['message']))}</td>"
            "</tr>"
        )
        for finding in report["findings"]
    )
    if not findings_html:
        findings_html = "<tr><td colspan='3'>No findings</td></tr>"

    def render_gap_rows(rows: Any) -> str:
        if not isinstance(rows, list):
            return ""
        rendered: list[str] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            missing_ids = row.get("missingIds")
            missing_cell = ""
            if isinstance(missing_ids, list) and missing_ids:
                missing_cell = escape(", ".join(str(value) for value in missing_ids if isinstance(value, str)))
            rendered.append(
                "<tr>"
                f"<td>{escape(str(row.get('bucket', 'unknown')))}</td>"
                f"<td>{escape(str(row.get('manifestCount', 0)))}</td>"
                f"<td>{escape(str(row.get('sceneCount', 0)))}</td>"
                f"<td>{missing_cell}</td>"
                "</tr>"
            )
        return "".join(rendered)

    roof_usage_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('buildingModelCount', 0)))}</td>"
            f"<td>{escape(str(row.get('directRoofCount', 0)))}</td>"
            f"<td>{escape(str(row.get('mergedRoofOnlyCount', 0)))}</td>"
            f"<td>{escape(str(row.get('noRoofEvidenceCount', 0)))}</td></tr>"
        )
        for bucket, row in _sorted_roof_coverage_rows(report["scene"].get("buildingRoofCoverageByUsage"))
    )
    roof_shape_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('buildingModelCount', 0)))}</td>"
            f"<td>{escape(str(row.get('directRoofCount', 0)))}</td>"
            f"<td>{escape(str(row.get('mergedRoofOnlyCount', 0)))}</td>"
            f"<td>{escape(str(row.get('noRoofEvidenceCount', 0)))}</td></tr>"
        )
        for bucket, row in _sorted_roof_coverage_rows(report["scene"].get("buildingRoofCoverageByShape"))
    )
    manifest_roof_usage_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("buildingCountByUsage"))
    )
    manifest_roof_shape_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("buildingCountByRoofShape"))
    )
    manifest_road_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("roadCountByKind"))
    )
    manifest_road_subkind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("roadCountBySubkind"))
    )
    water_type_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('surfacePartCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("waterSurfacePartCountByType") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    water_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('surfacePartCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("waterSurfacePartCountByKind") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    manifest_water_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("waterCountByKind"))
    )
    road_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('surfacePartCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("roadSurfacePartCountByKind") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    road_subkind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('surfacePartCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("roadSurfacePartCountBySubkind") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    prop_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('instanceCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("propInstanceCountByKind") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    ambient_prop_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('instanceCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("ambientPropInstanceCountByKind") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    manifest_prop_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("propCountByKind"))
    )
    tree_species_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('instanceCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("treeInstanceCountBySpecies") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    tree_connectivity_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('treeInstanceCount', 0)))}</td>"
            f"<td>{escape(str(row.get('connectedCount', 0)))}</td>"
            f"<td>{escape(str(row.get('missingTrunkCount', 0)))}</td>"
            f"<td>{escape(str(row.get('missingCanopyCount', 0)))}</td>"
            f"<td>{escape(str(row.get('detachedCanopyCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("treeConnectivityBySpecies") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    procedural_tree_connectivity_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('treeInstanceCount', 0)))}</td>"
            f"<td>{escape(str(row.get('connectedCount', 0)))}</td>"
            f"<td>{escape(str(row.get('missingTrunkCount', 0)))}</td>"
            f"<td>{escape(str(row.get('missingCanopyCount', 0)))}</td>"
            f"<td>{escape(str(row.get('detachedCanopyCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("proceduralTreeConnectivityByKind") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    manifest_tree_species_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("treeCountBySpecies"))
    )
    vegetation_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('instanceCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("vegetationInstanceCountByKind") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    manifest_vegetation_kind_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("vegetationCountByKind"))
    )
    road_kind_gap_rows = render_gap_rows(report["summary"].get("roadKindGaps"))
    road_subkind_gap_rows = render_gap_rows(report["summary"].get("roadSubkindGaps"))
    water_kind_gap_rows = render_gap_rows(report["summary"].get("waterKindGaps"))
    prop_kind_gap_rows = render_gap_rows(report["summary"].get("propKindGaps"))
    tree_species_gap_rows = render_gap_rows(report["summary"].get("treeSpeciesGaps"))
    vegetation_kind_gap_rows = render_gap_rows(report["summary"].get("vegetationKindGaps"))
    wall_material_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('buildingModelCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("buildingModelCountByWallMaterial") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    roof_material_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(row.get('buildingModelCount', 0)))}</td></tr>"
        )
        for bucket, row in sorted((report["scene"].get("buildingModelCountByRoofMaterial") or {}).items())
        if isinstance(bucket, str) and isinstance(row, dict)
    )
    manifest_wall_material_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("buildingCountByExplicitWallMaterial"))
    )
    manifest_roof_material_rows = "".join(
        (
            f"<tr><td>{escape(bucket)}</td>"
            f"<td>{escape(str(count))}</td></tr>"
        )
        for bucket, count in _sorted_manifest_count_rows(report["manifest"].get("buildingCountByExplicitRoofMaterial"))
    )
    wall_material_gap_rows = render_gap_rows(report["summary"].get("explicitWallMaterialGaps"))
    roof_material_gap_rows = render_gap_rows(report["summary"].get("explicitRoofMaterialGaps"))

    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Scene Fidelity Audit</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f4f4f0;
      --ink: #111111;
      --muted: #5f645f;
      --line: #d6d6cf;
      --accent: #0d5c63;
      --paper: #fbfbf8;
    }}
    body {{
      margin: 0;
      font-family: "IBM Plex Sans", "Avenir Next", sans-serif;
      background: radial-gradient(circle at top left, #ffffff, var(--bg) 55%);
      color: var(--ink);
    }}
    main {{
      max-width: 1080px;
      margin: 0 auto;
      padding: 40px 28px 80px;
    }}
    h1, h2 {{
      font-weight: 600;
      letter-spacing: -0.03em;
      margin: 0 0 16px;
    }}
    p, li {{
      color: var(--muted);
      line-height: 1.55;
    }}
    .metric-strip {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin: 28px 0 36px;
    }}
    .metric {{
      background: rgba(251, 251, 248, 0.8);
      border: 1px solid var(--line);
      padding: 14px 16px;
    }}
    .metric-label {{
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--muted);
    }}
    .metric-value {{
      font-size: 28px;
      font-weight: 600;
      margin-top: 8px;
      color: var(--accent);
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      background: rgba(251, 251, 248, 0.7);
      border: 1px solid var(--line);
    }}
    th, td {{
      text-align: left;
      padding: 12px 14px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }}
    th {{
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--muted);
    }}
    pre {{
      overflow: auto;
      padding: 16px;
      border: 1px solid var(--line);
      background: var(--paper);
      font-size: 12px;
      line-height: 1.4;
    }}
  </style>
</head>
<body>
  <main>
    <h1>Scene Fidelity Audit</h1>
    <p>Marker: {escape(str(report["summary"]["marker"]))}</p>
    <div class="metric-strip">
      <div class="metric"><div class="metric-label">building_model_ratio</div><div class="metric-value">{float(report["summary"].get("building_model_ratio", 0.0)):.3f}</div></div>
      <div class="metric"><div class="metric-label">road_geometry_ratio</div><div class="metric-value">{float(report["summary"].get("road_geometry_ratio", 0.0)):.3f}</div></div>
      <div class="metric"><div class="metric-label">prop_instance_ratio</div><div class="metric-value">{float(report["summary"].get("prop_instance_ratio", 0.0)):.3f}</div></div>
      <div class="metric"><div class="metric-label">vegetation_instance_ratio</div><div class="metric-value">{float(report["summary"].get("vegetation_instance_ratio", 0.0)):.3f}</div></div>
      <div class="metric"><div class="metric-label">water_geometry_ratio</div><div class="metric-value">{float(report["summary"].get("water_geometry_ratio", 0.0)):.3f}</div></div>
      <div class="metric"><div class="metric-label">chunk_ratio</div><div class="metric-value">{float(report["summary"].get("chunk_ratio", 0.0)):.3f}</div></div>
    </div>
    {"<div class=\"metric-strip\">" + scene_metrics_html + "</div>" if scene_metrics_html else ""}

    <h2>Findings</h2>
    <table>
      <thead><tr><th>Severity</th><th>Code</th><th>Message</th></tr></thead>
      <tbody>{findings_html}</tbody>
    </table>

    {'<h2>Roof Coverage By Usage</h2><table><thead><tr><th>Usage</th><th>Buildings</th><th>Direct Roof</th><th>Merged Only</th><th>No Roof Evidence</th></tr></thead><tbody>' + roof_usage_rows + '</tbody></table>' if roof_usage_rows else ''}

    {'<h2>Scene Roof Coverage By Shape</h2><table><thead><tr><th>Roof Shape</th><th>Buildings</th><th>Direct Roof</th><th>Merged Only</th><th>No Roof Evidence</th></tr></thead><tbody>' + roof_shape_rows + '</tbody></table>' if roof_shape_rows else ''}

    {'<h2>Manifest Roof Expectations By Usage</h2><table><thead><tr><th>Usage</th><th>Manifest Buildings</th></tr></thead><tbody>' + manifest_roof_usage_rows + '</tbody></table>' if manifest_roof_usage_rows else ''}

    {'<h2>Manifest Roof Expectations By Shape</h2><table><thead><tr><th>Roof Shape</th><th>Manifest Buildings</th></tr></thead><tbody>' + manifest_roof_shape_rows + '</tbody></table>' if manifest_roof_shape_rows else ''}

    {'<h2>Effective Building Wall Materials</h2><table><thead><tr><th>Material</th><th>Scene Buildings</th></tr></thead><tbody>' + wall_material_rows + '</tbody></table>' if wall_material_rows else ''}

    {'<h2>Effective Building Roof Materials</h2><table><thead><tr><th>Material</th><th>Scene Buildings</th></tr></thead><tbody>' + roof_material_rows + '</tbody></table>' if roof_material_rows else ''}

    {'<h2>Manifest Explicit Wall Materials</h2><table><thead><tr><th>Material</th><th>Manifest Buildings</th></tr></thead><tbody>' + manifest_wall_material_rows + '</tbody></table>' if manifest_wall_material_rows else ''}

    {'<h2>Manifest Explicit Roof Materials</h2><table><thead><tr><th>Material</th><th>Manifest Buildings</th></tr></thead><tbody>' + manifest_roof_material_rows + '</tbody></table>' if manifest_roof_material_rows else ''}

    {'<h2>Explicit Wall Material Gaps</h2><table><thead><tr><th>Material</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + wall_material_gap_rows + '</tbody></table>' if wall_material_gap_rows else ''}

    {'<h2>Explicit Roof Material Gaps</h2><table><thead><tr><th>Material</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + roof_material_gap_rows + '</tbody></table>' if roof_material_gap_rows else ''}

    {'<h2>Manifest Road Kinds</h2><table><thead><tr><th>Road Kind</th><th>Manifest Roads</th></tr></thead><tbody>' + manifest_road_kind_rows + '</tbody></table>' if manifest_road_kind_rows else ''}

    {'<h2>Manifest Road Subkinds</h2><table><thead><tr><th>Road Subkind</th><th>Manifest Roads</th></tr></thead><tbody>' + manifest_road_subkind_rows + '</tbody></table>' if manifest_road_subkind_rows else ''}

    {'<h2>Water Surface Breakdown</h2><table><thead><tr><th>Surface Type</th><th>Surface Parts</th></tr></thead><tbody>' + water_type_rows + '</tbody></table>' if water_type_rows else ''}

    {'<h2>Manifest Water Kinds</h2><table><thead><tr><th>Water Kind</th><th>Manifest Water Features</th></tr></thead><tbody>' + manifest_water_kind_rows + '</tbody></table>' if manifest_water_kind_rows else ''}

    {'<h2>Water Surface By Kind</h2><table><thead><tr><th>Water Kind</th><th>Surface Parts</th></tr></thead><tbody>' + water_kind_rows + '</tbody></table>' if water_kind_rows else ''}

    {'<h2>Water Kind Gaps</h2><table><thead><tr><th>Water Kind</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + water_kind_gap_rows + '</tbody></table>' if water_kind_gap_rows else ''}

    {'<h2>Road Surface By Kind</h2><table><thead><tr><th>Road Kind</th><th>Surface Parts</th></tr></thead><tbody>' + road_kind_rows + '</tbody></table>' if road_kind_rows else ''}

    {'<h2>Road Kind Gaps</h2><table><thead><tr><th>Road Kind</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + road_kind_gap_rows + '</tbody></table>' if road_kind_gap_rows else ''}

    {'<h2>Road Surface By Subkind</h2><table><thead><tr><th>Road Subkind</th><th>Surface Parts</th></tr></thead><tbody>' + road_subkind_rows + '</tbody></table>' if road_subkind_rows else ''}

    {'<h2>Road Subkind Gaps</h2><table><thead><tr><th>Road Subkind</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + road_subkind_gap_rows + '</tbody></table>' if road_subkind_gap_rows else ''}

    {'<h2>Prop Breakdown</h2><table><thead><tr><th>Prop Kind</th><th>Instances</th></tr></thead><tbody>' + prop_kind_rows + '</tbody></table>' if prop_kind_rows else ''}

    {'<h2>Manifest Props</h2><table><thead><tr><th>Prop Kind</th><th>Manifest Props</th></tr></thead><tbody>' + manifest_prop_kind_rows + '</tbody></table>' if manifest_prop_kind_rows else ''}

    {'<h2>Prop Kind Gaps</h2><table><thead><tr><th>Prop Kind</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + prop_kind_gap_rows + '</tbody></table>' if prop_kind_gap_rows else ''}

    {'<h2>Ambient Props</h2><table><thead><tr><th>Prop Kind</th><th>Instances</th></tr></thead><tbody>' + ambient_prop_kind_rows + '</tbody></table>' if ambient_prop_kind_rows else ''}

    {'<h2>Tree Species</h2><table><thead><tr><th>Species</th><th>Instances</th></tr></thead><tbody>' + tree_species_rows + '</tbody></table>' if tree_species_rows else ''}

    {'<h2>Manifest Trees By Species</h2><table><thead><tr><th>Species</th><th>Manifest Trees</th></tr></thead><tbody>' + manifest_tree_species_rows + '</tbody></table>' if manifest_tree_species_rows else ''}

    {'<h2>Tree Species Gaps</h2><table><thead><tr><th>Species</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + tree_species_gap_rows + '</tbody></table>' if tree_species_gap_rows else ''}

    {'<h2>Tree Connectivity</h2><table><thead><tr><th>Species</th><th>Trees</th><th>Connected</th><th>Missing Trunk</th><th>Missing Canopy</th><th>Detached Canopy</th></tr></thead><tbody>' + tree_connectivity_rows + '</tbody></table>' if tree_connectivity_rows else ''}

    {'<h2>Procedural Tree Connectivity</h2><table><thead><tr><th>Kind</th><th>Trees</th><th>Connected</th><th>Missing Trunk</th><th>Missing Canopy</th><th>Detached Canopy</th></tr></thead><tbody>' + procedural_tree_connectivity_rows + '</tbody></table>' if procedural_tree_connectivity_rows else ''}

    {'<h2>Vegetation Breakdown</h2><table><thead><tr><th>Vegetation Kind</th><th>Instances</th></tr></thead><tbody>' + vegetation_kind_rows + '</tbody></table>' if vegetation_kind_rows else ''}

    {'<h2>Manifest Vegetation Kinds</h2><table><thead><tr><th>Vegetation Kind</th><th>Manifest Vegetation</th></tr></thead><tbody>' + manifest_vegetation_kind_rows + '</tbody></table>' if manifest_vegetation_kind_rows else ''}

    {'<h2>Vegetation Kind Gaps</h2><table><thead><tr><th>Vegetation Kind</th><th>Manifest</th><th>Scene</th><th>Missing IDs</th></tr></thead><tbody>' + vegetation_kind_gap_rows + '</tbody></table>' if vegetation_kind_gap_rows else ''}

    <h2>Scene Payload</h2>
    <pre>{escape(json.dumps(report["scene"], indent=2, sort_keys=True))}</pre>

    <h2>Manifest Zone</h2>
    <pre>{escape(json.dumps(report["manifest"], indent=2, sort_keys=True))}</pre>
  </main>
</body>
</html>
"""
    html_path.write_text(html, encoding="utf-8")


def _to_metric_label(name: str) -> str:
    label = []
    for index, char in enumerate(name):
        if char.isupper() and index > 0:
            label.append("_")
        label.append(char.lower())
    return "".join(label)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Compare manifest truth to scene summary markers in a Studio log.")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--marker", default="ARNIS_SCENE_PLAY")
    parser.add_argument("--report-json", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--html-out", type=Path)
    args = parser.parse_args(argv)

    if args.report_json:
        report = _load_json(args.report_json)
    else:
        if args.manifest is None or args.log is None:
            parser.error("--manifest and --log are required unless --report-json is provided")
        report = build_report(args.manifest, args.log, marker=args.marker)
        if args.json_out:
            args.json_out.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
        else:
            print(json.dumps(report, indent=2, sort_keys=True))
    if args.html_out:
        write_html_report(report, args.html_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
