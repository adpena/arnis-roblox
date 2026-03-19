# Arnis HD Pipeline — Design Spec

**Date:** 2026-03-19
**Status:** Approved
**Schema target:** 0.4.0

## Problem Statement

The current pipeline has fundamental fidelity problems:

1. **Scale conflict** — Rust exporter uses `meters_per_stud = 1.0`, but `BuildingBuilder.lua:386` divides `height_m` by 0.3, making buildings 3.3x taller than terrain/roads expect.
2. **No unified elevation model** — each builder independently computes Y (terrain from grid, buildings from GroundSampler snap, roads from heuristic bridge detection, water from snap thresholds). Layers disagree on ground level.
3. **Terrain resolution too coarse** — 16-stud cells (16m at 1:1), 4-stud voxels. Produces a staircase.
4. **Incomplete data extraction** — OSM tags for surface, lanes, roof shape, building color, tree species are fetched but dropped or ignored.
5. **Limited material palette** — ~5 building materials, ~10 tree species, ~8 prop types with geometry.
6. **No external data fusion** — no satellite imagery, no high-res DEM, no vector tile enrichment.

## Architecture: Four Sub-Projects

```
SP-1: Coordinate Contract & Scale (foundation)
        │
   ┌────┴────┐
   ▼         ▼
SP-2: Data   SP-3: Builder
Source        Fidelity
Fusion        │
   │         │
   └────┬────┘
        ▼
SP-4: Material & Texture Pipeline
```

SP-1 must be implemented first. SP-2 and SP-3 can be designed in parallel but SP-3 consumes SP-2's richer data. SP-4 builds on all three.

---

## SP-1: Coordinate Contract & Scale

### Decision: Canonical Scale

`meters_per_stud = 0.3`

Rationale: Roblox default R15 humanoid is 5.326 studs tall, representing ~1.7m. 1.7 / 5.326 ≈ 0.319. Rounded to 0.3 for a slight "heroic scale."

| Real world | In studs | Character reference |
|-----------|----------|---------------------|
| 3.5m lane | ~12 studs | Character can walk across naturally |
| 30m building | ~100 studs | 10-story, proportional to character |
| 10m tree | ~33 studs | Provides shade at sidewalk scale |
| 2m sidewalk | ~7 studs | Comfortable walking width |

**Where it lives:** `ExportConfig.meters_per_stud = 0.3` in Rust. Written into every manifest's `meta.metersPerStud`. Lua reads from manifest. Zero hardcoded scale constants anywhere else.

### Decision: Elevation Authority

The Rust exporter is the single source of truth for all Y positions. The terrain heightfield is the ground reference.

**Contract:**
- `TerrainGrid.heights[]` — sampled from DEM at export time
- `Building.base_y` — ground elevation at centroid, from same DEM
- `Road.points[].y` — ground elevation at each vertex (or bridge deck elevation)
- `Water.surfaceY` — water surface elevation from DEM/river data
- `Prop.position.y` — ground elevation at prop location

**Roblox builders read these values directly. No re-sampling, no snap thresholds, no delta checks.**

GroundSampler remains available for runtime queries (player placement, physics) but is NOT used by builders during chunk import.

**Edge cases:**
- Bridges: tagged `elevated: true` in manifest, Y = bridge deck elevation. Builder places at that Y.
- Tunnels: tagged `tunnel: true`, builder skips surface rendering.
- Sloped terrain under buildings: exporter samples multiple footprint vertices, uses minimum ground elevation as `base_y`.

### Decision: Terrain Resolution

| Parameter | Current | New | Impact |
|-----------|---------|-----|--------|
| `cell_size_studs` | 16 | 4 | 4x horizontal resolution (1.2m real-world) |
| Voxel size (TerrainBuilder) | 4 | 2 | 2x vertical precision (0.6m) |
| Grid per chunk | 16x16 = 256 cells | 64x64 = 4,096 cells | 16x more height samples |
| Chunk size | 256 studs | 256 studs | Unchanged |

At 0.3 m/stud, a 256-stud chunk = 76.8m. With 4-stud cells: 64 cells across, each 1.2m. Enough to capture sidewalks and building footprint edges.

Performance: 4,096 floats per chunk (32KB). With 2-stud voxels and variable height range, the 3D voxel array for a chunk can grow large (e.g., 128×20×128 = 327K voxels for 40 studs of height variance). Roblox `WriteVoxels` has an observed limit of ~4M voxels per call. **TerrainBuilder must write in column strips or sub-regions** when the total voxel count exceeds a safe threshold (e.g., 500K), rather than attempting a single whole-chunk WriteVoxels call.

### Schema 0.4.0 Changes

```
meta:
  metersPerStud: 0.3              # was 1.0
  schemaVersion: "0.4.0"

chunks[].terrain:
  cellSizeStuds: 4                # was 16
  width: 64                       # was 16
  depth: 64                       # was 16
  heights: [f64; 4096]            # was [f64; 256]

chunks[].buildings[]:
  baseY: <authoritative>          # from DEM, no Lua re-sample
  height: <in studs at 0.3 m/s>  # no division in Lua
  minHeight: f64                  # NEW — elevation of base above ground
  usage: string                   # NEW — OSM building usage tag
  roofShape: string               # NEW — flat/gabled/hipped/dome/mansard
  roofColor: Color                # NEW — separate roof color (replaces nothing; additive)
  wallColor: Color                # NEW — replaces existing `color` field on buildings
  roofMaterial: string            # NEW — from OSM roof:material or satellite

chunks[].roads[]:
  points[].y: <authoritative>     # from DEM, no ground-snap in Lua
  elevated: bool                  # NEW — replaces heuristic bridge detection
  tunnel: bool                    # NEW — underground segment
  sidewalk: string                # NEW — "both"/"left"/"right"/"no"

chunks[].water[]:
  surfaceY: f64                   # NEW — authoritative surface elevation (polygon water only; ribbon water uses per-point Y)

chunks[].props[]:
  height: f64                     # NEW — real-world height for trees
  leafType: string                # NEW — broadleaved/needleleaved
```

### Migration: 0.3.0 to 0.4.0

`Migrations.lua` adds a migration function:

1. Set `meta.metersPerStud = 0.3`
2. Scale spatial coordinate fields by `1.0 / 0.3` (≈ 3.333) — old manifests stored 1 stud = 1 meter, new manifests store 1 stud = 0.3 meters, so the same real-world distance requires more studs:

**Fields that ARE scaled (× 3.333):**
- `chunks[].originStuds` (x, y, z)
- `chunks[].terrain.heights[]`
- `chunks[].terrain.cellSizeStuds`
- `chunks[].buildings[].baseY`
- `chunks[].buildings[].height`
- `chunks[].buildings[].footprint[].x`, `.z`
- `chunks[].buildings[].rooms[].floorY`, `.height`, `.footprint`
- `chunks[].roads[].points[]` (x, y, z)
- `chunks[].roads[].widthStuds`
- `chunks[].rails[].points[]` (x, y, z)
- `chunks[].rails[].widthStuds`
- `chunks[].water[].points[]` (x, y, z), `.widthStuds`, `.footprint`
- `chunks[].props[].position` (x, y, z)
- `chunks[].landuse[].footprint[].x`, `.z`
- `chunks[].barriers[].points[]` (x, y, z)
- `meta.chunkSizeStuds`

**Fields that are NOT scaled:**
- `chunks[].buildings[].height_m` (already in meters)
- `chunks[].buildings[].levels`, `.roofLevels` (counts)
- `chunks[].buildings[].roof` (string)
- `chunks[].roads[].lanes` (count)
- `chunks[].props[].yawDegrees`, `.scale`
- `chunks[].terrain.width`, `.depth` (grid dimensions, not spatial)
- All string/boolean fields

3. Rename `buildings[].color` → `buildings[].wallColor`. Add `buildings[].roofColor` defaulting to nil.
4. New fields default to nil (builders handle absence gracefully)
4. Terrain grid dimensions stay as-is for old manifests (new exports get 64×64)
5. Validate: `#terrain.heights == terrain.width * terrain.depth` and `#terrain.materials == terrain.width * terrain.depth` (when present)

### Files Changed

| File | Change |
|------|--------|
| `rust/.../lib.rs` | `ExportConfig::default().meters_per_stud = 0.3` |
| `rust/.../chunker.rs:121` | `cell_size = 4` (was 16) |
| `roblox/.../WorldConfig.lua` | Remove `MetersPerStud`. Read from manifest at import time. |
| `roblox/.../BuildingBuilder.lua` | Remove `getBuildingHeight()` function's `METERS_PER_STUD = 0.3` division. Use `building.height` directly. `levels * 14` becomes last-resort fallback only. |
| `roblox/.../RoadBuilder.lua` | Remove bridge heuristic. Read `elevated` flag. |
| `roblox/.../WaterBuilder.lua` | Remove snap threshold. Use `surfaceY` directly. |
| `roblox/.../Version.lua` | `SchemaVersion = "0.4.0"` |
| `roblox/.../Migrations.lua` | Add 0.3.0 → 0.4.0 migration |
| `roblox/.../ChunkSchema.lua` | Validate new fields |
| `specs/chunk-manifest.schema.json` | Update to 0.4.0 with new fields |
| `rust/.../manifest.rs` | Add new fields to structs (`elevated`, `tunnel`, `sidewalk`, `surfaceY`, etc.) |
| `rust/.../arbx_pipeline/src/lib.rs` | Add `elevated`, `tunnel`, `bridge`, `sidewalk` to `RoadFeature`; add `min_height`, `roof_shape`, `roof_colour`, `roof_material` to `BuildingFeature` |
| Overpass adapter (pipeline) | Extract new tags (`bridge`, `tunnel`, `sidewalk`, `roof:shape`, `roof:material`, `roof:colour`, `min_height`) during feature construction |

---

## SP-2: Data Source Fusion

### Data Source Hierarchy

| Source | Authority | Resolution | What It Provides |
|--------|-----------|-----------|-----------------|
| Mapbox Terrain-DEM v2 | Elevation | ~20-30m at z15 (bilinear interpolated to cell resolution) | Real-world height at every point |
| OSM / Overpass API | Semantics | N/A | Tags: usage, surface, lanes, roof type, species, names |
| Mapbox Vector Tiles | Geometry | z14-z16 | Building footprints, road geometry, landuse polygons |
| Mapbox Satellite | Material hints | ~1.2m at z17 | Roof color, ground cover, road surface tone |

### Conflict Resolution

- **Building height:** OSM `height` tag > MVT `height` > estimate from `levels` > usage-based default
- **Road classification:** OSM `highway` tag always (more granular than MVT)
- **Geometry:** MVT polygons > OSM polygons (better simplification). OSM polylines > MVT (more vertices).
- **Materials:** OSM tag > satellite classification > usage-based default > hardcoded fallback

### Mapbox DEM Integration

New `MapboxDemProvider` implementing existing `ElevationProvider` trait:

```rust
pub struct MapboxDemProvider {
    tile_cache: TileCache,     // z15 tiles, LRU cached to disk
    api_key: String,
}

impl ElevationProvider for MapboxDemProvider {
    fn sample_height_at(&self, latlon: LatLon) -> f32 {
        // Fetch/cache z15 terrain-rgb tile
        // Bilinear interpolation within tile
    }
}
```

Drop-in replacement for `PerlinElevationProvider`. The chunker already calls `elevation.sample_height_at()` everywhere.

### Expanded Overpass Tag Extraction

Tags to extract per feature type:

**Buildings:** `building`, `building:levels`, `building:colour`, `building:material`, `roof:shape`, `roof:material`, `roof:colour`, `roof:height`, `min_height`, `height`, `name`, `amenity`, `shop`

**Roads:** `highway`, `surface`, `lanes`, `maxspeed`, `lit`, `sidewalk`, `cycleway`, `bridge`, `tunnel`, `layer`, `name`, `oneway`

**Water:** `waterway`, `natural=water`, `water`, `intermittent`, `width`, `depth`, `name`

**Props/Nodes:** `natural=tree`, `species`, `genus`, `height`, `circumference`, `leaf_type`, `leaf_cycle`, `amenity`, `highway=street_lamp`, `highway=traffic_signals`, `barrier`

**Landuse:** `landuse`, `natural`, `leisure`, `surface`, `sport`

### Mapbox Vector Tile Integration

Fetch MVT layers: `building`, `road`, `landuse`, `water`, `poi`.

Feature matching with OSM:
1. For buildings: match by centroid proximity (<5m)
2. For roads: match by Hausdorff distance on segments
3. Merge: MVT geometry + OSM tags → unified Feature

### Satellite Tile Integration

Fetch z17 satellite tiles (≈1.2m/pixel resolution).

Three classification pipelines:
1. **Roof classification** — dominant color within building footprint → material + color
2. **Ground cover** — per-cell green-channel heuristic → terrain material
3. **Road surface tone** — centerline pixel brightness → surface inference

### Tile Caching

```
out/tiles/
├── mapbox-dem/z15/
├── mapbox-mvt/z14/
├── mapbox-sat/z17/
└── cache-manifest.json
```

Tiles fetched once, cached to disk. A 2km^2 Austin export uses ~50-100 tiles per layer.

### API Key Management

Read from (in priority order):
1. `MAPBOX_ACCESS_TOKEN` env var
2. `.env` file in project root
3. `--mapbox-token` CLI flag

### New Rust Crate Structure

```
rust/crates/
├── arbx_geo/           # existing — add MapboxDemProvider
├── arbx_pipeline/      # existing — expand Feature fields
├── arbx_roblox_export/ # existing — consume richer Features
├── arbx_datasource/    # NEW — Overpass client, MVT client, satellite client
└── arbx_fusion/        # NEW — feature matching + merging logic
```

---

## SP-3: Builder Fidelity

### BuildingBuilder Upgrades

| Feature | Data Source | Implementation |
|---------|------------|----------------|
| Correct height | Manifest `height` (studs) | Use directly. Remove `getBuildingHeight()` division. |
| Per-building color | OSM `colour` / satellite | `Color3.fromRGB()` on wall parts |
| Material from tag | OSM `material_tag` (expanded) | 15+ material lookup entries |
| Facade windows | Procedural from `levels` + `usage` | Recessed Glass parts in grid pattern on walls |
| Facade doors | `rooms[0].has_door` | Part on longest ground-floor edge facing road |
| Roof geometry | OSM `roof:shape` | flat/gabled (2 WedgeParts)/hipped (4 wedges)/dome/mansard |
| Roof color | OSM `roof:colour` / satellite | Separate roof color from wall color |
| min_height | OSM `min_height` | Elevate `base_y`, creates stilted structures |

**Window generation:**
- For each wall edge > 4 studs: compute `windowsPerFloor = floor(edgeLength / windowSpacing)`
- Window spacing by usage: office=4, residential=6, warehouse=12, commercial=5 (ground floor)
- Each window: thin Part (recessed 0.3 studs), material=Glass, color=dark blue/grey
- Instance budget: dedicated `MaxWindowsPerChunk = 3000` (separate from `MaxPerChunk`). When over budget, progressively reduce: first drop windows on non-street-facing walls, then reduce to every-other window, then skip windows entirely for smallest buildings. Consider Decal-based windows as a future LOD fallback.

### RoadBuilder Upgrades

| Feature | Data Source | Implementation |
|---------|------------|----------------|
| Lane-aware width | OSM `lanes` | `width = lanes * 12` studs (~3.5m per lane) |
| Lane markings | Procedural | Thin white/yellow parts. Dashed center, solid edge. |
| Surface material | OSM `surface` (expanded) | asphalt/concrete/cobblestone/gravel/unpaved/paving_stones |
| Bridge rendering | Manifest `elevated: true` | Deck parts + support pillar parts underneath |
| Tunnel handling | Manifest `tunnel: true` | Skip surface rendering |
| Sidewalk sides | OSM `sidewalk` tag | "both"/"left"/"right"/"no" placement |
| Crosswalks | Intersection detection | White stripe parts at detected intersections |
| Curb detail | When sidewalk present | Raised edge parts (0.5 stud height) |

### WaterBuilder Upgrades

| Feature | Data Source | Implementation |
|---------|------------|----------------|
| Island cutouts | `holes[]` in manifest | Subtract from water fill, fill with terrain |
| Surface elevation | `surfaceY` (authoritative) | Direct placement, no snapping |
| River width | OSM `width` / waterway type estimate | river=40, stream=10, canal=20, ditch=5 studs |
| Terrain carving | Below `surfaceY` | TerrainBuilder carves depression under water |

### PropBuilder Upgrades

Expand from ~8 to ~30+ prop types with geometry. Key additions:

- Trees: species-aware (25 species with distinct canopy shape/color/scale)
- Street furniture: bollard, fountain, mailbox, parking_meter, bicycle_parking
- Barriers: fence, wall, hedge (linear features along `barrier` ways)
- Infrastructure: power_tower, power_pole

Tree species palette expanded to 25 entries with shape (sphere/cone/columnar/drooping), color, and scale per species.

### TerrainBuilder Upgrades

| Feature | Implementation |
|---------|----------------|
| 2-stud voxels | `VOXEL_SIZE = 2` |
| Bilinear interpolation | Smooth between cell heights when writing sub-cell voxels |
| Per-cell materials | From satellite + OSM landuse, written to `terrain.materials[]` |
| Slope-aware materials | >45 degrees → Rock, 15-45 → Ground, <15 → classified material |
| Water carving | Carve terrain 2-4 studs below water `surfaceY` |
| Road imprinting | Flatten terrain to road elevation where roads pass |

### LanduseBuilder Upgrades

| Feature | Implementation |
|---------|----------------|
| Satellite-derived materials | Per-cell ground cover classification |
| Park features | Detect `leisure=park`, add benches/paths/trees from OSM |
| Parking lots | `amenity=parking` → Asphalt + stall markings |
| Sports fields | `leisure=pitch` → material + line markings |

---

## SP-4: Material & Texture Pipeline

### Roof Classification

```
Input:  satellite pixels within building footprint + OSM roof:material tag
Output: { material: string, color: Color }

Priority: OSM tag > satellite classification > usage default > "Concrete"

Satellite color → material mapping:
  dark grey/black     → Asphalt (tar roof)
  light grey          → Concrete
  red/brown           → Brick (tile)
  dark brown          → WoodPlanks (shingle)
  silver/white        → Metal
  green               → Slate (patina/green roof)
```

### Ground Cover Classification

```
Input:  satellite pixel + OSM landuse polygon (if present)
Output: terrain material enum

Priority: OSM landuse tag > satellite green-channel heuristic > brightness > "Ground"

Satellite classification:
  high green channel dominance    → Grass
  moderate green                  → LeafyGrass
  very bright (>200)              → Sand or Concrete
  bright (150-200)                → Pavement
  medium (80-150)                 → Asphalt or Ground
  dark (<80)                      → Rock or Mud
```

### Road Surface Inference

```
Input:  satellite pixels along road centerline (when OSM surface tag is absent)
Output: inferred surface tag

Brightness mapping:
  bright (>160) → concrete
  medium (100-160) → asphalt
  dark/brown (<100) → unpaved
```

### Per-Building Color Extraction

```
Input:  satellite pixels at building footprint edge (facade) + interior (roof)
Output: { wallColor: Color, roofColor: Color }

Used as fallback when OSM colour/roof:colour tags are absent.
```

---

## Performance Considerations

- **Instance budget:** Window/door generation respects `InstanceBudget.MaxPerChunk`. Skip detail for distant or dense chunks.
- **Terrain WriteVoxels:** Batched per chunk. 64x64 grid with 2-stud voxels = manageable.
- **Tile caching:** All Mapbox/satellite fetches cached to disk. No re-fetch on re-export.
- **Parallel terrain sampling:** Already uses rayon. Higher resolution grid benefits from parallelism.
- **EditableMesh merging:** Building shells and road surfaces continue to use mesh merging where possible. Windows/doors are separate parts (need Glass material).

## Testing Strategy

- **Coordinate contract tests:** Assert that building base_y matches terrain height at same XZ position (within voxel precision).
- **Scale regression test:** Known building (e.g., Texas State Capitol, 94.5m tall) should be ~315 studs. Assert within 5%.
- **Round-trip test:** Export sample features → import → verify all parts are within 1 stud of expected Y.
- **Migration test:** Load 0.3.0 manifest → migrate to 0.4.0 → verify scale is correct.
- **Material coverage test:** Export Austin downtown → count buildings with non-default materials → assert > 60%.

## Unchanged in 0.4.0

- `chunks[].rails[]` — preserved as-is, no new fields
- `chunks[].barriers[]` — preserved as-is, no new fields

## Quality Bar: "Seamless and Beautiful"

The goal is not just correctness but visual quality that makes the world feel real:

- **Layer coherence:** Zero visible gaps between terrain, roads, buildings, water. Every surface meets its neighbor cleanly. Roads sit flush on terrain. Buildings rest on ground. Water fills depressions.
- **Material variety:** No two adjacent buildings should have the same material+color unless they really do in the real world. Every surface has the right material for what it is.
- **Proportional scale:** A character walking through the world should feel like a person in a city. Streets are wide enough to walk. Buildings tower overhead. Trees provide shade.
- **Detail density:** Windows on every building. Lane markings on every road. Curbs on every sidewalk. Trees along every park. Streetlamps along every lit road.
- **Smooth terrain:** No visible stairstepping. Slopes blend naturally. Terrain under roads is flat. Terrain under water is carved.

## Non-Goals

- Real-time HTTP geodata calls from Roblox (per AGENTS.md rule 1)
- Building interiors beyond room data in manifest (per ADR-003, shell-first)
- Artist-authored mesh assets (procedural geometry only for now)
- Arbitrary raster textures on terrain (Roblox limitation)
