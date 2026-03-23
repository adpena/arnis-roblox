#!/usr/bin/env python3
"""
Refresh the Studio preview manifest from the current exported Austin JSON manifest.

This keeps edit-mode preview aligned with the same authoritative manifest content
used to generate runtime sample-data, instead of relying on stale checked-in
preview fixtures or copying runtime Lua shards wholesale.
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path
from typing import Any

from json_manifest_to_sharded_lua import CHUNK_LIST_FIELDS, INDEX_ONLY_FIELDS, lua_len, write_lua_module


ROOT = Path(__file__).resolve().parents[1]
SOURCE_INDEX = ROOT / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestIndex.lua"
SOURCE_JSON = ROOT / "rust" / "out" / "austin-manifest.json"
PREVIEW_DIR = ROOT / "roblox" / "src" / "ServerScriptService" / "StudioPreview"
PREVIEW_INDEX = PREVIEW_DIR / "AustinPreviewManifestIndex.lua"
PREVIEW_SHARDS = PREVIEW_DIR / "AustinPreviewManifestChunks"
MAX_PREVIEW_BYTES = 199_998

TARGET_CHUNK_IDS = ["-1_-1", "0_-1", "-1_0", "0_0"]

SCHEMA_RE = re.compile(r'return \{schemaVersion="(?P<schema>[^"]+)"')
NUMERIC_STRING_RE = re.compile(r"^-?\d+(?:\.\d+)?$")


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


def write_preview_index(schema_version: str, chunk_refs: list[tuple[str, dict[str, Any]]], shard_names: list[str]) -> None:

    lines = [
        "return {",
        f'    schemaVersion = "{schema_version}",',
        "    meta = {",
        '        worldName = "AustinPreviewDowntown",',
        '        generator = "arbx_roblox_export",',
        '        source = "pipeline-export",',
        "        metersPerStud = 1,",
        "        chunkSizeStuds = 256,",
        "        bbox = { minLat = 30.245, minLon = -97.765, maxLat = 30.305, maxLon = -97.715 },",
        "        canonicalAnchor = {",
        "            positionOffsetFromHeuristicStuds = { x = 0, y = 0, z = -192 },",
        "            lookDirectionStuds = { x = 0, y = 0, z = 1 },",
        "        },",
        "        notes = {",
        '            "studio preview subset derived from rust/out/austin-manifest.json",',
        '            "kept in sync with runtime sample-data generation to avoid stale preview drift",',
        "        },",
        "    },",
        '    shardFolder = "AustinPreviewManifestChunks",',
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
    PREVIEW_INDEX.write_text("\n".join(lines), encoding="utf-8")


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
    source_manifest = json.loads(SOURCE_JSON.read_text(encoding="utf-8"))
    schema_version = source_manifest.get("schemaVersion")
    if not isinstance(schema_version, str) or not schema_version:
        raise SystemExit(f"missing schemaVersion in {SOURCE_JSON}")
    source_chunks = {chunk["id"]: chunk for chunk in source_manifest.get("chunks", [])}

    preview_chunk_refs: list[tuple[str, dict[str, Any]]] = []
    for chunk_id in TARGET_CHUNK_IDS:
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

    shutil.rmtree(PREVIEW_SHARDS, ignore_errors=True)
    PREVIEW_SHARDS.mkdir(parents=True, exist_ok=True)

    shard_names: list[str] = []
    shard_index = 1
    for chunk_id, chunk_ref in preview_chunk_refs:
        chunk = source_chunks[chunk_id]
        fragments = fragment_preview_chunk(chunk, MAX_PREVIEW_BYTES)
        for fragment in fragments:
            shard_name = f"AustinPreviewManifestIndex_{shard_index:03d}"
            write_lua_module(PREVIEW_SHARDS / f"{shard_name}.lua", {"chunks": [fragment]})
            chunk_ref["shards"].append(shard_name)
            shard_names.append(shard_name)
            shard_index += 1

    write_preview_index(schema_version, preview_chunk_refs, shard_names)

    print(f"Refreshed StudioPreview from {SOURCE_JSON}")
    print(f"Wrote {len(shard_names)} preview shards to {PREVIEW_SHARDS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
