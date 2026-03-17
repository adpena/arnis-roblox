#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "specs" / "generated" / "synthetic-manifest.json"

def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schemaVersion": "0.1.0",
        "meta": {
            "worldName": "SyntheticGrid",
            "generator": "scripts/generate_synthetic_manifest.py",
            "source": "synthetic",
            "metersPerStud": 1.0,
            "chunkSizeStuds": 256,
            "bbox": {
                "minLat": 0,
                "minLon": 0,
                "maxLat": 1,
                "maxLon": 1
            },
            "notes": ["Generated synthetic manifest"]
        },
        "chunks": []
    }

    for x in range(2):
        for z in range(2):
            manifest["chunks"].append({
                "id": f"{x}_{z}",
                "originStuds": {"x": x * 256, "y": 0, "z": z * 256},
                "roads": [],
                "buildings": [],
                "water": [],
                "props": []
            })

    OUT.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote {OUT}")

if __name__ == "__main__":
    main()
