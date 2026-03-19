# Backlog

## Epic A — Contracts

- [x] finalize chunk schema (v0.3.0 stable)
- [x] finalize world config schema
- [x] add migration notes mechanism
- [x] add manifest version upgrade helper

## Epic B — Rust exporter

- [x] multi-chunk sample exporter
- [x] deterministic sort order
- [x] chunk ownership rules
- [x] adapter trait for upstream geodata
- [x] real geodata adapter (OSM/Overpass)
- [x] CLI commands for validate / diff / stats

## Epic C — Roblox importer

- [x] real terrain voxel writer
- [x] road strip batching or merging (EditableMesh)
- [x] building shell merge behavior (EditableMesh)
- [x] chunk unload/reload
- [x] per-chunk profiling summary
- [x] LOD / visibility distance selection (StreamingService)

## Epic D — Tooling

- [x] stronger repo checks (selene + cargo test)
- [x] optional TestEZ integration
- [x] CI workflow
- [x] serialized perf snapshots

## Epic E — Fidelity

- [x] water material strategy (EditableMesh merging)
- [x] tree/light prefab strategy (Pooling + Prefabs)
- [x] rail/power layers
- [x] interiors only after shell perf is stable

## Epic F — HD Pipeline

- [x] SP-1: Coordinate contract (meters_per_stud=0.3, schema 0.4.0, elevation authority, terrain 64x64)
- [x] SP-2: Data source fusion (z15 DEM, live Overpass tags, satellite tile classification, expanded OSM fields maxspeed/lit/oneway/layer/roofHeight/name/width/intermittent/circumference, Lua schema validation, JSON schema and docs updated)
- [x] SP-3: Builder fidelity (bilinear terrain interpolation, slope-aware materials, roof colors/materials from satellite, glass window panes, usage-aware window density, lane-aware road width, directional sidewalks, street lighting, water terrain carving, island preservation, height-based tree scaling, leaf type canopy shapes, palm tree rendering, 25+ tree species)
- [x] SP-4: Material & texture pipeline (integrated into SP-2 satellite classification + SP-3 builder consumption — roof materials from satellite, per-cell terrain materials, ground cover classification)

## Epic G — AAA Polish

- [x] EditableMesh merging: buildings (walls+roofs merged per material), roads (surface quads merged)
- [x] Day/night cycle: Heartbeat clock, street light toggle, window warm glow, atmosphere shifts
- [x] Procedural facade details: window sills, foundations, cornices, rooftop AC equipment
- [x] 25+ prop types: fountain, bollard, power tower/pole, mailbox, vending machine, bike parking, etc.
- [x] Crosswalks (zebra stripe rendering), stairways (highway=steps), tunnel geometry
- [x] Atmospheric effects: Bloom, ColorCorrection, SunRays, geographic latitude from manifest
- [x] LOD system: CollectionService tagging, distance-based Heartbeat culling
- [x] WorldConfig fully wired: all builder parameters configurable from central hub
- [x] Table-driven OSM extraction: 330→50 lines, clean architecture
- [x] Window budget enforcement in ImportService
- [x] --profile presets (insane/high/balanced/fast), --yolo mode, worldwide SRTM

## Epic H — Gameplay & Demo

- [x] Car: spring suspension, drift physics, SpotLight headlights, engine/screech/horn sounds, handbrake drift, FOV 70-105 scaling, G-force camera shake
- [x] Jetpack: BodyForce with thrust ramp, 60s fuel, flame particles (pre-computed tiers), wind sound, fuel gauge, camera pull-back
- [x] Parachute: pendulum physics (BallSocketConstraint), 3:1 glide ratio, stall mechanic, wind drift, white+red canopy, DepthOfField
- [x] Cinematic camera: C key orbit (150 stud radius, 60 FOV, DepthOfField)
- [x] Gamepad support: full thumbstick + trigger mapping for all vehicles (Y/X/A/B buttons)
- [x] HUD: speedometer, altimeter, fuel bar (color thresholds), mode icons, auto-fade control hints
- [x] Ambient soundscape: city hum, altitude wind, park birds, water flow (context-aware, smooth volume lerp)
- [x] Surface-aware footstep sounds: 3 categories (hard/soft/hollow) matched to terrain material via raycast
- [x] Parked cars: deterministic scatter along residential/secondary roads (8 color variants, size variation)
- [x] Pedestrian NPCs: simple Part-based figures on sidewalks (8 per chunk, LOD-tagged)
- [x] Loading screen: fade-in, city name, version, animated progress bar, controls hint, smooth fade-out
- [x] Live minimap: bottom-left, M key fullscreen toggle (TweenService animation), compass heading (N/NE/E...)
- [x] 26 road surface physics types with real-world friction coefficients (asphalt 0.75 to ice 0.12)
- [x] Road AI metadata: every road Part tagged with Oneway/MaxSpeed/Lanes attributes for future vehicle AI
- [x] Smoothness pass: zero per-frame allocations, dt-scaled lerps, no audio pops, no FOV snaps

## Epic I — Performance & Polish

- [x] EditableMesh merging for buildings (walls + roofs + detail batched per material)
- [x] EditableMesh merging for roads (surface quads batched per material/physics)
- [x] Strip-based terrain WriteVoxels (16x memory reduction at VoxelSize=1)
- [x] LRU satellite tile cache (proper eviction, 4096-tile cap)
- [x] Slope-following rendering across all linear features (roads, barriers, rails, water ribbons)
- [x] Road terrain imprinting (FillBlock Asphalt under road surfaces, respects road material)
- [x] Building PBR materials: 20+ materials with per-material color palettes
- [x] Multi-lobe tree canopy (4 overlapping spheres with species-seeded color variation)
- [x] Improved props: 3-light traffic signals, benches with backrest, street lamps with arm detail
- [x] Procedural facade details: pilasters, foundations, cornices, window sills, rooftop AC equipment
- [x] Commercial awnings, parking lot stall markings, manholes, drain grates
- [x] Reflective water surfaces (Glass overlay, 0.35 reflectance)
- [x] 5-phase atmospheric transitions: dawn fog → day → golden hour → dusk → night (lerped)
- [x] Night window glow: 75% lit (deterministic hash), interior PointLights, warm color variation
- [x] Geo-aware sun positioning from manifest bbox + configurable DateTime
- [x] LOD system: CollectionService tagging (LOD_Detail, LOD_Interior, StreetLight, InteriorLight, Road)
- [x] WorldConfig fully wired into all builders (all hardcoded constants replaced)
- [x] Table-driven OSM node extraction (22 specs, 330→50 lines)
- [x] GeoUtils shared module (deduplicated pointInPolygon across 4 builders)
- [x] CLI: --profile presets, --yolo, --world-name, --terrain-cell-size, --version, comprehensive help + explain
