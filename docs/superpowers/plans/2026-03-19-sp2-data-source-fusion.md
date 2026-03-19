# SP-2: Data Source Fusion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the pipeline with higher-resolution elevation, complete OSM tag extraction, live Overpass fetching, and satellite-derived material classification so SP-3 builders have maximum data to work with.

**Architecture:** Expand existing infrastructure rather than building new crates. The TerrariumElevationProvider already fetches real DEM tiles — bump it to z15 for higher resolution. The OverpassAdapter already extracts most tags — propagate the missing ones. Add satellite tile fetching (similar pattern to Terrarium) for material classification. Add live Overpass API client as alternative to file-based. Mapbox MVT deferred until value is proven — OSM + Overture already provides good geometry.

**Tech Stack:** Rust (arbx_geo for elevation, arbx_pipeline for tag extraction, arbx_roblox_export for manifest), reqwest (new HTTP client dep), image crate (already present for PNG decoding)

**Spec:** `docs/superpowers/specs/2026-03-19-arnis-hd-pipeline-design.md` (SP-2 section)

**Key insight from exploration:** TerrariumElevationProvider already works with real-world AWS S3 terrain tiles. Overpass adapter already extracts ~80% of needed tags. The gap is propagation (tags extracted but not forwarded to Features), resolution (z13 → z15), and satellite imagery (new).

---

### Task 1: Upgrade Terrarium DEM to z15 for higher resolution

**Files:**
- Modify: `rust/crates/arbx_geo/src/lib.rs` (TerrariumElevationProvider)
- Modify: `rust/crates/arbx_cli/src/main.rs` (DEFAULT_ZOOM)

The current TerrariumElevationProvider uses z13 tiles (~150m/pixel). At z15 we get ~38m/pixel — 4x better horizontal resolution. The tile fetching, caching, and interpolation code already works.

- [ ] **Step 1: Find and update DEFAULT_ZOOM constant**

In `arbx_cli/src/main.rs`, find the zoom level constant used when constructing TerrariumElevationProvider and change from 13 to 15.

In `arbx_geo/src/lib.rs`, find any hardcoded zoom level in TerrariumElevationProvider::new() and update to 15.

- [ ] **Step 2: Test with sample export**

Run: `cd rust && cargo run --bin arbx_cli -- compile --source rust/data/austin_overpass.json 2>&1 | head -20`

Verify it downloads z15 tiles (filenames should contain `15_` prefix). The tiles will be larger but still small (~200KB each PNG).

- [ ] **Step 3: Commit**

```bash
git add rust/crates/arbx_geo/src/lib.rs rust/crates/arbx_cli/src/main.rs
git commit -m "feat(rust): upgrade Terrarium DEM to z15 for ~38m/pixel elevation resolution"
```

---

### Task 2: Propagate missing OSM tags through pipeline Features

**Files:**
- Modify: `rust/crates/arbx_pipeline/src/lib.rs` (BuildingFeature, RoadFeature, PropFeature, WaterFeature structs + Overpass adapter)
- Modify: `rust/crates/arbx_roblox_export/src/manifest.rs` (BuildingShell, RoadSegment, PropInstance)
- Modify: `rust/crates/arbx_roblox_export/src/chunker.rs` (pass through new fields)

The Overpass adapter already reads many tags but doesn't propagate them to Feature structs. Add:

**BuildingFeature** — add fields:
```rust
pub roof_colour: Option<String>,    // from OSM roof:colour (distinct from building:colour)
pub roof_material: Option<String>,  // from OSM roof:material (distinct from building:material)
pub roof_height: Option<f64>,       // from OSM roof:height
pub name: Option<String>,           // from OSM name
```

**RoadFeature** — add fields:
```rust
pub maxspeed: Option<u32>,          // from OSM maxspeed
pub lit: Option<bool>,              // from OSM lit=yes/no
pub oneway: Option<bool>,           // from OSM oneway=yes/no
pub layer: Option<i32>,             // from OSM layer
```

**WaterRibbonFeature** and **WaterPolygonFeature** — add fields:
```rust
pub width: Option<f64>,             // from OSM width (meters)
pub intermittent: Option<bool>,     // from OSM intermittent=yes/no
```

**PropFeature** — add field:
```rust
pub circumference: Option<f64>,     // from OSM circumference (meters, for trees)
```

- [ ] **Step 1: Add fields to pipeline Feature structs**

Add the fields listed above to the respective structs in `arbx_pipeline/src/lib.rs`.

- [ ] **Step 2: Extract tags in Overpass adapter**

In `emit_area_way()` for buildings, add:
```rust
roof_colour: tags.get("roof:colour").or_else(|| tags.get("roof:color")).map(|s| s.to_lowercase()),
roof_material: tags.get("roof:material").map(|s| s.to_lowercase()),
roof_height: tags.get("roof:height").and_then(|h| h.parse::<f64>().ok()),
name: tags.get("name").cloned(),
```

In `emit_linear_way()` for roads, add:
```rust
maxspeed: tags.get("maxspeed").and_then(|s| s.replace("mph", "").trim().parse().ok()),
lit: tags.get("lit").map(|s| s == "yes"),
oneway: tags.get("oneway").map(|s| s == "yes" || s == "1"),
layer: tags.get("layer").and_then(|s| s.parse().ok()),
```

For water ribbons, add:
```rust
width: tags.get("width").and_then(|w| w.parse::<f64>().ok()),
intermittent: tags.get("intermittent").map(|s| s == "yes"),
```

For tree props, add:
```rust
circumference: tags.get("circumference").and_then(|c| c.parse::<f64>().ok()),
```

- [ ] **Step 3: Add corresponding fields to manifest structs**

In `manifest.rs`, add to `BuildingShell`:
```rust
pub roof_height: Option<f64>,
pub name: Option<String>,
```
(roof_colour and roof_material already mapped to roof_color and roof_material from SP-1)

In `RoadSegment`, add:
```rust
pub maxspeed: Option<u32>,
pub lit: Option<bool>,
pub oneway: Option<bool>,
pub layer: Option<i32>,
```

In `WaterFeature`, add:
```rust
pub width: Option<f64>,
pub intermittent: Option<bool>,
```

In `PropInstance`, add:
```rust
pub circumference: Option<f64>,
```

- [ ] **Step 4: Update JSON serialization for new fields**

Add serialization for all new optional fields in the respective `write_json()` implementations.

- [ ] **Step 5: Pass through new fields in chunker**

In `chunker.rs`, update `ingest()` to pass the new fields from pipeline Features to manifest structs.

For buildings: pass `roof_colour` → parse to Color for `roof_color`, pass `roof_material` directly, pass `roof_height`, `name`.
For roads: pass `maxspeed`, `lit`, `oneway`, `layer`.
For water: pass `width`, `intermittent`.
For props: pass `circumference`.

- [ ] **Step 6: Fix all construction sites (SyntheticAustinAdapter, tests, etc.)**

Add `field: None` to all struct construction sites that don't have the data.

- [ ] **Step 7: Verify compilation and tests**

Run: `cd rust && cargo test --workspace 2>&1`
All tests must pass.

- [ ] **Step 8: Commit**

```bash
git add rust/crates/
git commit -m "feat(rust): propagate roof:colour, roof:material, maxspeed, lit, oneway, layer, width, intermittent through pipeline"
```

---

### Task 3: Add reqwest HTTP client and live Overpass API fetching

**Files:**
- Modify: `rust/Cargo.toml` (workspace deps)
- Modify: `rust/crates/arbx_pipeline/Cargo.toml` (add reqwest)
- Create: `rust/crates/arbx_pipeline/src/overpass_client.rs`
- Modify: `rust/crates/arbx_pipeline/src/lib.rs` (new module, LiveOverpassAdapter)
- Modify: `rust/crates/arbx_cli/src/main.rs` (add --live flag)

- [ ] **Step 1: Add reqwest dependency**

In `rust/crates/arbx_pipeline/Cargo.toml`, add:
```toml
reqwest = { version = "0.12", features = ["blocking", "json"] }
```

- [ ] **Step 2: Create overpass_client module**

Create `rust/crates/arbx_pipeline/src/overpass_client.rs`:

```rust
use crate::{PipelineError, PipelineResult};
use arbx_geo::BoundingBox;
use std::fs;
use std::path::PathBuf;

const OVERPASS_API: &str = "https://overpass-api.de/api/interpreter";

pub fn fetch_overpass(bbox: BoundingBox, cache_dir: &str) -> PipelineResult<PathBuf> {
    let cache_path = PathBuf::from(cache_dir).join(format!(
        "overpass_{:.4}_{:.4}_{:.4}_{:.4}.json",
        bbox.min.lat, bbox.min.lon, bbox.max.lat, bbox.max.lon
    ));

    if cache_path.exists() {
        eprintln!("Using cached Overpass data: {}", cache_path.display());
        return Ok(cache_path);
    }

    let query = build_overpass_query(bbox);
    eprintln!("Fetching Overpass data for bbox: {:.4},{:.4},{:.4},{:.4}",
        bbox.min.lat, bbox.min.lon, bbox.max.lat, bbox.max.lon);

    let client = reqwest::blocking::Client::builder()
        .user_agent("arnis-roblox/0.1 (geodata pipeline)")
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| PipelineError::IO(format!("HTTP client error: {}", e)))?;

    let response = client
        .post(OVERPASS_API)
        .body(format!("data={}", urlencoding::encode(&query)))
        .send()
        .map_err(|e| PipelineError::IO(format!("Overpass request failed: {}", e)))?;

    if !response.status().is_success() {
        return Err(PipelineError::IO(format!(
            "Overpass returned status {}", response.status()
        )));
    }

    let body = response.text()
        .map_err(|e| PipelineError::IO(format!("Failed to read response: {}", e)))?;

    fs::create_dir_all(cache_dir)
        .map_err(|e| PipelineError::IO(format!("Failed to create cache dir: {}", e)))?;
    fs::write(&cache_path, &body)
        .map_err(|e| PipelineError::IO(format!("Failed to write cache: {}", e)))?;

    eprintln!("Cached Overpass data to: {}", cache_path.display());
    Ok(cache_path)
}

fn build_overpass_query(bbox: BoundingBox) -> String {
    let bb = format!("{},{},{},{}", bbox.min.lat, bbox.min.lon, bbox.max.lat, bbox.max.lon);
    format!(
        r#"[out:json][timeout:90];
(
  way["building"]({bb});
  way["building:part"]({bb});
  way["highway"]({bb});
  way["railway"]({bb});
  way["waterway"]({bb});
  way["natural"="water"]({bb});
  relation["natural"="water"]({bb});
  relation["type"="multipolygon"]["building"]({bb});
  way["landuse"]({bb});
  way["natural"]({bb});
  way["leisure"]({bb});
  way["amenity"]({bb});
  way["barrier"]({bb});
  way["power"]({bb});
  node["natural"="tree"]({bb});
  node["amenity"]({bb});
  node["highway"="street_lamp"]({bb});
  node["highway"="traffic_signals"]({bb});
  node["highway"="bus_stop"]({bb});
  node["emergency"="fire_hydrant"]({bb});
);
out body;
>;
out skel qt;"#,
        bb = bb
    )
}
```

- [ ] **Step 3: Add urlencoding dependency**

In `rust/crates/arbx_pipeline/Cargo.toml`:
```toml
urlencoding = "2"
```

- [ ] **Step 4: Register module and create LiveOverpassAdapter**

In `arbx_pipeline/src/lib.rs`, add `pub mod overpass_client;` and create:

```rust
pub struct LiveOverpassAdapter {
    pub bbox: BoundingBox,
    pub meters_per_stud: f64,
    pub cache_dir: String,
}

impl SourceAdapter for LiveOverpassAdapter {
    fn name(&self) -> &'static str { "live-overpass" }

    fn load(&self, bbox: BoundingBox) -> PipelineResult<Vec<Feature>> {
        let path = overpass_client::fetch_overpass(bbox, &self.cache_dir)?;
        let file_adapter = OverpassAdapter {
            path,
            meters_per_stud: self.meters_per_stud,
        };
        file_adapter.load(bbox)
    }
}
```

- [ ] **Step 5: Add --live CLI flag**

In `arbx_cli/src/main.rs`, add a `--live` flag that uses `LiveOverpassAdapter` instead of file-based when no `--source` is provided. Cache to `out/overpass/`.

- [ ] **Step 6: Test with a small bbox**

Run: `cd rust && cargo run --bin arbx_cli -- compile --live --bbox 30.265,-97.745,30.270,-97.740 --out out/test_live.json 2>&1`

Verify it fetches from Overpass API, caches the response, and produces a valid manifest.

- [ ] **Step 7: Commit**

```bash
git add rust/
git commit -m "feat(rust): add live Overpass API client with disk caching"
```

---

### Task 4: Add satellite tile fetcher for material classification

**Files:**
- Create: `rust/crates/arbx_geo/src/satellite.rs`
- Modify: `rust/crates/arbx_geo/src/lib.rs` (new module)
- Modify: `rust/crates/arbx_geo/Cargo.toml` (add reqwest)

Pattern after the existing TerrariumElevationProvider: fetch z17 tiles from a satellite imagery source, cache to disk, sample pixels.

- [ ] **Step 1: Create satellite tile fetcher**

Create `rust/crates/arbx_geo/src/satellite.rs`:

```rust
use crate::LatLon;
use image::{DynamicImage, GenericImageView};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Copy)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    pub fn brightness(&self) -> f32 {
        (self.r as f32 * 0.299 + self.g as f32 * 0.587 + self.b as f32 * 0.114)
    }

    pub fn green_dominance(&self) -> f32 {
        (self.g as f32 - self.r as f32.max(0.0)) / 255.0
    }
}

pub struct SatelliteTileProvider {
    zoom: u32,
    cache_dir: PathBuf,
    tiles: HashMap<(u32, u32), DynamicImage>,
    api_key: Option<String>,
}

impl SatelliteTileProvider {
    pub fn new(cache_dir: &str, api_key: Option<String>) -> Self {
        let cache_path = PathBuf::from(cache_dir);
        fs::create_dir_all(&cache_path).ok();
        Self {
            zoom: 17,
            cache_dir: cache_path,
            tiles: HashMap::new(),
            api_key,
        }
    }

    pub fn sample_pixel(&mut self, latlon: LatLon) -> Option<Rgb> {
        let (tx, ty) = latlon_to_tile(latlon, self.zoom);
        let tile = self.get_or_fetch_tile(tx, ty)?;
        let (px, py) = latlon_to_pixel_in_tile(latlon, self.zoom, tx, ty);
        let pixel = tile.get_pixel(px.min(255), py.min(255));
        Some(Rgb { r: pixel[0], g: pixel[1], b: pixel[2] })
    }

    /// Sample the dominant color within a polygon (footprint points as LatLon)
    pub fn sample_polygon_dominant(&mut self, points: &[LatLon]) -> Option<Rgb> {
        if points.is_empty() { return None; }
        // Sample at centroid + a few interior points
        let n = points.len() as f64;
        let clat = points.iter().map(|p| p.lat).sum::<f64>() / n;
        let clon = points.iter().map(|p| p.lon).sum::<f64>() / n;
        self.sample_pixel(LatLon::new(clat, clon))
    }

    fn get_or_fetch_tile(&mut self, tx: u32, ty: u32) -> Option<&DynamicImage> {
        if !self.tiles.contains_key(&(tx, ty)) {
            let img = self.fetch_tile(tx, ty)?;
            self.tiles.insert((tx, ty), img);
        }
        self.tiles.get(&(tx, ty))
    }

    fn fetch_tile(&self, tx: u32, ty: u32) -> Option<DynamicImage> {
        let cache_file = self.cache_dir.join(format!("{}_{}_z{}.png", tx, ty, self.zoom));
        if cache_file.exists() {
            return image::open(&cache_file).ok();
        }

        // Try Mapbox satellite if API key is available
        let url = if let Some(ref key) = self.api_key {
            format!(
                "https://api.mapbox.com/v4/mapbox.satellite/{}/{}/{}.png?access_token={}",
                self.zoom, tx, ty, key
            )
        } else {
            // Fallback: use ESRI World Imagery (free, no API key needed)
            format!(
                "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{}/{}/{}",
                self.zoom, ty, tx
            )
        };

        eprintln!("Fetching satellite tile z{}/{}/{}", self.zoom, tx, ty);
        std::thread::sleep(std::time::Duration::from_millis(200));

        let output = std::process::Command::new("curl")
            .args(["-sL", "-o", cache_file.to_str().unwrap(),
                   "-H", "User-Agent: arnis-roblox/0.1 (geodata pipeline)",
                   &url])
            .output()
            .ok()?;

        if !output.status.success() {
            eprintln!("WARN: satellite tile fetch failed for z{}/{}/{}", self.zoom, tx, ty);
            return None;
        }

        image::open(&cache_file).ok()
    }
}

/// Classify a roof material from satellite pixel color
pub fn classify_roof_material(rgb: Rgb) -> &'static str {
    let b = rgb.brightness();
    let r = rgb.r as f32;
    let g = rgb.g as f32;
    let blue = rgb.b as f32;

    if b < 80.0 { return "Asphalt"; }          // dark = tar roof
    if b > 200.0 && (r - g).abs() < 30.0 { return "Metal"; }  // bright neutral = metal
    if r > 150.0 && g < 120.0 && blue < 120.0 { return "Brick"; }  // reddish = tile
    if r > 100.0 && g > 80.0 && blue < 80.0 { return "WoodPlanks"; }  // brownish = shingle
    if g > r && g > blue && g > 120.0 { return "Slate"; }  // greenish = patina
    if b > 160.0 { return "Concrete"; }         // bright grey = concrete
    "Concrete"                                    // default
}

/// Classify ground cover material from satellite pixel color
pub fn classify_ground_material(rgb: Rgb) -> &'static str {
    let green_dom = (rgb.g as f32 - rgb.r as f32) / 255.0;
    let b = rgb.brightness();

    if green_dom > 0.15 { return "Grass"; }
    if green_dom > 0.05 { return "LeafyGrass"; }
    if b > 200.0 { return "Concrete"; }
    if b > 160.0 { return "Pavement"; }
    if b > 100.0 { return "Asphalt"; }
    if b > 60.0 { return "Ground"; }
    "Rock"
}

fn latlon_to_tile(ll: LatLon, zoom: u32) -> (u32, u32) {
    let n = 2_u32.pow(zoom) as f64;
    let x = ((ll.lon + 180.0) / 360.0 * n) as u32;
    let lat_rad = ll.lat.to_radians();
    let y = ((1.0 - (lat_rad.tan() + 1.0 / lat_rad.cos()).ln() / std::f64::consts::PI) / 2.0 * n) as u32;
    (x, y)
}

fn latlon_to_pixel_in_tile(ll: LatLon, zoom: u32, tx: u32, ty: u32) -> (u32, u32) {
    let n = 2_u32.pow(zoom) as f64;
    let x_frac = (ll.lon + 180.0) / 360.0 * n - tx as f64;
    let lat_rad = ll.lat.to_radians();
    let y_frac = (1.0 - (lat_rad.tan() + 1.0 / lat_rad.cos()).ln() / std::f64::consts::PI) / 2.0 * n - ty as f64;
    ((x_frac * 256.0) as u32, (y_frac * 256.0) as u32)
}
```

- [ ] **Step 2: Register module**

In `arbx_geo/src/lib.rs`, add: `pub mod satellite;`

- [ ] **Step 3: Verify compilation**

Run: `cd rust && cargo check --workspace 2>&1`

- [ ] **Step 4: Commit**

```bash
git add rust/crates/arbx_geo/
git commit -m "feat(rust): add satellite tile fetcher with roof/ground material classification"
```

---

### Task 5: Integrate satellite classification into export pipeline

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/chunker.rs`
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs`
- Modify: `rust/crates/arbx_cli/src/main.rs`

Wire satellite classification into the chunker so buildings get roof colors/materials and terrain gets per-cell materials.

- [ ] **Step 1: Add SatelliteTileProvider to Chunker**

Modify the `Chunker` struct to optionally hold a `SatelliteTileProvider`. When present, during `ingest()` for buildings, sample satellite pixels at the building centroid to populate `roof_color` and `roof_material` (if not already set from OSM tags).

- [ ] **Step 2: Classify terrain materials from satellite**

In `ensure_chunk()`, after computing terrain heights, if satellite provider is available, sample each cell's centroid and set the per-cell material using `classify_ground_material()`.

- [ ] **Step 3: Populate roof colors from satellite**

In `ingest()` for buildings, after setting `roof_material` from OSM tags, if satellite is available and roof_material is still None, sample the satellite and classify.

- [ ] **Step 4: Add --satellite CLI flag**

In `arbx_cli/src/main.rs`, add `--satellite` flag (and optionally `--mapbox-token` for Mapbox tiles). When enabled, construct SatelliteTileProvider with cache dir `out/tiles/satellite/`.

- [ ] **Step 5: Test with Austin export**

Run: `cd rust && cargo run --bin arbx_cli -- compile --source rust/data/austin_overpass.json --satellite --out out/test_satellite.json 2>&1`

Verify the manifest now has per-cell terrain materials and building roof colors.

- [ ] **Step 6: Commit**

```bash
git add rust/
git commit -m "feat(rust): integrate satellite material classification into chunker for roofs and terrain"
```

---

### Task 6: Update Lua schema validation for new fields

**Files:**
- Modify: `roblox/src/ReplicatedStorage/Shared/ChunkSchema.lua`

Add validation for the new optional fields added in Task 2:

- Roads: `maxspeed` (number), `lit` (boolean), `oneway` (boolean), `layer` (number)
- Buildings: `roofHeight` (number), `name` (string)
- Water: `width` (number), `intermittent` (boolean)
- Props: `circumference` (number), `height` (number), `leafType` (string)

All fields are optional — validate type only when present.

- [ ] **Step 1: Add validation rules**
- [ ] **Step 2: Commit**

```bash
git add roblox/src/ReplicatedStorage/Shared/ChunkSchema.lua
git commit -m "feat(lua): validate new SP-2 schema fields (maxspeed, lit, roofHeight, width, etc.)"
```

---

### Task 7: Update documentation

**Files:**
- Modify: `docs/chunk_schema.md`
- Modify: `docs/backlog.md`
- Modify: `specs/chunk-manifest.schema.json`

- [ ] **Step 1: Update chunk_schema.md with new fields**

Add the new fields to the schema documentation under each feature type.

- [ ] **Step 2: Update JSON schema spec**

Add the new optional properties to the JSON schema for roads, buildings, water, and props.

- [ ] **Step 3: Mark SP-2 complete in backlog**

Change `- [ ] SP-2` to `- [x] SP-2` in `docs/backlog.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/ specs/
git commit -m "docs: update schema docs and backlog for SP-2 data source fusion completion"
```

---

### Task 8: Integration verification

- [ ] **Step 1: Run full Rust test suite**

Run: `cd rust && cargo test --workspace 2>&1`
All tests must pass.

- [ ] **Step 2: Generate Austin manifest with satellite**

Run: `cd rust && cargo run --bin arbx_cli -- compile --source rust/data/austin_overpass.json --satellite --out out/austin_hd.json 2>&1`

- [ ] **Step 3: Inspect manifest for data richness**

Check that:
- Buildings have `roofColor`, `roofMaterial`, `roofShape`, `usage`, `name` populated
- Roads have `maxspeed`, `lit`, `oneway` where OSM has them
- Terrain cells have varied materials (not all "Grass")
- Props have `height`, `leafType`, `circumference` for trees

- [ ] **Step 4: Count enrichment**

```bash
cat out/austin_hd.json | python3 -c "
import json, sys
m = json.load(sys.stdin)
bldgs = [b for c in m['chunks'] for b in c.get('buildings', [])]
with_roof_color = sum(1 for b in bldgs if b.get('roofColor'))
with_usage = sum(1 for b in bldgs if b.get('usage'))
with_name = sum(1 for b in bldgs if b.get('name'))
print(f'Buildings: {len(bldgs)} total, {with_roof_color} with roofColor, {with_usage} with usage, {with_name} with name')
roads = [r for c in m['chunks'] for r in c.get('roads', [])]
with_lit = sum(1 for r in roads if r.get('lit') is not None)
print(f'Roads: {len(roads)} total, {with_lit} with lit')
"
```

- [ ] **Step 5: Commit any remaining fixes**

```bash
git add -A && git commit -m "chore: SP-2 data source fusion integration verification"
```
