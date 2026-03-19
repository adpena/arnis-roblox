//! Live Overpass API client with disk caching.
//!
//! Fetches OpenStreetMap data from the Overpass API for a given bounding box.
//! Results are cached to disk by bbox coordinates so repeated runs for the
//! same area skip the network entirely.
//!
//! Uses `curl` subprocess (no new Cargo dependencies) matching the pattern
//! established by `TerrariumElevationProvider` in `arbx_geo`.

use std::fs;
use std::path::PathBuf;

use arbx_geo::BoundingBox;

use crate::{PipelineError, PipelineResult};

/// Build the Overpass QL query for the given bbox.
///
/// The bbox is expressed in south,west,north,east order (Overpass convention).
fn build_query(bbox: BoundingBox) -> String {
    let s = bbox.min.lat;
    let w = bbox.min.lon;
    let n = bbox.max.lat;
    let e = bbox.max.lon;
    let bb = format!("{},{},{},{}", s, w, n, e);

    format!(
        r#"[out:json][timeout:90];
(
  way["building"]({bb});
  way["building:part"]({bb});
  way["highway"]({bb});
  way["highway"="footway"]({bb});
  way["highway"="path"]({bb});
  way["highway"="pedestrian"]({bb});
  way["highway"="steps"]({bb});
  way["highway"="cycleway"]({bb});
  way["man_made"="bridge"]({bb});
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
  node["highway"="crossing"]({bb});
  node["emergency"="fire_hydrant"]({bb});
  node["tourism"="information"]({bb});
  node["amenity"="fountain"]({bb});
  node["amenity"="drinking_water"]({bb});
  node["amenity"="telephone"]({bb});
  node["amenity"="post_box"]({bb});
  node["amenity"="vending_machine"]({bb});
);
out body;
>;
out skel qt;"#,
        bb = bb
    )
}

/// Derive a deterministic cache filename from the bbox coordinates.
///
/// Uses 6 decimal places of precision (~0.1 m), replacing `.` and `-` so the
/// filename is safe on all platforms.
fn cache_filename(bbox: BoundingBox) -> String {
    // Format: overpass_<s>_<w>_<n>_<e>.json  (dots and minus signs replaced)
    let fmt = |v: f64| format!("{:.6}", v).replace('.', "p").replace('-', "m");
    format!(
        "overpass_{}_{}_{}_{}. json",
        fmt(bbox.min.lat),
        fmt(bbox.min.lon),
        fmt(bbox.max.lat),
        fmt(bbox.max.lon),
    )
    // strip the accidental space that crept in above
    .replace(" ", "")
}

/// Fetch Overpass data for `bbox`, caching the result under `cache_dir`.
///
/// * If a cached file already exists it is returned immediately without any
///   network call.
/// * Otherwise the query is POSTed to `https://overpass-api.de/api/interpreter`
///   using a `curl` subprocess (no new Cargo dependencies) and the response is
///   written to `<cache_dir>/<bbox-derived-name>.json`.
///
/// Returns the path to the JSON file on success.
pub fn fetch_overpass(bbox: BoundingBox, cache_dir: &str) -> PipelineResult<PathBuf> {
    fs::create_dir_all(cache_dir)
        .map_err(|e| PipelineError::IO(format!("cannot create cache dir {cache_dir}: {e}")))?;

    let filename = cache_filename(bbox);
    let cached_path = PathBuf::from(cache_dir).join(&filename);

    if cached_path.exists() {
        eprintln!(
            "[overpass] cache hit: {}",
            cached_path.display()
        );
        return Ok(cached_path);
    }

    eprintln!(
        "[overpass] fetching live data for bbox ({:.5},{:.5},{:.5},{:.5})…",
        bbox.min.lat, bbox.min.lon, bbox.max.lat, bbox.max.lon
    );
    eprintln!("[overpass] please be patient — respecting Overpass API rate limits");
    // Be polite: wait 1 second before hitting the public API
    std::thread::sleep(std::time::Duration::from_secs(1));

    let query = build_query(bbox);

    let out_str = cached_path.to_str().ok_or_else(|| {
        PipelineError::IO("cache path is not valid UTF-8".to_string())
    })?;

    let output = std::process::Command::new("curl")
        .args([
            "-s",
            "--fail",
            "--user-agent",
            "arnis-roblox/1.0 (open-source educational project)",
            "--retry",
            "3",
            "--retry-delay",
            "5",
            "-X",
            "POST",
            "https://overpass-api.de/api/interpreter",
            "--data-urlencode",
            // pass the raw QL; curl --data-urlencode encodes it for us
            &format!("data={}", query),
            "-o",
            out_str,
        ])
        .output()
        .map_err(|e| PipelineError::IO(format!("failed to spawn curl: {e}")))?;

    if !output.status.success() {
        // Remove any partial file
        let _ = fs::remove_file(&cached_path);
        return Err(PipelineError::IO(format!(
            "overpass fetch failed (exit {}): {}",
            output.status,
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    // Sanity-check: the file must exist and contain at least the "elements" key
    let content = fs::read_to_string(&cached_path)
        .map_err(|e| PipelineError::IO(format!("failed to read downloaded file: {e}")))?;

    if !content.contains("\"elements\"") {
        let _ = fs::remove_file(&cached_path);
        return Err(PipelineError::IO(
            "overpass response did not contain expected 'elements' key — possibly an API error"
                .to_string(),
        ));
    }

    eprintln!(
        "[overpass] saved {} bytes to {}",
        content.len(),
        cached_path.display()
    );

    Ok(cached_path)
}

/// Minimal percent-encoding for use in a `application/x-www-form-urlencoded`
/// body.  Only used as a fallback; the primary path uses curl's own
/// `--data-urlencode`.
#[allow(dead_code)]
fn urlencoded(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for byte in s.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9'
            | b'-' | b'_' | b'.' | b'~' => out.push(byte as char),
            b' ' => out.push('+'),
            b => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbx_geo::BoundingBox;

    #[test]
    fn cache_filename_is_deterministic() {
        let bbox = BoundingBox::new(30.26, -97.75, 30.27, -97.74);
        let a = cache_filename(bbox);
        let b = cache_filename(bbox);
        assert_eq!(a, b);
        assert!(a.starts_with("overpass_"));
        assert!(a.ends_with(".json"));
        assert!(!a.contains('.') || a.ends_with(".json"), "dots only in .json suffix");
    }

    #[test]
    fn cache_filename_differs_for_different_bboxes() {
        let b1 = BoundingBox::new(30.26, -97.75, 30.27, -97.74);
        let b2 = BoundingBox::new(51.50, -0.13, 51.51, -0.12);
        assert_ne!(cache_filename(b1), cache_filename(b2));
    }

    #[test]
    fn build_query_contains_bbox_coords() {
        let bbox = BoundingBox::new(30.26, -97.75, 30.27, -97.74);
        let q = build_query(bbox);
        // south,west,north,east
        assert!(q.contains("30.26,-97.75,30.27,-97.74"), "query should embed bbox: {}", q);
        assert!(q.contains("way[\"building\"]"));
        assert!(q.contains("node[\"natural\"=\"tree\"]"));
        // pedestrian infrastructure
        assert!(q.contains("way[\"highway\"=\"footway\"]"), "missing footway: {}", q);
        assert!(q.contains("way[\"highway\"=\"path\"]"), "missing path: {}", q);
        assert!(q.contains("way[\"highway\"=\"pedestrian\"]"), "missing pedestrian: {}", q);
        assert!(q.contains("way[\"highway\"=\"steps\"]"), "missing steps: {}", q);
        assert!(q.contains("way[\"highway\"=\"cycleway\"]"), "missing cycleway: {}", q);
        assert!(q.contains("way[\"man_made\"=\"bridge\"]"), "missing bridge: {}", q);
        // crosswalks and urban furniture nodes
        assert!(q.contains("node[\"highway\"=\"crossing\"]"), "missing crossing node: {}", q);
        assert!(q.contains("node[\"tourism\"=\"information\"]"), "missing tourism info: {}", q);
        assert!(q.contains("node[\"amenity\"=\"fountain\"]"), "missing fountain: {}", q);
        assert!(q.contains("node[\"amenity\"=\"drinking_water\"]"), "missing drinking_water: {}", q);
        assert!(q.contains("node[\"amenity\"=\"telephone\"]"), "missing telephone: {}", q);
        assert!(q.contains("node[\"amenity\"=\"post_box\"]"), "missing post_box: {}", q);
        assert!(q.contains("node[\"amenity\"=\"vending_machine\"]"), "missing vending_machine: {}", q);
    }

    #[test]
    fn fetch_returns_cached_file_without_network() {
        use std::io::Write;

        let tmp_dir = std::env::temp_dir().join("arbx_overpass_test_cache");
        let _ = std::fs::remove_dir_all(&tmp_dir); // clean slate
        std::fs::create_dir_all(&tmp_dir).unwrap();

        let bbox = BoundingBox::new(30.26, -97.75, 30.27, -97.74);
        let filename = cache_filename(bbox);
        let cache_file = tmp_dir.join(&filename);

        // Pre-populate the cache with a minimal valid Overpass JSON
        let fake_json = r#"{"elements":[]}"#;
        let mut f = std::fs::File::create(&cache_file).unwrap();
        f.write_all(fake_json.as_bytes()).unwrap();

        let result = fetch_overpass(bbox, tmp_dir.to_str().unwrap());
        assert!(result.is_ok(), "expected Ok, got {:?}", result);
        assert_eq!(result.unwrap(), cache_file);

        let _ = std::fs::remove_dir_all(&tmp_dir);
    }
}
