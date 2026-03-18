#!/usr/bin/env python3
"""Download Overture Maps building footprints for Austin, TX."""
import subprocess
import sys
import os
import json

BBOX = "-97.765,30.245,-97.715,30.305"  # west,south,east,north
OUTPUT = "rust/data/overture_buildings.geojson"


def main():
    os.makedirs("rust/data", exist_ok=True)

    if os.path.exists(OUTPUT):
        import time
        age_days = (time.time() - os.path.getmtime(OUTPUT)) / 86400
        if age_days < 7:
            print(f"Using cached Overture buildings ({age_days:.1f} days old)")
            return

    print(f"Downloading Overture buildings for bbox {BBOX}...")
    result = subprocess.run([
        "overturemaps", "download",
        f"--bbox={BBOX}",
        "-f", "geojson",
        "--type=building",
        "-o", OUTPUT
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Warning: Overture download failed: {result.stderr}")
        print("Continuing without Overture data.")
        return

    # Some versions of the overturemaps CLI omit the closing `]}` on the
    # FeatureCollection.  Append it when necessary so the file is valid JSON.
    with open(OUTPUT, "rb+") as f:
        f.seek(-2, 2)
        tail = f.read()
        if not tail.endswith(b"]}"):
            f.seek(0, 2)
            f.write(b"\n]}")

    with open(OUTPUT) as f:
        data = json.load(f)
    count = len(data.get("features", []))
    print(f"Downloaded {count} Overture buildings → {OUTPUT}")


if __name__ == "__main__":
    main()
