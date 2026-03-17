use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::Instant;

use arbx_geo::{BoundingBox, PerlinElevationProvider};
use arbx_pipeline::{run_pipeline, NormalizeStage, TriangulateStage, ValidateStage};
use arbx_roblox_export::{build_sample_multi_chunk, export_to_chunks, ExportConfig};

fn print_help() {
    println!("arbx_cli");
    println!();
    println!("Commands:");
    println!("  sample [--out PATH] [--grid X,Z]   Emit the sample manifest");
    println!("  compile [--out PATH] [--source PATH] [--bbox MIN_LAT,MIN_LON,MAX_LAT,MAX_LON]");
    println!("                                     Run the pipeline and emit a manifest");
    println!("  config [--out PATH]               Emit a default world configuration JSON");
    println!("  stats <PATH>                       Print statistics for a manifest file");
    println!("  validate <PATH>                    Validate a manifest file");
    println!("  diff <PATH1> <PATH2>               Compare two manifest files");
    println!("  explain                            Print the scaffold mission");
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
    let mut bbox = BoundingBox::new(30.26, -97.75, 30.27, -97.74);

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
                let value = args.get(i + 1)
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
            other => {
                return Err(format!("unknown argument to compile: {other}"));
            }
        }
    }

    let start = Instant::now();

    let adapter: Box<dyn arbx_pipeline::SourceAdapter> = if let Some(path) = &source_path {
        if path.to_string_lossy().ends_with(".json") {
            let content =
                fs::read_to_string(path).map_err(|e| format!("failed to read source: {}", e))?;
            if content.contains("\"elements\"") {
                Box::new(arbx_pipeline::OverpassAdapter { path: path.clone() })
            } else {
                Box::new(arbx_pipeline::FileSourceAdapter { path: path.clone() })
            }
        } else {
            Box::new(arbx_pipeline::FileSourceAdapter { path: path.clone() })
        }
    } else {
        Box::new(arbx_pipeline::SyntheticAustinAdapter)
    };

    println!("Compiling from {}...", adapter.name());

    let stages = [
        &ValidateStage as &dyn arbx_pipeline::PipelineStage,
        &NormalizeStage as &dyn arbx_pipeline::PipelineStage,
        &TriangulateStage as &dyn arbx_pipeline::PipelineStage,
    ];

    let ctx = run_pipeline(adapter.as_ref(), bbox, &stages)
        .map_err(|e| format!("pipeline failed: {:?}", e))?;

    let config = ExportConfig::default();
    let elevation = PerlinElevationProvider::default();
    let manifest = export_to_chunks(ctx.features, ctx.bbox, &config, &elevation).to_json_pretty();
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
  "metersPerStud": 1.0,
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
    let path = args.first().ok_or("stats requires a path to a manifest file")?;
    let content = fs::read_to_string(path).map_err(|e| format!("failed to read manifest: {}", e))?;

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
            total_bldgs += c["buildings"].as_array().map(|a| a.len() as u64).unwrap_or(0);
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
    let path = args.first().ok_or("validate requires a path to a manifest file")?;
    let start = Instant::now();

    let content = fs::read_to_string(path).map_err(|e| format!("failed to read manifest: {}", e))?;
    let v: serde_json::Value =
        serde_json::from_str(&content).map_err(|e| format!("invalid JSON: {}", e))?;

    // Validate top-level structure
    let schema_version = v.get("schemaVersion")
        .and_then(|v| v.as_str())
        .ok_or("missing or invalid schemaVersion")?;

    if schema_version != "0.2.0" {
        return Err(format!("unsupported schemaVersion: {} (expected 0.2.0)", schema_version));
    }

    // Validate meta section
    let meta = v.get("meta").ok_or("missing meta section")?;
    let required_meta = ["worldName", "generator", "source", "metersPerStud", "chunkSizeStuds", "bbox", "totalFeatures"];
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
    let chunks = v.get("chunks").and_then(|v| v.as_array())
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
        let origin = chunk.get("originStuds").ok_or(format!("{} missing originStuds", prefix))?;
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
            let heights = terrain.get("heights").and_then(|v| v.as_array())
                .ok_or(format!("{}.terrain.heights must be an array", prefix))?;
            let width = terrain.get("width").and_then(|v| v.as_u64()).unwrap_or(0);
            let depth = terrain.get("depth").and_then(|v| v.as_u64()).unwrap_or(0);
            let expected = width * depth;
            if heights.len() as u64 != expected {
                return Err(format!("{}.terrain.heights length mismatch: expected {}, got {}",
                    prefix, expected, heights.len()));
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
                let points = road.get("points").and_then(|v| v.as_array())
                    .ok_or(format!("{} missing points", road_prefix))?;
                if points.len() < 2 {
                    return Err(format!("{}.points must have at least 2 points", road_prefix));
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

    let m1_content = fs::read_to_string(m1_path).map_err(|e| format!("failed to read {}: {}", m1_path, e))?;
    let m2_content = fs::read_to_string(m2_path).map_err(|e| format!("failed to read {}: {}", m2_path, e))?;

    let v1: serde_json::Value = serde_json::from_str(&m1_content).map_err(|e| format!("invalid JSON in {}: {}", m1_path, e))?;
    let v2: serde_json::Value = serde_json::from_str(&m2_content).map_err(|e| format!("invalid JSON in {}: {}", m2_path, e))?;

    if v1["schemaVersion"] != v2["schemaVersion"] {
        println!("Schema versions differ: {} vs {}", v1["schemaVersion"], v2["schemaVersion"]);
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

fn cmd_explain() {
    println!("This scaffold splits the project into:");
    println!("- Rust-side export/compiler crates");
    println!("- Roblox-side importer/runtime modules");
    println!("- optional Studio plugin/editor helpers");
    println!();
    println!("The next serious step is replacing placeholder builders with optimized implementations.");
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
        "explain" => {
            cmd_explain();
            Ok(())
        }
        "--help" | "-h" | "help" => {
            print_help();
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

    fn write_temp_manifest(content: &str) -> NamedTempFile {
        let mut file = NamedTempFile::new().unwrap();
        file.write_all(content.as_bytes()).unwrap();
        file
    }

    #[test]
    fn diff_identical_manifests() {
        let content = r#"{
            "schemaVersion": "0.2.0",
            "meta": { "totalFeatures": 10 },
            "chunks": [{}, {}]
        }"#;
        let f1 = write_temp_manifest(content);
        let f2 = write_temp_manifest(content);
        assert!(cmd_diff(&[f1.path().to_str().unwrap().to_string(), f2.path().to_str().unwrap().to_string()]).is_ok());
    }

    #[test]
    fn diff_different_versions() {
        let c1 = r#"{ "schemaVersion": "0.2.0", "meta": { "totalFeatures": 10 }, "chunks": [] }"#;
        let c2 = r#"{ "schemaVersion": "0.1.0", "meta": { "totalFeatures": 10 }, "chunks": [] }"#;
        let f1 = write_temp_manifest(c1);
        let f2 = write_temp_manifest(c2);
        assert!(cmd_diff(&[f1.path().to_str().unwrap().to_string(), f2.path().to_str().unwrap().to_string()]).is_ok());
    }
}
