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
MAX_PREVIEW_BYTES = 199_999

TARGET_CHUNK_IDS = ["-1_-1", "0_-1", "-1_0", "0_0"]

CHUNK_REF_RE = re.compile(
    r'\{\s*id\s*=\s*"(?P<id>[^"]+)"(?P<body>[\s\S]*?)shards\s*=\s*\{(?P<shards>[\s\S]*?)\}\s*,?\s*\}',
    re.MULTILINE,
)
SCHEMA_RE = re.compile(r'return \{schemaVersion="(?P<schema>[^"]+)"')
ORIGIN_RE = re.compile(r"originStuds\s*=\s*\{\s*x\s*=\s*(?P<x>[^,]+),\s*y\s*=\s*(?P<y>[^,]+),\s*z\s*=\s*(?P<z>[^}]+)\s*\}")
FEATURE_COUNT_RE = re.compile(r"featureCount\s*=\s*(?P<value>\d+)")
STREAMING_COST_RE = re.compile(r"streamingCost\s*=\s*(?P<value>\d+)")
SHARD_NAME_RE = re.compile(r'"([^"]+)"')
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
    for match in CHUNK_REF_RE.finditer(source_text):
        body = match.group("body")
        origin_match = ORIGIN_RE.search(body)
        if origin_match is None:
            raise SystemExit(f'could not parse originStuds for chunk {match.group("id")}')
        chunk_refs[match.group("id")] = {
            "x": origin_match.group("x"),
            "y": origin_match.group("y"),
            "z": origin_match.group("z"),
            "shards": SHARD_NAME_RE.findall(match.group("shards")),
        }
        feature_count_match = FEATURE_COUNT_RE.search(body)
        if feature_count_match is not None:
            chunk_refs[match.group("id")]["featureCount"] = feature_count_match.group("value")
        streaming_cost_match = STREAMING_COST_RE.search(body)
        if streaming_cost_match is not None:
            chunk_refs[match.group("id")]["streamingCost"] = streaming_cost_match.group("value")
        partition_version_match = re.search(r'partitionVersion\s*=\s*"(?P<value>[^"]+)"', body)
        if partition_version_match is not None:
            chunk_refs[match.group("id")]["partitionVersion"] = partition_version_match.group("value")
        subplans_text = _extract_lua_table(body, "subplans")
        if subplans_text is not None:
            chunk_refs[match.group("id")]["subplans"] = _parse_lua_table_value(subplans_text)

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

        current = {"id": chunk["id"], field: []}
        for item in values:
            current[field].append(item)
            if chunk_fragment_len(current) <= max_bytes:
                continue

            current[field].pop()
            if not current[field]:
                raise SystemExit(f"preview chunk {chunk.get('id')} field {field} contains an entry larger than max bytes {max_bytes}")
            fragments.append(current)
            current = {"id": chunk["id"], field: [item]}
            if chunk_fragment_len(current) > max_bytes:
                raise SystemExit(f"preview chunk {chunk.get('id')} field {field} contains an entry larger than max bytes {max_bytes}")

        if current[field]:
            fragments.append(current)

    return fragments


def main() -> int:
    source_text = SOURCE_INDEX.read_text(encoding="utf-8")
    schema_version, source_chunk_refs = parse_source_index(source_text)
    source_manifest = json.loads(SOURCE_JSON.read_text(encoding="utf-8"))
    source_chunks = {chunk["id"]: chunk for chunk in source_manifest.get("chunks", [])}

    preview_chunk_refs: list[tuple[str, dict[str, Any]]] = []
    for chunk_id in TARGET_CHUNK_IDS:
        chunk_ref = source_chunk_refs.get(chunk_id)
        if chunk_ref is None:
            raise SystemExit(f"missing chunk {chunk_id} in AustinManifestIndex.lua")
        if chunk_id not in source_chunks:
            raise SystemExit(f"missing chunk {chunk_id} in {SOURCE_JSON}")
        preview_chunk_refs.append(
            (
                chunk_id,
                {
                    "x": chunk_ref["x"],
                    "y": chunk_ref["y"],
                    "z": chunk_ref["z"],
                    "featureCount": chunk_ref.get("featureCount"),
                    "streamingCost": chunk_ref.get("streamingCost"),
                    "shards": [],
                },
            )
        )
        if chunk_ref.get("partitionVersion") is not None:
            preview_chunk_refs[-1][1]["partitionVersion"] = chunk_ref["partitionVersion"]
        if chunk_ref.get("subplans") is not None:
            preview_chunk_refs[-1][1]["subplans"] = chunk_ref["subplans"]

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
