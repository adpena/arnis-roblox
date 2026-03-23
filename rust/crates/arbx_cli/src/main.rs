use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::Instant;

use arbx_geo::{
    BoundingBox, ElevationProvider, FlatElevationProvider, HgtElevationProvider,
    OffsetElevationProvider, TerrariumElevationProvider,
};
use arbx_pipeline::{
    run_pipeline, ElevationEnrichmentStage, NormalizeStage, TriangulateStage, ValidateStage,
};
use arbx_roblox_export::{
    build_sample_multi_chunk, export_to_chunks, ExportConfig, SatelliteTileProvider,
};
use rayon::prelude::*;
use serde_json::{json, Value};

const SCENE_INDEX_VERSION: u64 = 2;

fn srtm_tile_name(lat: f64, lon: f64) -> String {
    let lat_i = lat.floor() as i32;
    let lon_i = lon.floor() as i32;
    let ns = if lat_i >= 0 { "N" } else { "S" };
    let ew = if lon_i >= 0 { "E" } else { "W" };
    format!("{}{:02}{}{:03}", ns, lat_i.abs(), ew, lon_i.abs())
}

fn print_help() {
    println!("arbx_cli — Arnis HD Pipeline");
    println!();
    println!("Generates high-fidelity Roblox world manifests from real-world geodata.");
    println!("Works for any location on Earth. Outputs Schema 0.4.0 JSON manifests.");
    println!();
    println!("USAGE:");
    println!("  arbx_cli <COMMAND> [OPTIONS]");
    println!();
    println!("COMMANDS:");
    println!("  compile    Build a chunk manifest from geodata sources");
    println!("  sample     Emit a synthetic sample manifest for testing");
    println!("  stats      Print statistics for a manifest file");
    println!("  validate   Validate a manifest against the schema");
    println!("  diff       Compare two manifest files");
    println!("  scene-index Build a compact per-chunk scene-audit summary");
    println!("  scene-audit Compare Studio scene markers against manifest truth");
    println!("  config     Emit a default world configuration JSON");
    println!("  explain    Print the full pipeline architecture for agents");
    println!();
    println!("COMPILE OPTIONS:");
    println!("  --source PATH          Input Overpass JSON file (omit for synthetic data)");
    println!("  --live                 Fetch live from Overpass API (auto-cached to --cache-dir)");
    println!("  --bbox S,W,N,E         Bounding box: min_lat,min_lon,max_lat,max_lon");
    println!("                         Example: --bbox 30.26,-97.75,30.27,-97.74 (Austin TX)");
    println!("  --out PATH             Output manifest file (default: stdout)");
    println!("  --world-name NAME      World name in manifest metadata (default: ExportedWorld)");
    println!("  --meters-per-stud N    Scale factor (default: 0.3 = Roblox humanoid proportional)");
    println!("  --terrain-cell-size N  Terrain grid precision in studs (default: 2, range: 1-32)");
    println!("                         Lower = more detailed terrain, more memory");
    println!("  --satellite [DIR]      Enable satellite material classification");
    println!("                         Fetches ESRI z19 imagery, caches to DIR (default: out/tiles/satellite)");
    println!("  --cache-dir PATH       Overpass API response cache (default: out/overpass)");
    println!();
    println!("QUALITY PROFILES:");
    println!(
        "  --profile insane       cell=1 sat=on  (256x256 grid, ~2GB RAM, M5 Max / workstation)"
    );
    println!("  --profile high         cell=2 sat=on  (128x128 grid, ~512MB RAM) [default]");
    println!("  --profile balanced     cell=4 sat=off (64x64 grid, ~128MB RAM, 8GB machines)");
    println!("  --profile fast         cell=8 sat=off (32x32 grid, ~32MB RAM, CI/testing)");
    println!("  --yolo                 Alias for --profile insane");
    println!();
    println!("SAMPLE OPTIONS:");
    println!("  --out PATH             Output file (default: stdout)");
    println!("  --grid X,Z             Multi-chunk grid dimensions (default: 1,1)");
    println!();
    println!("OTHER:");
    println!("  --help, -h             Show this help");
    println!("  --version, -V          Show version");
    println!();
    println!("EXAMPLES:");
    println!("  # Austin downtown, maximum fidelity");
    println!("  arbx_cli compile --source data/austin_overpass.json --yolo --out out/austin.json");
    println!();
    println!("  # Live fetch any city, high quality");
    println!("  arbx_cli compile --live --bbox 35.68,139.75,35.69,139.76 --world-name Tokyo --out out/tokyo.json");
    println!();
    println!("  # CI/testing: fast synthetic export");
    println!("  arbx_cli compile --profile fast --out out/test.json");
    println!();
    println!("  # Validate an existing manifest");
    println!("  arbx_cli validate out/austin.json");
    println!();
    println!("  # Compare two exports");
    println!("  arbx_cli diff out/v1.json out/v2.json");
    println!();
    println!("  # Build a compact chunk summary for fast scene audits");
    println!(
        "  arbx_cli scene-index --manifest out/austin.json --json-out out/austin.scene-index.json"
    );
    println!();
    println!("  # Compare Studio scene markers against manifest truth");
    println!("  arbx_cli scene-audit --manifest-summary out/austin.scene-index.json --log studio.log --marker ARNIS_SCENE_EDIT");
    println!();
    println!("  # Get pipeline info (for AI agents)");
    println!("  arbx_cli explain");
    println!();
    println!("OUTPUT FORMAT:");
    println!("  Schema 0.4.0 JSON manifest with:");
    println!("  - metersPerStud: 0.3 (configurable)");
    println!("  - Chunks with terrain grids, roads, buildings, water, props, landuse, barriers");
    println!("  - DEM-derived elevation for all features");
    println!("  - Satellite-classified roof/ground materials (when --satellite is used)");
    println!("  - All coordinates in stud-space relative to chunk origins");
    println!();
    println!("EXIT CODES:");
    println!("  0  Success");
    println!("  1  Error (message on stderr)");
}

fn cmd_sample(args: &[String]) -> Result<(), String> {
    let mut out_path: Option<PathBuf> = None;
    let mut grid = (1, 1);

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--out" => {
                let value = args.get(i + 1).ok_or("--out requires a path")?;
                out_path = Some(PathBuf::from(value));
                i += 2;
            }
            "--grid" => {
                let value = args.get(i + 1).ok_or("--grid requires X,Z")?;
                let parts: Vec<&str> = value.split(',').collect();
                if parts.len() != 2 {
                    return Err("--grid requires X,Z format".to_string());
                }
                let x = parts[0].parse::<i32>().map_err(|_| "invalid X in grid")?;
                let z = parts[1].parse::<i32>().map_err(|_| "invalid Z in grid")?;
                grid = (x, z);
                i += 2;
            }
            other => {
                return Err(format!("unknown argument to sample: {other}"));
            }
        }
    }

    let start = Instant::now();
    let manifest = build_sample_multi_chunk(grid.0, grid.1).to_json_pretty();
    let duration = start.elapsed();

    if let Some(path) = out_path {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| format!("create dir failed: {err}"))?;
        }
        fs::write(&path, manifest).map_err(|err| format!("write failed: {err}"))?;
        println!("Wrote {} in {:?}", path.display(), duration);
    } else {
        print!("{manifest}");
        eprintln!("Generated in {:?}", duration);
    }

    Ok(())
}

fn cmd_compile(args: &[String]) -> Result<(), String> {
    let mut out_path: Option<PathBuf> = None;
    let mut source_path: Option<PathBuf> = None;
    // Default bbox covers downtown Austin. Overridden by --bbox to match the OSM fetch area.
    let mut bbox = BoundingBox::new(30.26, -97.75, 30.27, -97.74);
    // 0.3 = Roblox humanoid-scale. Use --meters-per-stud to override.
    let mut meters_per_stud: f64 = 0.3;
    // --live: fetch from the Overpass API instead of a local file.
    let mut live = false;
    // --cache-dir: where to store cached Overpass responses (default: out/overpass).
    let mut cache_dir = "out/overpass".to_string();
    // --satellite: optional satellite tile directory for material enrichment.
    let mut satellite_dir: Option<String> = None;
    // --terrain-cell-size: terrain grid cell size in studs (2 = high, 4 = balanced, 8 = fast).
    let mut terrain_cell_size: i32 = 2;
    // --world-name: name written into the manifest meta.
    let mut world_name = "ExportedWorld".to_string();

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--out" => {
                let value = args.get(i + 1).ok_or("--out requires a path")?;
                out_path = Some(PathBuf::from(value));
                i += 2;
            }
            "--source" => {
                let value = args.get(i + 1).ok_or("--source requires a path")?;
                source_path = Some(PathBuf::from(value));
                i += 2;
            }
            "--bbox" => {
                let value = args
                    .get(i + 1)
                    .ok_or("--bbox requires MIN_LAT,MIN_LON,MAX_LAT,MAX_LON")?;
                let p: Vec<f64> = value
                    .split(',')
                    .map(|s| {
                        s.trim()
                            .parse::<f64>()
                            .map_err(|_| format!("invalid number in bbox: {}", s))
                    })
                    .collect::<Result<Vec<f64>, String>>()?;
                if p.len() != 4 {
                    return Err("--bbox requires 4 values".to_string());
                }
                bbox = BoundingBox::new(p[0], p[1], p[2], p[3]);
                i += 2;
            }
            "--world-name" => {
                world_name = args
                    .get(i + 1)
                    .ok_or("--world-name requires a name")?
                    .clone();
                i += 2;
            }
            "--meters-per-stud" => {
                let value = args
                    .get(i + 1)
                    .ok_or("--meters-per-stud requires a number")?;
                meters_per_stud = value
                    .parse::<f64>()
                    .map_err(|_| format!("invalid --meters-per-stud value: {value}"))?;
                if meters_per_stud <= 0.0 {
                    return Err("--meters-per-stud must be positive".to_string());
                }
                i += 2;
            }
            "--live" => {
                live = true;
                i += 1;
            }
            "--cache-dir" => {
                let value = args.get(i + 1).ok_or("--cache-dir requires a path")?;
                cache_dir = value.clone();
                i += 2;
            }
            "--terrain-cell-size" => {
                let value = args
                    .get(i + 1)
                    .ok_or("--terrain-cell-size requires a number")?;
                terrain_cell_size = value
                    .parse::<i32>()
                    .map_err(|_| format!("invalid --terrain-cell-size: {value}"))?;
                if !(1..=32).contains(&terrain_cell_size) {
                    return Err("--terrain-cell-size must be 1-32".to_string());
                }
                i += 2;
            }
            "--profile" => {
                let profile = args.get(i + 1).ok_or("--profile requires a preset name")?;
                match profile.as_str() {
                    "insane" => {
                        terrain_cell_size = 1;
                        if satellite_dir.is_none() {
                            satellite_dir = Some("out/tiles/satellite".to_string());
                        }
                        eprintln!("Profile: insane — cell=1, satellite=on (36GB+ RAM)");
                    }
                    "high" => {
                        terrain_cell_size = 2;
                        if satellite_dir.is_none() {
                            satellite_dir = Some("out/tiles/satellite".to_string());
                        }
                        eprintln!("Profile: high — cell=2, satellite=on (16GB+ RAM)");
                    }
                    "balanced" => {
                        terrain_cell_size = 4;
                        eprintln!("Profile: balanced — cell=4 (8GB+ RAM)");
                    }
                    "fast" => {
                        terrain_cell_size = 8;
                        eprintln!("Profile: fast — cell=8 (4GB+ RAM)");
                    }
                    other => {
                        return Err(format!(
                            "unknown profile: {other} (valid: insane, high, balanced, fast)"
                        ));
                    }
                }
                i += 2;
            }
            "--yolo" => {
                terrain_cell_size = 1; // 256×256 grid = 65,536 cells per chunk
                                       // satellite enabled automatically
                if satellite_dir.is_none() {
                    satellite_dir = Some("out/tiles/satellite".to_string());
                }
                eprintln!(
                    "YOLO MODE (--profile insane): terrain cell=1, satellite=on, maximum fidelity"
                );
                i += 1;
            }
            "--satellite" => {
                // Optional tile directory argument: use it if the next token doesn't start with '-'
                if let Some(next) = args.get(i + 1) {
                    if !next.starts_with('-') {
                        satellite_dir = Some(next.clone());
                        i += 2;
                        continue;
                    }
                }
                satellite_dir = Some("out/tiles/satellite".to_string());
                i += 1;
            }
            other => {
                return Err(format!("unknown argument to compile: {other}"));
            }
        }
    }

    let start = Instant::now();

    let adapter: Box<dyn arbx_pipeline::SourceAdapter> = if let Some(path) = &source_path {
        // --source always uses the file-based adapter regardless of --live
        if path.to_string_lossy().ends_with(".json") {
            let content =
                fs::read_to_string(path).map_err(|e| format!("failed to read source: {}", e))?;
            if content.contains("\"elements\"") {
                Box::new(arbx_pipeline::OverpassAdapter {
                    path: path.clone(),
                    meters_per_stud,
                })
            } else {
                Box::new(arbx_pipeline::FileSourceAdapter { path: path.clone() })
            }
        } else {
            Box::new(arbx_pipeline::FileSourceAdapter { path: path.clone() })
        }
    } else if live {
        // --live with no --source: fetch from the Overpass API
        Box::new(arbx_pipeline::LiveOverpassAdapter {
            bbox,
            meters_per_stud,
            cache_dir,
        })
    } else {
        Box::new(arbx_pipeline::SyntheticAustinAdapter { meters_per_stud })
    };

    println!(
        "Compiling from {}... (meters_per_stud={meters_per_stud})",
        adapter.name()
    );

    let config = ExportConfig {
        meters_per_stud,
        terrain_cell_size,
        world_name: world_name.clone(),
        ..ExportConfig::default()
    };

    // ── Create elevation provider BEFORE the pipeline so the enrichment
    //    stage can inject DEM-derived Y values into every feature. ──────────

    // Compute the SRTM tile name from the bbox center (supports any worldwide location).
    let tile_name = srtm_tile_name(bbox.center().lat, bbox.center().lon);
    let hgt_path = PathBuf::from(format!("data/{}.hgt", tile_name));
    if !hgt_path.exists() {
        eprintln!("Attempting to download SRTM elevation tile {tile_name}.hgt...");
        let gz_path = PathBuf::from(format!("data/{}.hgt.gz", tile_name));
        let url = format!(
            "https://s3.amazonaws.com/elevation-tiles-prod/skadi/{}/{}.hgt.gz",
            &tile_name[..3],
            tile_name
        );
        let status = std::process::Command::new("curl")
            .args([
                "-L",
                "-o",
                gz_path.to_str().unwrap(),
                url.as_str(),
                "--silent",
                "--fail",
                "--user-agent",
                "arnis-roblox/1.0 (open-source educational project)",
                "--retry",
                "3",
                "--retry-delay",
                "5",
            ])
            .status();
        if status.map(|s| s.success()).unwrap_or(false) {
            let _ = std::process::Command::new("gunzip")
                .arg(gz_path.to_str().unwrap())
                .status();
            if hgt_path.exists() {
                eprintln!("Downloaded {tile_name}.hgt successfully.");
            }
        } else {
            eprintln!("Could not download SRTM tile, using flat elevation.");
        }
    }

    let elevation: Box<dyn arbx_geo::ElevationProvider> = {
        // Try Terrarium tiles first (no API key required, auto-cached).
        match TerrariumElevationProvider::new(&bbox, TerrariumElevationProvider::DEFAULT_ZOOM) {
            Ok(terrarium) => {
                let center = bbox.center();
                let base = terrarium.sample_height_at(center);
                eprintln!(
                    "Using Terrarium elevation, base offset = {:.1}m at bbox center",
                    base
                );
                Box::new(OffsetElevationProvider::new(Box::new(terrarium), base))
            }
            Err(e) => {
                eprintln!("Terrarium tiles unavailable ({e}), falling back to SRTM/flat.");
                if hgt_path.exists() {
                    let hgt = HgtElevationProvider::new(PathBuf::from("data"));
                    let base = hgt.sample_height_at(bbox.center());
                    eprintln!(
                        "Using SRTM elevation, base offset = {:.1}m at bbox center",
                        base
                    );
                    Box::new(OffsetElevationProvider::new(Box::new(hgt), base))
                } else {
                    eprintln!("No SRTM tile found, using flat elevation.");
                    Box::new(FlatElevationProvider { height: 0.0 })
                }
            }
        }
    };

    // ── Run pipeline with elevation enrichment as the final stage ──────────
    let enrichment = ElevationEnrichmentStage {
        elevation: elevation.as_ref(),
        meters_per_stud,
        bbox_center: bbox.center(),
    };

    let stages: [&dyn arbx_pipeline::PipelineStage; 4] = [
        &ValidateStage,
        &NormalizeStage,
        &TriangulateStage,
        &enrichment,
    ];

    let ctx = run_pipeline(adapter.as_ref(), bbox, &stages)
        .map_err(|e| format!("pipeline failed: {:?}", e))?;

    let mut sat_provider = satellite_dir.as_deref().map(SatelliteTileProvider::new);
    let manifest = export_to_chunks(
        ctx.features,
        ctx.bbox,
        &config,
        elevation.as_ref(),
        sat_provider.as_mut(),
    );
    // Rust export remains the single authoritative partition function for additive chunkRefs metadata.
    let manifest = manifest.to_json_pretty();
    let duration = start.elapsed();

    if let Some(path) = out_path {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| format!("create dir failed: {err}"))?;
        }
        fs::write(&path, manifest).map_err(|err| format!("write failed: {err}"))?;
        println!("Compiled and wrote {} in {:?}", path.display(), duration);
    } else {
        print!("{manifest}");
        eprintln!("Compiled in {:?}", duration);
    }

    Ok(())
}

fn cmd_config(args: &[String]) -> Result<(), String> {
    let mut out_path: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--out" => {
                let value = args.get(i + 1).ok_or("--out requires a path")?;
                out_path = Some(PathBuf::from(value));
                i += 2;
            }
            other => {
                return Err(format!("unknown argument to config: {other}"));
            }
        }
    }

    let config_json = r#"{
  "metersPerStud": 0.3,
  "chunkSizeStuds": 256,
  "terrainMode": "voxel",
  "roadMode": "mesh",
  "buildingMode": "shellMesh",
  "streamingEnabled": true,
  "streamingTargetRadius": 1024,
  "instanceBudget": {
    "maxPerChunk": 1500,
    "maxPropsPerChunk": 250
  }
}"#;

    if let Some(path) = out_path {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| format!("create dir failed: {err}"))?;
        }
        fs::write(&path, config_json).map_err(|err| format!("write failed: {err}"))?;
        println!("Wrote configuration to {}", path.display());
    } else {
        println!("{config_json}");
    }

    Ok(())
}

fn cmd_stats(args: &[String]) -> Result<(), String> {
    let path = args
        .first()
        .ok_or("stats requires a path to a manifest file")?;
    let content =
        fs::read_to_string(path).map_err(|e| format!("failed to read manifest: {}", e))?;

    let v: serde_json::Value =
        serde_json::from_str(&content).map_err(|e| format!("invalid JSON: {}", e))?;

    println!("Manifest: {}", path);
    println!("Version:  {}", v["schemaVersion"]);
    if let Some(meta) = v.get("meta") {
        println!("World:    {}", meta["worldName"]);
        println!("Features: {}", meta["totalFeatures"]);
        println!("Source:   {}", meta["source"]);
    }

    if let Some(chunks) = v["chunks"].as_array() {
        println!("Chunks:   {}", chunks.len());
        let mut total_roads = 0;
        let mut total_rails = 0;
        let mut total_bldgs = 0;
        let mut total_props = 0;
        for c in chunks {
            total_roads += c["roads"].as_array().map(|a| a.len() as u64).unwrap_or(0);
            total_rails += c["rails"].as_array().map(|a| a.len() as u64).unwrap_or(0);
            total_bldgs += c["buildings"]
                .as_array()
                .map(|a| a.len() as u64)
                .unwrap_or(0);
            total_props += c["props"].as_array().map(|a| a.len() as u64).unwrap_or(0);
        }
        println!("  - Roads:     {}", total_roads);
        println!("  - Rails:     {}", total_rails);
        println!("  - Buildings: {}", total_bldgs);
        println!("  - Props:     {}", total_props);
    }

    Ok(())
}

fn cmd_validate(args: &[String]) -> Result<(), String> {
    let path = args
        .first()
        .ok_or("validate requires a path to a manifest file")?;
    let start = Instant::now();

    let content =
        fs::read_to_string(path).map_err(|e| format!("failed to read manifest: {}", e))?;
    let v: serde_json::Value =
        serde_json::from_str(&content).map_err(|e| format!("invalid JSON: {}", e))?;

    // Validate top-level structure
    let schema_version = v
        .get("schemaVersion")
        .and_then(|v| v.as_str())
        .ok_or("missing or invalid schemaVersion")?;

    if schema_version != "0.4.0" {
        return Err(format!(
            "unsupported schemaVersion: {} (expected 0.4.0)",
            schema_version
        ));
    }

    // Validate meta section
    let meta = v.get("meta").ok_or("missing meta section")?;
    let required_meta = [
        "worldName",
        "generator",
        "source",
        "metersPerStud",
        "chunkSizeStuds",
        "bbox",
        "totalFeatures",
    ];
    for field in &required_meta {
        if meta.get(field).is_none() {
            return Err(format!("meta missing required field: {}", field));
        }
    }

    // Validate bbox
    let bbox = meta.get("bbox").ok_or("missing bbox")?;
    let bbox_fields = ["minLat", "minLon", "maxLat", "maxLon"];
    for field in &bbox_fields {
        if bbox.get(field).and_then(|v| v.as_f64()).is_none() {
            return Err(format!("bbox missing required field: {}", field));
        }
    }

    // Validate chunks
    let chunks = v
        .get("chunks")
        .and_then(|v| v.as_array())
        .ok_or("missing or invalid chunks array")?;

    if chunks.is_empty() {
        return Err("chunks array is empty".to_string());
    }

    for (i, chunk) in chunks.iter().enumerate() {
        let prefix = format!("chunks[{}]", i);

        // Validate chunk id
        if chunk.get("id").and_then(|v| v.as_str()).is_none() {
            return Err(format!("{} missing id", prefix));
        }

        // Validate originStuds
        let origin = chunk
            .get("originStuds")
            .ok_or(format!("{} missing originStuds", prefix))?;
        let origin_fields = ["x", "y", "z"];
        for field in &origin_fields {
            if origin.get(field).and_then(|v| v.as_f64()).is_none() {
                return Err(format!("{}.originStuds missing field: {}", prefix, field));
            }
        }

        // Validate terrain if present
        if let Some(terrain) = chunk.get("terrain") {
            let terrain_fields = ["cellSizeStuds", "width", "depth", "heights", "material"];
            for field in &terrain_fields {
                if terrain.get(field).is_none() {
                    return Err(format!("{}.terrain missing field: {}", prefix, field));
                }
            }
            let heights = terrain
                .get("heights")
                .and_then(|v| v.as_array())
                .ok_or(format!("{}.terrain.heights must be an array", prefix))?;
            let width = terrain.get("width").and_then(|v| v.as_u64()).unwrap_or(0);
            let depth = terrain.get("depth").and_then(|v| v.as_u64()).unwrap_or(0);
            let expected = width * depth;
            if heights.len() as u64 != expected {
                return Err(format!(
                    "{}.terrain.heights length mismatch: expected {}, got {}",
                    prefix,
                    expected,
                    heights.len()
                ));
            }
        }

        // Validate roads
        if let Some(roads) = chunk.get("roads").and_then(|v| v.as_array()) {
            for (j, road) in roads.iter().enumerate() {
                let road_prefix = format!("{}.roads[{}]", prefix, j);
                if road.get("id").and_then(|v| v.as_str()).is_none() {
                    return Err(format!("{} missing id", road_prefix));
                }
                if road.get("widthStuds").and_then(|v| v.as_f64()).is_none() {
                    return Err(format!("{} missing widthStuds", road_prefix));
                }
                let points = road
                    .get("points")
                    .and_then(|v| v.as_array())
                    .ok_or(format!("{} missing points", road_prefix))?;
                if points.len() < 2 {
                    return Err(format!(
                        "{}.points must have at least 2 points",
                        road_prefix
                    ));
                }
            }
        }

        // Validate buildings
        if let Some(buildings) = chunk.get("buildings").and_then(|v| v.as_array()) {
            for (j, bldg) in buildings.iter().enumerate() {
                let bldg_prefix = format!("{}.buildings[{}]", prefix, j);
                if bldg.get("id").and_then(|v| v.as_str()).is_none() {
                    return Err(format!("{} missing id", bldg_prefix));
                }
                if bldg.get("footprint").and_then(|v| v.as_array()).is_none() {
                    return Err(format!("{} missing footprint", bldg_prefix));
                }
                if bldg.get("baseY").and_then(|v| v.as_f64()).is_none() {
                    return Err(format!("{} missing baseY", bldg_prefix));
                }
                if bldg.get("height").and_then(|v| v.as_f64()).is_none() {
                    return Err(format!("{} missing height", bldg_prefix));
                }
            }
        }
    }

    let duration = start.elapsed();
    println!("✓ Manifest validated successfully: {}", path);
    println!("  Version: {}", schema_version);
    println!("  Chunks: {}", chunks.len());
    println!("  Validated in {:?}", duration);

    Ok(())
}

fn cmd_diff(args: &[String]) -> Result<(), String> {
    if args.len() < 2 {
        return Err("diff requires two manifest paths".to_string());
    }
    let m1_path = &args[0];
    let m2_path = &args[1];

    let m1_content =
        fs::read_to_string(m1_path).map_err(|e| format!("failed to read {}: {}", m1_path, e))?;
    let m2_content =
        fs::read_to_string(m2_path).map_err(|e| format!("failed to read {}: {}", m2_path, e))?;

    let v1: serde_json::Value = serde_json::from_str(&m1_content)
        .map_err(|e| format!("invalid JSON in {}: {}", m1_path, e))?;
    let v2: serde_json::Value = serde_json::from_str(&m2_content)
        .map_err(|e| format!("invalid JSON in {}: {}", m2_path, e))?;

    if v1["schemaVersion"] != v2["schemaVersion"] {
        println!(
            "Schema versions differ: {} vs {}",
            v1["schemaVersion"], v2["schemaVersion"]
        );
    }

    let c1 = v1["chunks"].as_array().map(|a| a.len()).unwrap_or(0);
    let c2 = v2["chunks"].as_array().map(|a| a.len()).unwrap_or(0);

    if c1 != c2 {
        println!("Chunk count differs: {} vs {}", c1, c2);
    } else {
        println!("Both manifests have {} chunks", c1);
    }

    let f1 = v1["meta"]["totalFeatures"].as_u64().unwrap_or(0);
    let f2 = v2["meta"]["totalFeatures"].as_u64().unwrap_or(0);

    if f1 != f2 {
        println!("Total features differ: {} vs {}", f1, f2);
    }

    Ok(())
}

fn safe_f64(value: Option<&Value>) -> f64 {
    value.and_then(Value::as_f64).unwrap_or(0.0)
}

fn parse_latest_marker_from_str(log_content: &str, marker: &str) -> Result<Value, String> {
    let prefix = format!("{marker} ");
    let mut latest_payload: Option<Value> = None;
    let mut latest_error: Option<String> = None;
    for line in log_content.lines() {
        let Some(marker_index) = line.find(&prefix) else {
            continue;
        };
        let payload = &line[marker_index + prefix.len()..];
        match serde_json::from_str::<Value>(payload.trim()) {
            Ok(value) if value.is_object() => {
                latest_payload = Some(value);
            }
            Ok(_) => {}
            Err(err) => {
                latest_error = Some(format!("invalid {marker} payload: {err}"));
            }
        }
    }
    if let Some(payload) = latest_payload {
        Ok(payload)
    } else if let Some(error) = latest_error {
        Err(error)
    } else {
        Err(format!("no {marker} marker found in log"))
    }
}

fn chunk_center(chunk: &Value, chunk_size: f64) -> (f64, f64) {
    let origin = chunk.get("originStuds").and_then(Value::as_object);
    let origin_x = origin
        .and_then(|value| value.get("x"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let origin_z = origin
        .and_then(|value| value.get("z"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    (origin_x + chunk_size * 0.5, origin_z + chunk_size * 0.5)
}

fn ratio(actual: f64, expected: f64) -> f64 {
    if expected <= 0.0 {
        if actual <= 0.0 {
            1.0
        } else {
            0.0
        }
    } else {
        actual / expected
    }
}

fn build_manifest_zone_summary(manifest: &Value, payload: &Value) -> Result<Value, String> {
    let meta = manifest
        .get("meta")
        .and_then(Value::as_object)
        .ok_or("manifest missing meta")?;
    let chunk_size = safe_f64(meta.get("chunkSizeStuds"));
    let focus = payload.get("focus").and_then(Value::as_object);
    let scene = payload.get("scene").and_then(Value::as_object);
    let focus_x = focus
        .and_then(|value| value.get("x"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let focus_z = focus
        .and_then(|value| value.get("z"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let radius = payload.get("radius").and_then(Value::as_f64).unwrap_or(0.0);
    let radius_sq = radius * radius;
    let requested_chunk_ids: HashSet<String> = scene
        .and_then(|value| value.get("chunkIds"))
        .and_then(Value::as_array)
        .map(|chunk_ids| {
            chunk_ids
                .iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect()
        })
        .unwrap_or_default();

    let chunks = manifest
        .get("chunks")
        .and_then(Value::as_array)
        .ok_or("manifest missing chunks")?;

    #[derive(Default, Clone)]
    struct ChunkCounts {
        chunk_count: usize,
        road_count: usize,
        roads_with_sidewalks: usize,
        roads_with_crossings: usize,
        building_count: usize,
        chunks_with_roads: usize,
        chunks_with_sidewalk_roads: usize,
        chunks_with_crossing_roads: usize,
        chunks_with_buildings: usize,
    }

    let candidate_chunks: Vec<&Value> = if requested_chunk_ids.is_empty() {
        chunks
            .iter()
            .filter(|chunk| {
                let (center_x, center_z) = chunk_center(chunk, chunk_size.max(256.0));
                let dx = center_x - focus_x;
                let dz = center_z - focus_z;
                radius <= 0.0 || dx * dx + dz * dz <= radius_sq
            })
            .collect()
    } else {
        chunks
            .iter()
            .filter(|chunk| {
                chunk
                    .get("id")
                    .and_then(Value::as_str)
                    .map(|id| requested_chunk_ids.contains(id))
                    .unwrap_or(false)
            })
            .collect()
    };

    let chunk_ids: Vec<String> = candidate_chunks
        .iter()
        .filter_map(|chunk| {
            chunk
                .get("id")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
        .collect();

    let counts = candidate_chunks
        .par_iter()
        .map(|chunk| {
            let roads = chunk.get("roads").and_then(Value::as_array);
            let buildings = chunk.get("buildings").and_then(Value::as_array);
            let road_count = chunk
                .get("roadCount")
                .and_then(Value::as_u64)
                .map(|value| value as usize)
                .unwrap_or_else(|| roads.map_or(0, Vec::len));
            let roads_with_sidewalks = chunk
                .get("roadsWithSidewalks")
                .and_then(Value::as_u64)
                .map(|value| value as usize)
                .unwrap_or_else(|| {
                    roads.map_or(0, |values| {
                        values
                            .iter()
                            .filter(|road| {
                                road.get("hasSidewalk")
                                    .and_then(Value::as_bool)
                                    .unwrap_or(false)
                                    || road
                                        .get("subkind")
                                        .and_then(Value::as_str)
                                        .is_some_and(|value| value == "sidewalk")
                                    || road
                                        .get("sidewalk")
                                        .and_then(Value::as_str)
                                        .is_some_and(|value| value != "no")
                            })
                            .count()
                    })
                });
            let roads_with_crossings = chunk
                .get("roadsWithCrossings")
                .and_then(Value::as_u64)
                .map(|value| value as usize)
                .unwrap_or_else(|| {
                    roads.map_or(0, |values| {
                        values
                            .iter()
                            .filter(|road| {
                                road.get("subkind")
                                    .and_then(Value::as_str)
                                    .is_some_and(|value| value == "crossing")
                            })
                            .count()
                    })
                });
            let building_count = chunk
                .get("buildingCount")
                .and_then(Value::as_u64)
                .map(|value| value as usize)
                .unwrap_or_else(|| buildings.map_or(0, Vec::len));
            let chunks_with_roads = chunk
                .get("chunksWithRoads")
                .and_then(Value::as_bool)
                .unwrap_or_else(|| roads.is_some_and(|value| !value.is_empty()));
            let chunks_with_sidewalk_roads = chunk
                .get("chunksWithSidewalkRoads")
                .and_then(Value::as_bool)
                .unwrap_or(roads_with_sidewalks > 0);
            let chunks_with_crossing_roads = chunk
                .get("chunksWithCrossingRoads")
                .and_then(Value::as_bool)
                .unwrap_or(roads_with_crossings > 0);
            let chunks_with_buildings = chunk
                .get("chunksWithBuildings")
                .and_then(Value::as_bool)
                .unwrap_or_else(|| buildings.is_some_and(|value| !value.is_empty()));
            ChunkCounts {
                chunk_count: 1,
                road_count,
                roads_with_sidewalks,
                roads_with_crossings,
                building_count,
                chunks_with_roads: usize::from(chunks_with_roads),
                chunks_with_sidewalk_roads: usize::from(chunks_with_sidewalk_roads),
                chunks_with_crossing_roads: usize::from(chunks_with_crossing_roads),
                chunks_with_buildings: usize::from(chunks_with_buildings),
            }
        })
        .reduce(ChunkCounts::default, |mut left, right| {
            left.chunk_count += right.chunk_count;
            left.road_count += right.road_count;
            left.roads_with_sidewalks += right.roads_with_sidewalks;
            left.roads_with_crossings += right.roads_with_crossings;
            left.building_count += right.building_count;
            left.chunks_with_roads += right.chunks_with_roads;
            left.chunks_with_sidewalk_roads += right.chunks_with_sidewalk_roads;
            left.chunks_with_crossing_roads += right.chunks_with_crossing_roads;
            left.chunks_with_buildings += right.chunks_with_buildings;
            left
        });

    Ok(json!({
        "chunkCount": counts.chunk_count,
        "chunkIds": chunk_ids,
        "roadCount": counts.road_count,
        "roadsWithSidewalks": counts.roads_with_sidewalks,
        "roadsWithCrossings": counts.roads_with_crossings,
        "buildingCount": counts.building_count,
        "chunksWithRoads": counts.chunks_with_roads,
        "chunksWithSidewalkRoads": counts.chunks_with_sidewalk_roads,
        "chunksWithCrossingRoads": counts.chunks_with_crossing_roads,
        "chunksWithBuildings": counts.chunks_with_buildings,
    }))
}

fn build_scene_manifest_index_from_str(manifest_content: &str) -> Result<Value, String> {
    let manifest: Value = serde_json::from_str(manifest_content)
        .map_err(|err| format!("invalid manifest JSON: {err}"))?;
    let meta = manifest
        .get("meta")
        .and_then(Value::as_object)
        .ok_or("manifest missing meta")?;
    let chunks = manifest
        .get("chunks")
        .and_then(Value::as_array)
        .ok_or("manifest missing chunks")?;

    let summarized_chunks: Vec<Value> = chunks
        .par_iter()
        .map(|chunk| {
            let roads = chunk.get("roads").and_then(Value::as_array);
            let buildings = chunk.get("buildings").and_then(Value::as_array);
            let roads_with_sidewalks = roads.map_or(0, |values| {
                values
                    .iter()
                    .filter(|road| {
                        road.get("hasSidewalk").and_then(Value::as_bool).unwrap_or(false)
                            || road
                                .get("subkind")
                                .and_then(Value::as_str)
                                .is_some_and(|value| value == "sidewalk")
                            || road
                                .get("sidewalk")
                                .and_then(Value::as_str)
                                .is_some_and(|value| value != "no")
                    })
                    .count()
            });
            let roads_with_crossings = roads.map_or(0, |values| {
                values
                    .iter()
                    .filter(|road| {
                        road
                            .get("subkind")
                            .and_then(Value::as_str)
                            .is_some_and(|value| value == "crossing")
                    })
                    .count()
            });
            json!({
                "id": chunk.get("id").cloned().unwrap_or(Value::Null),
                "originStuds": chunk.get("originStuds").cloned().unwrap_or_else(|| json!({"x": 0.0, "y": 0.0, "z": 0.0})),
                "roadCount": roads.map_or(0, Vec::len),
                "roadsWithSidewalks": roads_with_sidewalks,
                "roadsWithCrossings": roads_with_crossings,
                "buildingCount": buildings.map_or(0, Vec::len),
                "chunksWithRoads": roads.is_some_and(|value| !value.is_empty()),
                "chunksWithSidewalkRoads": roads_with_sidewalks > 0,
                "chunksWithCrossingRoads": roads_with_crossings > 0,
                "chunksWithBuildings": buildings.is_some_and(|value| !value.is_empty()),
            })
        })
        .collect();

    Ok(json!({
        "meta": {
            "worldName": meta.get("worldName").cloned().unwrap_or(Value::Null),
            "chunkSizeStuds": meta.get("chunkSizeStuds").cloned().unwrap_or(json!(256)),
            "schemaVersion": manifest.get("schemaVersion").cloned().unwrap_or(Value::Null),
            "sceneIndexVersion": SCENE_INDEX_VERSION,
        },
        "chunks": summarized_chunks,
    }))
}

fn build_scene_audit_report_from_str(
    manifest_content: &str,
    log_content: &str,
    marker: &str,
) -> Result<Value, String> {
    let manifest: Value = serde_json::from_str(manifest_content)
        .map_err(|err| format!("invalid manifest JSON: {err}"))?;
    let mut payload = parse_latest_marker_from_str(log_content, marker)?;
    let mut scene = payload
        .get("scene")
        .cloned()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}));
    let chunk_marker = format!("{marker}_CHUNKS");
    if let Ok(chunk_payload) = parse_latest_marker_from_str(log_content, &chunk_marker) {
        if let Some(chunk_ids) = chunk_payload.get("chunkIds").cloned() {
            if let Some(scene_object) = scene.as_object_mut() {
                scene_object.insert("chunkIds".to_string(), chunk_ids);
            }
        }
    }
    if let Some(payload_object) = payload.as_object_mut() {
        payload_object.insert("scene".to_string(), scene.clone());
    }
    let manifest_summary = build_manifest_zone_summary(&manifest, &payload)?;

    let scene_chunk_count = scene.get("chunkCount").and_then(Value::as_u64).unwrap_or(0);
    let scene_building_models = scene
        .get("buildingModelCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_buildings_with_direct_shell = scene
        .get("buildingModelsWithDirectShell")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_buildings_missing_direct_shell = scene
        .get("buildingModelsMissingDirectShell")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_merged_building_mesh_parts = scene
        .get("mergedBuildingMeshPartCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_building_shell_parts = scene
        .get("buildingShellPartCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_road_chunks = scene
        .get("chunksWithRoadGeometry")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_road_mesh_parts = scene
        .get("roadMeshPartCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_sidewalk_surface_parts = scene
        .get("sidewalkSurfacePartCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_crossing_surface_parts = scene
        .get("crossingSurfacePartCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_curb_surface_parts = scene
        .get("curbSurfacePartCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_chunks_with_sidewalk_surfaces = scene
        .get("chunksWithSidewalkSurfaces")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_chunks_with_crossing_surfaces = scene
        .get("chunksWithCrossingSurfaces")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_chunks_with_curb_surfaces = scene
        .get("chunksWithCurbSurfaces")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let scene_road_detail_parts = scene
        .get("roadDetailPartCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let manifest_chunk_count = manifest_summary
        .get("chunkCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let manifest_building_count = manifest_summary
        .get("buildingCount")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let manifest_road_chunk_count = manifest_summary
        .get("chunksWithRoads")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let manifest_sidewalk_road_count = manifest_summary
        .get("roadsWithSidewalks")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let manifest_crossing_road_count = manifest_summary
        .get("roadsWithCrossings")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let manifest_sidewalk_road_chunks = manifest_summary
        .get("chunksWithSidewalkRoads")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let manifest_crossing_road_chunks = manifest_summary
        .get("chunksWithCrossingRoads")
        .and_then(Value::as_u64)
        .unwrap_or(0);

    let mut findings = Vec::new();
    if scene_chunk_count < manifest_chunk_count {
        findings.push(json!({
            "severity": "high",
            "code": "scene_chunk_gap",
            "message": format!(
                "scene built {} chunks but manifest expected {}",
                scene_chunk_count, manifest_chunk_count
            )
        }));
    }
    if scene_building_models < manifest_building_count {
        findings.push(json!({
            "severity": "high",
            "code": "missing_building_models",
            "message": format!(
                "scene built {} building models but manifest expected {}",
                scene_building_models, manifest_building_count
            )
        }));
    }
    if manifest_road_chunk_count > 0 && scene_road_chunks < manifest_road_chunk_count {
        findings.push(json!({
            "severity": "high",
            "code": "missing_road_geometry",
            "message": format!(
                "scene has road geometry in {} chunks but manifest expected {}",
                scene_road_chunks, manifest_road_chunk_count
            )
        }));
    }
    if manifest_sidewalk_road_chunks > 0
        && scene_chunks_with_sidewalk_surfaces < manifest_sidewalk_road_chunks
    {
        findings.push(json!({
            "severity": "high",
            "code": "missing_sidewalk_surfaces",
            "message": format!(
                "scene has sidewalk surfaces in {} chunks but manifest expected {} chunks with sidewalk roads",
                scene_chunks_with_sidewalk_surfaces, manifest_sidewalk_road_chunks
            )
        }));
    }
    if manifest_sidewalk_road_chunks > 0
        && scene_chunks_with_curb_surfaces < manifest_sidewalk_road_chunks
    {
        findings.push(json!({
            "severity": "medium",
            "code": "missing_curb_surfaces",
            "message": format!(
                "scene has curb surfaces in {} chunks but manifest expected {} chunks with sidewalk roads",
                scene_chunks_with_curb_surfaces, manifest_sidewalk_road_chunks
            )
        }));
    }
    if manifest_crossing_road_chunks > 0
        && scene_chunks_with_crossing_surfaces < manifest_crossing_road_chunks
    {
        findings.push(json!({
            "severity": if scene_chunks_with_crossing_surfaces == 0 { "high" } else { "medium" },
            "code": "missing_crossing_surfaces",
            "message": format!(
                "scene has crossing surfaces in {} chunks but manifest expected {} chunks with crossing ways",
                scene_chunks_with_crossing_surfaces, manifest_crossing_road_chunks
            )
        }));
    }

    let missing_direct_shell_ratio = ratio(
        scene_buildings_missing_direct_shell as f64,
        scene_building_models as f64,
    );
    let merged_building_mesh_ratio = ratio(
        scene_merged_building_mesh_parts as f64,
        scene_building_models as f64,
    );
    let road_detail_to_mesh_ratio = if scene_road_mesh_parts == 0 {
        if scene_road_detail_parts == 0 {
            1.0
        } else {
            f64::INFINITY
        }
    } else {
        scene_road_detail_parts as f64 / scene_road_mesh_parts as f64
    };

    if scene_buildings_missing_direct_shell > 0 {
        findings.push(json!({
            "severity": if missing_direct_shell_ratio >= 0.2 { "high" } else { "medium" },
            "code": "missing_direct_building_shells",
            "message": format!(
                "{} of {} building models are missing direct shell geometry",
                scene_buildings_missing_direct_shell, scene_building_models
            )
        }));
    }

    if scene_merged_building_mesh_parts > scene_building_shell_parts && scene_building_models > 0 {
        findings.push(json!({
            "severity": "medium",
            "code": "merged_building_geometry_dominates",
            "message": format!(
                "merged building mesh parts ({}) exceed direct shell parts ({}) in the audited scene",
                scene_merged_building_mesh_parts, scene_building_shell_parts
            )
        }));
    }

    if scene_road_detail_parts > 0 && road_detail_to_mesh_ratio > 8.0 {
        findings.push(json!({
            "severity": "medium",
            "code": "road_detail_overwhelms_mesh",
            "message": format!(
                "road detail parts ({}) outweigh road mesh parts ({}) by {:.2}x",
                scene_road_detail_parts, scene_road_mesh_parts, road_detail_to_mesh_ratio
            )
        }));
    }

    Ok(json!({
        "generatedAt": format!("{:?}", std::time::SystemTime::now()),
        "phase": payload.get("phase").cloned().unwrap_or(Value::Null),
        "rootName": payload.get("rootName").cloned().unwrap_or(Value::Null),
        "focus": payload.get("focus").cloned().unwrap_or(Value::Null),
        "radius": payload.get("radius").cloned().unwrap_or(Value::Null),
        "scene": scene,
        "manifest": manifest_summary,
        "summary": {
            "marker": marker,
            "chunk_ratio": ratio(scene_chunk_count as f64, manifest_chunk_count as f64),
            "building_model_ratio": ratio(scene_building_models as f64, manifest_building_count as f64),
            "road_geometry_ratio": ratio(scene_road_chunks as f64, manifest_road_chunk_count as f64),
            "sidewalk_chunk_presence_ratio": ratio(scene_chunks_with_sidewalk_surfaces as f64, manifest_sidewalk_road_chunks as f64),
            "crossing_chunk_presence_ratio": ratio(scene_chunks_with_crossing_surfaces as f64, manifest_crossing_road_chunks as f64),
            "curb_chunk_presence_ratio": ratio(scene_chunks_with_curb_surfaces as f64, manifest_sidewalk_road_chunks as f64),
            "sidewalk_surface_part_count": scene_sidewalk_surface_parts,
            "crossing_surface_part_count": scene_crossing_surface_parts,
            "curb_surface_part_count": scene_curb_surface_parts,
            "manifest_roads_with_sidewalks": manifest_sidewalk_road_count,
            "manifest_roads_with_crossings": manifest_crossing_road_count,
            "missing_direct_shell_ratio": missing_direct_shell_ratio,
            "direct_shell_coverage_ratio": ratio(scene_buildings_with_direct_shell as f64, scene_building_models as f64),
            "merged_building_mesh_ratio": merged_building_mesh_ratio,
            "road_detail_to_mesh_ratio": road_detail_to_mesh_ratio,
        },
        "findings": findings,
    }))
}

fn cmd_scene_index(args: &[String]) -> Result<(), String> {
    let mut manifest_path: Option<PathBuf> = None;
    let mut json_out: Option<PathBuf> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--manifest" => {
                manifest_path = Some(PathBuf::from(
                    args.get(i + 1).ok_or("--manifest requires a path")?,
                ));
                i += 2;
            }
            "--json-out" => {
                json_out = Some(PathBuf::from(
                    args.get(i + 1).ok_or("--json-out requires a path")?,
                ));
                i += 2;
            }
            other => return Err(format!("unknown argument to scene-index: {other}")),
        }
    }

    let manifest_path = manifest_path.ok_or("--manifest is required")?;
    let manifest_content = fs::read_to_string(&manifest_path)
        .map_err(|err| format!("failed to read manifest {}: {err}", manifest_path.display()))?;
    let index = build_scene_manifest_index_from_str(&manifest_content)?;
    let output = serde_json::to_string_pretty(&index)
        .map_err(|err| format!("failed to encode scene index: {err}"))?;

    if let Some(path) = json_out {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| format!("create dir failed: {err}"))?;
        }
        fs::write(&path, output).map_err(|err| format!("write failed: {err}"))?;
    } else {
        println!("{output}");
    }
    Ok(())
}

fn cmd_scene_audit(args: &[String]) -> Result<(), String> {
    let mut manifest_path: Option<PathBuf> = None;
    let mut manifest_summary_path: Option<PathBuf> = None;
    let mut log_path: Option<PathBuf> = None;
    let mut marker = "ARNIS_SCENE_PLAY".to_string();
    let mut json_out: Option<PathBuf> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--manifest" => {
                manifest_path = Some(PathBuf::from(
                    args.get(i + 1).ok_or("--manifest requires a path")?,
                ));
                i += 2;
            }
            "--manifest-summary" => {
                manifest_summary_path = Some(PathBuf::from(
                    args.get(i + 1)
                        .ok_or("--manifest-summary requires a path")?,
                ));
                i += 2;
            }
            "--log" => {
                log_path = Some(PathBuf::from(
                    args.get(i + 1).ok_or("--log requires a path")?,
                ));
                i += 2;
            }
            "--marker" => {
                marker = args.get(i + 1).ok_or("--marker requires a value")?.clone();
                i += 2;
            }
            "--json-out" => {
                json_out = Some(PathBuf::from(
                    args.get(i + 1).ok_or("--json-out requires a path")?,
                ));
                i += 2;
            }
            other => return Err(format!("unknown argument to scene-audit: {other}")),
        }
    }

    let manifest_source_path = manifest_summary_path
        .clone()
        .or(manifest_path.clone())
        .ok_or("--manifest or --manifest-summary is required")?;
    let log_path = log_path.ok_or("--log is required")?;
    let manifest_content = fs::read_to_string(&manifest_source_path).map_err(|err| {
        format!(
            "failed to read manifest source {}: {err}",
            manifest_source_path.display()
        )
    })?;
    let log_content = fs::read_to_string(&log_path)
        .map_err(|err| format!("failed to read log {}: {err}", log_path.display()))?;
    let mut report = build_scene_audit_report_from_str(&manifest_content, &log_content, &marker)?;
    if let Some(object) = report.as_object_mut() {
        object.insert(
            "manifestPath".to_string(),
            Value::String(manifest_source_path.display().to_string()),
        );
        object.insert(
            "logPath".to_string(),
            Value::String(log_path.display().to_string()),
        );
    }
    let output = serde_json::to_string_pretty(&report)
        .map_err(|err| format!("failed to encode report: {err}"))?;

    if let Some(path) = json_out {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| format!("create dir failed: {err}"))?;
        }
        fs::write(&path, output).map_err(|err| format!("write failed: {err}"))?;
    } else {
        println!("{output}");
    }

    Ok(())
}

fn cmd_explain() {
    println!("ARNIS HD PIPELINE — Architecture Overview");
    println!();
    println!("DATA FLOW:");
    println!("  Input → Overpass JSON / Live API → Feature Extraction → Elevation Enrichment");
    println!("  → Chunking → Satellite Classification → Schema 0.4.0 Manifest");
    println!();
    println!("SCHEMA VERSION: 0.4.0");
    println!("SCALE: 1 stud = 0.3 meters (configurable)");
    println!();
    println!("FEATURE TYPES IN MANIFEST:");
    println!("  terrain    Height grid with per-cell materials (satellite-classified)");
    println!("  roads      Polylines with lanes, surface, elevated/tunnel flags, sidewalk mode");
    println!("  rails      Polylines with track count");
    println!("  buildings  Polygon shells with height, roof shape/color/material, usage, rooms");
    println!("  water      Ribbons (rivers) or polygons (lakes) with surfaceY, holes for islands");
    println!("  props      Point instances: 25+ types (trees, lamps, fountains, bollards, etc.)");
    println!("  landuse    Ground polygons (parks, parking, forest, etc.)");
    println!("  barriers   Linear features (walls, fences, hedges, guard rails)");
    println!();
    println!("ELEVATION:");
    println!("  All feature Y positions are DEM-derived (Terrarium/SRTM).");
    println!("  Roblox builders read manifest values directly — no runtime re-sampling.");
    println!();
    println!("SATELLITE CLASSIFICATION:");
    println!("  When --satellite is enabled, the pipeline:");
    println!("  1. Fetches ESRI World Imagery tiles at z19 (~0.3m/pixel)");
    println!("  2. Classifies building roofs: Asphalt/Metal/Brick/WoodPlanks/Slate/Concrete");
    println!("  3. Classifies terrain ground cover: Grass/LeafyGrass/Concrete/Asphalt/Rock/Ground");
    println!("  4. Sets roof colors from satellite pixel values");
    println!();
    println!("ROBLOX IMPORT:");
    println!("  The manifest is consumed by ImportService in Roblox Studio.");
    println!("  Builders create Parts, EditableMesh, and Terrain voxels.");
    println!("  WorldConfig.lua controls all rendering parameters.");
    println!("  LOD system uses CollectionService tagging for distance culling.");
    println!("  Day/night cycle toggles street lights and window glow.");
    println!();
    println!("RUST CRATES:");
    println!("  arbx_geo             BoundingBox, elevation providers (Terrarium, SRTM, Flat)");
    println!("  arbx_pipeline        Feature extraction, pipeline stages (validate/normalize/triangulate/enrich)");
    println!(
        "  arbx_roblox_export   Chunker, builders, satellite tile provider, manifest serialisation"
    );
    println!("  arbx_cli             CLI entry point (this binary)");
    println!();
    println!("ROBLOX MODULES:");
    println!("  ImportService        Orchestrates chunk loading and builder dispatch");
    println!("  StreamingService     Loads/unloads chunks based on player proximity");
    println!("  ChunkSchema          Lua-side schema definition matching the JSON manifest");
    println!("  WorldConfig          Rendering knobs: scale, LOD, instance budgets");
    println!("  Migrations           Schema upgrade path for older manifests");
    println!("  Profiler             Timing and instance-count telemetry");
    println!();
    println!("PIPELINE STAGES (in order):");
    println!("  1. ValidateStage       Reject malformed or unsupported input features");
    println!("  2. NormalizeStage      Canonicalise tags, units, and coordinate winding");
    println!("  3. TriangulateStage    Decompose polygons for mesh builders");
    println!("  4. ElevationEnrichment Inject DEM-derived Y offsets into every feature");
    println!();
    println!("MANIFEST TOP-LEVEL STRUCTURE:");
    println!(r#"  {{ "schemaVersion": "0.4.0","#);
    println!(
        r#"    "meta": {{ worldName, generator, source, metersPerStud, chunkSizeStuds, bbox, totalFeatures }},"#
    );
    println!(
        r#"    "chunks": [ {{ id, originStuds, terrain, roads, rails, buildings, water, props, landuse, barriers }} ]"#
    );
    println!(r#"  }}"#);
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();

    let Some(command) = args.first().map(String::as_str) else {
        print_help();
        return;
    };

    let result = match command {
        "sample" => cmd_sample(&args[1..]),
        "compile" => cmd_compile(&args[1..]),
        "config" => cmd_config(&args[1..]),
        "stats" => cmd_stats(&args[1..]),
        "validate" => cmd_validate(&args[1..]),
        "diff" => cmd_diff(&args[1..]),
        "scene-index" => cmd_scene_index(&args[1..]),
        "scene-audit" => cmd_scene_audit(&args[1..]),
        "explain" => {
            cmd_explain();
            Ok(())
        }
        "--help" | "-h" | "help" => {
            print_help();
            Ok(())
        }
        "--version" | "-V" | "version" => {
            println!("arbx_cli 0.4.0 (arnis-roblox HD pipeline)");
            Ok(())
        }
        other => Err(format!("unknown command: {other}")),
    };

    if let Err(message) = result {
        eprintln!("error: {message}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn srtm_tile_name_austin() {
        // Austin, TX: center ~30.265, -97.745 → SW corner N30W098
        assert_eq!(srtm_tile_name(30.265, -97.745), "N30W098");
    }

    #[test]
    fn srtm_tile_name_tokyo() {
        // Tokyo: center ~35.685, 139.695 → SW corner N35E139
        assert_eq!(srtm_tile_name(35.685, 139.695), "N35E139");
    }

    #[test]
    fn srtm_tile_name_london() {
        // London: center ~51.505, -0.125 → SW corner N51W001
        assert_eq!(srtm_tile_name(51.505, -0.125), "N51W001");
    }

    #[test]
    fn srtm_tile_name_southern_hemisphere() {
        // Santiago, Chile: center ~-33.455, -70.645 → SW corner S34W071
        assert_eq!(srtm_tile_name(-33.455, -70.645), "S34W071");
    }

    #[test]
    fn srtm_tile_name_eastern_zero() {
        // Exactly on the prime meridian, northern hemisphere → N51E000
        assert_eq!(srtm_tile_name(51.5, 0.0), "N51E000");
    }

    fn write_temp_manifest(content: &str) -> NamedTempFile {
        let mut file = NamedTempFile::new().unwrap();
        file.write_all(content.as_bytes()).unwrap();
        file
    }

    #[test]
    fn diff_identical_manifests() {
        let content = r#"{
            "schemaVersion": "0.3.0",
            "meta": { "totalFeatures": 10 },
            "chunks": [{}, {}]
        }"#;
        let f1 = write_temp_manifest(content);
        let f2 = write_temp_manifest(content);
        assert!(cmd_diff(&[
            f1.path().to_str().unwrap().to_string(),
            f2.path().to_str().unwrap().to_string()
        ])
        .is_ok());
    }

    #[test]
    fn diff_different_versions() {
        let c1 = r#"{ "schemaVersion": "0.3.0", "meta": { "totalFeatures": 10 }, "chunks": [] }"#;
        let c2 = r#"{ "schemaVersion": "0.1.0", "meta": { "totalFeatures": 10 }, "chunks": [] }"#;
        let f1 = write_temp_manifest(c1);
        let f2 = write_temp_manifest(c2);
        assert!(cmd_diff(&[
            f1.path().to_str().unwrap().to_string(),
            f2.path().to_str().unwrap().to_string()
        ])
        .is_ok());
    }

    #[test]
    fn scene_audit_uses_latest_marker_and_exact_chunk_ids() {
        let manifest = r#"{
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SceneAuditTown",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [{ "id": "road_1" }, { "id": "road_2" }],
                    "buildings": [{ "id": "bldg_1" }, { "id": "bldg_2" }],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                },
                {
                    "id": "1_0",
                    "originStuds": { "x": 256, "y": 0, "z": 0 },
                    "roads": [{ "id": "road_3" }],
                    "buildings": [{ "id": "bldg_3" }],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;
        let log = r#"2026-03-20 18:35:01.000  ARNIS_SCENE_PLAY {"phase":"play","focus":{"x":64.0,"z":64.0},"radius":350.0,"rootName":"GeneratedWorld_Austin","scene":{"chunkCount":1,"buildingModelCount":1,"chunksWithBuildingModels":1,"roadTaggedPartCount":1,"chunksWithRoadGeometry":1}}
2026-03-20 18:35:02.000  noise
2026-03-20 18:35:03.000  ARNIS_SCENE_PLAY {"phase":"play","focus":{"x":128.0,"z":128.0},"radius":400.0,"rootName":"GeneratedWorld_Austin","scene":{"chunkCount":2,"chunkIds":["0_0","1_0"],"buildingModelCount":1,"buildingDetailPartCount":0,"chunksWithBuildingModels":1,"roadTaggedPartCount":0,"chunksWithRoadGeometry":0,"meshPartCount":0,"basePartCount":0}}"#;

        let report = build_scene_audit_report_from_str(manifest, log, "ARNIS_SCENE_PLAY").unwrap();

        assert_eq!(report["scene"]["chunkCount"], 2);
        assert_eq!(report["manifest"]["chunkCount"], 2);
        assert_eq!(report["manifest"]["buildingCount"], 3);
        assert_eq!(report["manifest"]["roadCount"], 3);
        assert_eq!(
            report["summary"]["building_model_ratio"].as_f64().unwrap(),
            1.0 / 3.0
        );
        assert_eq!(
            report["summary"]["road_geometry_ratio"].as_f64().unwrap(),
            0.0
        );
        assert_eq!(
            report["findings"]
                .as_array()
                .unwrap()
                .iter()
                .filter_map(|finding| finding.get("code").and_then(|code| code.as_str()))
                .collect::<Vec<_>>(),
            vec!["missing_building_models", "missing_road_geometry"]
        );
    }

    #[test]
    fn scene_audit_ignores_truncated_later_marker_if_last_valid_marker_exists() {
        let manifest = r#"{
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SceneAuditTown",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [],
                    "buildings": [],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;
        let log = r#"2026-03-20 18:35:03.000  ARNIS_SCENE_EDIT {"phase":"edit","focus":{"x":128.0,"z":128.0},"radius":400.0,"rootName":"GeneratedWorld_Austin","scene":{"chunkCount":1,"buildingModelCount":0,"chunksWithBuildingModels":0,"roadTaggedPartCount":0,"chunksWithRoadGeometry":0,"meshPartCount":0,"basePartCount":0}}
2026-03-20 18:35:04.000  ARNIS_SCENE_EDIT {"phase":"edit","focus":{"x":128.0,"z":128.0},"radius":400.0,"rootName":"GeneratedWorld_Austin","scene":{"chunkCount":1,"buildingModelCount":0,"chunksWithBuildingModels":0"#;

        let report = build_scene_audit_report_from_str(manifest, log, "ARNIS_SCENE_EDIT").unwrap();

        assert_eq!(report["phase"], "edit");
        assert_eq!(report["scene"]["chunkCount"], 1);
    }

    #[test]
    fn scene_audit_merges_chunk_marker_into_scene_payload() {
        let manifest = r#"{
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SceneAuditTown",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [{ "id": "road_1" }, { "id": "road_2" }],
                    "buildings": [{ "id": "bldg_1" }, { "id": "bldg_2" }],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                },
                {
                    "id": "1_0",
                    "originStuds": { "x": 256, "y": 0, "z": 0 },
                    "roads": [{ "id": "road_3" }],
                    "buildings": [{ "id": "bldg_3" }],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;
        let log = r#"2026-03-20 18:35:03.000  ARNIS_SCENE_PLAY_CHUNKS {"phase":"play","chunkIds":["0_0","1_0"]}
2026-03-20 18:35:04.000  ARNIS_SCENE_PLAY {"phase":"play","focus":{"x":64.0,"z":64.0},"radius":50.0,"rootName":"GeneratedWorld_Austin","scene":{"chunkCount":2,"buildingModelCount":1,"chunksWithBuildingModels":1,"roadTaggedPartCount":0,"chunksWithRoadGeometry":0,"meshPartCount":0,"basePartCount":0}}"#;

        let report = build_scene_audit_report_from_str(manifest, log, "ARNIS_SCENE_PLAY").unwrap();

        assert_eq!(report["manifest"]["chunkCount"], 2);
        assert_eq!(report["manifest"]["buildingCount"], 3);
    }

    #[test]
    fn scene_audit_flags_chunk_gap_without_chunk_ids() {
        let manifest = r#"{
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SceneAuditTown",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [],
                    "buildings": [],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                },
                {
                    "id": "1_0",
                    "originStuds": { "x": 256, "y": 0, "z": 0 },
                    "roads": [],
                    "buildings": [],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;
        let log = r#"2026-03-20 18:35:03.000  ARNIS_SCENE_EDIT {"phase":"edit","focus":{"x":128.0,"z":128.0},"radius":400.0,"rootName":"GeneratedWorld_Austin","scene":{"chunkCount":1,"buildingModelCount":0,"chunksWithBuildingModels":0,"roadTaggedPartCount":0,"chunksWithRoadGeometry":0,"meshPartCount":0,"basePartCount":0}}"#;

        let report = build_scene_audit_report_from_str(manifest, log, "ARNIS_SCENE_EDIT").unwrap();
        let codes = report["findings"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|finding| finding.get("code").and_then(|code| code.as_str()))
            .collect::<Vec<_>>();

        assert_eq!(report["manifest"]["chunkCount"], 2);
        assert!(codes.contains(&"scene_chunk_gap"));
    }

    #[test]
    fn scene_audit_flags_shell_loss_and_road_detail_skew() {
        let manifest = r#"{
            "meta": {
                "worldName": "SceneAuditTown",
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roadCount": 1,
                    "buildingCount": 3,
                    "chunksWithRoads": true,
                    "chunksWithBuildings": true
                }
            ]
        }"#;
        let log = r#"2026-03-20 18:35:04.000  ARNIS_SCENE_EDIT {"phase":"edit","focus":{"x":128.0,"z":128.0},"radius":200.0,"rootName":"GeneratedWorld_AustinPreview","scene":{"chunkCount":1,"buildingModelCount":3,"chunksWithBuildingModels":1,"roadTaggedPartCount":4,"chunksWithRoadGeometry":1,"meshPartCount":1,"basePartCount":40,"buildingModelsWithDirectShell":1,"buildingModelsMissingDirectShell":2,"mergedBuildingMeshPartCount":7,"buildingShellPartCount":3,"roadMeshPartCount":1,"roadDetailPartCount":30}}"#;

        let report = build_scene_audit_report_from_str(manifest, log, "ARNIS_SCENE_EDIT").unwrap();
        let codes = report["findings"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|finding| finding.get("code").and_then(|code| code.as_str()))
            .collect::<Vec<_>>();

        assert!(codes.contains(&"missing_direct_building_shells"));
        assert!(codes.contains(&"merged_building_geometry_dominates"));
        assert!(codes.contains(&"road_detail_overwhelms_mesh"));
    }

    #[test]
    fn scene_audit_flags_missing_sidewalk_and_curb_surfaces() {
        let manifest = r#"{
            "meta": {
                "worldName": "SceneAuditTown",
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [
                        { "id": "road_1", "hasSidewalk": true }
                    ],
                    "buildings": [],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;
        let log = r#"2026-03-20 18:35:04.000  ARNIS_SCENE_EDIT {"phase":"edit","focus":{"x":128.0,"z":128.0},"radius":200.0,"rootName":"GeneratedWorld_AustinPreview","scene":{"chunkCount":1,"buildingModelCount":0,"chunksWithBuildingModels":0,"roadTaggedPartCount":1,"chunksWithRoadGeometry":1,"roadMeshPartCount":1,"roadDetailPartCount":0,"sidewalkSurfacePartCount":0,"curbSurfacePartCount":0,"chunksWithSidewalkSurfaces":0,"chunksWithCurbSurfaces":0}}"#;

        let report = build_scene_audit_report_from_str(manifest, log, "ARNIS_SCENE_EDIT").unwrap();
        let codes = report["findings"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|finding| finding.get("code").and_then(|code| code.as_str()))
            .collect::<Vec<_>>();

        assert_eq!(report["manifest"]["roadsWithSidewalks"], 1);
        assert_eq!(report["manifest"]["chunksWithSidewalkRoads"], 1);
        assert!(codes.contains(&"missing_sidewalk_surfaces"));
        assert!(codes.contains(&"missing_curb_surfaces"));
    }

    #[test]
    fn scene_audit_flags_missing_crossing_surfaces() {
        let manifest = r#"{
            "meta": {
                "worldName": "SceneAuditTown",
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [
                        { "id": "road_1", "kind": "footway", "subkind": "crossing" }
                    ],
                    "buildings": [],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;
        let log = r#"2026-03-20 18:35:04.000  ARNIS_SCENE_EDIT {"phase":"edit","focus":{"x":128.0,"z":128.0},"radius":200.0,"rootName":"GeneratedWorld_AustinPreview","scene":{"chunkCount":1,"buildingModelCount":0,"chunksWithBuildingModels":0,"roadTaggedPartCount":0,"chunksWithRoadGeometry":0,"roadMeshPartCount":0,"roadDetailPartCount":0,"crossingSurfacePartCount":0,"chunksWithCrossingSurfaces":0}}"#;

        let report = build_scene_audit_report_from_str(manifest, log, "ARNIS_SCENE_EDIT").unwrap();
        let codes = report["findings"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|finding| finding.get("code").and_then(|code| code.as_str()))
            .collect::<Vec<_>>();

        assert_eq!(report["manifest"]["roadsWithCrossings"], 1);
        assert_eq!(report["manifest"]["chunksWithCrossingRoads"], 1);
        assert!(codes.contains(&"missing_crossing_surfaces"));
    }

    #[test]
    fn scene_index_summarizes_chunk_counts_for_fast_audits() {
        let manifest = r#"{
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SceneAuditTown",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [{ "id": "road_1" }],
                    "buildings": [{ "id": "bldg_1" }, { "id": "bldg_2" }],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;

        let index = build_scene_manifest_index_from_str(manifest).unwrap();

        assert_eq!(index["meta"]["chunkSizeStuds"], 256);
        assert_eq!(index["meta"]["sceneIndexVersion"], SCENE_INDEX_VERSION);
        assert_eq!(index["chunks"][0]["id"], "0_0");
        assert_eq!(index["chunks"][0]["roadCount"], 1);
        assert_eq!(index["chunks"][0]["buildingCount"], 2);
        assert_eq!(index["chunks"][0]["chunksWithRoads"], true);
        assert_eq!(index["chunks"][0]["chunksWithBuildings"], true);
    }

    #[test]
    fn scene_index_counts_sidewalk_subkind_roads() {
        let manifest = r#"{
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SceneAuditTown",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [
                        { "id": "road_1", "kind": "footway", "subkind": "sidewalk" },
                        { "id": "road_2", "kind": "residential", "hasSidewalk": true },
                        { "id": "road_3", "kind": "path" }
                    ],
                    "buildings": [],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;

        let index = build_scene_manifest_index_from_str(manifest).unwrap();

        assert_eq!(index["chunks"][0]["roadsWithSidewalks"], 2);
        assert_eq!(index["chunks"][0]["chunksWithSidewalkRoads"], true);
        assert_eq!(index["chunks"][0]["roadsWithCrossings"], 0);
        assert_eq!(index["chunks"][0]["chunksWithCrossingRoads"], false);
    }

    #[test]
    fn scene_index_counts_crossing_subkind_roads() {
        let manifest = r#"{
            "schemaVersion": "0.4.0",
            "meta": {
                "worldName": "SceneAuditTown",
                "metersPerStud": 0.3,
                "chunkSizeStuds": 256
            },
            "chunks": [
                {
                    "id": "0_0",
                    "originStuds": { "x": 0, "y": 0, "z": 0 },
                    "roads": [
                        { "id": "road_1", "kind": "footway", "subkind": "crossing" },
                        { "id": "road_2", "kind": "pedestrian", "subkind": "crossing" },
                        { "id": "road_3", "kind": "path" }
                    ],
                    "buildings": [],
                    "water": [],
                    "props": [],
                    "landuse": [],
                    "barriers": [],
                    "rails": []
                }
            ]
        }"#;

        let index = build_scene_manifest_index_from_str(manifest).unwrap();

        assert_eq!(index["chunks"][0]["roadsWithCrossings"], 2);
        assert_eq!(index["chunks"][0]["chunksWithCrossingRoads"], true);
    }
}
