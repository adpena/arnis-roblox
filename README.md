# Arnis Roblox — Real-World Cities in Roblox

Generate any location on Earth in Roblox with high fidelity. An open-source pipeline that transforms OpenStreetMap geodata, real-world elevation, and satellite imagery into playable Roblox worlds with cars, jetpacks, and parachutes.

> **One command. Any city. Any planet.**
> ```bash
> arbx_cli compile --live --bbox 30.26,-97.75,30.27,-97.74 --yolo --out austin.json
> ```

## What It Does

The Arnis Roblox pipeline takes a bounding box (latitude/longitude) and produces a complete Roblox world:

- **Terrain** with real-world elevation from DEM, bilinear interpolation, slope-aware materials
- **Buildings** with satellite-derived roof colors, 20+ PBR materials, glass windows, facades, interiors
- **Roads** with lane-aware width, surface-specific physics (26 surface types), street lighting, crosswalks
- **Water** with reflective surfaces, terrain carving, island preservation, intermittent dry beds
- **Vegetation** with 25+ tree species, multi-lobe canopies, palm fronds, height-based scaling
- **Infrastructure** with 25+ prop types (fountains, bollards, power poles, traffic signals, benches...)
- **Barriers** with kind-aware rendering (walls, fences, hedges, guard rails)
- **Ambient life** with parked cars, pedestrian NPCs, surface-aware footstep sounds
- **Day/night cycle** with 5-phase atmospheric transitions, window glow, street light toggle
- **Live minimap** rendering roads/buildings/water from manifest data, M key fullscreen toggle
- **Gameplay** with a driveable car, jetpack, and parachute — all with physics, particles, and sound

## Quick Start

### Prerequisites

- Rust toolchain (for the CLI pipeline)
- `vertigo-sync` (Rojo-compatible Studio sync and build tooling)

### 1. Export a city

```bash
cd rust

# Austin TX, maximum fidelity (requires 16GB+ RAM)
cargo run --bin arbx_cli -- compile --live --bbox 30.26,-97.75,30.27,-97.74 --yolo --out ../out/austin.json

# Tokyo, balanced quality
cargo run --bin arbx_cli -- compile --live --bbox 35.68,139.75,35.69,139.76 --profile balanced --out ../out/tokyo.json

# London with satellite material classification
cargo run --bin arbx_cli -- compile --live --bbox 51.50,-0.13,51.51,-0.12 --satellite --out ../out/london.json
```

### 2. Bootstrap a clean Arnis Studio place

```bash
python3 scripts/bootstrap_arnis_studio.py --open --serve
```

This builds the supported clean place from [`roblox/default.project.json`](/Users/adpena/Projects/arnis-roblox/roblox/default.project.json) into `roblox/out/arnis-test-clean.rbxlx`, starts the local `vsync serve --project default.project.json` process, and opens it in Studio when available. `scripts/bootstrap_vsync_place.py` remains as a compatibility shim for the older command name.

For a stable Austin export outside `roblox/out`, use:

```bash
bash scripts/build_austin_max_fidelity_place.sh
```

That runs the Austin export with `--yolo` (`terrain_cell_size=1`, satellite on), then builds a clean `.rbxlx` into [`exports/`](/Users/adpena/Projects/arnis-roblox/exports).

For an end-to-end Studio validation pass against that exported place, use:

```bash
bash scripts/test_austin_max_fidelity_e2e.sh
```

### 3. Enable live sync when you want iteration

```bash
cd roblox
vsync serve --project default.project.json
```

Install the generic `VertigoSyncPlugin`, let it connect to the local `vsync` server, then press Play. The world loads with a loading screen, atmospheric effects, and full gameplay.

### 4. Play

| Key | Action |
|-----|--------|
| **V** | Spawn/enter car |
| **J** | Toggle jetpack |
| **P** | Deploy parachute (when falling) |
| **M** | Toggle fullscreen map |
| **C** | Cinematic orbit camera |
| **H** | Car horn |
| **E** | Exit car |
| **Space** | Car brake / Jetpack ascend |
| **Shift** | Jetpack descend |
| **A/D** | Parachute steer |
| **S** | Parachute flare |

Gamepad fully supported (thumbsticks + triggers + face buttons).

## Quality Profiles

```bash
arbx_cli compile --profile <PROFILE> ...
```

| Profile | Terrain Grid | Satellite | RAM | Use Case |
|---------|-------------|-----------|-----|----------|
| `insane` | 256x256 (cell=1) | z19 on | ~2GB | M5 Max / workstation demo |
| `high` | 128x128 (cell=2) | z19 on | ~512MB | Default |
| `balanced` | 64x64 (cell=4) | off | ~128MB | 8GB machines |
| `fast` | 32x32 (cell=8) | off | ~32MB | CI / testing |
| `--yolo` | = `insane` | | | For Jensen |

## Architecture

```
OSM/Overpass Data + Mapbox DEM + ESRI Satellite
        │
        ▼
┌─ RUST PIPELINE ─────────────────────────────────┐
│ ValidateStage → NormalizeStage → TriangulateStage│
│ → ElevationEnrichmentStage (DEM Y for all)       │
│ → Chunker (satellite classification, surfaceY)   │
└──────────────────────┬──────────────────────────┘
                       │ Schema 0.4.0 JSON manifest
                       ▼
┌─ ROBLOX RUNTIME ────────────────────────────────┐
│ ImportService orchestrates per-chunk builders:    │
│  TerrainBuilder  │ BuildingBuilder │ RoadBuilder  │
│  WaterBuilder    │ PropBuilder     │ RoomBuilder   │
│  BarrierBuilder  │ LanduseBuilder  │ RailBuilder   │
│                                                   │
│ + DayNightCycle + MinimapService + AmbientLife    │
│ + StreamingService (LOD) + LoadingScreen          │
│ + AmbientSoundscape + VehicleController          │
└──────────────────────────────────────────────────┘
```

## VertigoSync Boundary

VertigoSync is an optional Studio-sync integration, not part of the core importer contract. This repo owns manifest correctness, importer/runtime behavior, and edit/play verification; VertigoSync should live in an adjacent repo and integrate through a thin compatibility layer only.

That does not make it disposable. It is still a key local-development tool for this project, and bugs in sync transport or plugin packaging should be fixed in `vertigo-sync` rather than hidden inside importer/runtime code.

See [docs/vertigo-sync-boundary.md](/Users/adpena/Projects/arnis-roblox/docs/vertigo-sync-boundary.md).

## Data Sources

| Source | What It Provides | Resolution |
|--------|-----------------|------------|
| **OSM / Overpass API** | Buildings, roads, water, props, landuse, barriers, semantics | Tag-level |
| **Terrarium DEM** | Real-world elevation | ~38m/pixel (z15) |
| **ESRI World Imagery** | Satellite photos for material classification | ~0.3m/pixel (z19) |
| **Overture Maps** | Building gap-fill with height data | Varies |
| **SRTM** | Fallback elevation data | ~30m |

## Schema 0.4.0

The manifest carries 8 feature layers per chunk:

- **terrain** — height grid with per-cell satellite-classified materials
- **roads** — polylines with lanes, surface, elevated/tunnel, sidewalk, maxspeed, lit, oneway, layer
- **rails** — polylines with track count
- **buildings** — polygon shells with height, roof shape/color/material, usage, rooms, name
- **water** — ribbons or polygons with surfaceY, holes (islands), width, intermittent
- **props** — 25+ types with species, height, leafType, circumference
- **landuse** — ground polygons (parks, parking, forest, etc.)
- **barriers** — linear features (walls, fences, hedges, guard rails, kerbs)

## Key Features

### Rendering
- **EditableMesh merging** for buildings and roads (10-100x draw call reduction)
- **Bilinear terrain interpolation** with slope-aware material transitions
- **20+ PBR building materials** (Brick, Marble, Limestone, CorrugatedSteel, Glass...)
- **Per-material color palettes** (neighboring buildings get subtly different shades)
- **Procedural facade details** (pilasters, foundations, cornices, window sills, rooftop equipment)
- **Multi-lobe tree canopies** with species-aware colors and shapes (palms, conifers, broadleaf)
- **Reflective water surfaces** (Glass overlay with 0.35 reflectance)
- **26 surface physics types** with real-world friction coefficients

### Atmosphere
- **5-phase day/night cycle**: dawn (fog + god rays) → day → golden hour → dusk → night
- **Smooth lerped transitions** on all atmospheric properties
- **75% of windows glow warm at night** (deterministic position-based hash)
- **Interior PointLights** visible through glass
- **Geo-aware sun positioning** from manifest bbox + configurable DateTime

### Performance
- **LOD system** with CollectionService tagging and distance-based Heartbeat culling
- **Window instance budget** (configurable per chunk via WorldConfig)
- **Strip-based terrain allocation** (16x memory reduction at VoxelSize=1)
- **Proper LRU satellite tile cache** (4096-tile cap)
- **Zero per-frame allocations** in the render loop
- **Frame-rate-independent lerps** everywhere

### Gameplay
- **Car**: spring suspension, drift physics, SpotLight headlights, engine/screech/horn sounds, handbrake, FOV scaling, G-force camera shake
- **Jetpack**: BodyForce with thrust ramp, 60s fuel, flame particles, wind sound, fuel gauge
- **Parachute**: pendulum physics, 3:1 glide ratio, stall mechanic, wind drift, DepthOfField
- **Cinematic camera**: slow orbit with DepthOfField
- **Ambient soundscape**: city hum, wind, birds, water (context-aware), surface footsteps

## Configuration

All rendering parameters are in `roblox/src/ReplicatedStorage/Shared/WorldConfig.lua`:

```lua
VoxelSize = 1,                    -- terrain smoothness (1-4)
EnableWindowRendering = true,      -- glass window panes on buildings
EnableStreetLighting = true,       -- PointLights along lit roads
EnableAtmosphere = true,           -- Bloom, SunRays, ColorCorrection
EnableDayNightCycle = true,        -- animated time of day
EnableMinimap = true,              -- live map overlay
EnableAmbientLife = true,          -- parked cars + pedestrian NPCs
DateTime = "auto",                 -- "auto" or "2024-06-15T18:30"
InstanceBudget = {
    MaxPerChunk = 8000,
    MaxWindowsPerChunk = 10000,
},
```

## CLI Reference

```bash
arbx_cli --help          # full help with examples
arbx_cli explain         # pipeline architecture (for AI agents)
arbx_cli --version       # version info
arbx_cli compile ...     # build manifest from geodata
arbx_cli sample ...      # emit synthetic test manifest
arbx_cli stats PATH      # manifest statistics
arbx_cli validate PATH   # schema validation
arbx_cli diff A B        # compare two manifests
arbx_cli config          # emit default WorldConfig JSON
```

## Repository Layout

```
.
├── rust/                          # Rust pipeline
│   └── crates/
│       ├── arbx_cli/              # CLI binary
│       ├── arbx_geo/              # Elevation, satellite, projection
│       ├── arbx_pipeline/         # Feature extraction, Overpass, stages
│       └── arbx_roblox_export/    # Chunker, manifest, materials
├── roblox/                        # Roblox project (Vertigo Sync / Rojo-style project file)
│   └── src/
│       ├── ReplicatedStorage/     # WorldConfig, Schema, Migrations
│       ├── ServerScriptService/   # ImportService + all builders
│       └── StarterPlayer/         # VehicleController, AmbientSoundscape
├── specs/                         # JSON schema, sample manifests
├── docs/                          # Architecture, schema, backlog
└── scripts/                       # Build, test, export scripts
```

## Credits

Inspired by the [Arnis](https://github.com/louis-e/arnis) project by louis-e, which generates real-world Minecraft maps from OpenStreetMap data. This project ports and extends the concept to Roblox with high-fidelity rendering, real-time gameplay, and satellite material classification.

Data sources: [OpenStreetMap](https://www.openstreetmap.org/) contributors, [ESRI World Imagery](https://www.arcgis.com/), [AWS Terrarium](https://registry.opendata.aws/terrain-tiles/), [Overture Maps](https://overturemaps.org/).

## License

See `NOTICE` for attribution. This project contains original code only — no upstream Arnis source code is copied.
