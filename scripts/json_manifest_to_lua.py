#!/usr/bin/env python3
"""
Convert a JSON manifest (as emitted by arbx_cli) into a Lua ModuleScript
that returns an equivalent table.

Usage:
  python scripts/json_manifest_to_lua.py \
    --json rust/out/austin-manifest.json \
    --module roblox/src/ServerStorage/SampleData/AustinManifest.lua
"""

import argparse
import json
from typing import Any, TextIO


def to_lua(value: Any, out: TextIO, indent: int = 0) -> None:
    pad = " " * indent
    if isinstance(value, dict):
        out.write("{\n")
        items = list(value.items())
        for i, (k, v) in enumerate(items):
            out.write(f"{' ' * (indent + 2)}{k} = ")
            to_lua(v, out, indent + 2)
            if i + 1 != len(items):
                out.write(",")
            out.write("\n")
        out.write(pad + "}")
    elif isinstance(value, list):
        out.write("{")
        if value:
            out.write("\n")
            for i, v in enumerate(value):
                out.write(" " * (indent + 2))
                to_lua(v, out, indent + 2)
                if i + 1 != len(value):
                    out.write(",")
                out.write("\n")
            out.write(pad + "}")
        else:
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
        # numbers
        out.write(str(value))


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert JSON manifest to Lua module")
    parser.add_argument("--json", required=True, help="Input JSON manifest path")
    parser.add_argument("--module", required=True, help="Output Lua module path")
    args = parser.parse_args()

    with open(args.json, "r", encoding="utf-8") as f:
        data = json.load(f)

    with open(args.module, "w", encoding="utf-8") as out:
        out.write("return ")
        to_lua(data, out, indent=0)
        out.write("\n")

    print(f"Wrote Lua module to {args.module}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

