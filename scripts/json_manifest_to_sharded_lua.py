#!/usr/bin/env python3
"""
Convert a large JSON manifest into a sharded Lua manifest layout suitable for
Roblox Studio sync/runtime loading.

Outputs:
  - <output-dir>/<index-name>.lua
  - <output-dir>/<shard-folder>/<index-name>_NNN.lua

The index module includes lightweight chunk refs so runtime code can resolve a
chunk to its shard modules without loading the entire manifest up front.
"""

import argparse
import json
import io
from pathlib import Path
from typing import Any, TextIO


def to_lua(value: Any, out: TextIO, indent: int = 0) -> None:
    if isinstance(value, dict):
        out.write("{")
        items = list(value.items())
        for i, (k, v) in enumerate(items):
            out.write(f"{k}=")
            to_lua(v, out, indent + 2)
            if i + 1 != len(items):
                out.write(",")
        out.write("}")
    elif isinstance(value, list):
        out.write("{")
        for i, v in enumerate(value):
            to_lua(v, out, indent + 2)
            if i + 1 != len(value):
                out.write(",")
        out.write("}")
    elif isinstance(value, str):
        escaped = (
            value.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
        )
        out.write(f'"{escaped}"')
    elif isinstance(value, bool):
        out.write("true" if value else "false")
    elif value is None:
        out.write("nil")
    else:
        out.write(str(value))


def write_lua_module(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as out:
        out.write("return ")
        to_lua(data, out, indent=0)
        out.write("\n")


def lua_len(value: Any) -> int:
    out = io.StringIO()
    out.write("return ")
    to_lua(value, out, indent=0)
    out.write("\n")
    return len(out.getvalue().encode("utf-8"))


def clear_existing_shards(shard_dir: Path, index_name: str) -> None:
    if not shard_dir.exists():
        return
    pattern = f"{index_name}_*.lua"
    for existing in shard_dir.glob(pattern):
        existing.unlink()


CHUNK_LIST_FIELDS = [
    "roads",
    "rails",
    "buildings",
    "water",
    "props",
    "landuse",
    "barriers",
    "rooms",
]
INDEX_ONLY_FIELDS = {
    "partitionVersion",
    "subplans",
}


def empty_chunk_fragment(chunk: dict[str, Any]) -> dict[str, Any]:
    fragment = {}
    for key, value in chunk.items():
        if key in INDEX_ONLY_FIELDS:
            continue
        if key in CHUNK_LIST_FIELDS and isinstance(value, list):
            fragment[key] = []
        else:
            fragment[key] = value
    return fragment


def fragment_chunk(chunk: dict[str, Any], max_bytes: int | None) -> list[dict[str, Any]]:
    if max_bytes is None:
        return [chunk]

    base = empty_chunk_fragment(chunk)
    if lua_len({"chunks": [base]}) > max_bytes:
        raise SystemExit(f"chunk {chunk.get('id')} base metadata exceeds max bytes {max_bytes}")

    fragments: list[dict[str, Any]] = []
    current = empty_chunk_fragment(chunk)

    for field in CHUNK_LIST_FIELDS:
        values = chunk.get(field)
        if not isinstance(values, list) or not values:
            continue

        for item in values:
            current[field].append(item)
            if lua_len({"chunks": [current]}) <= max_bytes:
                continue

            current[field].pop()
            if any(isinstance(current.get(k), list) and current[k] for k in CHUNK_LIST_FIELDS):
                fragments.append(current)
                current = empty_chunk_fragment(chunk)

            current[field].append(item)
            if lua_len({"chunks": [current]}) > max_bytes:
                raise SystemExit(
                    f"chunk {chunk.get('id')} field {field} contains an entry larger than max bytes {max_bytes}"
                )

    if any(isinstance(current.get(k), list) and current[k] for k in CHUNK_LIST_FIELDS):
        fragments.append(current)
    elif not fragments:
        fragments.append(current)

    return fragments


def chunk_feature_count(chunk: dict[str, Any]) -> int:
    total = 0
    for key in ("roads", "rails", "buildings", "water", "props", "landuse", "barriers"):
        value = chunk.get(key)
        if isinstance(value, list):
            total += len(value)
    if chunk.get("terrain") is not None:
        total += 1
    return total


def chunk_streaming_cost(chunk: dict[str, Any]) -> int:
    weights = {
        "roads": 4,
        "rails": 3,
        "buildings": 12,
        "water": 2,
        "props": 1,
        "landuse": 6,
        "barriers": 2,
    }
    total = 0
    for key, weight in weights.items():
        value = chunk.get(key)
        if isinstance(value, list):
            total += len(value) * weight
    if chunk.get("terrain") is not None:
        total += 8
    return total


def chunk_ref_metadata(chunk: dict[str, Any]) -> dict[str, Any]:
    chunk_ref = {
        "id": chunk["id"],
        "originStuds": chunk.get("originStuds", {"x": 0, "y": 0, "z": 0}),
        "featureCount": chunk.get("featureCount", chunk_feature_count(chunk)),
        "streamingCost": chunk.get("streamingCost", chunk_streaming_cost(chunk)),
        "shards": [],
    }
    if chunk.get("partitionVersion") is not None:
        chunk_ref["partitionVersion"] = chunk["partitionVersion"]
    if chunk.get("subplans") is not None:
        chunk_ref["subplans"] = chunk["subplans"]
    return chunk_ref


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert JSON manifest to sharded Lua modules")
    parser.add_argument("--json", required=True, help="Input JSON manifest path")
    parser.add_argument("--output-dir", required=True, help="Output Lua directory")
    parser.add_argument("--index-name", default="AustinManifestIndex", help="Index module name")
    parser.add_argument("--shard-folder", default="AustinManifestChunks", help="Shard folder name")
    parser.add_argument("--chunks-per-shard", type=int, default=32, help="Chunks per shard module")
    parser.add_argument("--max-bytes", type=int, default=None, help="Maximum Lua module size in bytes")
    args = parser.parse_args()

    with open(args.json, "r", encoding="utf-8") as f:
        data = json.load(f)

    source_chunks = data.get("chunks", [])
    if not isinstance(source_chunks, list) or not source_chunks:
        raise SystemExit("manifest must contain a non-empty chunks array")

    chunks: list[dict[str, Any]] = []
    chunk_ref_by_id: dict[str, dict[str, Any]] = {}
    for chunk in source_chunks:
        chunk_id = chunk["id"]
        chunk_ref_by_id[chunk_id] = chunk_ref_metadata(chunk)
        chunks.extend(fragment_chunk(chunk, args.max_bytes))

    output_dir = Path(args.output_dir)
    shard_dir = output_dir / args.shard_folder
    clear_existing_shards(shard_dir, args.index_name)
    shard_names = []

    shard_count = (len(chunks) + args.chunks_per_shard - 1) // args.chunks_per_shard
    for shard_index in range(shard_count):
        start = shard_index * args.chunks_per_shard
        end = start + args.chunks_per_shard
        shard_chunks = chunks[start:end]
        shard_name = f"{args.index_name}_{shard_index + 1:03d}"
        shard_names.append(shard_name)
        for shard_chunk in shard_chunks:
            chunk_ref_by_id[shard_chunk["id"]]["shards"].append(shard_name)
        write_lua_module(shard_dir / f"{shard_name}.lua", {"chunks": shard_chunks})

    index_module = {
        "schemaVersion": data["schemaVersion"],
        "meta": data["meta"],
        "shardFolder": args.shard_folder,
        "shards": shard_names,
        "chunkCount": len(source_chunks),
        "fragmentCount": len(chunks),
        "chunksPerShard": args.chunks_per_shard,
        "chunkRefs": [chunk_ref_by_id[chunk["id"]] for chunk in source_chunks],
    }
    write_lua_module(output_dir / f"{args.index_name}.lua", index_module)

    print(f"Wrote index module to {output_dir / f'{args.index_name}.lua'}")
    print(f"Wrote {shard_count} shard modules to {shard_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
