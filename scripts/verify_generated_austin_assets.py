#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any


MAX_PREVIEW_BYTES = 199_999
EXPECTED_PREVIEW_CHUNK_IDS = {"-1_-1", "0_-1", "-1_0", "0_0"}
STALE_ROOMS_PATTERN = re.compile(r"\brooms\s*=\s*\{")
STALE_FACADE_PATTERN = re.compile(r"\bfacadeStyle\s*=")
PREVIEW_SPLIT_PATTERN = "AustinPreviewManifestIndex_*_*.lua"
CHUNK_COUNT_RE = re.compile(r"\bchunkCount\s*=\s*(\d+)")
FRAGMENT_COUNT_RE = re.compile(r"\bfragmentCount\s*=\s*(\d+)")
FEATURE_COUNT_RE = re.compile(r"\bfeatureCount\s*=\s*\d+")
STREAMING_COST_RE = re.compile(r"\bstreamingCost\s*=\s*\d+")
CHUNK_REF_RE = re.compile(
    r'\{\s*id\s*=\s*"(?P<id>[^"]+)"(?P<body>[\s\S]*?)shards\s*=\s*\{(?P<shards>[\s\S]*?)\}\s*,?\s*\}',
    re.MULTILINE,
)
SHARD_NAME_RE = re.compile(r"\"([^\"]+)\"")
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


def runtime_shard_dir(root: Path) -> Path:
    return root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestChunks"


def preview_dir(root: Path) -> Path:
    return root / "roblox" / "src" / "ServerScriptService" / "StudioPreview"


def preview_shard_dir(root: Path) -> Path:
    return preview_dir(root) / "AustinPreviewManifestChunks"


def preview_index_path(root: Path) -> Path:
    return preview_dir(root) / "AustinPreviewManifestIndex.lua"


def runtime_index_path(root: Path) -> Path:
    return root / "roblox" / "src" / "ServerStorage" / "SampleData" / "AustinManifestIndex.lua"


def _find_stale_fields(shard_paths: list[Path]) -> list[str]:
    stale_paths: list[str] = []
    for path in shard_paths:
        text = path.read_text(encoding="utf-8")
        if STALE_ROOMS_PATTERN.search(text) or STALE_FACADE_PATTERN.search(text):
            stale_paths.append(path.name)
    return stale_paths


def _parse_preview_chunk_refs(index_text: str) -> dict[str, list[str]]:
    chunk_refs: dict[str, list[str]] = {}
    for match in CHUNK_REF_RE.finditer(index_text):
        chunk_id = match.group("id")
        shard_names = SHARD_NAME_RE.findall(match.group("shards"))
        chunk_refs[chunk_id] = shard_names
    return chunk_refs


def _validate_chunk_subplans(chunk_id: str, body: str) -> list[str]:
    errors: list[str] = []
    subplans_text = _extract_lua_table(body, "subplans")
    if subplans_text is None:
        return errors

    if re.search(r'partitionVersion\s*=\s*"[^"]+"', body) is None:
        errors.append(f"chunk {chunk_id} has subplans but is missing partitionVersion")

    parsed_subplans = _parse_lua_table_value(subplans_text)
    if not isinstance(parsed_subplans, list):
        errors.append(f"chunk {chunk_id} has malformed subplans table")
        return errors

    required_fields = ("id", "layer", "featureCount", "streamingCost")
    for index, subplan in enumerate(parsed_subplans):
        if not isinstance(subplan, dict):
            errors.append(f"chunk {chunk_id} has malformed subplan entry at index {index}")
            continue

        missing_fields = [field for field in required_fields if field not in subplan]
        if missing_fields:
            errors.append(
                f"chunk {chunk_id} has malformed subplan {subplan.get('id', index)} missing "
                + ", ".join(missing_fields)
            )
            continue

        bounds = subplan.get("bounds")
        if bounds is not None and not isinstance(bounds, dict):
            errors.append(f"chunk {chunk_id} has malformed subplan {subplan['id']} bounds")

    return errors


def collect_errors(root: Path) -> list[str]:
    errors: list[str] = []

    sample_shards = sorted(runtime_shard_dir(root).glob("AustinManifestIndex_*.lua"))
    if not sample_shards:
        errors.append("missing runtime sample-data shard modules")
    else:
        stale_runtime = _find_stale_fields(sample_shards)
        if stale_runtime:
            errors.append(
                "runtime sample-data shards still contain stale synthetic rooms/facade styling: "
                + ", ".join(stale_runtime)
            )

    runtime_index = runtime_index_path(root)
    if runtime_index.exists() and sample_shards:
        runtime_index_text = runtime_index.read_text(encoding="utf-8")
        if FEATURE_COUNT_RE.search(runtime_index_text) is None or STREAMING_COST_RE.search(runtime_index_text) is None:
            errors.append("runtime index is missing chunk scheduling metadata")
        runtime_chunk_refs = _parse_preview_chunk_refs(runtime_index_text)
        referenced_runtime_shards = sorted(
            {shard_name for shard_names in runtime_chunk_refs.values() for shard_name in shard_names}
        )
        actual_runtime_shards = sorted(path.stem for path in sample_shards)
        missing_runtime_shards = sorted(set(referenced_runtime_shards) - set(actual_runtime_shards))
        if missing_runtime_shards:
            errors.append(
                "runtime index references missing runtime shard modules: "
                + ", ".join(missing_runtime_shards)
            )
        unreferenced_runtime_shards = sorted(set(actual_runtime_shards) - set(referenced_runtime_shards))
        if unreferenced_runtime_shards:
            errors.append(
                "runtime shard directory contains unreferenced runtime shard modules: "
                + ", ".join(unreferenced_runtime_shards)
            )

    preview_shards = sorted(preview_shard_dir(root).glob("AustinPreviewManifestIndex_*.lua"))
    if not preview_shards:
        errors.append("missing preview shard modules")
    else:
        oversize = [f"{path.name} ({path.stat().st_size} bytes)" for path in preview_shards if path.stat().st_size >= MAX_PREVIEW_BYTES]
        if oversize:
            errors.append(
                "preview shard modules exceed the VertigoSync Lua source limit: " + ", ".join(oversize)
            )

        stale_preview = _find_stale_fields(preview_shards)
        if stale_preview:
            errors.append(
                "preview shards still contain stale synthetic rooms/facade styling: "
                + ", ".join(stale_preview)
            )

    split_layout = sorted(preview_shard_dir(root).glob(PREVIEW_SPLIT_PATTERN))
    if split_layout:
        errors.append(
            "preview shard folder still mixes split and monolithic layouts: "
            + ", ".join(path.name for path in split_layout)
        )

    index_path = preview_index_path(root)
    if not index_path.exists():
        errors.append("missing preview index module")
        return errors

    index_text = index_path.read_text(encoding="utf-8")
    if FEATURE_COUNT_RE.search(index_text) is None or STREAMING_COST_RE.search(index_text) is None:
        errors.append("preview index is missing chunk scheduling metadata")
    chunk_refs = _parse_preview_chunk_refs(index_text)
    if not chunk_refs:
        errors.append("preview index does not contain any chunk refs")
        return errors

    for match in CHUNK_REF_RE.finditer(index_text):
        errors.extend(_validate_chunk_subplans(match.group("id"), match.group("body")))

    chunk_ids = set(chunk_refs)
    if chunk_ids != EXPECTED_PREVIEW_CHUNK_IDS:
        errors.append(
            "preview index chunk ids drifted from the expected Austin preview subset: "
            + ", ".join(sorted(chunk_ids))
        )

    referenced_shards = sorted({shard_name for shard_names in chunk_refs.values() for shard_name in shard_names})
    actual_shards = sorted(path.stem for path in preview_shards)
    missing_shards = sorted(set(referenced_shards) - set(actual_shards))
    if missing_shards:
        errors.append("preview index references missing preview shard modules: " + ", ".join(missing_shards))

    unreferenced_shards = sorted(set(actual_shards) - set(referenced_shards))
    if unreferenced_shards:
        errors.append("preview shard directory contains unreferenced shard modules: " + ", ".join(unreferenced_shards))

    chunk_count_match = CHUNK_COUNT_RE.search(index_text)
    if chunk_count_match is None:
        errors.append("preview index is missing chunkCount")
    else:
        chunk_count = int(chunk_count_match.group(1))
        if chunk_count != len(chunk_refs):
            errors.append(
                f"preview index chunkCount is {chunk_count}, expected {len(chunk_refs)}"
            )

    fragment_count_match = FRAGMENT_COUNT_RE.search(index_text)
    if fragment_count_match is None:
        errors.append("preview index is missing fragmentCount")
    else:
        fragment_count = int(fragment_count_match.group(1))
        if fragment_count != len(referenced_shards):
            errors.append(
                f"preview index fragmentCount is {fragment_count}, expected {len(referenced_shards)}"
            )

    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    errors = collect_errors(root)
    if errors:
        for error in errors:
            print(f"[verify_generated_austin_assets] ERROR: {error}")
        return 1

    print("[verify_generated_austin_assets] Generated Austin assets look consistent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
