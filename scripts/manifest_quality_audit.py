#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from datetime import datetime, timezone
from html import escape
from pathlib import Path
from typing import Any


DEFAULT_MANIFEST_PATH = Path("rust/out/austin-manifest.json")
DEFAULT_SOURCE_PATHS = [
    Path("rust/data/austin_overpass.json"),
    Path("rust/data/overture_buildings.geojson"),
]
LARGE_BUILDING_AREA_THRESHOLD = 2_500.0
HOTSPOT_LIMIT = 8
PEDESTRIAN_ROAD_KINDS = {
    "bridleway",
    "corridor",
    "cycleway",
    "footway",
    "path",
    "pedestrian",
    "steps",
    "track",
}
VEGETATION_LANDUSE_KINDS = {
    "cemetery",
    "farmland",
    "farmyard",
    "forest",
    "garden",
    "grass",
    "greenfield",
    "meadow",
    "orchard",
    "park",
    "recreation_ground",
    "village_green",
    "wood",
}
SUSPICIOUS_GLASS_USAGES = {
    "bank",
    "church",
    "civic",
    "courthouse",
    "detached",
    "government",
    "house",
    "hospital",
    "mosque",
    "religious",
    "school",
    "temple",
    "terrace",
    "university",
}
SUSPICIOUS_PLASTIC_USAGES = {
    "bank",
    "church",
    "civic",
    "courthouse",
    "detached",
    "government",
    "hospital",
    "house",
    "mosque",
    "religious",
    "school",
    "temple",
    "terrace",
    "university",
}
SUSPICIOUS_GLASS_NAME_PATTERNS = (
    ("capitol", "name:capitol"),
    ("cathedral", "name:cathedral"),
    ("church", "name:church"),
    ("counties", "name:counties"),
    ("courthouse", "name:courthouse"),
    ("executive office", "name:executive office"),
    ("library", "name:library"),
    ("museum", "name:museum"),
    ("office building", "name:office building"),
    ("school", "name:school"),
    ("state office", "name:state office"),
    ("temple", "name:temple"),
    ("university", "name:university"),
)
IDENTITY_PRIORITY_USAGE_SIGNALS = {
    "bank",
    "civic",
    "courthouse",
    "government",
    "hospital",
    "mosque",
    "religious",
    "school",
    "temple",
    "university",
}
IDENTITY_PRIORITY_NAME_PATTERNS = (
    ("capitol", "name:capitol"),
    ("cathedral", "name:cathedral"),
    ("church", "name:church"),
    ("courthouse", "name:courthouse"),
    ("memorial", "name:memorial"),
    ("museum", "name:museum"),
    ("state office", "name:state office"),
    ("supreme court", "name:supreme court"),
    ("temple", "name:temple"),
    ("university", "name:university"),
)
USAGE_EQUIVALENCE_GROUPS = {
    "civic": {
        "civic",
        "courthouse",
        "fire_station",
        "police",
        "townhall",
        "post_office",
        "community_centre",
        "social_centre",
        "arts_centre",
        "theatre",
        "cinema",
        "studio",
    },
    "religious": {"religious", "church", "cathedral", "mosque", "temple", "synagogue", "chapel", "shrine"},
    "restaurant": {"restaurant", "bar", "biergarten", "cafe", "fast_food", "food_court", "pub"},
    "school": {"school", "college", "university", "library", "kindergarten"},
}
USAGE_EQUIVALENCE_LOOKUP = {
    label: family
    for family, labels in USAGE_EQUIVALENCE_GROUPS.items()
    for label in labels
}
SOURCE_BUILDING_MATERIAL_LOOKUP = {
    "glass": "glass",
    "mirror": "glass",
    "brick": "brick_masonry",
    "bricks": "brick_masonry",
    "brickwork": "brick_masonry",
    "masonry": "brick_masonry",
    "stone": "brick_masonry",
    "sandstone": "brick_masonry",
    "limestone": "brick_masonry",
    "granite": "brick_masonry",
    "marble": "brick_masonry",
    "cobblestone": "brick_masonry",
    "concrete": "concrete",
    "reinforced_concrete": "concrete",
    "cement": "concrete",
    "steel": "metal",
    "metal": "metal",
    "aluminium": "metal",
    "aluminum": "metal",
    "iron": "metal",
    "sheet_metal": "metal",
    "metal_sheet": "metal",
    "corrugated_metal": "metal",
    "copper": "metal",
    "wood": "wood",
    "timber": "wood",
    "log": "wood",
    "wood_planks": "wood",
}
MANIFEST_BUILDING_MATERIAL_LOOKUP = {
    "Glass": "glass",
    "Brick": "brick_masonry",
    "Cobblestone": "brick_masonry",
    "Limestone": "brick_masonry",
    "Marble": "brick_masonry",
    "Granite": "brick_masonry",
    "Sandstone": "brick_masonry",
    "Slate": "brick_masonry",
    "Concrete": "concrete",
    "Metal": "metal",
    "CorrodedMetal": "metal",
    "DiamondPlate": "metal",
    "Foil": "metal",
    "Plastic": "plastic",
    "SmoothPlastic": "plastic",
    "Wood": "wood",
    "WoodPlanks": "wood",
}
STRONG_IDENTITY_USAGE_SIGNALS = {
    "bank",
    "cathedral",
    "church",
    "civic",
    "courthouse",
    "government",
    "hospital",
    "mosque",
    "religious",
    "school",
    "temple",
    "university",
}
STRONG_IDENTITY_NAME_PATTERNS = (
    ("capitol", "name:capitol"),
    ("mansion", "name:mansion"),
    ("courthouse", "name:courthouse"),
    ("church", "name:church"),
    ("cathedral", "name:cathedral"),
    ("temple", "name:temple"),
    ("mosque", "name:mosque"),
    ("school", "name:school"),
    ("university", "name:university"),
    ("hospital", "name:hospital"),
    ("visitor center", "name:visitor center"),
    ("state office", "name:state office"),
    ("office building", "name:office building"),
    ("museum", "name:museum"),
    ("library", "name:library"),
)


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


def _polygon_area(points: list[dict[str, Any]]) -> float:
    if len(points) < 3:
        return 0.0
    area = 0.0
    for index, point in enumerate(points):
        nxt = points[(index + 1) % len(points)]
        area += _safe_float(point.get("x")) * _safe_float(nxt.get("z"))
        area -= _safe_float(nxt.get("x")) * _safe_float(point.get("z"))
    return abs(area) * 0.5


def _projected_polygon_area(
    coords: list[tuple[float, float]],
    *,
    center_lat: float | None,
    center_lon: float | None,
    meters_per_stud: float,
) -> float:
    if center_lat is None or center_lon is None or len(coords) < 3:
        return 0.0
    projected = []
    for lat, lon in coords:
        x, z = _project_latlon_to_studs(lat, lon, center_lat, center_lon, meters_per_stud)
        projected.append({"x": x, "z": z})
    return _polygon_area(projected)


def _projected_ring(
    coords: list[tuple[float, float]],
    *,
    center_lat: float | None,
    center_lon: float | None,
    meters_per_stud: float,
) -> list[dict[str, float]]:
    if center_lat is None or center_lon is None:
        return []
    projected: list[dict[str, float]] = []
    for lat, lon in coords:
        x, z = _project_latlon_to_studs(lat, lon, center_lat, center_lon, meters_per_stud)
        projected.append({"x": x, "z": z})
    return projected


def _ratio(numerator: float, denominator: float) -> float:
    if denominator <= 0:
        return 0.0
    return numerator / denominator


def _suspicious_material_signals(*, usage: Any, name: Any, material: Any) -> list[str]:
    normalized_usage = str(usage or "").lower()
    normalized_name = str(name or "").lower()
    material_family = _normalize_manifest_material_value(str(material or ""))
    signals: list[str] = []
    if material_family == "glass":
        if normalized_usage in SUSPICIOUS_GLASS_USAGES:
            signals.append(f"usage:{normalized_usage}")
        for pattern, label in SUSPICIOUS_GLASS_NAME_PATTERNS:
            if pattern in normalized_name:
                signals.append(label)
    elif material_family == "plastic":
        if normalized_usage in SUSPICIOUS_PLASTIC_USAGES:
            signals.append(f"usage:{normalized_usage}")
            signals.append("family:plastic")
    return signals


def _entropy(counter: Counter[str | None]) -> float:
    total = sum(counter.values())
    if total <= 0:
        return 0.0
    entropy = 0.0
    for count in counter.values():
        probability = count / total
        if probability > 0:
            entropy -= probability * math.log2(probability)
    return entropy


def _normalized_entropy(counter: Counter[str | None]) -> float:
    buckets = len([key for key, count in counter.items() if count > 0])
    if buckets <= 1:
        return 0.0
    return _entropy(counter) / math.log2(buckets)


def _percentile(values: list[float], ratio: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil((len(ordered) - 1) * ratio)))
    return ordered[index]


def _numeric_stats(values: list[float]) -> dict[str, float]:
    if not values:
        return {
            "count": 0.0,
            "min": 0.0,
            "max": 0.0,
            "mean": 0.0,
            "median": 0.0,
            "p95": 0.0,
        }
    ordered = sorted(values)
    middle = len(ordered) // 2
    median = ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) * 0.5
    return {
        "count": float(len(ordered)),
        "min": ordered[0],
        "max": ordered[-1],
        "mean": sum(ordered) / len(ordered),
        "median": median,
        "p95": _percentile(ordered, 0.95),
    }


def _increment_nested_distribution(
    container: dict[str, Counter[str]],
    outer_key: Any,
    inner_key: Any,
) -> None:
    outer = str(outer_key or "unknown")
    inner = str(inner_key or "unknown")
    row = container.get(outer)
    if row is None:
        row = Counter()
        container[outer] = row
    row[inner] += 1


def _build_source_usage_diagnostics(
    canonical_source_buildings: list[dict[str, Any]],
    source_usage_mismatches: list[dict[str, Any]],
    source_usage_refinements: list[dict[str, Any]],
    source_material_mismatches: list[dict[str, Any]],
    source_identity_loss_records: list[dict[str, Any]],
    source_identity_transform_records: list[dict[str, Any]],
) -> tuple[dict[str, dict[str, int]], list[dict[str, int | str]]]:
    diagnostics: dict[str, dict[str, int]] = {}

    def ensure(signal: str) -> dict[str, int]:
        row = diagnostics.get(signal)
        if row is None:
            row = {
                "source_count": 0,
                "mismatch_count": 0,
                "refinement_count": 0,
                "material_mismatch_count": 0,
                "identity_loss_count": 0,
                "identity_transform_count": 0,
            }
            diagnostics[signal] = row
        return row

    for source_record in canonical_source_buildings:
        signal = str(source_record.get("source_usage_signal") or "unknown")
        ensure(signal)["source_count"] += 1

    for row in source_usage_mismatches:
        signal = str(row.get("source_usage_signal") or "unknown")
        ensure(signal)["mismatch_count"] += 1

    for row in source_usage_refinements:
        signal = str(row.get("source_usage_signal") or "unknown")
        ensure(signal)["refinement_count"] += 1

    for row in source_material_mismatches:
        signal = str(row.get("source_usage_signal") or row.get("manifest_usage") or "unknown")
        ensure(signal)["material_mismatch_count"] += 1

    for row in source_identity_loss_records:
        signal = str(row.get("source_usage_signal") or "unknown")
        ensure(signal)["identity_loss_count"] += 1

    for row in source_identity_transform_records:
        signal = str(row.get("source_usage_signal") or "unknown")
        ensure(signal)["identity_transform_count"] += 1

    top_mismatch_types = sorted(
        (
            {"source_usage_signal": signal, **counts}
            for signal, counts in diagnostics.items()
            if counts["mismatch_count"] > 0
            or counts["identity_loss_count"] > 0
            or counts["identity_transform_count"] > 0
            or counts["material_mismatch_count"] > 0
        ),
        key=lambda row: (
            -int(row["mismatch_count"]),
            -int(row["identity_loss_count"]),
            -int(row["identity_transform_count"]),
            -int(row["material_mismatch_count"]),
            -int(row["source_count"]),
            str(row["source_usage_signal"]),
        ),
    )

    return diagnostics, top_mismatch_types[:HOTSPOT_LIMIT]


def _top_hotspots(items: list[dict[str, Any]], key: str, limit: int = HOTSPOT_LIMIT) -> list[dict[str, Any]]:
    ranked = sorted(
        items,
        key=lambda item: (_safe_float(item.get(key)), str(item.get("chunk_id"))),
        reverse=True,
    )
    return ranked[:limit]


def _clamp_score(score: float) -> float:
    return max(0.0, min(100.0, score))


def _format_bbox(meta: dict[str, Any]) -> dict[str, Any]:
    bbox = meta.get("bbox") if isinstance(meta.get("bbox"), dict) else {}
    min_lat = bbox.get("minLat")
    min_lon = bbox.get("minLon")
    max_lat = bbox.get("maxLat")
    max_lon = bbox.get("maxLon")
    if None in (min_lat, min_lon, max_lat, max_lon):
        return {
            "bbox": bbox,
            "center_lat": None,
            "center_lon": None,
            "openstreetmap_url": None,
        }

    center_lat = (_safe_float(min_lat) + _safe_float(max_lat)) * 0.5
    center_lon = (_safe_float(min_lon) + _safe_float(max_lon)) * 0.5
    return {
        "bbox": bbox,
        "center_lat": center_lat,
        "center_lon": center_lon,
        "openstreetmap_url": (
            "https://www.openstreetmap.org/?mlat="
            f"{center_lat:.6f}&mlon={center_lon:.6f}#map=14/{center_lat:.6f}/{center_lon:.6f}"
        ),
    }


def _expanded_bbox(bbox: dict[str, Any], factor: float = 0.1) -> dict[str, float]:
    min_lat = _safe_float(bbox.get("minLat"))
    min_lon = _safe_float(bbox.get("minLon"))
    max_lat = _safe_float(bbox.get("maxLat"))
    max_lon = _safe_float(bbox.get("maxLon"))
    margin = max(max_lat - min_lat, max_lon - min_lon) * factor
    return {
        "minLat": min_lat - margin,
        "minLon": min_lon - margin,
        "maxLat": max_lat + margin,
        "maxLon": max_lon + margin,
    }


def _mercator_latlon_to_meters(lat: float, lon: float) -> tuple[float, float]:
    radius = 6_378_137.0
    x = math.radians(lon) * radius
    lat_radians = math.radians(lat)
    y = math.log(math.tan(lat_radians) + (1.0 / math.cos(lat_radians))) * radius
    return x, y


def _project_latlon_to_studs(lat: float, lon: float, center_lat: float, center_lon: float, meters_per_stud: float) -> tuple[float, float]:
    center_x, center_y = _mercator_latlon_to_meters(center_lat, center_lon)
    point_x, point_y = _mercator_latlon_to_meters(lat, lon)
    dx = (point_x - center_x) / meters_per_stud
    dz = (center_y - point_y) / meters_per_stud
    return dx, dz


def _bbox_contains_latlon(bbox: dict[str, Any], lat: float, lon: float) -> bool:
    min_lat = _safe_float(bbox.get("minLat"))
    min_lon = _safe_float(bbox.get("minLon"))
    max_lat = _safe_float(bbox.get("maxLat"))
    max_lon = _safe_float(bbox.get("maxLon"))
    return min_lat <= lat <= max_lat and min_lon <= lon <= max_lon


def _new_bounds() -> dict[str, float | None]:
    return {"min_x": None, "max_x": None, "min_z": None, "max_z": None}


def _extend_bounds(bounds: dict[str, float | None], x: float, z: float) -> None:
    bounds["min_x"] = x if bounds["min_x"] is None else min(bounds["min_x"], x)
    bounds["max_x"] = x if bounds["max_x"] is None else max(bounds["max_x"], x)
    bounds["min_z"] = z if bounds["min_z"] is None else min(bounds["min_z"], z)
    bounds["max_z"] = z if bounds["max_z"] is None else max(bounds["max_z"], z)


def _bounds_metrics(bounds: dict[str, float | None]) -> dict[str, float]:
    if None in (bounds["min_x"], bounds["max_x"], bounds["min_z"], bounds["max_z"]):
        return {
            "min_x": 0.0,
            "max_x": 0.0,
            "min_z": 0.0,
            "max_z": 0.0,
            "span_x": 0.0,
            "span_z": 0.0,
        }
    return {
        "min_x": float(bounds["min_x"]),
        "max_x": float(bounds["max_x"]),
        "min_z": float(bounds["min_z"]),
        "max_z": float(bounds["max_z"]),
        "span_x": float(bounds["max_x"] - bounds["min_x"]),
        "span_z": float(bounds["max_z"] - bounds["min_z"]),
    }


def _alignment_ratio(actual: float, expected: float) -> float:
    if actual <= 0 or expected <= 0:
        return 0.0
    return min(actual, expected) / max(actual, expected)


def _polygon_centroid(points: list[dict[str, float]]) -> tuple[float, float] | None:
    if not points:
        return None

    twice_area = 0.0
    centroid_x = 0.0
    centroid_z = 0.0
    for index, point in enumerate(points):
        nxt = points[(index + 1) % len(points)]
        x1 = _safe_float(point.get("x"))
        z1 = _safe_float(point.get("z"))
        x2 = _safe_float(nxt.get("x"))
        z2 = _safe_float(nxt.get("z"))
        cross = x1 * z2 - x2 * z1
        twice_area += cross
        centroid_x += (x1 + x2) * cross
        centroid_z += (z1 + z2) * cross

    if abs(twice_area) <= 1e-9:
        return (
            sum(_safe_float(point.get("x")) for point in points) / len(points),
            sum(_safe_float(point.get("z")) for point in points) / len(points),
        )

    factor = 1.0 / (3.0 * twice_area)
    return centroid_x * factor, centroid_z * factor


def _point_in_polygon(point: tuple[float, float], polygon: list[dict[str, float]]) -> bool:
    if len(polygon) < 3:
        return False

    px, pz = point
    inside = False
    previous = polygon[-1]
    for current in polygon:
        current_above = _safe_float(current.get("z")) > pz
        previous_above = _safe_float(previous.get("z")) > pz
        if current_above != previous_above:
            intersect_x = (_safe_float(previous.get("x")) - _safe_float(current.get("x"))) * (
                pz - _safe_float(current.get("z"))
            ) / ((_safe_float(previous.get("z")) - _safe_float(current.get("z"))) + 1e-12) + _safe_float(
                current.get("x")
            )
            if px < intersect_x:
                inside = not inside
        previous = current
    return inside


def _footprints_substantially_overlap(
    existing: list[dict[str, float]], candidate: list[dict[str, float]]
) -> bool:
    if len(existing) < 3 or len(candidate) < 3:
        return False

    existing_min_x = min(_safe_float(point.get("x")) for point in existing)
    existing_max_x = max(_safe_float(point.get("x")) for point in existing)
    existing_min_z = min(_safe_float(point.get("z")) for point in existing)
    existing_max_z = max(_safe_float(point.get("z")) for point in existing)
    candidate_min_x = min(_safe_float(point.get("x")) for point in candidate)
    candidate_max_x = max(_safe_float(point.get("x")) for point in candidate)
    candidate_min_z = min(_safe_float(point.get("z")) for point in candidate)
    candidate_max_z = max(_safe_float(point.get("z")) for point in candidate)

    overlap_min_x = max(existing_min_x, candidate_min_x)
    overlap_min_z = max(existing_min_z, candidate_min_z)
    overlap_max_x = min(existing_max_x, candidate_max_x)
    overlap_max_z = min(existing_max_z, candidate_max_z)
    if overlap_max_x <= overlap_min_x or overlap_max_z <= overlap_min_z:
        return False

    existing_area = _polygon_area(existing)
    candidate_area = _polygon_area(candidate)
    if existing_area <= 0 or candidate_area <= 0:
        return False

    overlap_area = (overlap_max_x - overlap_min_x) * (overlap_max_z - overlap_min_z)
    overlap_ratio = overlap_area / min(existing_area, candidate_area)
    if overlap_ratio < 0.85:
        return False

    existing_centroid = _polygon_centroid(existing)
    candidate_centroid = _polygon_centroid(candidate)
    if existing_centroid is None or candidate_centroid is None:
        return False

    centroid_dx = existing_centroid[0] - candidate_centroid[0]
    centroid_dz = existing_centroid[1] - candidate_centroid[1]
    centroid_distance = math.sqrt(centroid_dx * centroid_dx + centroid_dz * centroid_dz)
    max_centroid_distance = max(8.0, math.sqrt(min(existing_area, candidate_area)) * 0.15)
    if centroid_distance > max_centroid_distance:
        return False

    return _point_in_polygon(candidate_centroid, existing) or _point_in_polygon(existing_centroid, candidate)


def _footprint_bounds(points: list[dict[str, float]]) -> tuple[float, float, float, float] | None:
    if len(points) < 3:
        return None
    min_x = min(_safe_float(point.get("x")) for point in points)
    max_x = max(_safe_float(point.get("x")) for point in points)
    min_z = min(_safe_float(point.get("z")) for point in points)
    max_z = max(_safe_float(point.get("z")) for point in points)
    return min_x, min_z, max_x, max_z


def _bucket_keys_for_bounds(
    bounds: tuple[float, float, float, float], cell_size: float = 256.0
) -> list[tuple[int, int]]:
    min_x, min_z, max_x, max_z = bounds
    min_bucket_x = math.floor(min_x / cell_size)
    max_bucket_x = math.floor(max_x / cell_size)
    min_bucket_z = math.floor(min_z / cell_size)
    max_bucket_z = math.floor(max_z / cell_size)
    return [
        (bucket_x, bucket_z)
        for bucket_x in range(min_bucket_x, max_bucket_x + 1)
        for bucket_z in range(min_bucket_z, max_bucket_z + 1)
    ]


def _canonicalize_source_buildings(
    source_buildings: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    canonical: list[dict[str, Any]] = []
    duplicate_counts = {"overture_dropped_as_duplicate": 0}
    spatial_index: dict[tuple[int, int], list[int]] = {}

    for source_building in sorted(source_buildings, key=lambda item: 0 if item.get("source") == "osm" else 1):
        projected = source_building.get("projected")
        if not isinstance(projected, list):
            canonical.append(source_building)
            continue
        bounds = _footprint_bounds(projected)
        if bounds is None:
            canonical.append(source_building)
            continue

        candidate_indices: set[int] = set()
        for bucket_key in _bucket_keys_for_bounds(bounds):
            candidate_indices.update(spatial_index.get(bucket_key, []))

        if source_building.get("source") == "overture" and any(
            _footprints_substantially_overlap(canonical[index].get("projected", []), projected)
            for index in candidate_indices
        ):
            duplicate_counts["overture_dropped_as_duplicate"] += 1
            continue

        source_building = dict(source_building)
        source_building["_bounds"] = bounds
        canonical.append(source_building)
        canonical_index = len(canonical) - 1
        for bucket_key in _bucket_keys_for_bounds(bounds):
            spatial_index.setdefault(bucket_key, []).append(canonical_index)

    return canonical, duplicate_counts


def _point_in_zone(
    x: float,
    z: float,
    *,
    focus_x: float | None,
    focus_z: float | None,
    radius: float | None,
) -> bool:
    if focus_x is None or focus_z is None or radius is None:
        return True
    dx = x - focus_x
    dz = z - focus_z
    return dx * dx + dz * dz <= radius * radius


def _compact_json_snippet(data: Any, max_chars: int = 420) -> str:
    text = json.dumps(data, indent=2, sort_keys=True)
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 3] + "..."


def _extract_source_snippet(path: Path) -> str:
    data = _load_json(path)
    if "osm3s" in data or "elements" in data:
        elements = data.get("elements") if isinstance(data.get("elements"), list) else []
        tagged_sample = None
        for element in elements:
            if isinstance(element, dict) and isinstance(element.get("tags"), dict):
                tagged_sample = {
                    "type": element.get("type"),
                    "id": element.get("id"),
                    "tags": element.get("tags"),
                }
                break
        snippet = {
            "generator": data.get("generator"),
            "osm3s": data.get("osm3s"),
            "sample_tagged_element": tagged_sample,
        }
        return _compact_json_snippet(snippet)

    if data.get("type") == "FeatureCollection" and isinstance(data.get("features"), list):
        features = data.get("features") or []
        sample_feature = None
        for feature in features:
            if not isinstance(feature, dict):
                continue
            sample_feature = {
                "type": feature.get("type"),
                "geometry_type": (feature.get("geometry") or {}).get("type")
                if isinstance(feature.get("geometry"), dict)
                else None,
                "properties": feature.get("properties"),
            }
            break
        snippet = {
            "type": "FeatureCollection",
            "feature_count": len(features),
            "sample_feature": sample_feature,
        }
        return _compact_json_snippet(snippet)

    meta = data.get("meta") if isinstance(data.get("meta"), dict) else None
    snippet = {"keys": list(data.keys())[:10], "meta": meta}
    return _compact_json_snippet(snippet)


def _build_source_context(path: Path) -> dict[str, Any]:
    return {
        "path": str(path),
        "exists": path.exists(),
        "size_bytes": path.stat().st_size if path.exists() else None,
        "snippet": _extract_source_snippet(path) if path.exists() else None,
    }


def _normalize_source_usage_value(value: str) -> str:
    normalized = value.strip().lower()
    if normalized == "semidetached_house":
        return "house"
    if normalized == "terraced_house":
        return "terrace"
    if normalized == "public":
        return "civic"
    return normalized


def _split_material_tokens(value: str) -> list[str]:
    normalized = value.strip().lower().replace("-", "_").replace(" ", "_")
    for separator in ("/", ";", ",", "|"):
        normalized = normalized.replace(separator, ";")
    return [token for token in (part.strip("_ ") for part in normalized.split(";")) if token]


def _normalize_source_material_value(value: str) -> str | None:
    for token in _split_material_tokens(value):
        material_family = SOURCE_BUILDING_MATERIAL_LOOKUP.get(token)
        if material_family:
            return material_family
    return None


def _classify_osm_material_signal(tags: dict[str, Any]) -> dict[str, str] | None:
    for tag_key in ("building:material", "material"):
        raw_value = str(tags.get(tag_key) or "").strip()
        if not raw_value:
            continue
        material_family = _normalize_source_material_value(raw_value)
        if material_family:
            return {
                "tag": tag_key,
                "raw": raw_value,
                "family": material_family,
            }
    return None


def _normalize_manifest_material_value(value: str) -> str | None:
    return MANIFEST_BUILDING_MATERIAL_LOOKUP.get(str(value or "").strip())


def _normalize_identity_text(value: Any) -> str:
    return " ".join(str(value or "").strip().lower().split())


def _normalize_name_for_match(value: Any) -> str:
    text = str(value or "").strip().lower()
    return "".join(character for character in text if character.isalnum())


def _classify_overture_usage_signal(properties: dict[str, Any]) -> str | None:
    for key in ("class", "subtype"):
        raw_value = str(properties.get(key) or "").strip()
        if not raw_value:
            continue
        normalized = _normalize_source_usage_value(raw_value)
        if normalized:
            return normalized
    return None


def _overture_source_id(properties: dict[str, Any]) -> str | None:
    sources = properties.get("sources")
    if isinstance(sources, list):
        for source in sources:
            if not isinstance(source, dict):
                continue
            record_id = str(source.get("record_id") or "").strip()
            if record_id:
                return f"ov_{record_id}"
    overture_id = str(properties.get("id") or "").strip()
    if overture_id:
        return f"ov_{overture_id}"
    return None


def _strong_source_identity_name_signals(name: Any) -> list[str]:
    normalized_name = str(name or "").strip().lower()
    if not normalized_name:
        return []
    signals: list[str] = []
    for pattern, label in STRONG_IDENTITY_NAME_PATTERNS:
        if pattern in normalized_name:
            signals.append(label)
    return signals


def _strong_source_identity_reasons(source_record: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    usage_signal = str(source_record.get("source_usage_signal") or "").strip().lower()
    if usage_signal in STRONG_IDENTITY_USAGE_SIGNALS:
        reasons.append(f"usage:{usage_signal}")
    name_signals = _strong_source_identity_name_signals(source_record.get("name"))
    reasons.extend(name_signals)
    if source_record.get("has_parts") is True:
        reasons.append("has_parts")
    material_signal = str(source_record.get("source_material_signal") or "").strip().lower()
    if material_signal in {"brick_masonry", "glass", "metal", "wood"}:
        reasons.append(f"material:{material_signal}")

    if reasons:
        return list(dict.fromkeys(reasons))

    normalized_name = _normalize_name_for_match(source_record.get("name"))
    if normalized_name and len(normalized_name) >= 18:
        return ["named"]

    return []


def _identity_record_key(source_record: dict[str, Any]) -> str | None:
    source_id = str(source_record.get("source_id") or "").strip()
    if source_id:
        return f"id:{source_id}"
    normalized_name = _normalize_name_for_match(source_record.get("name"))
    if normalized_name:
        return f"name:{normalized_name}"
    return None


def _build_record_spatial_index(
    records: list[dict[str, Any]],
    *,
    projected_key: str = "projected",
) -> dict[tuple[int, int], list[dict[str, Any]]]:
    spatial_index: dict[tuple[int, int], list[dict[str, Any]]] = {}
    for record in records:
        projected = record.get(projected_key)
        if not isinstance(projected, list):
            continue
        bounds = _footprint_bounds(projected)
        if bounds is None:
            continue
        record["_bounds"] = bounds
        for bucket_key in _bucket_keys_for_bounds(bounds):
            spatial_index.setdefault(bucket_key, []).append(record)
    return spatial_index


def _find_overlapping_records(
    source_projected: list[dict[str, float]],
    spatial_index: dict[tuple[int, int], list[dict[str, Any]]],
    *,
    projected_key: str = "projected",
) -> list[dict[str, Any]]:
    bounds = _footprint_bounds(source_projected)
    if bounds is None:
        return []

    candidate_records: list[dict[str, Any]] = []
    seen_ids: set[int] = set()
    for bucket_key in _bucket_keys_for_bounds(bounds):
        for candidate in spatial_index.get(bucket_key, []):
            marker = id(candidate)
            if marker in seen_ids:
                continue
            seen_ids.add(marker)
            candidate_projected = candidate.get(projected_key)
            if not isinstance(candidate_projected, list):
                continue
            if _footprints_substantially_overlap(candidate_projected, source_projected):
                candidate_records.append(candidate)
    return candidate_records


def _classify_osm_building_usage_signal(tags: dict[str, Any]) -> str | None:
    office = str(tags.get("office") or "").strip().lower()
    if office == "government":
        return "government"
    if office:
        return "office"

    government = str(tags.get("government") or "").strip().lower()
    if government in {"yes", "government", "state", "legislative", "executive", "judicial"}:
        return "government"

    tourism = str(tags.get("tourism") or "").strip().lower()
    if tourism in {"hotel", "motel", "hostel"}:
        return "hotel"

    amenity = str(tags.get("amenity") or "").strip().lower()
    amenity_map = {
        "restaurant": "restaurant",
        "bar": "restaurant",
        "cafe": "restaurant",
        "fast_food": "restaurant",
        "pub": "restaurant",
        "food_court": "restaurant",
        "biergarten": "restaurant",
        "parking": "parking",
        "parking_entrance": "parking",
        "parking_space": "parking",
        "place_of_worship": "religious",
        "school": "school",
        "college": "university",
        "university": "university",
        "library": "school",
        "kindergarten": "school",
        "hospital": "hospital",
        "clinic": "hospital",
        "doctors": "hospital",
        "dentist": "hospital",
        "pharmacy": "hospital",
        "veterinary": "hospital",
        "bank": "bank",
        "fuel": "garage",
        "car_wash": "garage",
        "car_rental": "garage",
        "vehicle_inspection": "garage",
        "fire_station": "civic",
        "police": "civic",
        "courthouse": "courthouse",
        "townhall": "civic",
        "post_office": "civic",
        "community_centre": "civic",
        "social_centre": "civic",
        "arts_centre": "civic",
        "theatre": "civic",
        "cinema": "civic",
        "studio": "civic",
    }
    if amenity in amenity_map:
        return amenity_map[amenity]

    shop = str(tags.get("shop") or "").strip().lower()
    if shop == "supermarket":
        return "supermarket"
    if shop:
        return "retail"

    landuse = str(tags.get("landuse") or "").strip().lower()
    if landuse in {"commercial", "retail"}:
        return "commercial"
    if landuse in {"industrial", "depot"}:
        return "industrial"

    man_made = str(tags.get("man_made") or "").strip().lower()
    if man_made in {"storage_tank", "silo", "works", "water_tower", "tower", "mast"}:
        return "industrial"

    name = str(tags.get("name") or "").strip().lower()
    if (
        "capitol" in name
        or "legislative" in name
        or "governor" in name
        or "state office" in name
    ):
        return "government"
    if "supreme court" in name or "courthouse" in name or "court building" in name:
        return "courthouse"

    building = str(tags.get("building") or tags.get("building:part") or "").strip()
    if not building:
        return None
    normalized_building = _normalize_source_usage_value(building)
    if normalized_building in {"yes", "building"}:
        return "building"
    return normalized_building


def _normalize_usage_equivalence(value: str) -> str:
    normalized = str(value or "").strip().lower()
    return USAGE_EQUIVALENCE_LOOKUP.get(normalized, normalized)


def _is_benign_usage_refinement(source_signal: str, manifest_usage: str) -> bool:
    if not source_signal or not manifest_usage:
        return False
    return _normalize_usage_equivalence(source_signal) == _normalize_usage_equivalence(manifest_usage)


def _source_identity_signals(
    *,
    source_usage_signal: Any,
    name: Any,
    has_inner: bool,
    has_parts: bool,
) -> list[str]:
    normalized_usage = str(source_usage_signal or "").strip().lower()
    normalized_name = _normalize_identity_text(name)
    signals: list[str] = []
    if normalized_name:
        signals.append("named")
    if normalized_usage in IDENTITY_PRIORITY_USAGE_SIGNALS:
        signals.append(f"usage:{normalized_usage}")
    for pattern, label in IDENTITY_PRIORITY_NAME_PATTERNS:
        if pattern in normalized_name:
            signals.append(label)
    if has_inner:
        signals.append("structure:inner")
    if has_parts:
        signals.append("structure:parts")
    return signals


def _is_priority_identity_record(record: dict[str, Any]) -> bool:
    signals = record.get("source_identity_signals")
    if not isinstance(signals, list) or not signals:
        return False
    if "structure:inner" in signals or "structure:parts" in signals:
        return True
    if any(str(signal).startswith("name:") for signal in signals):
        return True
    return len(signals) >= 2


def _build_osm_summary(source_paths: list[Path]) -> dict[str, Any]:
    summary = {
        "element_count": 0,
        "type_counts": {},
        "tagged_element_count": 0,
        "relation_count": 0,
        "multipolygon_relation_count": 0,
        "inner_role_member_count": 0,
        "building_tagged_element_count": 0,
        "building_way_count": 0,
        "building_part_way_count": 0,
        "building_relation_count": 0,
        "building_relation_with_inner_count": 0,
        "building_relation_outer_member_count": 0,
        "standalone_building_way_count": 0,
        "standalone_building_part_way_count": 0,
        "building_surface_geometry_count": 0,
        "highway_way_count": 0,
        "landuse_element_count": 0,
        "water_element_count": 0,
        "source_highway_signal_distribution": {},
        "source_pedestrian_signal_distribution": {},
        "source_vegetation_signal_distribution": {},
        "source_water_signal_distribution": {},
    }

    for path in source_paths:
        if not path.exists():
            continue
        data = _load_json(path)
        elements = data.get("elements")
        if not isinstance(elements, list):
            continue

        relation_managed_building_way_ids: set[int] = set()
        type_counts: Counter[str] = Counter()
        tagged_element_count = 0
        relation_count = 0
        multipolygon_relation_count = 0
        inner_role_member_count = 0
        building_tagged_element_count = 0
        building_way_count = 0
        building_part_way_count = 0
        building_relation_count = 0
        building_relation_with_inner_count = 0
        building_relation_outer_member_count = 0
        standalone_building_way_count = 0
        standalone_building_part_way_count = 0
        highway_way_count = 0
        landuse_element_count = 0
        water_element_count = 0
        source_highway_signal_distribution: Counter[str] = Counter()
        source_pedestrian_signal_distribution: Counter[str] = Counter()
        source_vegetation_signal_distribution: Counter[str] = Counter()
        source_water_signal_distribution: Counter[str] = Counter()

        for element in elements:
            if not isinstance(element, dict) or element.get("type") != "relation":
                continue
            tags = element.get("tags") if isinstance(element.get("tags"), dict) else {}
            members = element.get("members") if isinstance(element.get("members"), list) else []
            if not ("building" in tags or "building:part" in tags):
                continue
            for member in members:
                if not isinstance(member, dict):
                    continue
                if member.get("type") == "way" and member.get("role") in ("outer", ""):
                    member_ref = member.get("ref")
                    if isinstance(member_ref, int):
                        relation_managed_building_way_ids.add(member_ref)
                        building_relation_outer_member_count += 1

        for element in elements:
            if not isinstance(element, dict):
                continue
            element_type = str(element.get("type"))
            type_counts[element_type] += 1
            tags = element.get("tags") if isinstance(element.get("tags"), dict) else {}
            if tags:
                tagged_element_count += 1
                if "building" in tags:
                    building_tagged_element_count += 1
                    if element_type == "way":
                        building_way_count += 1
                        if int(element.get("id", 0)) not in relation_managed_building_way_ids:
                            standalone_building_way_count += 1
                if "building:part" in tags and element_type == "way":
                    building_part_way_count += 1
                    if int(element.get("id", 0)) not in relation_managed_building_way_ids:
                        standalone_building_part_way_count += 1
                if "highway" in tags and element_type == "way":
                    highway_way_count += 1
                    highway = str(tags.get("highway") or "").strip()
                    if highway:
                        source_highway_signal_distribution[f"highway:{highway}"] += 1
                        if highway in PEDESTRIAN_ROAD_KINDS:
                            source_pedestrian_signal_distribution[f"highway:{highway}"] += 1
                sidewalk = str(tags.get("sidewalk") or "").strip()
                if sidewalk:
                    source_pedestrian_signal_distribution[f"sidewalk:{sidewalk}"] += 1
                if "landuse" in tags:
                    landuse_element_count += 1
                    landuse = str(tags.get("landuse") or "").strip()
                    if landuse:
                        source_vegetation_signal_distribution[f"landuse:{landuse}"] += 1
                leisure = str(tags.get("leisure") or "").strip()
                if leisure in {"garden", "nature_reserve", "park", "pitch", "playground", "recreation_ground"}:
                    source_vegetation_signal_distribution[f"leisure:{leisure}"] += 1
                natural = str(tags.get("natural") or "").strip()
                if natural:
                    if natural in {"grassland", "heath", "scrub", "tree", "tree_row", "wetland", "wood"}:
                        source_vegetation_signal_distribution[f"natural:{natural}"] += 1
                if ("natural" in tags and tags.get("natural") == "water") or "water" in tags or "waterway" in tags:
                    water_element_count += 1
                if natural == "water":
                    source_water_signal_distribution["natural:water"] += 1
                waterway = tags.get("waterway")
                if isinstance(waterway, str) and waterway:
                    source_water_signal_distribution[f"waterway:{waterway}"] += 1
                if tags.get("leisure") == "swimming_pool":
                    source_water_signal_distribution["leisure:swimming_pool"] += 1
                if tags.get("amenity") == "fountain":
                    source_water_signal_distribution["amenity:fountain"] += 1
                if tags.get("amenity") == "drinking_water":
                    source_water_signal_distribution["amenity:drinking_water"] += 1
                if "tree" in tags:
                    source_vegetation_signal_distribution["tree:tagged"] += 1
            if element_type == "relation":
                relation_count += 1
                is_building_relation = "building" in tags
                if is_building_relation:
                    building_relation_count += 1
                if tags.get("type") == "multipolygon":
                    multipolygon_relation_count += 1
                members = element.get("members") if isinstance(element.get("members"), list) else []
                relation_has_inner = False
                for member in members:
                    if isinstance(member, dict) and member.get("role") == "inner":
                        inner_role_member_count += 1
                        relation_has_inner = True
                if is_building_relation and relation_has_inner:
                    building_relation_with_inner_count += 1

        summary["element_count"] += len(elements)
        summary["type_counts"] = dict(Counter(summary["type_counts"]) + type_counts)
        summary["tagged_element_count"] += tagged_element_count
        summary["relation_count"] += relation_count
        summary["multipolygon_relation_count"] += multipolygon_relation_count
        summary["inner_role_member_count"] += inner_role_member_count
        summary["building_tagged_element_count"] += building_tagged_element_count
        summary["building_way_count"] += building_way_count
        summary["building_part_way_count"] += building_part_way_count
        summary["building_relation_count"] += building_relation_count
        summary["building_relation_with_inner_count"] += building_relation_with_inner_count
        summary["building_relation_outer_member_count"] += building_relation_outer_member_count
        summary["standalone_building_way_count"] += standalone_building_way_count
        summary["standalone_building_part_way_count"] += standalone_building_part_way_count
        summary["building_surface_geometry_count"] += (
            standalone_building_way_count
            + standalone_building_part_way_count
            + building_relation_outer_member_count
        )
        summary["highway_way_count"] += highway_way_count
        summary["landuse_element_count"] += landuse_element_count
        summary["water_element_count"] += water_element_count
        summary["source_highway_signal_distribution"] = dict(
            (Counter(summary["source_highway_signal_distribution"]) + source_highway_signal_distribution).most_common(40)
        )
        summary["source_pedestrian_signal_distribution"] = dict(
            (Counter(summary["source_pedestrian_signal_distribution"]) + source_pedestrian_signal_distribution).most_common(
                40
            )
        )
        summary["source_vegetation_signal_distribution"] = dict(
            (Counter(summary["source_vegetation_signal_distribution"]) + source_vegetation_signal_distribution).most_common(
                40
            )
        )
        summary["source_water_signal_distribution"] = dict(
            (Counter(summary["source_water_signal_distribution"]) + source_water_signal_distribution).most_common(30)
        )

    return summary


def _build_source_summary(
    source_paths: list[Path],
    *,
    bbox: dict[str, Any],
    bounds_bbox: dict[str, Any] | None = None,
    center_lat: float | None,
    center_lon: float | None,
    meters_per_stud: float,
    focus_x: float | None = None,
    focus_z: float | None = None,
    radius: float | None = None,
) -> tuple[dict[str, Any], dict[str, float | None], list[dict[str, Any]]]:
    source_summary: dict[str, Any] = {}
    full_bounds = _new_bounds()
    bounded_bounds = _new_bounds()
    bounds_bbox = bounds_bbox or bbox
    source_buildings: list[dict[str, Any]] = []
    osm_source_usage_signal_distribution: Counter[str] = Counter()
    osm_source_material_signal_distribution: Counter[str] = Counter()

    def add_projected_point(lat: float, lon: float) -> None:
        if center_lat is None or center_lon is None:
            return
        if not _bbox_contains_latlon(bounds_bbox, lat, lon):
            return
        x, z = _project_latlon_to_studs(lat, lon, center_lat, center_lon, meters_per_stud)
        if not _point_in_zone(x, z, focus_x=focus_x, focus_z=focus_z, radius=radius):
            return
        _extend_bounds(bounded_bounds, x, z)

    def add_projected_point_unbounded(lat: float, lon: float) -> None:
        if center_lat is None or center_lon is None:
            return
        x, z = _project_latlon_to_studs(lat, lon, center_lat, center_lon, meters_per_stud)
        if not _point_in_zone(x, z, focus_x=focus_x, focus_z=focus_z, radius=radius):
            return
        _extend_bounds(full_bounds, x, z)

    def any_coord_in_zone(coords: list[tuple[float, float]]) -> bool:
        if center_lat is None or center_lon is None:
            return False
        for lat, lon in coords:
            if not _bbox_contains_latlon(bbox, lat, lon):
                continue
            x, z = _project_latlon_to_studs(lat, lon, center_lat, center_lon, meters_per_stud)
            if _point_in_zone(x, z, focus_x=focus_x, focus_z=focus_z, radius=radius):
                return True
        return False

    def coords_bbox_intersects_zone(coords: list[tuple[float, float]]) -> bool:
        if focus_x is None or focus_z is None or radius is None:
            return True
        if center_lat is None or center_lon is None or not coords:
            return False
        projected = [
            _project_latlon_to_studs(lat, lon, center_lat, center_lon, meters_per_stud)
            for lat, lon in coords
        ]
        min_x = min(x for x, _ in projected)
        max_x = max(x for x, _ in projected)
        min_z = min(z for _, z in projected)
        max_z = max(z for _, z in projected)
        closest_x = max(min_x, min(focus_x, max_x))
        closest_z = max(min_z, min(focus_z, max_z))
        return _point_in_zone(closest_x, closest_z, focus_x=focus_x, focus_z=focus_z, radius=radius)

    for path in source_paths:
        if not path.exists():
            continue
        data = _load_json(path)
        if "osm3s" in data or isinstance(data.get("elements"), list):
            source_summary["osm"] = _build_osm_summary([path])
            elements = data.get("elements") if isinstance(data.get("elements"), list) else []
            osm_building_geometry_count = 0
            osm_building_footprint_area = 0.0
            osm_road_geometry_count = 0
            osm_building_relation_with_inner_count = 0

            node_coords: dict[int, tuple[float, float]] = {}
            way_coords: dict[int, list[tuple[float, float]]] = {}
            way_tags: dict[int, dict[str, Any]] = {}
            inner_non_building_relation_contexts: dict[int, list[str]] = {}

            def is_relevant_osm_geometry(tags: dict[str, Any]) -> bool:
                return bool(
                    "building" in tags
                    or "building:part" in tags
                    or "highway" in tags
                    or "railway" in tags
                    or "landuse" in tags
                    or "leisure" in tags
                    or "amenity" in tags
                    or "barrier" in tags
                    or tags.get("natural") == "water"
                    or "water" in tags
                    or "waterway" in tags
                    or "tree" in tags
                )

            def is_area_osm_geometry(tags: dict[str, Any]) -> bool:
                return bool(
                    "building" in tags
                    or "building:part" in tags
                    or "landuse" in tags
                    or "leisure" in tags
                    or "amenity" in tags
                    or tags.get("natural") == "water"
                    or "water" in tags
                )

            def centroid_in_bbox(coords: list[tuple[float, float]]) -> bool:
                if not coords:
                    return False
                lat = sum(point[0] for point in coords) / len(coords)
                lon = sum(point[1] for point in coords) / len(coords)
                return _bbox_contains_latlon(bbox, lat, lon)

            def any_coord_in_bbox(coords: list[tuple[float, float]]) -> bool:
                for lat, lon in coords:
                    if _bbox_contains_latlon(bbox, lat, lon):
                        return True
                return False

            def coords_bbox_intersects_bbox(coords: list[tuple[float, float]]) -> bool:
                if not coords:
                    return False
                min_lat = min(lat for lat, _ in coords)
                max_lat = max(lat for lat, _ in coords)
                min_lon = min(lon for _, lon in coords)
                max_lon = max(lon for _, lon in coords)
                return not (
                    max_lat < _safe_float(bbox.get("minLat"))
                    or min_lat > _safe_float(bbox.get("maxLat"))
                    or max_lon < _safe_float(bbox.get("minLon"))
                    or min_lon > _safe_float(bbox.get("maxLon"))
                )

            for element in elements:
                if not isinstance(element, dict):
                    continue
                if element.get("type") != "node":
                    continue
                element_id = element.get("id")
                lat = element.get("lat")
                lon = element.get("lon")
                if isinstance(element_id, int) and isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
                    node_coords[element_id] = (float(lat), float(lon))

            for element in elements:
                if not isinstance(element, dict) or element.get("type") != "way":
                    continue
                element_id = element.get("id")
                node_ids = element.get("nodes") if isinstance(element.get("nodes"), list) else []
                coords: list[tuple[float, float]] = []
                for node_id in node_ids:
                    if isinstance(node_id, int) and node_id in node_coords:
                        coords.append(node_coords[node_id])
                if isinstance(element_id, int) and coords:
                    way_coords[element_id] = coords
                    way_tags[element_id] = element.get("tags") if isinstance(element.get("tags"), dict) else {}

            for element in elements:
                if not isinstance(element, dict) or element.get("type") != "relation":
                    continue
                tags = element.get("tags") if isinstance(element.get("tags"), dict) else {}
                if "building" in tags or "building:part" in tags:
                    continue
                members = element.get("members") if isinstance(element.get("members"), list) else []
                relation_context = str(
                    tags.get("name")
                    or tags.get("leisure")
                    or tags.get("landuse")
                    or tags.get("amenity")
                    or tags.get("natural")
                    or f"relation:{element.get('id')}"
                )
                for member in members:
                    if not isinstance(member, dict):
                        continue
                    if member.get("type") != "way" or member.get("role") != "inner":
                        continue
                    member_ref = member.get("ref")
                    if not isinstance(member_ref, int):
                        continue
                    member_tags = way_tags.get(member_ref) or {}
                    if "building" not in member_tags and "building:part" not in member_tags:
                        continue
                    inner_non_building_relation_contexts.setdefault(member_ref, []).append(relation_context)

            for element in elements:
                if not isinstance(element, dict):
                    continue

                element_type = element.get("type")
                tags = element.get("tags") if isinstance(element.get("tags"), dict) else {}
                if not is_relevant_osm_geometry(tags):
                    continue

                if element_type == "node":
                    element_id = element.get("id")
                    if isinstance(element_id, int) and element_id in node_coords:
                        lat, lon = node_coords[element_id]
                        add_projected_point(lat, lon)
                    continue

                if element_type == "way":
                    coords = way_coords.get(element.get("id"), [])
                    if not coords:
                        continue
                    if ("building" in tags or "building:part" in tags) and coords_bbox_intersects_bbox(coords) and coords_bbox_intersects_zone(coords):
                        osm_building_geometry_count += 1
                        osm_building_footprint_area += _projected_polygon_area(
                            coords,
                            center_lat=center_lat,
                            center_lon=center_lon,
                            meters_per_stud=meters_per_stud,
                        )
                        signal = _classify_osm_building_usage_signal(tags)
                        material_signal = _classify_osm_material_signal(tags)
                        source_name = tags.get("name")
                        source_has_parts = "building:part" in tags
                        source_buildings.append(
                            {
                                "source": "osm",
                                "source_id": f"osm_{element.get('id')}",
                                "source_usage_signal": signal,
                                "source_material_signal": material_signal["family"] if material_signal else None,
                                "source_material_raw": material_signal["raw"] if material_signal else None,
                                "source_material_tag": material_signal["tag"] if material_signal else None,
                                "name": source_name,
                                "name_normalized": _normalize_identity_text(source_name),
                                "has_parts": source_has_parts,
                                "has_inner": False,
                                "inner_of_non_building_relation": bool(
                                    inner_non_building_relation_contexts.get(int(element.get("id")))
                                ),
                                "inner_non_building_relation_contexts": list(
                                    dict.fromkeys(
                                        inner_non_building_relation_contexts.get(int(element.get("id")), [])
                                    )
                                ),
                                "source_identity_signals": _source_identity_signals(
                                    source_usage_signal=signal,
                                    name=source_name,
                                    has_inner=False,
                                    has_parts=source_has_parts,
                                ),
                                "projected": _projected_ring(
                                    coords,
                                    center_lat=center_lat,
                                    center_lon=center_lon,
                                    meters_per_stud=meters_per_stud,
                                ),
                            }
                        )
                        if signal:
                            osm_source_usage_signal_distribution[signal] += 1
                        if material_signal:
                            osm_source_material_signal_distribution[material_signal["family"]] += 1
                    if "highway" in tags and coords_bbox_intersects_bbox(coords) and coords_bbox_intersects_zone(coords):
                        osm_road_geometry_count += 1
                    if is_area_osm_geometry(tags):
                        coord_iterable = coords if coords_bbox_intersects_bbox(coords) else []
                    else:
                        coord_iterable = [
                            (lat, lon) for lat, lon in coords if _bbox_contains_latlon(bbox, lat, lon)
                        ]
                    if coord_iterable:
                        for lat, lon in coord_iterable:
                            add_projected_point_unbounded(lat, lon)
                    continue

                if element_type == "relation":
                    members = element.get("members") if isinstance(element.get("members"), list) else []
                    outer_rings: list[list[tuple[float, float]]] = []
                    inner_rings: list[list[tuple[float, float]]] = []
                    relation_has_parts = False
                    for member in members:
                        if not isinstance(member, dict) or member.get("type") != "way":
                            continue
                        member_ref = member.get("ref")
                        if isinstance(member_ref, int):
                            coords = way_coords.get(member_ref, [])
                            if not coords:
                                continue
                            member_tags = way_tags.get(member_ref) or {}
                            if "building:part" in member_tags:
                                relation_has_parts = True
                            if member.get("role") == "inner":
                                inner_rings.append(coords)
                            else:
                                outer_rings.append(coords)
                    if "building" in tags or "building:part" in tags:
                        relation_counted_for_inner = False
                        for ring in outer_rings:
                            if coords_bbox_intersects_bbox(ring) and coords_bbox_intersects_zone(ring):
                                osm_building_geometry_count += 1
                                ring_area = _projected_polygon_area(
                                    ring,
                                    center_lat=center_lat,
                                    center_lon=center_lon,
                                    meters_per_stud=meters_per_stud,
                                )
                                hole_area = 0.0
                                for inner_ring in inner_rings:
                                    if coords_bbox_intersects_bbox(inner_ring) and coords_bbox_intersects_zone(inner_ring):
                                        relation_counted_for_inner = True
                                        hole_area += _projected_polygon_area(
                                            inner_ring,
                                            center_lat=center_lat,
                                            center_lon=center_lon,
                                            meters_per_stud=meters_per_stud,
                                        )
                                osm_building_footprint_area += max(0.0, ring_area - hole_area)
                                signal = _classify_osm_building_usage_signal(tags)
                                material_signal = _classify_osm_material_signal(tags)
                                source_name = tags.get("name")
                                source_has_inner = bool(inner_rings)
                                source_has_parts = relation_has_parts or ("building:part" in tags)
                                source_buildings.append(
                                    {
                                        "source": "osm",
                                        "source_id": f"osm_{element.get('id')}",
                                        "source_usage_signal": signal,
                                        "source_material_signal": material_signal["family"] if material_signal else None,
                                        "source_material_raw": material_signal["raw"] if material_signal else None,
                                        "source_material_tag": material_signal["tag"] if material_signal else None,
                                        "name": source_name,
                                        "name_normalized": _normalize_identity_text(source_name),
                                        "has_parts": source_has_parts,
                                        "has_inner": source_has_inner,
                                        "inner_of_non_building_relation": False,
                                        "inner_non_building_relation_contexts": [],
                                        "source_identity_signals": _source_identity_signals(
                                            source_usage_signal=signal,
                                            name=source_name,
                                            has_inner=source_has_inner,
                                            has_parts=source_has_parts,
                                        ),
                                        "projected": _projected_ring(
                                            ring,
                                            center_lat=center_lat,
                                            center_lon=center_lon,
                                            meters_per_stud=meters_per_stud,
                                        ),
                                    }
                                )
                                if signal:
                                    osm_source_usage_signal_distribution[signal] += 1
                                if material_signal:
                                    osm_source_material_signal_distribution[material_signal["family"]] += 1
                        if relation_counted_for_inner:
                            osm_building_relation_with_inner_count += 1
                    relation_coords: list[tuple[float, float]] = []
                    if "building" in tags or "building:part" in tags:
                        for ring in outer_rings + inner_rings:
                            relation_coords.extend(ring)
                    elif outer_rings:
                        relation_coords.extend(max(outer_rings, key=len))
                        for ring in inner_rings:
                            relation_coords.extend(ring)
                    if is_area_osm_geometry(tags):
                        coord_iterable = relation_coords if coords_bbox_intersects_bbox(relation_coords) else []
                    else:
                        coord_iterable = [
                            (lat, lon)
                            for lat, lon in relation_coords
                            if _bbox_contains_latlon(bbox, lat, lon)
                        ]
                    if coord_iterable:
                        for lat, lon in coord_iterable:
                            add_projected_point_unbounded(lat, lon)
                    continue
            source_summary["osm_geometry"] = {
                "building_geometry_count": osm_building_geometry_count,
                "building_footprint_area": round(osm_building_footprint_area, 2),
                "road_geometry_count": osm_road_geometry_count,
                "building_relation_with_inner_count": osm_building_relation_with_inner_count,
                "source_usage_signal_distribution": dict(
                    osm_source_usage_signal_distribution.most_common(30)
                ),
                "source_material_signal_distribution": dict(
                    osm_source_material_signal_distribution.most_common(30)
                ),
            }
            continue

        if data.get("type") == "FeatureCollection" and isinstance(data.get("features"), list):
            feature_count = 0
            polygon_count = 0
            polygon_area = 0.0
            class_counts: Counter[str] = Counter()
            for feature in data.get("features") or []:
                if not isinstance(feature, dict):
                    continue
                feature_count += 1
                geometry = feature.get("geometry") if isinstance(feature.get("geometry"), dict) else {}
                geometry_type = geometry.get("type")
                coordinates = geometry.get("coordinates")
                if geometry_type == "Polygon":
                    polygon_count += 1
                properties = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
                source_class = properties.get("class")
                if source_class:
                    class_counts[str(source_class)] += 1

                def walk_coords(value: Any) -> None:
                    if isinstance(value, list) and len(value) >= 2 and all(
                        isinstance(coord, (int, float)) for coord in value[:2]
                    ):
                        lon = float(value[0])
                        lat = float(value[1])
                        add_projected_point(lat, lon)
                        return
                    if isinstance(value, list):
                        for item in value:
                            walk_coords(item)

                walk_coords(coordinates)
                if geometry_type == "Polygon" and isinstance(coordinates, list) and coordinates:
                    outer_ring = coordinates[0]
                    if isinstance(outer_ring, list):
                        latlon_ring = [
                            (float(point[1]), float(point[0]))
                            for point in outer_ring
                            if isinstance(point, list) and len(point) >= 2
                        ]
                        if any_coord_in_zone(latlon_ring):
                            polygon_area += _projected_polygon_area(
                                latlon_ring,
                                center_lat=center_lat,
                                center_lon=center_lon,
                                meters_per_stud=meters_per_stud,
                            )
                            source_buildings.append(
                                {
                                    "source": "overture",
                                    "source_id": _overture_source_id(properties),
                                    "source_usage_signal": _classify_overture_usage_signal(properties),
                                    "source_material_signal": _normalize_source_material_value(
                                        str(properties.get("facade_material") or "")
                                    ),
                                    "source_material_raw": str(properties.get("facade_material") or ""),
                                    "source_material_tag": "facade_material"
                                    if properties.get("facade_material")
                                    else None,
                                    "name": (
                                        (properties.get("names") or {}).get("primary")
                                        if isinstance(properties.get("names"), dict)
                                        else None
                                    ),
                                    "has_parts": properties.get("has_parts") is True,
                                    "projected": _projected_ring(
                                        latlon_ring,
                                        center_lat=center_lat,
                                        center_lon=center_lon,
                                        meters_per_stud=meters_per_stud,
                                    ),
                                }
                            )
                        else:
                            polygon_count -= 1

            source_summary["overture"] = {
                "feature_count": feature_count,
                "building_geometry_count": polygon_count,
                "building_footprint_area": round(polygon_area, 2),
                "class_counts": dict(class_counts.most_common(20)),
            }

    canonical_source_buildings, duplicate_counts = _canonicalize_source_buildings(source_buildings)
    canonical_source_breakdown = Counter(str(item.get("source") or "unknown") for item in canonical_source_buildings)
    canonical_source_area = sum(_polygon_area(item.get("projected", [])) for item in canonical_source_buildings)
    source_summary["canonical_buildings"] = {
        "building_geometry_count": len(canonical_source_buildings),
        "building_footprint_area": round(canonical_source_area, 2),
        "source_breakdown": dict(canonical_source_breakdown),
        "duplicate_overlap_counts": duplicate_counts,
        "raw_building_geometry_count": len(source_buildings),
    }
    source_summary["bounds"] = {
        "full_geometry": full_bounds,
        "in_bbox": bounded_bounds,
    }

    return source_summary, full_bounds, canonical_source_buildings


def _build_manifest_bounds(
    chunks: list[dict[str, Any]],
    *,
    focus_x: float | None = None,
    focus_z: float | None = None,
    radius: float | None = None,
) -> dict[str, float | None]:
    bounds = _new_bounds()

    def add_point(origin: dict[str, Any], point: dict[str, Any]) -> None:
        world_x = _safe_float(origin.get("x")) + _safe_float(point.get("x"))
        world_z = _safe_float(origin.get("z")) + _safe_float(point.get("z"))
        if not _point_in_zone(world_x, world_z, focus_x=focus_x, focus_z=focus_z, radius=radius):
            return
        _extend_bounds(bounds, world_x, world_z)

    for chunk in chunks:
        origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
        for road in chunk.get("roads", []) or []:
            for point in road.get("points", []) or []:
                if isinstance(point, dict):
                    add_point(origin, point)
        for rail in chunk.get("rails", []) or []:
            for point in rail.get("points", []) or []:
                if isinstance(point, dict):
                    add_point(origin, point)
        for building in chunk.get("buildings", []) or []:
            for point in building.get("footprint", []) or []:
                if isinstance(point, dict):
                    add_point(origin, point)
            for hole in building.get("holes", []) or []:
                if isinstance(hole, list):
                    for point in hole:
                        if isinstance(point, dict):
                            add_point(origin, point)
        for water in chunk.get("water", []) or []:
            feature_type = water.get("type")
            if feature_type == "polygon":
                for point in water.get("footprint", []) or []:
                    if isinstance(point, dict):
                        add_point(origin, point)
                for hole in water.get("holes", []) or []:
                    if isinstance(hole, list):
                        for point in hole:
                            if isinstance(point, dict):
                                add_point(origin, point)
            else:
                for point in water.get("points", []) or []:
                    if isinstance(point, dict):
                        add_point(origin, point)
        for landuse in chunk.get("landuse", []) or []:
            for point in landuse.get("footprint", []) or []:
                if isinstance(point, dict):
                    add_point(origin, point)
        for barrier in chunk.get("barriers", []) or []:
            for point in barrier.get("points", []) or []:
                if isinstance(point, dict):
                    add_point(origin, point)
        for prop in chunk.get("props", []) or []:
            position = prop.get("position")
            if isinstance(position, dict):
                add_point(origin, position)

    return bounds


def _build_height_alignment(chunks: list[dict[str, Any]], meters_per_stud: float) -> dict[str, float]:
    ratios: list[float] = []
    for chunk in chunks:
        for building in chunk.get("buildings", []) or []:
            height = building.get("height")
            height_m = building.get("height_m")
            if not isinstance(height, (int, float)) or not isinstance(height_m, (int, float)) or height_m <= 0:
                continue
            expected_height = height_m / meters_per_stud
            ratios.append(_alignment_ratio(float(height), expected_height))

    if not ratios:
        return {
            "building_height_alignment_ratio": 0.0,
            "count": 0.0,
            "median": 0.0,
            "p95": 0.0,
        }

    ordered = sorted(ratios)
    return {
        "building_height_alignment_ratio": round(sum(ratios) / len(ratios), 4),
        "count": float(len(ratios)),
        "median": round(ordered[len(ordered) // 2], 4),
        "p95": round(_percentile(ordered, 0.95), 4),
    }


def _add_finding(
    findings: list[dict[str, Any]],
    *,
    severity: str,
    code: str,
    message: str,
    metric: str,
    value: Any,
    threshold: Any,
) -> None:
    findings.append(
        {
            "severity": severity,
            "code": code,
            "message": message,
            "metric": metric,
            "value": value,
            "threshold": threshold,
        }
    )


def build_report(
    manifest_path: Path,
    source_paths: list[Path] | None = None,
    *,
    focus_x: float | None = None,
    focus_z: float | None = None,
    radius: float | None = None,
) -> dict[str, Any]:
    manifest_path = manifest_path.resolve()
    source_paths = [path.resolve() for path in (source_paths or [])]
    manifest = _load_json(manifest_path)
    meta = manifest.get("meta") if isinstance(manifest.get("meta"), dict) else {}
    chunks = manifest.get("chunks") if isinstance(manifest.get("chunks"), list) else []
    location_meta = _format_bbox(meta)
    source_bbox = _expanded_bbox(location_meta["bbox"]) if location_meta.get("bbox") else {}
    meters_per_stud = _safe_float(meta.get("metersPerStud"), 1.0)

    roof_distribution: Counter[str | None] = Counter()
    roof_distribution_by_usage: dict[str, Counter[str]] = {}
    roof_distribution_by_source_usage: dict[str, Counter[str]] = {}
    roof_distribution_by_source_type: dict[str, Counter[str]] = {}
    usage_distribution: Counter[str | None] = Counter()
    building_material_distribution: Counter[str | None] = Counter()
    road_kind_distribution: Counter[str | None] = Counter()
    road_subkind_distribution: Counter[str | None] = Counter()
    pedestrian_way_distribution: Counter[str | None] = Counter()
    road_surface_distribution: Counter[str | None] = Counter()
    terrain_material_distribution: Counter[str | None] = Counter()
    landuse_distribution: Counter[str | None] = Counter()
    prop_kind_distribution: Counter[str | None] = Counter()
    tree_species_distribution: Counter[str | None] = Counter()
    vegetation_signal_distribution: Counter[str | None] = Counter()
    water_kind_distribution: Counter[str | None] = Counter()
    water_kind_distribution_by_type: dict[str, Counter[str]] = {}
    water_kind_distribution_by_source_type: dict[str, Counter[str]] = {}

    building_count = 0
    manifest_osm_building_count = 0
    manifest_overture_building_count = 0
    manifest_unknown_building_count = 0
    building_hole_count = 0
    large_building_candidate_count = 0
    generic_usage_count = 0
    empty_chunk_count = 0
    roads_count = 0
    roads_missing_surface_count = 0
    roads_default_width_count = 0
    unique_road_ids: set[str] = set()
    unique_building_ids: set[str] = set()
    chunks_with_terrain = 0
    terrain_single_material_chunk_count = 0
    building_heights: list[float] = []
    building_areas: list[float] = []
    suspicious_material_assignments: list[dict[str, Any]] = []
    suspicious_material_assignment_by_signal: Counter[str] = Counter()
    glass_material_by_usage: Counter[str | None] = Counter()
    manifest_building_records: list[dict[str, Any]] = []
    global_manifest_record_ids: set[str] = set()
    chunk_rows: list[dict[str, Any]] = []
    filtered_chunk_count = 0

    def point_dicts_in_zone(origin: dict[str, Any], points: list[dict[str, Any]]) -> bool:
        if focus_x is None or focus_z is None or radius is None:
            return True
        world_points: list[tuple[float, float]] = []
        for point in points:
            if not isinstance(point, dict):
                continue
            world_x = _safe_float(origin.get("x")) + _safe_float(point.get("x"))
            world_z = _safe_float(origin.get("z")) + _safe_float(point.get("z"))
            world_points.append((world_x, world_z))
            if _point_in_zone(world_x, world_z, focus_x=focus_x, focus_z=focus_z, radius=radius):
                return True
        if not world_points:
            return False
        min_x = min(x for x, _ in world_points)
        max_x = max(x for x, _ in world_points)
        min_z = min(z for _, z in world_points)
        max_z = max(z for _, z in world_points)
        closest_x = max(min_x, min(focus_x, max_x))
        closest_z = max(min_z, min(focus_z, max_z))
        return _point_in_zone(closest_x, closest_z, focus_x=focus_x, focus_z=focus_z, radius=radius)

    def chunk_intersects_zone(chunk: dict[str, Any]) -> bool:
        if focus_x is None or focus_z is None or radius is None:
            return True
        origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
        chunk_size = _safe_float(meta.get("chunkSizeStuds"), 256.0)
        min_x = _safe_float(origin.get("x"))
        min_z = _safe_float(origin.get("z"))
        max_x = min_x + chunk_size
        max_z = min_z + chunk_size
        closest_x = max(min_x, min(focus_x, max_x))
        closest_z = max(min_z, min(focus_z, max_z))
        return _point_in_zone(closest_x, closest_z, focus_x=focus_x, focus_z=focus_z, radius=radius)

    for chunk in chunks:
        for building in chunk.get("buildings", []) or []:
            building_id = str(building.get("id") or "")
            if building_id:
                global_manifest_record_ids.add(building_id)

    for chunk in chunks:
        if not chunk_intersects_zone(chunk):
            continue
        filtered_chunk_count += 1
        chunk_id = str(chunk.get("id"))
        chunk_building_count = 0
        chunk_road_count = 0
        chunk_landuse_count = 0
        chunk_water_count = 0
        chunk_building_area = 0.0
        chunk_has_monotone_terrain = False

        feature_total = sum(
            len(chunk.get(layer, []))
            for layer in ("roads", "rails", "buildings", "water", "props", "landuse", "barriers")
        )
        if feature_total == 0:
            empty_chunk_count += 1

        terrain = chunk.get("terrain")
        if isinstance(terrain, dict):
            chunks_with_terrain += 1
            materials = terrain.get("materials")
            unique_materials: set[str] = set()
            if isinstance(materials, list) and materials:
                unique_materials = {str(material) for material in materials if material}
            elif terrain.get("material"):
                unique_materials = {str(terrain["material"])}

            if len(unique_materials) == 1 and unique_materials:
                terrain_single_material_chunk_count += 1
                chunk_has_monotone_terrain = True
            terrain_material_distribution.update(unique_materials)

        for road in chunk.get("roads", []) or []:
            origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
            if not point_dicts_in_zone(origin, road.get("points", []) or []):
                continue
            roads_count += 1
            chunk_road_count += 1
            road_id = str(road.get("id"))
            if road_id:
                unique_road_ids.add(road_id)
            road_kind = str(road.get("kind") or "unknown")
            road_subkind = str(road.get("subkind") or "unknown")
            road_kind_distribution[road_kind] += 1
            road_subkind_distribution[road_subkind] += 1
            if road_kind in PEDESTRIAN_ROAD_KINDS:
                pedestrian_way_distribution[road_kind] += 1
            elif road_subkind in {"crossing", "sidewalk", "trail"}:
                pedestrian_way_distribution[road_subkind] += 1
            road_surface = road.get("surface")
            road_surface_distribution[str(road_surface)] += 1
            if road_surface in (None, "", "None"):
                roads_missing_surface_count += 1
            if road.get("widthStuds") in (8, 10):
                roads_default_width_count += 1

        for building in chunk.get("buildings", []) or []:
            origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
            if not point_dicts_in_zone(origin, building.get("footprint", []) or []):
                continue
            building_count += 1
            building_id = str(building.get("id"))
            if building_id:
                unique_building_ids.add(building_id)
            if building_id.startswith("ov_"):
                manifest_overture_building_count += 1
            elif building_id.startswith("osm_"):
                manifest_osm_building_count += 1
            else:
                manifest_unknown_building_count += 1
            chunk_building_count += 1
            usage = building.get("usage")
            usage_distribution[str(usage)] += 1
            if usage in (None, "", "yes", "building", "default"):
                generic_usage_count += 1

            roof_distribution[str(building.get("roof"))] += 1
            _increment_nested_distribution(
                roof_distribution_by_usage,
                building.get("usage"),
                building.get("roof"),
            )
            material = str(building.get("material"))
            building_material_distribution[material] += 1
            height = _safe_float(building.get("height"))
            if material == "Glass":
                glass_material_by_usage[str(usage)] += 1
            building_name = str(building.get("name") or "")
            signals = _suspicious_material_signals(usage=usage, name=building_name, material=material)
            if signals:
                suspicious_material_assignment_by_signal.update(signals)
                suspicious_material_assignments.append(
                    {
                        "id": building_id,
                        "name": building_name,
                        "usage": str(usage),
                        "material": material,
                        "roof": str(building.get("roof")),
                        "height": height,
                        "chunk_id": chunk_id,
                        "signals": signals,
                        "reason": ", ".join(signals),
                    }
                )
            manifest_building_records.append(
                {
                    "id": building_id,
                    "name": str(building.get("name") or ""),
                    "name_normalized": _normalize_identity_text(building.get("name")),
                    "usage": str(usage),
                    "material": material,
                    "roof": str(building.get("roof")),
                    "chunk_id": chunk_id,
                    "hole_count": len(building.get("holes", []) or []),
                    "projected": [
                        {
                            "x": _safe_float(origin.get("x")) + _safe_float(point.get("x")),
                            "z": _safe_float(origin.get("z")) + _safe_float(point.get("z")),
                        }
                        for point in (building.get("footprint", []) or [])
                        if isinstance(point, dict)
                    ],
                }
            )
            area = _polygon_area(building.get("footprint", []) or [])
            building_heights.append(height)
            building_areas.append(area)
            chunk_building_area += area

            holes = building.get("holes")
            if isinstance(holes, list) and holes:
                building_hole_count += 1

            if area >= LARGE_BUILDING_AREA_THRESHOLD:
                large_building_candidate_count += 1

        for landuse in chunk.get("landuse", []) or []:
            origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
            if not point_dicts_in_zone(origin, landuse.get("footprint", []) or []):
                continue
            chunk_landuse_count += 1
            landuse_kind = str(landuse.get("kind") or "unknown")
            landuse_distribution[landuse_kind] += 1
            if landuse_kind in VEGETATION_LANDUSE_KINDS:
                vegetation_signal_distribution[landuse_kind] += 1

        for prop in chunk.get("props", []) or []:
            origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
            position = prop.get("position") if isinstance(prop.get("position"), dict) else {}
            if not point_dicts_in_zone(origin, [position]):
                continue
            prop_kind = str(prop.get("kind") or "unknown")
            prop_kind_distribution[prop_kind] += 1
            if prop_kind in {"tree", "tree_row", "hedge", "shrub", "fountain"}:
                vegetation_signal_distribution[prop_kind] += 1
            species = str(prop.get("species") or "").strip()
            if prop_kind == "tree" and species:
                tree_species_distribution[species] += 1

        for water in chunk.get("water", []) or []:
            origin = chunk.get("originStuds") if isinstance(chunk.get("originStuds"), dict) else {}
            points = water.get("footprint") if water.get("type") == "polygon" else water.get("points")
            if not point_dicts_in_zone(origin, points or []):
                continue
            chunk_water_count += 1
            water_kind = str(water.get("kind"))
            water_kind_distribution[water_kind] += 1
            _increment_nested_distribution(
                water_kind_distribution_by_type,
                water.get("type") or "ribbon",
                water_kind,
            )
            water_id = str(water.get("id") or "")
            source_type = "unknown"
            if water_id.startswith("osm_"):
                source_type = "osm"
            elif water_id.startswith("ov_"):
                source_type = "overture"
            _increment_nested_distribution(water_kind_distribution_by_source_type, source_type, water_kind)

        chunk_rows.append(
            {
                "chunk_id": chunk_id,
                "feature_count": feature_total,
                "building_count": chunk_building_count,
                "road_count": chunk_road_count,
                "landuse_count": chunk_landuse_count,
                "water_count": chunk_water_count,
                "building_area": round(chunk_building_area, 2),
                "terrain_material_monotone": chunk_has_monotone_terrain,
            }
        )

    flat_roof_ratio = _ratio(roof_distribution.get("flat", 0), building_count)
    generic_usage_ratio = _ratio(generic_usage_count, building_count)
    dominant_building_material_ratio = _ratio(
        building_material_distribution.most_common(1)[0][1] if building_material_distribution else 0,
        building_count,
    )
    roads_missing_surface_ratio = _ratio(roads_missing_surface_count, roads_count)
    roads_default_width_ratio = _ratio(roads_default_width_count, roads_count)
    terrain_single_material_ratio = _ratio(terrain_single_material_chunk_count, chunks_with_terrain)
    roof_diversity_score = _normalized_entropy(roof_distribution)
    usage_diversity_score = _normalized_entropy(usage_distribution)
    material_diversity_score = _normalized_entropy(building_material_distribution)
    road_surface_diversity_score = _normalized_entropy(road_surface_distribution)
    terrain_material_diversity_score = _normalized_entropy(terrain_material_distribution)
    osm_summary = _build_osm_summary(source_paths)
    source_summary, source_bounds, canonical_source_buildings = _build_source_summary(
        source_paths,
        bbox=source_bbox,
        bounds_bbox=location_meta["bbox"],
        center_lat=location_meta["center_lat"],
        center_lon=location_meta["center_lon"],
        meters_per_stud=meters_per_stud,
        focus_x=focus_x,
        focus_z=focus_z,
        radius=radius,
    )
    source_bounds_for_scale = (
        (source_summary.get("bounds") or {}).get("in_bbox")
        if isinstance(source_summary.get("bounds"), dict)
        else None
    ) or source_bounds
    manifest_bounds = _build_manifest_bounds(chunks, focus_x=focus_x, focus_z=focus_z, radius=radius)
    manifest_bounds_metrics = _bounds_metrics(manifest_bounds)
    source_bounds_metrics = _bounds_metrics(source_bounds_for_scale)
    source_full_bounds_metrics = _bounds_metrics(source_bounds)
    height_alignment = _build_height_alignment(chunks, meters_per_stud)

    raw_source_building_geometry_count = (
        int((source_summary.get("osm_geometry") or {}).get("building_geometry_count", 0))
        + int((source_summary.get("overture") or {}).get("building_geometry_count", 0))
    )
    canonical_source_building_geometry_count = int(
        (source_summary.get("canonical_buildings") or {}).get(
            "building_geometry_count", raw_source_building_geometry_count
        )
    )
    source_building_relations_with_inner = int(
        (source_summary.get("osm_geometry") or {}).get(
            "building_relation_with_inner_count",
            osm_summary.get("building_relation_with_inner_count", 0),
        )
    )
    source_osm_building_geometry_count = int((source_summary.get("osm_geometry") or {}).get("building_geometry_count", 0))
    source_overture_building_geometry_count = int((source_summary.get("overture") or {}).get("building_geometry_count", 0))
    source_road_geometry_count = int((source_summary.get("osm_geometry") or {}).get("road_geometry_count", 0))
    raw_source_building_footprint_area = (
        _safe_float((source_summary.get("osm_geometry") or {}).get("building_footprint_area"))
        + _safe_float((source_summary.get("overture") or {}).get("building_footprint_area"))
    )
    source_building_footprint_area = _safe_float(
        (source_summary.get("canonical_buildings") or {}).get(
            "building_footprint_area", raw_source_building_footprint_area
        )
    )
    canonical_source_breakdown = (source_summary.get("canonical_buildings") or {}).get("source_breakdown") or {}
    source_duplicate_overlap_counts = (source_summary.get("canonical_buildings") or {}).get(
        "duplicate_overlap_counts"
    ) or {}
    osm_source_usage_signal_distribution = (
        (source_summary.get("osm_geometry") or {}).get("source_usage_signal_distribution") or {}
    )
    canonical_osm_source_records = {
        str(item.get("source_id")): item
        for item in canonical_source_buildings
        if item.get("source") == "osm" and item.get("source_id")
    }
    osm_source_material_signal_distribution = (
        (source_summary.get("osm_geometry") or {}).get("source_material_signal_distribution") or {}
    )
    source_usage_confusion_raw: Counter[str] = Counter()
    source_usage_confusion: Counter[str] = Counter()
    source_usage_mismatches: list[dict[str, Any]] = []
    source_usage_refinements: list[dict[str, Any]] = []
    source_material_confusion: Counter[str] = Counter()
    source_material_mismatches: list[dict[str, Any]] = []
    source_identity_loss_records: list[dict[str, Any]] = []
    source_identity_transform_records: list[dict[str, Any]] = []
    inner_non_building_relation_identity_loss_records: list[dict[str, Any]] = []
    strong_source_building_count = 0
    seen_strong_identity_keys: set[str] = set()
    seen_loss_identity_keys: set[str] = set()
    seen_transform_identity_keys: set[str] = set()
    seen_inner_non_building_relation_identity_loss_keys: set[str] = set()
    source_material_comparable_count = 0
    source_material_match_count = 0
    manifest_records_by_id = {str(record.get("id")): record for record in manifest_building_records if record.get("id")}
    manifest_spatial_index = _build_record_spatial_index(manifest_building_records)
    for building_record in manifest_building_records:
        source_record = canonical_osm_source_records.get(building_record["id"])
        if not source_record:
            continue
        _increment_nested_distribution(
            roof_distribution_by_source_usage,
            source_record.get("source_usage_signal"),
            building_record.get("roof"),
        )
        _increment_nested_distribution(
            roof_distribution_by_source_type,
            source_record.get("source"),
            building_record.get("roof"),
        )
        source_signal = str(source_record.get("source_usage_signal") or "")
        if not source_signal:
            continue
        manifest_usage = str(building_record.get("usage") or "")
        source_usage_confusion_raw[f"{source_signal}->{manifest_usage}"] += 1
        if source_signal in {"building", "yes"}:
            continue
        row = {
            "id": building_record["id"],
            "name": building_record["name"] or source_record.get("name") or "",
            "source_usage_signal": source_signal,
            "manifest_usage": manifest_usage,
            "material": building_record["material"],
            "roof": building_record["roof"],
            "chunk_id": building_record["chunk_id"],
        }
        if _is_benign_usage_refinement(source_signal, manifest_usage):
            if source_signal != manifest_usage:
                source_usage_refinements.append(row)
            continue
        source_usage_confusion[f"{source_signal}->{manifest_usage}"] += 1
        source_usage_mismatches.append(row)
    for building_record in manifest_building_records:
        source_record = canonical_osm_source_records.get(building_record["id"])
        if not source_record:
            continue
        source_material_signal = str(source_record.get("source_material_signal") or "")
        if not source_material_signal:
            continue
        manifest_material_signal = _normalize_manifest_material_value(building_record["material"])
        if not manifest_material_signal:
            continue
        source_material_comparable_count += 1
        if source_material_signal == manifest_material_signal:
            source_material_match_count += 1
            continue
        source_material_confusion[f"{source_material_signal}->{manifest_material_signal}"] += 1
        source_material_mismatches.append(
            {
                "id": building_record["id"],
                "name": building_record["name"] or source_record.get("name") or "",
                "source_material_signal": source_material_signal,
                "source_material_raw": str(source_record.get("source_material_raw") or ""),
                "source_material_tag": str(source_record.get("source_material_tag") or ""),
                "manifest_material": building_record["material"],
                "manifest_material_signal": manifest_material_signal,
                "manifest_usage": building_record["usage"],
                "roof": building_record["roof"],
                "chunk_id": building_record["chunk_id"],
            }
        )
    for building_record in manifest_building_records:
        source_record = canonical_osm_source_records.get(building_record["id"])
        if source_record is None and str(building_record.get("id") or "").startswith("ov_"):
            source_record = next(
                (
                    item
                    for item in canonical_source_buildings
                    if item.get("source") == "overture" and str(item.get("source_id") or "") == building_record["id"]
                ),
                None,
            )
        if source_record is None:
            _increment_nested_distribution(
                roof_distribution_by_source_type,
                "unknown",
                building_record.get("roof"),
            )
            continue
        if source_record.get("source") != "osm":
            _increment_nested_distribution(
                roof_distribution_by_source_usage,
                source_record.get("source_usage_signal"),
                building_record.get("roof"),
            )
            _increment_nested_distribution(
                roof_distribution_by_source_type,
                source_record.get("source"),
                building_record.get("roof"),
            )
    for source_record in canonical_source_buildings:
        reasons = _strong_source_identity_reasons(source_record)
        if not reasons:
            continue
        identity_key = _identity_record_key(source_record)
        if identity_key and identity_key in seen_strong_identity_keys:
            continue
        if identity_key:
            seen_strong_identity_keys.add(identity_key)
        strong_source_building_count += 1
        source_id = str(source_record.get("source_id") or "")
        if source_id and source_id in global_manifest_record_ids:
            continue
        projected = source_record.get("projected")
        if not isinstance(projected, list) or len(projected) < 3:
            continue
        overlapping_records = _find_overlapping_records(projected, manifest_spatial_index)
        row = {
            "source_id": source_id,
            "name": str(source_record.get("name") or ""),
            "source": str(source_record.get("source") or ""),
            "source_usage_signal": str(source_record.get("source_usage_signal") or ""),
            "source_material_signal": str(source_record.get("source_material_signal") or ""),
            "identity_reasons": reasons,
        }
        if overlapping_records:
            if identity_key and identity_key in seen_transform_identity_keys:
                continue
            if identity_key:
                seen_transform_identity_keys.add(identity_key)
            source_identity_transform_records.append(
                {
                    **row,
                    "manifest_matches": [
                        {
                            "id": str(record.get("id") or ""),
                            "name": str(record.get("name") or ""),
                            "usage": str(record.get("usage") or ""),
                            "material": str(record.get("material") or ""),
                            "chunk_id": str(record.get("chunk_id") or ""),
                        }
                        for record in overlapping_records[:3]
                    ],
                }
            )
        else:
            if identity_key and identity_key in seen_loss_identity_keys:
                continue
            if identity_key:
                seen_loss_identity_keys.add(identity_key)
            source_identity_loss_records.append(row)
            if source_record.get("inner_of_non_building_relation"):
                if identity_key and identity_key in seen_inner_non_building_relation_identity_loss_keys:
                    continue
                if identity_key:
                    seen_inner_non_building_relation_identity_loss_keys.add(identity_key)
                inner_non_building_relation_identity_loss_records.append(
                    {
                        **row,
                        "relation_contexts": list(
                            dict.fromkeys(source_record.get("inner_non_building_relation_contexts") or [])
                        ),
                    }
                )
    manifest_building_footprint_area = sum(building_areas)
    manifest_unique_building_geometry_count = len(unique_building_ids)
    manifest_unique_road_geometry_count = len(unique_road_ids)
    manifest_to_source_building_ratio = _ratio(building_count, canonical_source_building_geometry_count)
    unique_manifest_to_source_building_ratio = _ratio(
        manifest_unique_building_geometry_count, canonical_source_building_geometry_count
    )
    manifest_to_source_road_ratio = _ratio(manifest_unique_road_geometry_count, source_road_geometry_count)
    geometry_alignment_ratio = _alignment_ratio(building_count, canonical_source_building_geometry_count)
    building_footprint_area_alignment_ratio = _alignment_ratio(
        manifest_building_footprint_area, source_building_footprint_area
    )
    topology_alignment_ratio = _ratio(
        building_hole_count,
        source_building_relations_with_inner,
    )
    source_material_alignment_ratio = _ratio(source_material_match_count, source_material_comparable_count)
    source_identity_alignment_ratio = _ratio(
        strong_source_building_count - len(source_identity_loss_records) - len(source_identity_transform_records),
        strong_source_building_count,
    )
    source_identity_loss_by_usage = Counter(
        str(record.get("source_usage_signal") or "unknown") for record in source_identity_loss_records
    )
    source_identity_transform_by_usage = Counter(
        str(record.get("source_usage_signal") or "unknown") for record in source_identity_transform_records
    )
    source_identity_loss_by_reason = Counter(
        str(reason)
        for record in source_identity_loss_records
        for reason in (record.get("identity_reasons") or [])
    )
    source_identity_transform_by_reason = Counter(
        str(reason)
        for record in source_identity_transform_records
        for reason in (record.get("identity_reasons") or [])
    )
    source_usage_diagnostics, source_usage_diagnostics_top_mismatch_types = _build_source_usage_diagnostics(
        canonical_source_buildings,
        source_usage_mismatches,
        source_usage_refinements,
        source_material_mismatches,
        source_identity_loss_records,
        source_identity_transform_records,
    )
    inner_non_building_relation_identity_loss_by_context = Counter(
        str(context)
        for record in inner_non_building_relation_identity_loss_records
        for context in (record.get("relation_contexts") or [])
    )
    scale_alignment = {
        "manifest_bounds": manifest_bounds_metrics,
        "source_bounds": source_bounds_metrics,
        "source_full_geometry_bounds": source_full_bounds_metrics,
        "world_span_x_alignment_ratio": round(
            _alignment_ratio(manifest_bounds_metrics["span_x"], source_bounds_metrics["span_x"]),
            4,
        ),
        "world_span_z_alignment_ratio": round(
            _alignment_ratio(manifest_bounds_metrics["span_z"], source_bounds_metrics["span_z"]),
            4,
        ),
        **height_alignment,
    }
    scale_alignment["world_alignment_ratio"] = round(
        min(
            scale_alignment["world_span_x_alignment_ratio"],
            scale_alignment["world_span_z_alignment_ratio"],
        ),
        4,
    )
    quality_scores = {
        "building_semantics": round(
            _clamp_score(
                100.0
                * (
                    (1.0 - generic_usage_ratio) * 0.30
                    + roof_diversity_score * 0.20
                    + material_diversity_score * 0.15
                    + geometry_alignment_ratio * 0.20
                    + min(topology_alignment_ratio, 1.0) * 0.10
                    + building_footprint_area_alignment_ratio * 0.05
                )
            ),
            2,
        ),
        "terrain_semantics": round(
            _clamp_score(100.0 * ((1.0 - terrain_single_material_ratio) * 0.7 + terrain_material_diversity_score * 0.3)),
            2,
        ),
        "road_semantics": round(
            _clamp_score(100.0 * ((1.0 - roads_missing_surface_ratio) * 0.7 + road_surface_diversity_score * 0.3)),
            2,
        ),
        "source_alignment": round(
            _clamp_score(
                100.0
                * (
                    (geometry_alignment_ratio * 0.45)
                    + (min(topology_alignment_ratio, 1.0) * 0.25)
                    + (building_footprint_area_alignment_ratio * 0.20)
                    + (_alignment_ratio(roads_count, source_road_geometry_count) * 0.10)
                )
            ),
            2,
        ),
        "scale_alignment": round(
            _clamp_score(
                100.0
                * (
                    scale_alignment["world_alignment_ratio"] * 0.60
                    + scale_alignment["building_height_alignment_ratio"] * 0.40
                )
            ),
            2,
        ),
    }
    quality_scores["overall"] = round(
        (quality_scores["building_semantics"] * 0.45)
        + (quality_scores["terrain_semantics"] * 0.15)
        + (quality_scores["road_semantics"] * 0.15)
        + (quality_scores["source_alignment"] * 0.15)
        + (quality_scores["scale_alignment"] * 0.10),
        2,
    )

    summary = {
        "chunk_count": filtered_chunk_count,
        "empty_chunk_count": empty_chunk_count,
        "building_count": building_count,
        "building_hole_count": building_hole_count,
        "large_building_candidate_count": large_building_candidate_count,
        "generic_usage_ratio": generic_usage_ratio,
        "flat_roof_ratio": flat_roof_ratio,
        "roof_distribution": dict(roof_distribution.most_common(20)),
        "roof_distribution_by_usage": {
            key: dict(counter.most_common(20)) for key, counter in sorted(roof_distribution_by_usage.items())
        },
        "roof_distribution_by_source_usage": {
            key: dict(counter.most_common(20))
            for key, counter in sorted(roof_distribution_by_source_usage.items())
        },
        "roof_distribution_by_source_type": {
            key: dict(counter.most_common(20))
            for key, counter in sorted(roof_distribution_by_source_type.items())
        },
        "roof_diversity_score": roof_diversity_score,
        "usage_diversity_score": usage_diversity_score,
        "usage_distribution": dict(usage_distribution.most_common(20)),
        "source_usage_signal_distribution": dict(
            Counter(osm_source_usage_signal_distribution).most_common(30)
        ),
        "source_material_signal_distribution": dict(
            Counter(osm_source_material_signal_distribution).most_common(30)
        ),
        "source_usage_confusion_raw": dict(source_usage_confusion_raw.most_common(30)),
        "source_usage_confusion": dict(source_usage_confusion.most_common(30)),
        "source_usage_mismatch_count": len(source_usage_mismatches),
        "source_usage_mismatches": source_usage_mismatches[:HOTSPOT_LIMIT],
        "source_usage_refinement_count": len(source_usage_refinements),
        "source_usage_refinements": source_usage_refinements[:HOTSPOT_LIMIT],
        "source_usage_diagnostics": source_usage_diagnostics,
        "source_usage_diagnostics_top_mismatch_types": source_usage_diagnostics_top_mismatch_types,
        "source_material_confusion": dict(source_material_confusion.most_common(30)),
        "source_material_mismatch_count": len(source_material_mismatches),
        "source_material_mismatches": source_material_mismatches[:HOTSPOT_LIMIT],
        "source_material_comparable_count": source_material_comparable_count,
        "source_material_alignment_ratio": round(source_material_alignment_ratio, 4),
        "strong_source_building_count": strong_source_building_count,
        "source_identity_loss_count": len(source_identity_loss_records),
        "source_identity_loss_records": source_identity_loss_records[:HOTSPOT_LIMIT],
        "source_identity_loss_by_usage": dict(source_identity_loss_by_usage.most_common(20)),
        "source_identity_loss_by_reason": dict(source_identity_loss_by_reason.most_common(20)),
        "source_identity_transform_count": len(source_identity_transform_records),
        "source_identity_transform_records": source_identity_transform_records[:HOTSPOT_LIMIT],
        "source_identity_transform_by_usage": dict(source_identity_transform_by_usage.most_common(20)),
        "source_identity_transform_by_reason": dict(source_identity_transform_by_reason.most_common(20)),
        "source_identity_alignment_ratio": round(source_identity_alignment_ratio, 4),
        "inner_non_building_relation_identity_loss_count": len(inner_non_building_relation_identity_loss_records),
        "inner_non_building_relation_identity_loss_records": inner_non_building_relation_identity_loss_records[
            :HOTSPOT_LIMIT
        ],
        "inner_non_building_relation_identity_loss_by_context": dict(
            inner_non_building_relation_identity_loss_by_context.most_common(20)
        ),
        "building_material_distribution": dict(building_material_distribution.most_common(20)),
        "glass_material_by_usage": dict(glass_material_by_usage.most_common(20)),
        "suspicious_material_assignment_count": len(suspicious_material_assignments),
        "suspicious_material_assignment_by_signal": dict(
            suspicious_material_assignment_by_signal.most_common(20)
        ),
        "suspicious_material_assignments": suspicious_material_assignments[:HOTSPOT_LIMIT],
        "building_material_diversity_score": material_diversity_score,
        "dominant_building_material_ratio": dominant_building_material_ratio,
        "roads_count": roads_count,
        "roads_missing_surface_ratio": roads_missing_surface_ratio,
        "roads_default_width_ratio": roads_default_width_ratio,
        "road_kind_distribution": dict(road_kind_distribution.most_common(20)),
        "road_subkind_distribution": dict(road_subkind_distribution.most_common(20)),
        "pedestrian_way_distribution": dict(pedestrian_way_distribution.most_common(20)),
        "road_surface_distribution": dict(road_surface_distribution.most_common(20)),
        "road_surface_diversity_score": road_surface_diversity_score,
        "terrain_chunk_count": chunks_with_terrain,
        "terrain_single_material_chunk_count": terrain_single_material_chunk_count,
        "terrain_single_material_ratio": terrain_single_material_ratio,
        "terrain_material_distribution": dict(terrain_material_distribution.most_common(20)),
        "terrain_material_diversity_score": terrain_material_diversity_score,
        "landuse_distribution": dict(landuse_distribution.most_common(20)),
        "prop_kind_distribution": dict(prop_kind_distribution.most_common(20)),
        "tree_species_distribution": dict(tree_species_distribution.most_common(20)),
        "vegetation_signal_distribution": dict(vegetation_signal_distribution.most_common(20)),
        "water_kind_distribution": dict(water_kind_distribution.most_common(20)),
        "water_kind_distribution_by_type": {
            key: dict(counter.most_common(20))
            for key, counter in sorted(water_kind_distribution_by_type.items())
        },
        "water_kind_distribution_by_source_type": {
            key: dict(counter.most_common(20))
            for key, counter in sorted(water_kind_distribution_by_source_type.items())
        },
        "source_water_signal_distribution": dict(
            Counter((source_summary.get("osm") or {}).get("source_water_signal_distribution") or {}).most_common(20)
        ),
        "source_highway_signal_distribution": dict(
            Counter((source_summary.get("osm") or {}).get("source_highway_signal_distribution") or {}).most_common(20)
        ),
        "source_pedestrian_signal_distribution": dict(
            Counter((source_summary.get("osm") or {}).get("source_pedestrian_signal_distribution") or {}).most_common(
                20
            )
        ),
        "source_vegetation_signal_distribution": dict(
            Counter((source_summary.get("osm") or {}).get("source_vegetation_signal_distribution") or {}).most_common(
                20
            )
        ),
        "stats": {
            "building_height": _numeric_stats(building_heights),
            "building_footprint_area": _numeric_stats(building_areas),
        },
        "source_alignment": {
            "source_building_geometry_count": canonical_source_building_geometry_count,
            "raw_source_building_geometry_count": raw_source_building_geometry_count,
            "manifest_to_source_building_ratio": manifest_to_source_building_ratio,
            "manifest_unique_building_geometry_count": manifest_unique_building_geometry_count,
            "unique_manifest_to_source_building_ratio": unique_manifest_to_source_building_ratio,
            "geometry_alignment_ratio": geometry_alignment_ratio,
            "source_road_geometry_count": source_road_geometry_count,
            "manifest_unique_road_geometry_count": manifest_unique_road_geometry_count,
            "manifest_to_source_road_ratio": manifest_to_source_road_ratio,
            "road_chunk_split_factor": round(_ratio(roads_count, manifest_unique_road_geometry_count), 4),
            "source_building_footprint_area": round(source_building_footprint_area, 2),
            "raw_source_building_footprint_area": round(raw_source_building_footprint_area, 2),
            "manifest_building_footprint_area": round(manifest_building_footprint_area, 2),
            "building_footprint_area_alignment_ratio": round(building_footprint_area_alignment_ratio, 4),
            "source_building_relations_with_inner": source_building_relations_with_inner,
            "manifest_building_hole_count": building_hole_count,
            "topology_alignment_ratio": topology_alignment_ratio,
            "source_building_source_breakdown": {
                "osm": source_osm_building_geometry_count,
                "overture": source_overture_building_geometry_count,
            },
            "manifest_building_source_breakdown": {
                "osm": manifest_osm_building_count,
                "overture": manifest_overture_building_count,
                "unknown": manifest_unknown_building_count,
            },
            "canonical_source_building_source_breakdown": canonical_source_breakdown,
            "source_duplicate_overlap_counts": source_duplicate_overlap_counts,
        },
        "scale_alignment": scale_alignment,
        "hotspots": {
            "chunk_building_density": _top_hotspots(chunk_rows, "building_count"),
            "chunk_road_density": _top_hotspots(chunk_rows, "road_count"),
            "chunk_feature_density": _top_hotspots(chunk_rows, "feature_count"),
            "empty_chunks": [row for row in chunk_rows if row["feature_count"] == 0][:HOTSPOT_LIMIT],
        },
        "quality_scores": quality_scores,
    }

    findings: list[dict[str, Any]] = []
    if building_count >= 10 and flat_roof_ratio >= 0.95:
        _add_finding(
            findings,
            severity="error",
            code="roof_shape_collapse",
            message="Roof shape diversity collapsed; almost every building roof resolves to flat.",
            metric="flat_roof_ratio",
            value=round(flat_roof_ratio, 4),
            threshold=">= 0.95",
        )
    if large_building_candidate_count >= 10 and building_hole_count == 0:
        _add_finding(
            findings,
            severity="error",
            code="building_hole_absence",
            message="Large buildings exist but no building holes/courtyards survived into the manifest.",
            metric="building_hole_count",
            value=building_hole_count,
            threshold=f">= 1 when large_building_candidate_count >= 10 (actual {large_building_candidate_count})",
        )
    if source_building_relations_with_inner > 0 and building_hole_count == 0:
        _add_finding(
            findings,
            severity="error",
            code="source_to_manifest_topology_loss",
            message="OSM building relations contain inner rings, but the manifest lost every building hole/courtyard.",
            metric="building_relation_with_inner_count",
            value=source_building_relations_with_inner,
            threshold="manifest building_hole_count should retain source inner topology",
        )
    if canonical_source_building_geometry_count > 0 and manifest_to_source_building_ratio < 0.75:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_geometry_gap",
            message="Manifest building geometry count is materially below the source building geometry count.",
            metric="manifest_to_source_building_ratio",
            value=round(manifest_to_source_building_ratio, 4),
            threshold="< 0.75",
        )
    if canonical_source_building_geometry_count > 0 and manifest_to_source_building_ratio > 1.25:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_geometry_bloat",
            message="Manifest building geometry count materially exceeds the combined source building geometry count.",
            metric="manifest_to_source_building_ratio",
            value=round(manifest_to_source_building_ratio, 4),
            threshold="> 1.25",
        )
    if source_osm_building_geometry_count > 0 and _ratio(manifest_osm_building_count, source_osm_building_geometry_count) > 1.25:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_osm_building_bloat",
            message="Manifest OSM-derived building count materially exceeds the source OSM building geometry count.",
            metric="manifest_to_source_osm_building_ratio",
            value=round(_ratio(manifest_osm_building_count, source_osm_building_geometry_count), 4),
            threshold="> 1.25",
        )
    if source_overture_building_geometry_count > 0 and _ratio(manifest_overture_building_count, source_overture_building_geometry_count) > 1.25:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_overture_building_bloat",
            message="Manifest Overture-derived building count materially exceeds the source Overture building geometry count.",
            metric="manifest_to_source_overture_building_ratio",
            value=round(_ratio(manifest_overture_building_count, source_overture_building_geometry_count), 4),
            threshold="> 1.25",
        )
    if source_building_footprint_area > 0 and manifest_building_footprint_area / source_building_footprint_area > 1.25:
        _add_finding(
            findings,
            severity="error",
            code="source_to_manifest_building_area_bloat",
            message="Manifest building footprint area materially exceeds the projected source building footprint area.",
            metric="building_footprint_area_ratio",
            value=round(manifest_building_footprint_area / source_building_footprint_area, 4),
            threshold="> 1.25",
        )
    if source_building_footprint_area > 0 and manifest_building_footprint_area / source_building_footprint_area < 0.75:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_building_area_gap",
            message="Manifest building footprint area is materially below the projected source building footprint area.",
            metric="building_footprint_area_ratio",
            value=round(manifest_building_footprint_area / source_building_footprint_area, 4),
            threshold="< 0.75",
        )
    if source_road_geometry_count > 0 and manifest_to_source_road_ratio < 0.75:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_road_gap",
            message="Manifest road geometry count is materially below the source highway geometry count.",
            metric="manifest_to_source_road_ratio",
            value=round(manifest_to_source_road_ratio, 4),
            threshold="< 0.75",
        )
    if source_road_geometry_count > 0 and manifest_to_source_road_ratio > 1.25:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_road_bloat",
            message="Manifest road geometry count materially exceeds the source highway geometry count.",
            metric="manifest_to_source_road_ratio",
            value=round(manifest_to_source_road_ratio, 4),
            threshold="> 1.25",
        )
    if building_count >= 10 and generic_usage_ratio >= 0.75:
        _add_finding(
            findings,
            severity="error",
            code="building_usage_collapse",
            message="Building usage semantics collapsed into generic 'yes' for too many buildings.",
            metric="generic_usage_ratio",
            value=round(generic_usage_ratio, 4),
            threshold=">= 0.75",
        )
    if building_count >= 10 and dominant_building_material_ratio >= 0.95:
        _add_finding(
            findings,
            severity="warning",
            code="building_material_collapse",
            message="Building material diversity is too low; one material dominates nearly the whole place.",
            metric="dominant_building_material_ratio",
            value=round(dominant_building_material_ratio, 4),
            threshold=">= 0.95",
        )
    if suspicious_material_assignments:
        _add_finding(
            findings,
            severity="warning",
            code="implausible_building_material_assignments",
            message="Manifest contains suspicious building material assignments, such as glass on civic or landmark-like buildings.",
            metric="suspicious_material_assignment_count",
            value=len(suspicious_material_assignments),
            threshold="== 0",
        )
    if source_usage_mismatches:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_usage_drift",
            message="Manifest building usage diverged from source semantic signals for a non-trivial set of OSM buildings.",
            metric="source_usage_mismatch_count",
            value=len(source_usage_mismatches),
            threshold="== 0",
        )
    if source_material_mismatches:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_material_drift",
            message="Manifest building materials diverged from explicit source wall-material tags for a non-trivial set of OSM buildings.",
            metric="source_material_mismatch_count",
            value=len(source_material_mismatches),
            threshold="== 0",
        )
    if source_identity_loss_records:
        _add_finding(
            findings,
            severity="error",
            code="source_to_manifest_identity_loss",
            message="Strongly-signaled source buildings disappeared before manifest emission.",
            metric="source_identity_loss_count",
            value=len(source_identity_loss_records),
            threshold="== 0",
        )
    if source_identity_transform_records:
        _add_finding(
            findings,
            severity="warning",
            code="source_to_manifest_identity_transform",
            message="Strongly-signaled source buildings survived only as transformed nearby shells without exact identity retention.",
            metric="source_identity_transform_count",
            value=len(source_identity_transform_records),
            threshold="== 0",
        )
    if inner_non_building_relation_identity_loss_records:
        _add_finding(
            findings,
            severity="error",
            code="source_to_manifest_inner_building_identity_loss",
            message="Named building ways that were only inner members of non-building relations disappeared before manifest emission.",
            metric="inner_non_building_relation_identity_loss_count",
            value=len(inner_non_building_relation_identity_loss_records),
            threshold="== 0",
        )
    if chunks_with_terrain >= 1 and terrain_single_material_ratio >= 0.95:
        _add_finding(
            findings,
            severity="error",
            code="terrain_material_monotony",
            message="Terrain cover collapsed to a single material across nearly every chunk.",
            metric="terrain_single_material_ratio",
            value=round(terrain_single_material_ratio, 4),
            threshold=">= 0.95",
        )
    if roads_count >= 10 and roads_missing_surface_ratio >= 0.40:
        _add_finding(
            findings,
            severity="warning",
            code="road_surface_metadata_sparse",
            message="Many roads are missing explicit surface metadata, which encourages defaulting and visual drift.",
            metric="roads_missing_surface_ratio",
            value=round(roads_missing_surface_ratio, 4),
            threshold=">= 0.40",
        )
    if scale_alignment["world_alignment_ratio"] > 0 and scale_alignment["world_alignment_ratio"] < 0.85:
        _add_finding(
            findings,
            severity="error",
            code="world_scale_mismatch",
            message="Manifest world span drifted materially from the projected source span, indicating a likely X/Z scale mismatch.",
            metric="world_alignment_ratio",
            value=scale_alignment["world_alignment_ratio"],
            threshold="< 0.85",
        )
    if height_alignment["count"] > 0 and height_alignment["building_height_alignment_ratio"] < 0.85:
        _add_finding(
            findings,
            severity="error",
            code="building_height_scale_mismatch",
            message="Manifest building heights drift materially from source meter heights after meters-per-stud conversion.",
            metric="building_height_alignment_ratio",
            value=height_alignment["building_height_alignment_ratio"],
            threshold="< 0.85",
        )

    location = {
        "world_name": meta.get("worldName"),
        "generator": meta.get("generator"),
        "source": meta.get("source"),
        **location_meta,
    }

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "manifest_path": str(manifest_path),
        "schema_version": manifest.get("schemaVersion"),
        "zone": {
            "focus_x": focus_x,
            "focus_z": focus_z,
            "radius": radius,
        }
        if focus_x is not None and focus_z is not None and radius is not None
        else None,
        "location": location,
        "summary": summary,
        "osm_summary": osm_summary,
        "source_summary": source_summary,
        "findings": findings,
        "data_sources": [_build_source_context(path) for path in source_paths],
    }


def write_html_report(report: dict[str, Any], destination: Path) -> None:
    payload = json.dumps(report, separators=(",", ":"), sort_keys=True)
    initial_findings = "".join(
        (
            f'<tr data-finding-code="{escape(str(finding["code"]))}" '
            f'data-severity="{escape(str(finding["severity"]))}">'
            f'<td class="severity-{escape(str(finding["severity"]))}">{escape(str(finding["severity"]))}</td>'
            f'<td><code>{escape(str(finding["code"]))}</code></td>'
            f'<td>{escape(str(finding["message"]))}</td>'
            f'<td><code>{escape(str(finding["metric"]))}</code></td>'
            f'<td>{escape(str(finding["value"]))}</td>'
            f'<td>{escape(str(finding["threshold"]))}</td>'
            "</tr>"
        )
        for finding in report.get("findings", [])
    ) or '<tr><td colspan="6">No findings.</td></tr>'
    initial_hotspots = "".join(
        (
            "<tr>"
            f'<td><code>{escape(str(row.get("chunk_id")))}</code></td>'
            f'<td>{escape(str(row.get("feature_count", 0)))}</td>'
            f'<td>{escape(str(row.get("building_count", 0)))}</td>'
            f'<td>{escape(str(row.get("road_count", 0)))}</td>'
            f'<td>{escape(str(row.get("building_area", 0)))}</td>'
            f'<td>{("single" if row.get("terrain_material_monotone") else "mixed")}</td>'
            "</tr>"
        )
        for row in report.get("summary", {}).get("hotspots", {}).get("chunk_feature_density", [])
    ) or '<tr><td colspan="6">No hotspots recorded.</td></tr>'
    summary = report.get("summary", {})

    def render_distribution_item(label: str, key: str, value: Any) -> str:
        return (
            f"<li><span>{escape(label)} · <code>{escape(key)}</code></span>"
            f"<span>{escape(str(value))}</span></li>"
        )

    initial_distribution_items: list[str] = []
    initial_distribution_items.extend(
        render_distribution_item("roof", str(key), value)
        for key, value in list((summary.get("roof_distribution") or {}).items())[:5]
    )
    for label, bucket_map in (
        ("roof by usage", summary.get("roof_distribution_by_usage") or {}),
        ("roof by source usage", summary.get("roof_distribution_by_source_usage") or {}),
        ("roof by source", summary.get("roof_distribution_by_source_type") or {}),
        ("water by type", summary.get("water_kind_distribution_by_type") or {}),
        ("water by source", summary.get("water_kind_distribution_by_source_type") or {}),
    ):
        for key, value in list(bucket_map.items())[:4]:
            if not isinstance(value, dict):
                continue
            for inner_key, inner_value in list(value.items())[:2]:
                initial_distribution_items.append(
                    render_distribution_item(label, f"{key} / {inner_key}", inner_value)
                )
    initial_distribution_items.extend(
        render_distribution_item("usage", str(key), value)
        for key, value in list((summary.get("usage_distribution") or {}).items())[:5]
    )
    initial_distribution_items.extend(
        render_distribution_item("material", str(key), value)
        for key, value in list((summary.get("building_material_distribution") or {}).items())[:5]
    )
    initial_distribution_items.extend(
        render_distribution_item("manifest water", str(key), value)
        for key, value in list((summary.get("water_kind_distribution") or {}).items())[:8]
    )
    initial_distribution_items.extend(
        render_distribution_item("source water", str(key), value)
        for key, value in list((summary.get("source_water_signal_distribution") or {}).items())[:8]
    )
    initial_distribution_html = "".join(initial_distribution_items)
    initial_pedestrian_html = "".join(
        [
            *[
                render_distribution_item("source highway", str(key), value)
                for key, value in list((summary.get("source_highway_signal_distribution") or {}).items())[:8]
            ],
            *[
                render_distribution_item("source pedestrian", str(key), value)
                for key, value in list((summary.get("source_pedestrian_signal_distribution") or {}).items())[:8]
            ],
            *[
                render_distribution_item("manifest pedestrian", str(key), value)
                for key, value in list((summary.get("pedestrian_way_distribution") or {}).items())[:8]
            ],
            *[
                render_distribution_item("manifest road subkind", str(key), value)
                for key, value in list((summary.get("road_subkind_distribution") or {}).items())[:8]
            ],
        ]
    )
    initial_vegetation_html = "".join(
        [
            *[
                render_distribution_item("source vegetation", str(key), value)
                for key, value in list((summary.get("source_vegetation_signal_distribution") or {}).items())[:8]
            ],
            *[
                render_distribution_item("manifest vegetation", str(key), value)
                for key, value in list((summary.get("vegetation_signal_distribution") or {}).items())[:8]
            ],
            *[
                render_distribution_item("manifest props", str(key), value)
                for key, value in list((summary.get("prop_kind_distribution") or {}).items())[:8]
            ],
            *[
                render_distribution_item("tree species", str(key), value)
                for key, value in list((summary.get("tree_species_distribution") or {}).items())[:8]
            ],
        ]
    )
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Manifest Quality Audit</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f3f4ee;
      --fg: #141713;
      --muted: #667067;
      --rule: #d8dcd3;
      --accent: #0f5f4b;
      --panel: #fafbf6;
      --code-bg: #ecefe7;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background:
        radial-gradient(circle at top right, rgba(15, 95, 75, 0.06), transparent 22rem),
        var(--bg);
      color: var(--fg);
      font-family: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", Palatino, Georgia, serif;
      line-height: 1.5;
    }}
    main {{
      max-width: 1120px;
      margin: 0 auto;
      padding: 40px 28px 64px;
    }}
    h1, h2, h3 {{
      margin: 0 0 0.6rem;
      font-family: "SF Pro Display", "Inter", "Segoe UI", sans-serif;
      font-weight: 620;
      letter-spacing: -0.03em;
    }}
    h1 {{ font-size: clamp(2rem, 4vw, 3.2rem); }}
    h2 {{
      margin-top: 2.8rem;
      font-size: 0.93rem;
      text-transform: uppercase;
      letter-spacing: 0.11em;
      color: var(--muted);
    }}
    p {{ margin: 0.2rem 0 0.8rem; }}
    a {{ color: var(--accent); text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    code {{
      background: var(--code-bg);
      padding: 0.12rem 0.34rem;
      border-radius: 0.18rem;
      font-family: "SFMono-Regular", "SF Mono", Menlo, Consolas, monospace;
      font-size: 0.92em;
    }}
    pre {{
      margin: 0;
      background: var(--panel);
      border: 1px solid var(--rule);
      padding: 14px;
      overflow: auto;
      font-size: 0.84rem;
      line-height: 1.45;
      border-radius: 10px;
      font-family: "SFMono-Regular", "SF Mono", Menlo, Consolas, monospace;
    }}
    .lede {{
      max-width: 72ch;
      color: var(--muted);
    }}
    .meta-line {{
      color: var(--muted);
      font-family: "SF Pro Text", "Inter", "Segoe UI", sans-serif;
      font-size: 0.95rem;
    }}
    .metric-strip {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 18px;
      border-top: 1px solid var(--rule);
      border-bottom: 1px solid var(--rule);
      padding: 18px 0 20px;
      margin: 22px 0 30px;
      font-family: "SF Pro Text", "Inter", "Segoe UI", sans-serif;
    }}
    .metric-label {{
      display: block;
      margin-bottom: 4px;
      color: var(--muted);
      font-size: 0.77rem;
      text-transform: uppercase;
      letter-spacing: 0.09em;
    }}
    .metric-value {{
      font-size: 1.55rem;
      letter-spacing: -0.04em;
    }}
    .section-grid {{
      display: grid;
      grid-template-columns: minmax(0, 1.3fr) minmax(280px, 0.7fr);
      gap: 28px;
      align-items: start;
    }}
    .toolbar {{
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
      margin: 12px 0 18px;
      font-family: "SF Pro Text", "Inter", "Segoe UI", sans-serif;
    }}
    .toolbar input, .toolbar select {{
      min-width: 180px;
      border: 1px solid var(--rule);
      background: transparent;
      padding: 10px 12px;
      font: inherit;
      color: var(--fg);
      border-radius: 999px;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-family: "SF Pro Text", "Inter", "Segoe UI", sans-serif;
      font-size: 0.94rem;
    }}
    th, td {{
      padding: 10px 8px;
      text-align: left;
      vertical-align: top;
      border-top: 1px solid var(--rule);
    }}
    th {{
      color: var(--muted);
      font-size: 0.76rem;
      text-transform: uppercase;
      letter-spacing: 0.09em;
      font-weight: 600;
    }}
    .distribution-list, .source-list {{
      display: grid;
      gap: 16px;
    }}
    .distribution-list {{
      list-style: none;
      padding: 0;
      margin: 0;
      font-family: "SF Pro Text", "Inter", "Segoe UI", sans-serif;
    }}
    .distribution-list li {{
      display: flex;
      justify-content: space-between;
      gap: 16px;
      padding: 8px 0;
      border-top: 1px solid var(--rule);
    }}
    .source-meta, .quiet {{
      color: var(--muted);
      font-family: "SF Pro Text", "Inter", "Segoe UI", sans-serif;
      font-size: 0.9rem;
    }}
    .severity-error {{ color: #8c2c20; }}
    .severity-warning {{ color: #7a5f18; }}
    @media (max-width: 900px) {{
      .section-grid {{
        grid-template-columns: 1fr;
      }}
    }}
  </style>
</head>
<body>
  <main>
    <script id="report-data" type="application/json">{escape(payload)}</script>
    <p class="meta-line">Manifest intelligence · static-first artifact</p>
    <h1>Manifest Quality Audit</h1>
    <p class="lede">A fast, source-aware audit of generated world quality. Heavy metrics are precomputed in Python; the report ships as one compact JSON payload and renders into the DOM for filtering, inspection, and optimization triage.</p>
    <div id="header-meta" class="meta-line"></div>
    <section id="metric-strip" class="metric-strip"></section>

    <section class="section-grid">
      <div>
        <h2>Findings</h2>
        <div class="toolbar">
          <input id="finding-filter" type="search" placeholder="Filter findings, codes, metrics" />
          <select id="severity-filter">
            <option value="all">All Severities</option>
            <option value="error">Errors</option>
            <option value="warning">Warnings</option>
          </select>
        </div>
        <table>
          <thead>
            <tr><th>Severity</th><th>Code</th><th>Message</th><th>Metric</th><th>Value</th><th>Threshold</th></tr>
          </thead>
          <tbody id="findings-body">{initial_findings}</tbody>
        </table>
      </div>
      <aside>
        <h2>Location</h2>
        <div id="location-block"></div>
        <h2>Scores</h2>
        <div id="score-strip" class="metric-strip"></div>
      </aside>
    </section>

    <section class="section-grid">
      <div>
        <h2>Hotspots</h2>
        <table id="hotspot-table">
          <thead>
            <tr><th>Chunk</th><th>Features</th><th>Buildings</th><th>Roads</th><th>Building Area</th><th>Terrain</th></tr>
          </thead>
          <tbody id="hotspot-body">{initial_hotspots}</tbody>
        </table>
      </div>
      <aside>
        <h2>Distributions</h2>
        <ul id="distribution-list" class="distribution-list">{initial_distribution_html}</ul>
        <h2>Pedestrian Diagnostics</h2>
        <ul id="pedestrian-diagnostics-list" class="distribution-list">{initial_pedestrian_html}</ul>
        <h2>Vegetation Diagnostics</h2>
        <ul id="vegetation-diagnostics-list" class="distribution-list">{initial_vegetation_html}</ul>
        <h2>Suspicious Materials</h2>
        <ul id="material-risk-list" class="distribution-list"></ul>
        <h2>Usage Drift</h2>
        <ul id="usage-drift-list" class="distribution-list"></ul>
      </aside>
    </section>

    <section class="section-grid">
      <div>
        <h2>OSM Source Summary</h2>
        <pre id="osm-summary-block"></pre>
        <h2>Scale Alignment</h2>
        <pre id="scale-alignment-block"></pre>
      </div>
      <aside>
        <h2>Data Sources</h2>
        <div id="source-list" class="source-list"></div>
      </aside>
    </section>
  </main>
  <script>
    const report = JSON.parse(document.getElementById("report-data").textContent);
    const fmtInt = new Intl.NumberFormat("en-US");
    const fmtPct = new Intl.NumberFormat("en-US", {{ style: "percent", maximumFractionDigits: 1 }});
    const fmtNum = new Intl.NumberFormat("en-US", {{ maximumFractionDigits: 2 }});

    function metric(label, value) {{
      return `<div class="metric"><span class="metric-label">${{label}}</span><div class="metric-value">${{value}}</div></div>`;
    }}

    function renderHeader() {{
      const meta = report.location || {{}};
      const zone = report.zone;
      document.getElementById("header-meta").textContent =
        `Generated ${{report.generated_at}} · Schema ${{report.schema_version}} · ${{meta.world_name || "Unknown world"}}${{zone ? ` · zone (${{zone.focus_x}}, ${{zone.focus_z}}) r=${{zone.radius}}` : ""}}`;
      document.getElementById("metric-strip").innerHTML = [
        metric("Buildings", fmtInt.format(report.summary.building_count || 0)),
        metric("Roads", fmtInt.format(report.summary.roads_count || 0)),
        metric("Chunks", fmtInt.format(report.summary.chunk_count || 0)),
        metric("Suspicious Glass", fmtInt.format(report.summary.suspicious_material_assignment_count || 0)),
        metric("Material Drift", fmtInt.format(report.summary.source_material_mismatch_count || 0)),
        metric("Identity Loss", fmtInt.format(report.summary.source_identity_loss_count || 0)),
        metric("Identity Transform", fmtInt.format(report.summary.source_identity_transform_count || 0)),
        metric("Bldg ID Align", fmtPct.format((report.summary.source_alignment || {{}}).geometry_alignment_ratio || 0)),
        metric("Bldg Area Align", fmtPct.format((report.summary.source_alignment || {{}}).building_footprint_area_alignment_ratio || 0)),
        metric("Road ID Align", fmtPct.format((report.summary.source_alignment || {{}}).manifest_to_source_road_ratio || 0)),
        metric("Road Split", fmtNum.format((report.summary.source_alignment || {{}}).road_chunk_split_factor || 0)),
        metric("Flat Roofs", fmtPct.format(report.summary.flat_roof_ratio || 0)),
        metric("Generic Usage", fmtPct.format(report.summary.generic_usage_ratio || 0)),
        metric("Terrain Monotony", fmtPct.format(report.summary.terrain_single_material_ratio || 0)),
      ].join("");
      document.getElementById("score-strip").innerHTML = Object.entries(report.summary.quality_scores || {{}})
        .map(([key, value]) => metric(key.replaceAll("_", " "), fmtNum.format(value)))
        .join("");
    }}

    function renderLocation() {{
      const meta = report.location || {{}};
      const bbox = meta.bbox || {{}};
      const mapLink = meta.openstreetmap_url
        ? `<p><a href="${{meta.openstreetmap_url}}">OpenStreetMap</a></p>`
        : "";
      document.getElementById("location-block").innerHTML = `
        <p><strong>${{meta.world_name || "Unknown world"}}</strong></p>
        <p class="quiet">${{meta.source || "unknown source"}} · ${{meta.generator || "unknown generator"}}</p>
        <p class="quiet">BBox: ${{JSON.stringify(bbox)}}</p>
        ${{mapLink}}
      `;
    }}

    function renderFindings() {{
      const query = document.getElementById("finding-filter").value.trim().toLowerCase();
      const severity = document.getElementById("severity-filter").value;
      const rows = (report.findings || []).filter((finding) => {{
        const haystack = `${{finding.code}} ${{finding.message}} ${{finding.metric}}`.toLowerCase();
        return (!query || haystack.includes(query)) && (severity === "all" || finding.severity === severity);
      }});
      document.getElementById("findings-body").innerHTML = rows.length
        ? rows.map((finding) => `
            <tr data-finding-code="${{finding.code}}" data-severity="${{finding.severity}}">
              <td class="severity-${{finding.severity}}">${{finding.severity}}</td>
              <td><code>${{finding.code}}</code></td>
              <td>${{finding.message}}</td>
              <td><code>${{finding.metric}}</code></td>
              <td>${{finding.value}}</td>
              <td>${{finding.threshold}}</td>
            </tr>
          `).join("")
        : '<tr><td colspan="6">No findings match the current filter.</td></tr>';
    }}

    function renderHotspots() {{
      const hotspots = report.summary.hotspots?.chunk_feature_density || [];
      document.getElementById("hotspot-body").innerHTML = hotspots.length
        ? hotspots.map((row) => `
            <tr>
              <td><code>${{row.chunk_id}}</code></td>
              <td>${{fmtInt.format(row.feature_count || 0)}}</td>
              <td>${{fmtInt.format(row.building_count || 0)}}</td>
              <td>${{fmtInt.format(row.road_count || 0)}}</td>
              <td>${{fmtNum.format(row.building_area || 0)}}</td>
              <td>${{row.terrain_material_monotone ? "single" : "mixed"}}</td>
            </tr>
          `).join("")
        : '<tr><td colspan="6">No hotspots recorded.</td></tr>';
    }}

    function renderDistributions() {{
      const roof = Object.entries(report.summary.roof_distribution || {{}}).slice(0, 5);
      const roofByUsage = Object.entries(report.summary.roof_distribution_by_usage || {{}}).slice(0, 4);
      const roofBySourceUsage = Object.entries(report.summary.roof_distribution_by_source_usage || {{}}).slice(0, 4);
      const roofBySourceType = Object.entries(report.summary.roof_distribution_by_source_type || {{}}).slice(0, 4);
      const usage = Object.entries(report.summary.usage_distribution || {{}}).slice(0, 5);
      const material = Object.entries(report.summary.building_material_distribution || {{}}).slice(0, 5);
      const waterKinds = Object.entries(report.summary.water_kind_distribution || {{}}).slice(0, 8);
      const waterByType = Object.entries(report.summary.water_kind_distribution_by_type || {{}}).slice(0, 4);
      const waterBySource = Object.entries(report.summary.water_kind_distribution_by_source_type || {{}}).slice(0, 4);
      const sourceWaterSignals = Object.entries(report.summary.source_water_signal_distribution || {{}}).slice(0, 8);
      const sourceHighwaySignals = Object.entries(report.summary.source_highway_signal_distribution || {{}}).slice(0, 8);
      const sourcePedestrianSignals = Object.entries(report.summary.source_pedestrian_signal_distribution || {{}}).slice(0, 8);
      const sourceVegetationSignals = Object.entries(report.summary.source_vegetation_signal_distribution || {{}}).slice(0, 8);
      const pedestrianWays = Object.entries(report.summary.pedestrian_way_distribution || {{}}).slice(0, 8);
      const roadSubkinds = Object.entries(report.summary.road_subkind_distribution || {{}}).slice(0, 8);
      const propKinds = Object.entries(report.summary.prop_kind_distribution || {{}}).slice(0, 8);
      const treeSpecies = Object.entries(report.summary.tree_species_distribution || {{}}).slice(0, 8);
      const vegetationSignals = Object.entries(report.summary.vegetation_signal_distribution || {{}}).slice(0, 8);
      const glassByUsage = Object.entries(report.summary.glass_material_by_usage || {{}}).slice(0, 8);
      const glassBySignal = Object.entries(report.summary.suspicious_material_assignment_by_signal || {{}}).slice(0, 8);
      const suspicious = (report.summary.suspicious_material_assignments || []).slice(0, 8);
      const materialConfusion = Object.entries(report.summary.source_material_confusion || {{}}).slice(0, 8);
      const materialMismatches = (report.summary.source_material_mismatches || []).slice(0, 8);
      const identityLoss = (report.summary.source_identity_loss_records || []).slice(0, 8);
      const identityTransforms = (report.summary.source_identity_transform_records || []).slice(0, 8);
      const identityLossUsage = Object.entries(report.summary.source_identity_loss_by_usage || {{}}).slice(0, 8);
      const identityTransformUsage = Object.entries(report.summary.source_identity_transform_by_usage || {{}}).slice(0, 8);
      const identityLossReason = Object.entries(report.summary.source_identity_loss_by_reason || {{}}).slice(0, 8);
      const identityTransformReason = Object.entries(report.summary.source_identity_transform_by_reason || {{}}).slice(0, 8);
      const innerRelationIdentityLoss = (report.summary.inner_non_building_relation_identity_loss_records || []).slice(0, 8);
      const innerRelationIdentityContexts = Object.entries(report.summary.inner_non_building_relation_identity_loss_by_context || {{}}).slice(0, 8);
      const usageConfusion = Object.entries(report.summary.source_usage_confusion || {{}}).slice(0, 8);
      const usageMismatches = (report.summary.source_usage_mismatches || []).slice(0, 8);
      const usageRefinements = (report.summary.source_usage_refinements || []).slice(0, 6);
      const usageDiagnostics = (report.summary.source_usage_diagnostics_top_mismatch_types || []).slice(0, 8);
      const lines = [
        ...roof.map(([key, value]) => `<li><span>roof · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...roofByUsage.flatMap(([key, value]) => Object.entries(value || {{}}).slice(0, 2).map(([roofKey, count]) => `<li><span>roof by usage · <code>${{key}} / ${{roofKey}}</code></span><span>${{fmtInt.format(count)}}</span></li>`)),
        ...roofBySourceUsage.flatMap(([key, value]) => Object.entries(value || {{}}).slice(0, 2).map(([roofKey, count]) => `<li><span>roof by source usage · <code>${{key}} / ${{roofKey}}</code></span><span>${{fmtInt.format(count)}}</span></li>`)),
        ...roofBySourceType.flatMap(([key, value]) => Object.entries(value || {{}}).slice(0, 2).map(([roofKey, count]) => `<li><span>roof by source · <code>${{key}} / ${{roofKey}}</code></span><span>${{fmtInt.format(count)}}</span></li>`)),
        ...usage.map(([key, value]) => `<li><span>usage · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...material.map(([key, value]) => `<li><span>material · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...waterKinds.map(([key, value]) => `<li><span>manifest water · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...waterByType.flatMap(([key, value]) => Object.entries(value || {{}}).slice(0, 2).map(([waterKey, count]) => `<li><span>water by type · <code>${{key}} / ${{waterKey}}</code></span><span>${{fmtInt.format(count)}}</span></li>`)),
        ...waterBySource.flatMap(([key, value]) => Object.entries(value || {{}}).slice(0, 2).map(([waterKey, count]) => `<li><span>water by source · <code>${{key}} / ${{waterKey}}</code></span><span>${{fmtInt.format(count)}}</span></li>`)),
        ...sourceWaterSignals.map(([key, value]) => `<li><span>source water · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
      ];
      document.getElementById("distribution-list").innerHTML = lines.join("");
      document.getElementById("pedestrian-diagnostics-list").innerHTML = [
        ...sourceHighwaySignals.map(([key, value]) => `<li><span>source highway · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...sourcePedestrianSignals.map(([key, value]) => `<li><span>source pedestrian · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...pedestrianWays.map(([key, value]) => `<li><span>manifest pedestrian · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...roadSubkinds.map(([key, value]) => `<li><span>manifest road subkind · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
      ].join("") || "<li><span>No pedestrian diagnostics recorded.</span><span>n/a</span></li>";
      document.getElementById("vegetation-diagnostics-list").innerHTML = [
        ...sourceVegetationSignals.map(([key, value]) => `<li><span>source vegetation · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...vegetationSignals.map(([key, value]) => `<li><span>manifest vegetation · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...propKinds.map(([key, value]) => `<li><span>manifest props · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...treeSpecies.map(([key, value]) => `<li><span>tree species · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
      ].join("") || "<li><span>No vegetation diagnostics recorded.</span><span>n/a</span></li>";
      document.getElementById("material-risk-list").innerHTML = [
        ...glassByUsage.map(([key, value]) => `<li><span>glass usage · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...glassBySignal.map(([key, value]) => `<li><span>glass signal · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...materialConfusion.map(([key, value]) => `<li><span>source material · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...identityLossUsage.map(([key, value]) => `<li><span>identity loss usage · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...identityTransformUsage.map(([key, value]) => `<li><span>identity transform usage · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...identityLossReason.map(([key, value]) => `<li><span>identity loss reason · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...identityTransformReason.map(([key, value]) => `<li><span>identity transform reason · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...innerRelationIdentityContexts.map(([key, value]) => `<li><span>inner relation loss · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...suspicious.map((row) => `<li><span><code>${{row.name || row.id || "unknown"}}</code><br><span class="quiet">${{row.usage || "unknown"}} · ${{row.material || "unknown"}}</span></span><span>${{row.reason || "flagged"}}</span></li>`),
        ...materialMismatches.map((row) => `<li><span><code>${{row.name || row.id || "unknown"}}</code><br><span class="quiet">${{row.source_material_signal || "?"}} → ${{row.manifest_material_signal || "?"}}</span></span><span>${{row.manifest_material || "unknown"}}</span></li>`),
        ...identityLoss.map((row) => `<li><span><code>${{row.name || row.source_id || "unknown"}}</code><br><span class="quiet">${{(row.identity_reasons || []).join(", ") || "identity"}} · missing</span></span><span>lost</span></li>`),
        ...identityTransforms.map((row) => `<li><span><code>${{row.name || row.source_id || "unknown"}}</code><br><span class="quiet">${{(row.identity_reasons || []).join(", ") || "identity"}} · transformed</span></span><span>${{((row.manifest_matches || [])[0] || {{}}).name || ((row.manifest_matches || [])[0] || {{}}).id || "proxy"}}</span></li>`),
        ...innerRelationIdentityLoss.map((row) => `<li><span><code>${{row.name || row.source_id || "unknown"}}</code><br><span class="quiet">${{(row.relation_contexts || []).join(", ") || "relation"}} · inner building lost</span></span><span>${{row.source_id || "missing"}}</span></li>`),
      ].join("") || "<li><span>No suspicious material assignments detected.</span><span>clean</span></li>";
      document.getElementById("usage-drift-list").innerHTML = [
        ...usageDiagnostics.map((row) => `<li><span>usage diag · <code>${{row.source_usage_signal}}</code><br><span class="quiet">src ${{fmtInt.format(row.source_count || 0)}} · mismatch ${{fmtInt.format(row.mismatch_count || 0)}} · refine ${{fmtInt.format(row.refinement_count || 0)}} · material ${{fmtInt.format(row.material_mismatch_count || 0)}}</span></span><span>loss ${{fmtInt.format(row.identity_loss_count || 0)}} / transform ${{fmtInt.format(row.identity_transform_count || 0)}}</span></li>`),
        ...usageConfusion.map(([key, value]) => `<li><span>source→manifest · <code>${{key}}</code></span><span>${{fmtInt.format(value)}}</span></li>`),
        ...usageMismatches.map((row) => `<li><span><code>${{row.name || row.id || "unknown"}}</code><br><span class="quiet">${{row.source_usage_signal || "?"}} → ${{row.manifest_usage || "?"}}</span></span><span>${{row.material || "unknown"}}</span></li>`),
        ...usageRefinements.map((row) => `<li><span><code>${{row.name || row.id || "unknown"}}</code><br><span class="quiet">benign refinement · ${{row.source_usage_signal || "?"}} → ${{row.manifest_usage || "?"}}</span></span><span>ok</span></li>`),
      ].join("") || "<li><span>No source-to-manifest usage drift recorded.</span><span>clean</span></li>";
    }}

    function renderSources() {{
      document.getElementById("osm-summary-block").textContent = JSON.stringify(report.osm_summary || {{}}, null, 2);
      document.getElementById("scale-alignment-block").textContent = JSON.stringify(report.summary.scale_alignment || {{}}, null, 2);
      const sources = report.data_sources || [];
      const sourceSummary = report.source_summary || {{}};
      document.getElementById("source-list").innerHTML = sources.length
        ? sources.map((source) => {{
            const sourceType = source.path.includes("overture") ? "overture" : "osm";
            const summary = sourceSummary[sourceType] || {{}};
            return `
            <section>
              <h3>${{source.path}}</h3>
              <div class="source-meta">Size: ${{fmtInt.format(source.size_bytes || 0)}} bytes</div>
              <pre>${{JSON.stringify(summary, null, 2)}}</pre>
              <pre>${{source.snippet || ""}}</pre>
            </section>
          `;
        }}).join("")
        : "<p>No external source snippets were provided.</p>";
    }}

    renderHeader();
    renderLocation();
    renderFindings();
    renderHotspots();
    renderDistributions();
    renderSources();
    document.getElementById("finding-filter").addEventListener("input", renderFindings);
    document.getElementById("severity-filter").addEventListener("change", renderFindings);
  </script>
</body>
</html>
"""
    destination.write_text(html, encoding="utf-8")


def _print_summary(report: dict[str, Any]) -> None:
    summary = report["summary"]
    zone = report.get("zone")
    zone_prefix = (
        f"zone=({zone['focus_x']},{zone['focus_z']}) r={zone['radius']} "
        if isinstance(zone, dict)
        else ""
    )
    print(
        "[manifest_quality_audit] "
        + f"world={report['location'].get('world_name')} "
        + zone_prefix
        + f"chunks={summary['chunk_count']} "
        + f"buildings={summary['building_count']} "
        + f"roads={summary['roads_count']} "
        + f"overall_score={summary['quality_scores']['overall']}"
    )
    for finding in report["findings"]:
        print(
            "[manifest_quality_audit] "
            f"{finding['severity'].upper()} {finding['code']}: {finding['message']} "
            f"(value={finding['value']}, threshold={finding['threshold']})"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit manifest quality and emit JSON/HTML reports.")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST_PATH)
    parser.add_argument("--source", type=Path, action="append", default=[])
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--html-out", type=Path)
    parser.add_argument("--focus-x", type=float)
    parser.add_argument("--focus-z", type=float)
    parser.add_argument("--radius", type=float)
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if any error-severity findings exist.")
    args = parser.parse_args()

    source_paths = args.source or DEFAULT_SOURCE_PATHS
    report = build_report(
        args.manifest,
        source_paths,
        focus_x=args.focus_x,
        focus_z=args.focus_z,
        radius=args.radius,
    )
    _print_summary(report)

    if args.json_out:
        args.json_out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"[manifest_quality_audit] wrote JSON report to {args.json_out}")
    if args.html_out:
        write_html_report(report, args.html_out)
        print(f"[manifest_quality_audit] wrote HTML report to {args.html_out}")

    if args.strict and any(finding["severity"] == "error" for finding in report["findings"]):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
