#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from refresh_preview_from_sample_data import TARGET_CHUNK_IDS as PREVIEW_SELECTION_SEED_CHUNK_IDS
from refresh_preview_from_sample_data import derive_preview_chunk_ids, parse_source_chunk_size_studs


MAX_PREVIEW_BYTES = 199_999
STALE_ROOMS_PATTERN = re.compile(r"\brooms\s*=\s*\{")
STALE_FACADE_PATTERN = re.compile(r"\bfacadeStyle\s*=")
PREVIEW_SPLIT_PATTERN = "AustinPreviewManifestIndex_*_*.lua"
CHUNK_COUNT_RE = re.compile(r"\bchunkCount\s*=\s*(\d+)")
FRAGMENT_COUNT_RE = re.compile(r"\bfragmentCount\s*=\s*(\d+)")
NUMERIC_STRING_RE = re.compile(r"^-?\d+(?:\.\d+)?$")
INTEGER_STRING_RE = re.compile(r"^-?\d+$")


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


def _parse_index_chunk_ref_entries(index_text: str) -> list[dict[str, Any]]:
    chunk_refs_text = _extract_lua_table(index_text, "chunkRefs")
    if chunk_refs_text is None:
        return []

    parsed_chunk_refs = _parse_lua_table_value(chunk_refs_text)
    if not isinstance(parsed_chunk_refs, list):
        raise SystemExit("could not parse chunkRefs table")

    entries: list[dict[str, Any]] = []
    for index, chunk_ref in enumerate(parsed_chunk_refs):
        if not isinstance(chunk_ref, dict):
            raise SystemExit(f"could not parse chunkRef entry at index {index}")
        entries.append(chunk_ref)
    return entries


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
    for chunk_ref in _parse_index_chunk_ref_entries(index_text):
        chunk_id = chunk_ref.get("id")
        shard_names = chunk_ref.get("shards")
        if not isinstance(chunk_id, str):
            continue
        if not isinstance(shard_names, list) or not all(isinstance(shard_name, str) for shard_name in shard_names):
            continue
        chunk_refs[chunk_id] = shard_names
    return chunk_refs


def _is_string_scalar(value: Any) -> bool:
    return isinstance(value, str)


def _is_numeric_scalar(value: Any) -> bool:
    return isinstance(value, str) and NUMERIC_STRING_RE.match(value) is not None


def _is_integer_scalar(value: Any) -> bool:
    return isinstance(value, str) and INTEGER_STRING_RE.match(value) is not None


def _validate_chunk_scheduling_metadata(chunk_ref: dict[str, Any], *, label: str) -> list[str]:
    errors: list[str] = []
    chunk_id = chunk_ref.get("id", "<unknown>")
    has_subplans = chunk_ref.get("subplans") is not None

    feature_count = chunk_ref.get("featureCount")
    if feature_count is None:
        if not has_subplans:
            errors.append(f"{label} chunk {chunk_id} is missing featureCount")
    elif not _is_integer_scalar(feature_count):
        errors.append(f"{label} chunk {chunk_id} has malformed featureCount")

    streaming_cost = chunk_ref.get("streamingCost")
    if streaming_cost is None:
        if not has_subplans:
            errors.append(f"{label} chunk {chunk_id} is missing streamingCost")
    elif not _is_numeric_scalar(streaming_cost):
        errors.append(f"{label} chunk {chunk_id} has malformed streamingCost")

    return errors


def _validate_chunk_subplans(chunk_ref: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    chunk_id = chunk_ref.get("id", "<unknown>")
    parsed_subplans = chunk_ref.get("subplans")
    if parsed_subplans is None:
        return errors

    if not _is_string_scalar(chunk_ref.get("partitionVersion")):
        errors.append(f"chunk {chunk_id} has subplans but is missing partitionVersion")

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

        if not _is_string_scalar(subplan["id"]):
            errors.append(f"chunk {chunk_id} has malformed subplan {index} id")
        if not _is_string_scalar(subplan["layer"]):
            errors.append(f"chunk {chunk_id} has malformed subplan {subplan.get('id', index)} layer")
        if not _is_integer_scalar(subplan["featureCount"]):
            errors.append(f"chunk {chunk_id} has malformed subplan {subplan.get('id', index)} featureCount")
        if not _is_numeric_scalar(subplan["streamingCost"]):
            errors.append(f"chunk {chunk_id} has malformed subplan {subplan.get('id', index)} streamingCost")

        bounds = subplan.get("bounds")
        if bounds is not None:
            if not isinstance(bounds, dict):
                errors.append(f"chunk {chunk_id} has malformed subplan {subplan['id']} bounds")
            else:
                for key in ("minX", "minY", "maxX", "maxY"):
                    if key not in bounds:
                        errors.append(f"chunk {chunk_id} has malformed subplan {subplan['id']} bounds missing {key}")
                    elif not _is_numeric_scalar(bounds[key]):
                        errors.append(f"chunk {chunk_id} has malformed subplan {subplan['id']} bounds {key}")

    return errors


def _validate_index_total_features(
    index_text: str,
    chunk_ref_entries: list[dict[str, Any]],
    *,
    label: str,
) -> list[str]:
    errors: list[str] = []
    meta_text = _extract_lua_table(index_text, "meta")
    if meta_text is None:
        return errors

    parsed_meta = _parse_lua_table_value(meta_text)
    if not isinstance(parsed_meta, dict):
        errors.append(f"{label} index meta is malformed")
        return errors

    total_features = parsed_meta.get("totalFeatures")
    if total_features is None:
        if label == "preview":
            errors.append(f"{label} index meta is missing totalFeatures")
        return errors
    if not _is_integer_scalar(total_features):
        errors.append(f"{label} index meta has malformed totalFeatures")
        return errors

    expected_total_features = 0
    has_expected_total = False
    for chunk_ref in chunk_ref_entries:
        feature_count = chunk_ref.get("featureCount")
        if _is_integer_scalar(feature_count):
            expected_total_features += int(feature_count)
            has_expected_total = True

    if has_expected_total and int(total_features) != expected_total_features:
        errors.append(
            f"{label} index meta totalFeatures is {total_features}, expected {expected_total_features}"
        )

    return errors


def _coerce_int_scalar(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if _is_integer_scalar(value):
        return int(value)
    return None


def _merge_fragment_value(existing: Any, incoming: Any) -> Any:
    if isinstance(existing, list) and isinstance(incoming, list):
        return [*existing, *incoming]
    if isinstance(existing, dict) and isinstance(incoming, dict):
        merged = dict(existing)
        for key, value in incoming.items():
            if key in merged:
                merged[key] = _merge_fragment_value(merged[key], value)
            else:
                merged[key] = value
        return merged
    return existing if existing is not None else incoming


def _parse_preview_shard_chunks(path: Path) -> list[dict[str, Any]]:
    shard_text = path.read_text(encoding="utf-8")
    chunks_text = _extract_lua_table(shard_text, "chunks")
    if chunks_text is None:
        raise SystemExit(f"could not parse chunks table from {path}")

    parsed_chunks = _parse_lua_table_value(chunks_text)
    if not isinstance(parsed_chunks, list):
        raise SystemExit(f"could not parse chunks table from {path}")

    chunk_entries: list[dict[str, Any]] = []
    for index, chunk in enumerate(parsed_chunks):
        if not isinstance(chunk, dict):
            raise SystemExit(f"could not parse chunk entry {index} from {path}")
        chunk_entries.append(chunk)
    return chunk_entries


def _materialize_preview_chunk(chunk_id: str, shard_names: list[str], shard_paths_by_name: dict[str, Path]) -> dict[str, Any]:
    materialized: dict[str, Any] = {}
    for shard_name in shard_names:
        shard_path = shard_paths_by_name.get(shard_name)
        if shard_path is None:
            continue
        for chunk in _parse_preview_shard_chunks(shard_path):
            if chunk.get("id") != chunk_id:
                continue
            for key, value in chunk.items():
                if key == "id":
                    materialized[key] = value
                elif key in materialized:
                    materialized[key] = _merge_fragment_value(materialized[key], value)
                else:
                    materialized[key] = value
    return materialized


def _validate_preview_terrain_payloads(
    chunk_refs: dict[str, list[str]],
    shard_paths_by_name: dict[str, Path],
) -> list[str]:
    errors: list[str] = []

    for chunk_id, shard_names in chunk_refs.items():
        materialized = _materialize_preview_chunk(chunk_id, shard_names, shard_paths_by_name)
        terrain = materialized.get("terrain")
        if not isinstance(terrain, dict):
            continue

        width = _coerce_int_scalar(terrain.get("width"))
        depth = _coerce_int_scalar(terrain.get("depth"))
        if width is None or depth is None:
            continue

        expected_cells = width * depth
        heights = terrain.get("heights")
        if not isinstance(heights, list):
            errors.append(f"preview chunk {chunk_id} terrain is missing heights after shard merge")
            continue
        if len(heights) != expected_cells:
            errors.append(
                f"preview chunk {chunk_id} terrain heights length is {len(heights)}, expected {expected_cells}"
            )

        materials = terrain.get("materials")
        if materials is not None:
            if not isinstance(materials, list):
                errors.append(f"preview chunk {chunk_id} terrain materials payload is malformed after shard merge")
            elif len(materials) != expected_cells:
                errors.append(
                    f"preview chunk {chunk_id} terrain materials length is {len(materials)}, expected {expected_cells}"
                )

    return errors


def collect_errors(root: Path) -> list[str]:
    errors: list[str] = []
    expected_preview_chunk_ids: set[str] | None = None

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
        runtime_chunk_ref_entries = _parse_index_chunk_ref_entries(runtime_index_text)
        runtime_chunk_refs = _parse_preview_chunk_refs(runtime_index_text)
        runtime_chunk_ref_map = {
            chunk_ref["id"]: {
                "x": chunk_ref.get("originStuds", {}).get("x"),
                "y": chunk_ref.get("originStuds", {}).get("y"),
                "z": chunk_ref.get("originStuds", {}).get("z"),
                "shards": chunk_ref.get("shards") or [],
            }
            for chunk_ref in runtime_chunk_ref_entries
            if isinstance(chunk_ref.get("id"), str)
        }
        if all(chunk_id in runtime_chunk_ref_map for chunk_id in PREVIEW_SELECTION_SEED_CHUNK_IDS):
            runtime_chunk_size_studs = parse_source_chunk_size_studs(runtime_index_text)
            expected_preview_chunk_ids = set(
                derive_preview_chunk_ids(
                    runtime_chunk_ref_map,
                    seed_chunk_ids=PREVIEW_SELECTION_SEED_CHUNK_IDS,
                    chunk_size_studs=runtime_chunk_size_studs,
                )
            )
        errors.extend(
            _validate_index_total_features(
                runtime_index_text,
                runtime_chunk_ref_entries,
                label="runtime",
            )
        )
        for chunk_ref in runtime_chunk_ref_entries:
            errors.extend(_validate_chunk_scheduling_metadata(chunk_ref, label="runtime"))
            errors.extend(_validate_chunk_subplans(chunk_ref))
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
    preview_chunk_ref_entries = _parse_index_chunk_ref_entries(index_text)
    chunk_refs = _parse_preview_chunk_refs(index_text)
    if not chunk_refs:
        errors.append("preview index does not contain any chunk refs")
        return errors

    errors.extend(
        _validate_index_total_features(
            index_text,
            preview_chunk_ref_entries,
            label="preview",
        )
    )

    for chunk_ref in preview_chunk_ref_entries:
        errors.extend(_validate_chunk_scheduling_metadata(chunk_ref, label="preview"))
        errors.extend(_validate_chunk_subplans(chunk_ref))

    chunk_ids = set(chunk_refs)
    if expected_preview_chunk_ids is not None and chunk_ids != expected_preview_chunk_ids:
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
    else:
        shard_paths_by_name = {path.stem: path for path in preview_shards}
        errors.extend(_validate_preview_terrain_payloads(chunk_refs, shard_paths_by_name))

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
