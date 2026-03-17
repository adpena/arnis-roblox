#!/usr/bin/env python3
"""
Fetch OSM data from Overpass API for a bounding box and save as JSON.

This is a lightweight helper so you can drive the full Rust pipeline from
real OSM data with a single command, without baking HTTP clients into the
Rust crates yet.

Usage:
  python scripts/fetch_osm_overpass.py \
    --bbox 30.26,-97.75,30.27,-97.74 \
    --out rust/data/austin_overpass.json
"""

import argparse
import json
import sys
import time
from typing import Tuple

import urllib.parse
import urllib.request


OVERPASS_ENDPOINT = "https://overpass-api.de/api/interpreter"


def parse_bbox(arg: str) -> Tuple[float, float, float, float]:
    parts = arg.split(",")
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("bbox must be MIN_LAT,MIN_LON,MAX_LAT,MAX_LON")
    try:
        return tuple(float(p.strip()) for p in parts)  # type: ignore[return-value]
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid bbox value: {exc}") from exc


def build_overpass_query(bbox: Tuple[float, float, float, float]) -> str:
    min_lat, min_lon, max_lat, max_lon = bbox
    # Simple extract: highways, buildings, water, landuse
    # You can tune this later without changing the Rust side.
    return f"""
    [out:json][timeout:60];
    (
      way["highway"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["building"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["building:part"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["waterway"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["landuse"]({min_lat},{min_lon},{max_lat},{max_lon});
    );
    (._;>;);
    out body;
    """


def fetch_overpass(query: str) -> dict:
    data = urllib.parse.urlencode({"data": query}).encode("utf-8")
    req = urllib.request.Request(OVERPASS_ENDPOINT, data=data, method="POST")

    with urllib.request.urlopen(req, timeout=90) as resp:
        if resp.status != 200:
            raise RuntimeError(f"Overpass error: HTTP {resp.status}")
        text = resp.read().decode("utf-8")
        return json.loads(text)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Fetch OSM data from Overpass for a bbox")
    parser.add_argument(
        "--bbox",
        type=parse_bbox,
        required=True,
        help="MIN_LAT,MIN_LON,MAX_LAT,MAX_LON (e.g. 30.26,-97.75,30.27,-97.74)",
    )
    parser.add_argument(
        "--out",
        required=True,
        help="Output JSON file path (e.g. rust/data/austin_overpass.json)",
    )

    args = parser.parse_args(argv)

    bbox = args.bbox
    out_path = args.out

    print(f"[fetch_osm_overpass] Fetching OSM data for bbox={bbox} ...", file=sys.stderr)
    query = build_overpass_query(bbox)

    start = time.time()
    data = fetch_overpass(query)
    duration = time.time() - start

    # Basic sanity check: Overpass returns an "elements" array.
    if "elements" not in data:
        raise RuntimeError("Overpass response missing 'elements' key; unexpected format")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f)

    print(
        f"[fetch_osm_overpass] Wrote {len(data['elements'])} elements to {out_path} "
        f"in {duration:.2f}s",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

