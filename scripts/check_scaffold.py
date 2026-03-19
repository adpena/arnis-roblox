#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_FILES = [
    ROOT / "README.md",
    ROOT / "AGENTS.md",
    ROOT / "docs" / "architecture.md",
    ROOT / "specs" / "chunk-manifest.schema.json",
    ROOT / "specs" / "sample-chunk-manifest.json",
    ROOT / "rust" / "Cargo.toml",
    ROOT / "roblox" / "default.project.json",
]

def fail(message: str) -> None:
    print(f"[check_scaffold] ERROR: {message}")
    raise SystemExit(1)

def main() -> None:
    missing = [path for path in REQUIRED_FILES if not path.exists()]
    if missing:
        fail("Missing required files:\n" + "\n".join(str(path) for path in missing))

    manifest = json.loads((ROOT / "specs" / "sample-chunk-manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != "0.3.0":
        fail("sample manifest schemaVersion must be 0.3.0")

    if "meta" not in manifest or "chunks" not in manifest:
        fail("sample manifest missing meta or chunks")

    chunks = manifest["chunks"]
    if not isinstance(chunks, list) or not chunks:
        fail("sample manifest must contain at least one chunk")

    first = chunks[0]
    for key in ("id", "originStuds"):
        if key not in first:
            fail(f"first chunk missing key: {key}")

    print("[check_scaffold] Scaffold structure looks good.")

if __name__ == "__main__":
    main()
