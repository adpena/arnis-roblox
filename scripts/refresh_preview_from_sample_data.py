#!/usr/bin/env python3
"""
Refresh the Studio preview manifest from the current exported Austin manifest artifacts.

This keeps edit-mode preview aligned with the same authoritative manifest content
used to generate runtime sample-data, instead of relying on stale checked-in
preview fixtures or copying runtime Lua shards wholesale.
"""

from __future__ import annotations

import json
import mmap
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path
from typing import Any

from json_manifest_to_sharded_lua import CHUNK_LIST_FIELDS, INDEX_ONLY_FIELDS, lua_len, write_lua_module


ROOT = Path(__file__).resolve().parents[1]


def resolve_generated_artifact_root(root: Path) -> Path:
    artifact_dir = root / "rust" / "out"
    if artifact_dir.exists():
        return root

    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return root

    common_dir = Path(result.stdout.strip())
    shared_root = common_dir.parent if common_dir.name == ".git" else common_dir
    if (shared_root / "rust" / "out").exists():
        return shared_root
    return root


ARTIFACT_ROOT = resolve_generated_artifact_root(ROOT)
SOURCE_INDEX = ROOT / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestIndex.lua"
SOURCE_JSON = ARTIFACT_ROOT / "rust" / "out" / "austin-manifest.json"
SOURCE_SQLITE = ARTIFACT_ROOT / "rust" / "out" / "austin-manifest.sqlite"
PREVIEW_DIR = ROOT / "roblox" / "src" / "ServerScriptService" / "StudioPreview"
PREVIEW_INDEX = PREVIEW_DIR / "AustinPreviewManifestIndex.lua"
PREVIEW_SHARDS = PREVIEW_DIR / "AustinPreviewManifestChunks"
CANONICAL_SAMPLE_DATA_DIR = ROOT / "roblox" / "src" / "ServerStorage" / "SampleData"
CANONICAL_INDEX = CANONICAL_SAMPLE_DATA_DIR / "AustinCanonicalManifestIndex.lua"
CANONICAL_SHARDS = CANONICAL_SAMPLE_DATA_DIR / "AustinCanonicalManifestChunks"
MAX_PREVIEW_BYTES = 199_998

TARGET_CHUNK_IDS = ["-1_-1", "0_-1", "-1_0", "0_0"]
PREVIEW_LOAD_RADIUS_STUDS = 1024
PREVIEW_SELECTION_GUTTER_STUDS = 256
DEFAULT_CHUNK_SIZE_STUDS = 256
AUSTIN_SOUTH_OF_CAPITOL_OFFSET_STUDS = -256
COUNTED_FEATURE_FIELDS = ("roads", "rails", "buildings", "water", "props", "landuse", "barriers")
EXCLUDED_SPAWN_KINDS = {"motorway", "motorway_link", "trunk"}
ROAD_PRIORITY = {
    "footway": 10,
    "pedestrian": 12,
    "path": 14,
    "cycleway": 16,
    "living_street": 18,
    "service": 20,
    "residential": 24,
    "unclassified": 28,
    "tertiary": 36,
    "secondary": 52,
    "primary": 80,
    "trunk": 140,
    "motorway_link": 220,
    "motorway": 260,
    "track": 280,
}

SCHEMA_RE = re.compile(r'return \{schemaVersion="(?P<schema>[^"]+)"')
CHUNK_SIZE_RE = re.compile(r"\bchunkSizeStuds\s*=\s*(?P<chunk_size>-?\d+(?:\.\d+)?)")
NUMERIC_STRING_RE = re.compile(r"^-?\d+(?:\.\d+)?$")
JSON_WHITESPACE = b" \t\r\n"


def _extract_lua_table(text: str, field_name: str) -> str | None:
    match = re.search(rf"{re.escape(field_name)}\s*=\s*\{{", text)
    if match is None:
        return None

    start = text.find("{", match.start())
    if start < 0:
        return None

    depth = 0
    in_string = False
    escape = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : index]
    raise SystemExit(f"could not parse {field_name} table")


def _split_top_level_items(text: str) -> list[str]:
    items: list[str] = []
    start = 0
    depth = 0
    in_string = False
    escape = False

    for index, char in enumerate(text):
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif char == "," and depth == 0:
            item = text[start:index].strip()
            if item:
                items.append(item)
            start = index + 1

    tail = text[start:].strip()
    if tail:
        items.append(tail)
    return items


def _parse_lua_value(text: str) -> Any:
    value = text.strip()
    if not value:
        return None
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1].replace(r"\"", '"').replace(r"\\", "\\")
    if value.startswith("{") and value.endswith("}"):
        return _parse_lua_table_value(value[1:-1])
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "nil":
        return None
    return value


def _parse_lua_table_value(text: str) -> list[Any] | dict[str, Any]:
    items = _split_top_level_items(text)
    if not items:
        return []
    if all(re.match(r"^[A-Za-z_][A-Za-z0-9_]*\s*=", item) for item in items):
        result: dict[str, Any] = {}
        for item in items:
            key, value = item.split("=", 1)
            result[key.strip()] = _parse_lua_value(value)
        return result
    return [_parse_lua_value(item) for item in items]


def _parse_chunk_ref_entries(index_text: str) -> list[dict[str, Any]]:
    chunk_refs_text = _extract_lua_table(index_text, "chunkRefs")
    if chunk_refs_text is None:
        return []

    parsed_chunk_refs = _parse_lua_table_value(chunk_refs_text)
    if not isinstance(parsed_chunk_refs, list):
        raise SystemExit("could not parse chunkRefs from AustinManifestIndex.lua")

    entries: list[dict[str, Any]] = []
    for index, chunk_ref in enumerate(parsed_chunk_refs):
        if not isinstance(chunk_ref, dict):
            raise SystemExit(f"could not parse chunkRef entry at index {index}")
        entries.append(chunk_ref)
    return entries


def _format_lua_value(value: Any) -> str:
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{key} = {_format_lua_value(nested)}" for key, nested in value.items()) + " }"
    if isinstance(value, list):
        return "{ " + ", ".join(_format_lua_value(item) for item in value) + " }"
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, str) and NUMERIC_STRING_RE.match(value):
        return value
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return str(value)


def _skip_json_whitespace(buffer: mmap.mmap, position: int) -> int:
    while position < len(buffer) and buffer[position] in JSON_WHITESPACE:
        position += 1
    return position


def _scan_json_string_end(buffer: mmap.mmap, position: int) -> int:
    if position >= len(buffer) or buffer[position] != ord('"'):
        raise SystemExit(f"expected JSON string at byte offset {position} in {SOURCE_JSON}")

    position += 1
    escaped = False
    while position < len(buffer):
        byte = buffer[position]
        if escaped:
            escaped = False
        elif byte == ord("\\"):
            escaped = True
        elif byte == ord('"'):
            return position + 1
        position += 1

    raise SystemExit(f"unterminated JSON string in {SOURCE_JSON}")


def _scan_json_value_end(buffer: mmap.mmap, position: int) -> int:
    position = _skip_json_whitespace(buffer, position)
    if position >= len(buffer):
        raise SystemExit(f"unexpected end of JSON while parsing {SOURCE_JSON}")

    token = buffer[position]
    if token == ord('"'):
        return _scan_json_string_end(buffer, position)

    if token in (ord("{"), ord("[")):
        stack = [token]
        position += 1
        in_string = False
        escaped = False

        while position < len(buffer):
            byte = buffer[position]
            if in_string:
                if escaped:
                    escaped = False
                elif byte == ord("\\"):
                    escaped = True
                elif byte == ord('"'):
                    in_string = False
            else:
                if byte == ord('"'):
                    in_string = True
                elif byte in (ord("{"), ord("[")):
                    stack.append(byte)
                elif byte in (ord("}"), ord("]")):
                    opener = stack.pop()
                    if (opener, byte) not in ((ord("{"), ord("}")), (ord("["), ord("]"))):
                        raise SystemExit(f"malformed JSON nesting in {SOURCE_JSON}")
                    if not stack:
                        return position + 1
            position += 1

        raise SystemExit(f"unterminated JSON object/array in {SOURCE_JSON}")

    while position < len(buffer) and buffer[position] not in b",]}" + JSON_WHITESPACE:
        position += 1
    return position


def _decode_json_segment(buffer: mmap.mmap, start: int, end: int) -> Any:
    try:
        return json.loads(buffer[start:end].decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"could not decode JSON segment from {SOURCE_JSON}: {exc}") from exc


def _extract_target_chunks_from_manifest(
    buffer: mmap.mmap,
    position: int,
    target_chunk_ids: set[str],
    *,
    allow_early_return: bool,
) -> tuple[int, dict[str, dict[str, Any]], bool]:
    position = _skip_json_whitespace(buffer, position)
    if position >= len(buffer) or buffer[position] != ord("["):
        raise SystemExit(f"missing chunks array in {SOURCE_JSON}")

    position += 1
    remaining = set(target_chunk_ids)
    extracted: dict[str, dict[str, Any]] = {}

    while position < len(buffer):
        position = _skip_json_whitespace(buffer, position)
        if position >= len(buffer):
            break
        if buffer[position] == ord("]"):
            return position + 1, extracted, False

        value_end = _scan_json_value_end(buffer, position)
        chunk = _decode_json_segment(buffer, position, value_end)
        if not isinstance(chunk, dict):
            raise SystemExit(f"encountered non-object chunk entry in {SOURCE_JSON}")

        chunk_id = chunk.get("id")
        if isinstance(chunk_id, str) and chunk_id in remaining:
            extracted[chunk_id] = chunk
            remaining.remove(chunk_id)
            if not remaining and allow_early_return:
                return value_end, extracted, True

        position = _skip_json_whitespace(buffer, value_end)
        if position < len(buffer) and buffer[position] == ord(","):
            position += 1
            continue
        if position < len(buffer) and buffer[position] == ord("]"):
            return position + 1, extracted, False
        raise SystemExit(f"malformed chunks array in {SOURCE_JSON}")

    raise SystemExit(f"unterminated chunks array in {SOURCE_JSON}")


def load_source_manifest_subset_from_sqlite(
    source_sqlite: Path, target_chunk_ids: list[str]
) -> tuple[str, dict[str, dict[str, Any]]]:
    connection = sqlite3.connect(source_sqlite)
    try:
        row = connection.execute(
            """
            SELECT schema_version
            FROM manifest_meta
            WHERE singleton_id = 1
            """
        ).fetchone()
        if row is None or not isinstance(row[0], str) or not row[0]:
            raise SystemExit(f"missing schemaVersion in {source_sqlite}")
        schema_version = row[0]

        source_chunks: dict[str, dict[str, Any]] = {}
        for chunk_id in target_chunk_ids:
            row = connection.execute(
                """
                SELECT chunk_json
                FROM manifest_chunks
                WHERE chunk_id = ?
                """,
                (chunk_id,),
            ).fetchone()
            if row is None or not isinstance(row[0], str):
                raise SystemExit(f"missing chunk {chunk_id} in {source_sqlite}")
            chunk = json.loads(row[0])
            if not isinstance(chunk, dict):
                raise SystemExit(f"malformed chunk {chunk_id} in {source_sqlite}")
            source_chunks[chunk_id] = chunk
    finally:
        connection.close()

    return schema_version, source_chunks


def load_source_manifest_subset(
    source_json: Path, target_chunk_ids: list[str], *, source_sqlite: Path | None = None
) -> tuple[str, dict[str, dict[str, Any]]]:
    if source_sqlite is not None and source_sqlite.exists():
        return load_source_manifest_subset_from_sqlite(source_sqlite, target_chunk_ids)

    target_chunk_id_set = set(target_chunk_ids)
    if not target_chunk_id_set:
        raise SystemExit("target_chunk_ids must not be empty")

    with source_json.open("rb") as handle:
        try:
            with mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) as buffer:
                position = _skip_json_whitespace(buffer, 0)
                if position >= len(buffer) or buffer[position] != ord("{"):
                    raise SystemExit(f"{source_json} is not a JSON object manifest")

                position += 1
                schema_version: str | None = None
                source_chunks: dict[str, dict[str, Any]] = {}

                while position < len(buffer):
                    position = _skip_json_whitespace(buffer, position)
                    if position >= len(buffer):
                        break
                    if buffer[position] == ord("}"):
                        break

                    key_end = _scan_json_string_end(buffer, position)
                    key = _decode_json_segment(buffer, position, key_end)
                    if not isinstance(key, str):
                        raise SystemExit(f"malformed top-level key in {source_json}")

                    position = _skip_json_whitespace(buffer, key_end)
                    if position >= len(buffer) or buffer[position] != ord(":"):
                        raise SystemExit(f"missing ':' after key {key!r} in {source_json}")

                    value_start = _skip_json_whitespace(buffer, position + 1)
                    if key == "schemaVersion":
                        value_end = _scan_json_value_end(buffer, value_start)
                        schema_value = _decode_json_segment(buffer, value_start, value_end)
                        if not isinstance(schema_value, str) or not schema_value:
                            raise SystemExit(f"missing schemaVersion in {source_json}")
                        schema_version = schema_value
                        position = value_end
                    elif key == "chunks":
                        position, extracted_chunks, completed_early = _extract_target_chunks_from_manifest(
                            buffer,
                            value_start,
                            target_chunk_id_set - set(source_chunks),
                            allow_early_return=schema_version is not None,
                        )
                        source_chunks.update(extracted_chunks)
                        if completed_early and schema_version is not None:
                            missing_chunks = [chunk_id for chunk_id in target_chunk_ids if chunk_id not in source_chunks]
                            if missing_chunks:
                                raise SystemExit(
                                    "missing chunk(s) " + ", ".join(missing_chunks) + f" in {source_json}"
                                )
                            return schema_version, source_chunks
                    else:
                        position = _scan_json_value_end(buffer, value_start)

                    position = _skip_json_whitespace(buffer, position)
                    if position < len(buffer) and buffer[position] == ord(","):
                        position += 1
                        continue
                    if position < len(buffer) and buffer[position] == ord("}"):
                        break

        except ValueError as exc:
            raise SystemExit(f"could not memory-map {source_json}: {exc}") from exc

    if schema_version is None:
        raise SystemExit(f"missing schemaVersion in {source_json}")

    missing_chunks = [chunk_id for chunk_id in target_chunk_ids if chunk_id not in source_chunks]
    if missing_chunks:
        raise SystemExit("missing chunk(s) " + ", ".join(missing_chunks) + f" in {source_json}")

    return schema_version, source_chunks


def parse_source_index(source_text: str) -> tuple[str, dict[str, dict[str, Any]]]:
    schema_match = SCHEMA_RE.search(source_text)
    if schema_match is None:
        raise SystemExit("could not parse schemaVersion from AustinManifestIndex.lua")

    chunk_refs: dict[str, dict[str, Any]] = {}
    for entry in _parse_chunk_ref_entries(source_text):
        chunk_id = entry.get("id")
        if not isinstance(chunk_id, str):
            raise SystemExit("could not parse chunkRef id from AustinManifestIndex.lua")
        origin_studs = entry.get("originStuds")
        if not isinstance(origin_studs, dict):
            raise SystemExit(f"could not parse originStuds for chunk {chunk_id}")
        if any(axis not in origin_studs for axis in ("x", "y", "z")):
            raise SystemExit(f"could not parse originStuds for chunk {chunk_id}")
        shard_names = entry.get("shards")
        if not isinstance(shard_names, list) or not all(isinstance(shard_name, str) for shard_name in shard_names):
            raise SystemExit(f"could not parse shards for chunk {chunk_id}")
        chunk_refs[chunk_id] = {
            "x": origin_studs["x"],
            "y": origin_studs["y"],
            "z": origin_studs["z"],
            "shards": shard_names,
        }
        if entry.get("featureCount") is not None:
            chunk_refs[chunk_id]["featureCount"] = entry["featureCount"]
        if entry.get("streamingCost") is not None:
            chunk_refs[chunk_id]["streamingCost"] = entry["streamingCost"]
        if entry.get("partitionVersion") is not None:
            chunk_refs[chunk_id]["partitionVersion"] = entry["partitionVersion"]
        if entry.get("subplans") is not None:
            chunk_refs[chunk_id]["subplans"] = entry["subplans"]

    return schema_match.group("schema"), chunk_refs


def parse_source_chunk_size_studs(source_text: str) -> float:
    match = CHUNK_SIZE_RE.search(source_text)
    if match is None:
        return float(DEFAULT_CHUNK_SIZE_STUDS)
    return float(match.group("chunk_size"))


def _coerce_float(value: Any) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and NUMERIC_STRING_RE.match(value):
        return float(value)
    raise SystemExit(f"expected numeric chunk coordinate, got {value!r}")


def derive_preview_chunk_ids(
    chunk_refs: dict[str, dict[str, Any]],
    *,
    seed_chunk_ids: list[str] | tuple[str, ...] = TARGET_CHUNK_IDS,
    chunk_size_studs: float = DEFAULT_CHUNK_SIZE_STUDS,
    load_radius_studs: float = PREVIEW_LOAD_RADIUS_STUDS,
    gutter_studs: float = PREVIEW_SELECTION_GUTTER_STUDS,
) -> list[str]:
    if not chunk_refs:
        return list(seed_chunk_ids)

    seed_centers: list[tuple[float, float]] = []
    for chunk_id in seed_chunk_ids:
        chunk_ref = chunk_refs.get(chunk_id)
        if chunk_ref is None:
            raise SystemExit(f"missing seed chunk {chunk_id} in AustinManifestIndex.lua")
        center_x = _coerce_float(chunk_ref["x"]) + chunk_size_studs * 0.5
        center_z = _coerce_float(chunk_ref["z"]) + chunk_size_studs * 0.5
        seed_centers.append((center_x, center_z))

    focus_x = sum(center_x for center_x, _ in seed_centers) / len(seed_centers)
    focus_z = sum(center_z for _, center_z in seed_centers) / len(seed_centers)
    selection_radius_sq = (load_radius_studs + gutter_studs) ** 2

    selected_chunk_ids: list[str] = []
    for chunk_id, chunk_ref in chunk_refs.items():
        center_x = _coerce_float(chunk_ref["x"]) + chunk_size_studs * 0.5
        center_z = _coerce_float(chunk_ref["z"]) + chunk_size_studs * 0.5
        dx = center_x - focus_x
        dz = center_z - focus_z
        if dx * dx + dz * dz <= selection_radius_sq:
            selected_chunk_ids.append(chunk_id)

    selected_chunk_ids.sort(key=lambda chunk_id: tuple(int(part) for part in chunk_id.split("_", 1)))
    return selected_chunk_ids


def resolve_source_sqlite_path(source_json: Path) -> Path:
    expected_sqlite = source_json.with_suffix(".sqlite")
    if SOURCE_SQLITE == expected_sqlite:
        return SOURCE_SQLITE
    return expected_sqlite


def compute_preview_canonical_anchor_position(
    source_chunks: dict[str, dict[str, Any]],
    *,
    seed_chunk_ids: list[str] | tuple[str, ...] = TARGET_CHUNK_IDS,
    chunk_size_studs: float = DEFAULT_CHUNK_SIZE_STUDS,
) -> tuple[float, float, float]:
    weighted_x = 0.0
    weighted_z = 0.0
    weighted_count = 0
    bounds: dict[str, float] = {}

    def accumulate_point(x: float, y: float, z: float) -> None:
        bounds["minX"] = min(bounds.get("minX", x), x)
        bounds["maxX"] = max(bounds.get("maxX", x), x)
        bounds["minY"] = min(bounds.get("minY", y), y)
        bounds["maxY"] = max(bounds.get("maxY", y), y)
        bounds["minZ"] = min(bounds.get("minZ", z), z)
        bounds["maxZ"] = max(bounds.get("maxZ", z), z)

    def accumulate_ground_y(y: float) -> None:
        bounds["minGroundY"] = min(bounds.get("minGroundY", y), y)
        bounds["maxGroundY"] = max(bounds.get("maxGroundY", y), y)

    def accumulate_focus(x: float, z: float) -> None:
        nonlocal weighted_x, weighted_z, weighted_count
        weighted_x += x
        weighted_z += z
        weighted_count += 1

    for chunk_id in seed_chunk_ids:
        chunk = source_chunks.get(chunk_id)
        if chunk is None:
            raise SystemExit(f"missing preview seed chunk {chunk_id} in {SOURCE_JSON}")
        origin = chunk.get("originStuds") or {"x": 0, "y": 0, "z": 0}
        origin_x = float(origin.get("x", 0))
        origin_y = float(origin.get("y", 0))
        origin_z = float(origin.get("z", 0))

        if not chunk.get("roads") and not chunk.get("buildings") and not chunk.get("props"):
            accumulate_point(origin_x, origin_y, origin_z)
            accumulate_point(origin_x + chunk_size_studs, origin_y, origin_z + chunk_size_studs)
            accumulate_ground_y(origin_y)

        terrain = chunk.get("terrain")
        if isinstance(terrain, dict) and isinstance(terrain.get("heights"), list):
            for height in terrain["heights"]:
                accumulate_ground_y(origin_y + float(height or 0))

        for road in chunk.get("roads", []):
            for point in road.get("points", []):
                world_x = origin_x + float(point.get("x", 0))
                world_y = origin_y + float(point.get("y", 0))
                world_z = origin_z + float(point.get("z", 0))
                accumulate_point(world_x, world_y, world_z)
                accumulate_ground_y(world_y)
                accumulate_focus(world_x, world_z)

        for building in chunk.get("buildings", []):
            base_y = origin_y + float(building.get("baseY") or 0)
            for point in building.get("footprint", []):
                world_x = origin_x + float(point.get("x", 0))
                world_z = origin_z + float(point.get("z", 0))
                accumulate_point(world_x, base_y, world_z)
                accumulate_focus(world_x, world_z)
            accumulate_ground_y(base_y)

        for prop in chunk.get("props", []):
            position = prop.get("position")
            if isinstance(position, dict):
                world_x = origin_x + float(position.get("x", 0))
                world_y = origin_y + float(position.get("y", 0))
                world_z = origin_z + float(position.get("z", 0))
                accumulate_point(world_x, world_y, world_z)
                accumulate_focus(world_x, world_z)

    if not bounds:
        return (0.0, 0.0, 0.0)

    if weighted_count > 0:
        heuristic_focus_x = weighted_x / weighted_count
        heuristic_focus_z = weighted_z / weighted_count
    else:
        heuristic_focus_x = (bounds["minX"] + bounds["maxX"]) * 0.5
        heuristic_focus_z = (bounds["minZ"] + bounds["maxZ"]) * 0.5

    if "minGroundY" in bounds and "maxGroundY" in bounds:
        heuristic_focus_y = (bounds["minGroundY"] + bounds["maxGroundY"]) * 0.5
    else:
        heuristic_focus_y = (bounds["minY"] + bounds["maxY"]) * 0.5

    best_point: tuple[float, float, float] | None = None
    best_score: float | None = None
    for chunk_id in seed_chunk_ids:
        chunk = source_chunks[chunk_id]
        origin = chunk.get("originStuds") or {"x": 0, "y": 0, "z": 0}
        origin_x = float(origin.get("x", 0))
        origin_y = float(origin.get("y", 0))
        origin_z = float(origin.get("z", 0))
        for road in chunk.get("roads", []):
            kind = road.get("kind")
            if kind in EXCLUDED_SPAWN_KINDS:
                continue
            priority = ROAD_PRIORITY.get(kind, 65)
            points = road.get("points") or []
            for index in range(len(points) - 1):
                p1 = points[index]
                p2 = points[index + 1]
                mid_x = origin_x + (float(p1.get("x", 0)) + float(p2.get("x", 0))) * 0.5
                mid_y = origin_y + (float(p1.get("y", 0)) + float(p2.get("y", 0))) * 0.5
                mid_z = origin_z + (float(p1.get("z", 0)) + float(p2.get("z", 0))) * 0.5
                if abs(mid_y - heuristic_focus_y) > 18:
                    continue
                dx = mid_x - heuristic_focus_x
                dz = mid_z - heuristic_focus_z
                score = priority * 100000000 + dx * dx + dz * dz
                if best_score is None or score < best_score:
                    best_score = score
                    best_point = (mid_x, mid_y, mid_z)

    spawn_x, spawn_y, spawn_z = best_point or (heuristic_focus_x, heuristic_focus_y, heuristic_focus_z)
    return (spawn_x, spawn_y, spawn_z + AUSTIN_SOUTH_OF_CAPITOL_OFFSET_STUDS)


def _coerce_feature_count(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def count_chunk_features(chunk: dict[str, Any]) -> int:
    total = 1 if isinstance(chunk.get("terrain"), dict) else 0
    for field in COUNTED_FEATURE_FIELDS:
        values = chunk.get(field)
        if isinstance(values, list):
            total += len(values)
    return total


def compute_preview_total_features(
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


def write_preview_index(
    schema_version: str,
    total_features: int,
    chunk_refs: list[tuple[str, dict[str, Any]]],
    shard_names: list[str],
    *,
    canonical_anchor_position: tuple[float, float, float],
    chunk_size_studs: float,
    output_path: Path | None = None,
    world_name: str = "AustinPreviewDowntown",
    shard_folder: str = "AustinPreviewManifestChunks",
    notes: tuple[str, str] = (
        "studio preview subset derived from rust/out/austin-manifest.json",
        "kept in sync with runtime sample-data generation to avoid stale preview drift",
    ),
) -> None:
    output_path = PREVIEW_INDEX if output_path is None else output_path
    anchor_x, anchor_y, anchor_z = canonical_anchor_position

    lines = [
        "return {",
        f'    schemaVersion = "{schema_version}",',
        "    meta = {",
        f'        worldName = "{world_name}",',
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
        f'            "{notes[0]}",',
        f'            "{notes[1]}",',
        "        },",
        "    },",
        f'    shardFolder = "{shard_folder}",',
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

    for _, (chunk_id, chunk_ref) in enumerate(chunk_refs, start=1):
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
        chunk_shards = chunk_ref["shards"]
        shard_list = ", ".join(f'"{shard_name}"' for shard_name in chunk_shards)
        lines.append(f"            shards = {{ {shard_list} }},")
        lines.append("        },")

    lines.extend(["    },", "}", ""])
    output_path.write_text("\n".join(lines), encoding="utf-8")


def clone_chunk_ref_entries(chunk_refs: list[tuple[str, dict[str, Any]]]) -> list[tuple[str, dict[str, Any]]]:
    cloned: list[tuple[str, dict[str, Any]]] = []
    for chunk_id, chunk_ref in chunk_refs:
        cloned.append((chunk_id, _parse_lua_value(_format_lua_value(chunk_ref))))
    return cloned


def write_preview_style_shards(
    chunk_refs: list[tuple[str, dict[str, Any]]],
    source_chunks: dict[str, dict[str, Any]],
    *,
    shards_dir: Path,
    shard_prefix: str,
) -> list[str]:
    shutil.rmtree(shards_dir, ignore_errors=True)
    shards_dir.mkdir(parents=True, exist_ok=True)

    shard_names: list[str] = []
    shard_index = 1
    for chunk_id, chunk_ref in chunk_refs:
        chunk = source_chunks[chunk_id]
        fragments = fragment_preview_chunk(chunk, MAX_PREVIEW_BYTES)
        for fragment in fragments:
            shard_name = f"{shard_prefix}_{shard_index:03d}"
            write_lua_module(shards_dir / f"{shard_name}.lua", {"chunks": [fragment]})
            chunk_ref["shards"].append(shard_name)
            shard_names.append(shard_name)
            shard_index += 1
    return shard_names


def base_preview_chunk_fragment(chunk: dict) -> dict:
    fragment: dict = {"id": chunk["id"]}
    for key, value in chunk.items():
        if key == "id":
            continue
        if key in INDEX_ONLY_FIELDS:
            continue
        if key in CHUNK_LIST_FIELDS and isinstance(value, list):
            continue
        if key == "terrain" and isinstance(value, dict):
            terrain_fragment = {
                nested_key: nested_value
                for nested_key, nested_value in value.items()
                if nested_key not in {"heights", "materials"}
            }
            if terrain_fragment:
                fragment[key] = terrain_fragment
            continue
        fragment[key] = value
    return fragment


def chunk_fragment_len(fragment: dict) -> int:
    return lua_len({"chunks": [fragment]})


def fragment_list_payloads(
    chunk_id: str,
    values: list[Any],
    max_bytes: int,
    field_label: str,
    fragment_builder,
) -> list[dict]:
    fragments: list[dict] = []

    start = 0
    while start < len(values):
        low = start + 1
        high = len(values)
        best_end = start

        while low <= high:
            mid = (low + high) // 2
            if chunk_fragment_len(fragment_builder(values[start:mid])) <= max_bytes:
                best_end = mid
                low = mid + 1
            else:
                high = mid - 1

        if best_end == start:
            raise SystemExit(f"preview chunk {chunk_id} {field_label} contains an entry larger than max bytes {max_bytes}")

        fragments.append(fragment_builder(values[start:best_end]))
        start = best_end

    return fragments


def fragment_preview_chunk(chunk: dict, max_bytes: int) -> list[dict]:
    fragments: list[dict] = []

    base_fragment = base_preview_chunk_fragment(chunk)
    if chunk_fragment_len(base_fragment) > max_bytes:
        raise SystemExit(f"preview chunk {chunk.get('id')} base metadata exceeds max bytes {max_bytes}")
    fragments.append(base_fragment)

    terrain = chunk.get("terrain")
    if isinstance(terrain, dict):
        for terrain_key in ("heights", "materials"):
            terrain_value = terrain.get(terrain_key)
            if terrain_value is None:
                continue
            if isinstance(terrain_value, list):
                fragments.extend(
                    fragment_list_payloads(
                        chunk["id"],
                        terrain_value,
                        max_bytes,
                        f"terrain field {terrain_key}",
                        lambda items: {
                            "id": chunk["id"],
                            "terrain": {
                                terrain_key: list(items),
                            },
                        },
                    )
                )
                continue

            fragment = {
                "id": chunk["id"],
                "terrain": {
                    terrain_key: terrain_value,
                },
            }
            if chunk_fragment_len(fragment) > max_bytes:
                raise SystemExit(
                    f"preview chunk {chunk.get('id')} terrain field {terrain_key} exceeds max bytes {max_bytes}"
                )
            fragments.append(fragment)

    for field in CHUNK_LIST_FIELDS:
        values = chunk.get(field)
        if not isinstance(values, list) or not values:
            continue

        fragments.extend(
            fragment_list_payloads(
                chunk["id"],
                values,
                max_bytes,
                f"field {field}",
                lambda items: {"id": chunk["id"], field: list(items)},
            )
        )

    return fragments


def main() -> int:
    source_text = SOURCE_INDEX.read_text(encoding="utf-8")
    _, source_chunk_refs = parse_source_index(source_text)
    chunk_size_studs = parse_source_chunk_size_studs(source_text)
    preview_chunk_ids = derive_preview_chunk_ids(source_chunk_refs, chunk_size_studs=chunk_size_studs)
    source_sqlite = resolve_source_sqlite_path(SOURCE_JSON)
    schema_version, source_chunks = load_source_manifest_subset(
        SOURCE_JSON, preview_chunk_ids, source_sqlite=source_sqlite
    )
    canonical_anchor_position = compute_preview_canonical_anchor_position(
        source_chunks,
        chunk_size_studs=chunk_size_studs,
    )

    preview_chunk_refs: list[tuple[str, dict[str, Any]]] = []
    for chunk_id in preview_chunk_ids:
        chunk_ref = source_chunk_refs.get(chunk_id)
        if chunk_ref is None:
            raise SystemExit(f"missing chunk {chunk_id} in AustinManifestIndex.lua")
        source_chunk = source_chunks.get(chunk_id)
        if source_chunk is None:
            raise SystemExit(f"missing chunk {chunk_id} in {SOURCE_JSON}")
        origin_studs = source_chunk.get("originStuds")
        if not isinstance(origin_studs, dict) or any(axis not in origin_studs for axis in ("x", "y", "z")):
            raise SystemExit(f"missing canonical originStuds for chunk {chunk_id} in {SOURCE_JSON}")
        preview_chunk_ref: dict[str, Any] = {
            "x": origin_studs["x"],
            "y": origin_studs["y"],
            "z": origin_studs["z"],
            "shards": [],
        }
        if chunk_ref.get("featureCount") is not None:
            preview_chunk_ref["featureCount"] = chunk_ref["featureCount"]
        if chunk_ref.get("streamingCost") is not None:
            preview_chunk_ref["streamingCost"] = chunk_ref["streamingCost"]
        if chunk_ref.get("partitionVersion") is not None:
            preview_chunk_ref["partitionVersion"] = chunk_ref["partitionVersion"]
        if chunk_ref.get("subplans") is not None:
            preview_chunk_ref["subplans"] = chunk_ref["subplans"]
        preview_chunk_refs.append(
            (
                chunk_id,
                preview_chunk_ref,
            )
        )

    preview_chunk_refs_for_index = clone_chunk_ref_entries(preview_chunk_refs)
    canonical_chunk_refs_for_index = clone_chunk_ref_entries(preview_chunk_refs)
    shard_names = write_preview_style_shards(
        preview_chunk_refs_for_index,
        source_chunks,
        shards_dir=PREVIEW_SHARDS,
        shard_prefix="AustinPreviewManifestIndex",
    )
    canonical_shard_names = write_preview_style_shards(
        canonical_chunk_refs_for_index,
        source_chunks,
        shards_dir=CANONICAL_SHARDS,
        shard_prefix="AustinCanonicalManifestIndex",
    )
    total_features = compute_preview_total_features(preview_chunk_refs, source_chunks)
    write_preview_index(
        schema_version,
        total_features,
        preview_chunk_refs_for_index,
        shard_names,
        canonical_anchor_position=canonical_anchor_position,
        chunk_size_studs=chunk_size_studs,
        output_path=PREVIEW_INDEX,
    )
    write_preview_index(
        schema_version,
        total_features,
        canonical_chunk_refs_for_index,
        canonical_shard_names,
        canonical_anchor_position=canonical_anchor_position,
        chunk_size_studs=chunk_size_studs,
        output_path=CANONICAL_INDEX,
        world_name="AustinCanonicalBounded",
        shard_folder="AustinCanonicalManifestChunks",
        notes=(
            "bounded canonical full-bake subset derived from rust/out/austin-manifest.json",
            "kept in sync with Studio preview generation to prevent edit/play/export drift",
        ),
    )

    print(f"Refreshed StudioPreview from {SOURCE_JSON}")
    print(f"Selected {len(preview_chunk_ids)} preview chunks from AustinManifestIndex.lua")
    print(f"Wrote {len(shard_names)} preview shards to {PREVIEW_SHARDS}")
    print(f"Wrote {len(canonical_shard_names)} canonical sample-data shards to {CANONICAL_SHARDS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
