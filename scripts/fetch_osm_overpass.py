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
import random
import sys
import time
from typing import Tuple

import urllib.parse
import urllib.request
import urllib.error


# Rotate across public mirrors — same strategy as Arnis upstream
OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
]

USER_AGENT = "arnis-roblox/1.0 (open-source educational project; github.com/arnis-roblox)"

# Seconds to wait between retries (exponential: 5, 10, 20)
RETRY_BASE_DELAY = 5
MAX_RETRIES = 3


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
    # Extract: highways, buildings, water, landuse, and POI-like features
    # You can tune this later without changing the Rust side.
    return f"""
    [out:json][timeout:120];
    (
      way["highway"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["building"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["building:part"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["waterway"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["landuse"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["tourism"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["historic"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["man_made"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["barrier"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["power"]({min_lat},{min_lon},{max_lat},{max_lon});
      way["aeroway"]({min_lat},{min_lon},{max_lat},{max_lon});
    );
    (._;>;);
    out body;
    """


def fetch_overpass(query: str) -> dict:
    """POST query to a randomly selected Overpass mirror with retry/backoff."""
    encoded = urllib.parse.urlencode({"data": query}).encode("utf-8")
    endpoints = OVERPASS_ENDPOINTS[:]
    random.shuffle(endpoints)

    last_err: Exception = RuntimeError("no endpoints tried")
    for attempt in range(MAX_RETRIES):
        endpoint = endpoints[attempt % len(endpoints)]
        req = urllib.request.Request(endpoint, data=encoded, method="POST")
        req.add_header("User-Agent", USER_AGENT)
        try:
            with urllib.request.urlopen(req, timeout=150) as resp:
                if resp.status != 200:
                    raise RuntimeError(f"Overpass error: HTTP {resp.status}")
                text = resp.read().decode("utf-8")
                return json.loads(text)
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code in (429, 503):
                # Rate-limited or server busy — back off
                delay = RETRY_BASE_DELAY * (2 ** attempt)
                print(
                    f"[fetch_osm_overpass] HTTP {e.code} from {endpoint}, "
                    f"retrying in {delay}s (attempt {attempt+1}/{MAX_RETRIES})...",
                    file=sys.stderr,
                )
                time.sleep(delay)
            else:
                raise
        except Exception as e:
            last_err = e
            delay = RETRY_BASE_DELAY * (2 ** attempt)
            print(
                f"[fetch_osm_overpass] Error ({e}), retrying in {delay}s "
                f"(attempt {attempt+1}/{MAX_RETRIES})...",
                file=sys.stderr,
            )
            time.sleep(delay)

    raise last_err


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

    parser.add_argument(
        "--max-cache-hours",
        type=float,
        default=24.0,
        help="Skip fetch if output file is younger than this many hours (default: 24)",
    )
    args = parser.parse_args(argv)

    bbox = args.bbox
    out_path = args.out

    # Skip re-fetching if cache is fresh enough — avoids hammering Overpass
    import os
    if os.path.exists(out_path):
        age_hours = (time.time() - os.path.getmtime(out_path)) / 3600
        if age_hours < args.max_cache_hours:
            print(
                f"[fetch_osm_overpass] Using cached data ({age_hours:.1f}h old, "
                f"max {args.max_cache_hours}h) — skipping fetch.",
                file=sys.stderr,
            )
            return 0

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

