pub mod overture;
pub mod overpass_client;

use arbx_geo::{
    BoundingBox, ElevationProvider, Footprint, LatLon, Mercator, PerlinElevationProvider, Vec2,
    Vec3,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoadFeature {
    pub id: String,
    pub kind: String,
    pub lanes: Option<u32>,
    pub width_studs: f64,
    pub has_sidewalk: bool,
    pub surface: Option<String>,
    pub elevated: Option<bool>,
    pub tunnel: Option<bool>,
    pub sidewalk: Option<String>,
    pub points: Vec<Vec3>,
    pub maxspeed: Option<u32>,
    pub lit: Option<bool>,
    pub oneway: Option<bool>,
    pub layer: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RailFeature {
    pub id: String,
    pub kind: String,
    pub lanes: Option<u32>,
    pub width_studs: f64,
    pub points: Vec<Vec3>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BuildingFeature {
    pub id: String,
    pub footprint: Footprint,
    pub indices: Option<Vec<usize>>,
    pub base_y: f64,
    pub height: f64,
    pub height_m: Option<f64>,
    pub levels: Option<u32>,
    pub roof_levels: Option<u32>,
    pub min_height: Option<f64>,
    pub usage: Option<String>,
    pub roof: String,
    pub colour: Option<String>,
    pub material_tag: Option<String>,
    pub roof_colour: Option<String>,
    pub roof_material: Option<String>,
    pub roof_height: Option<f64>,
    pub name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WaterRibbonFeature {
    pub id: String,
    pub kind: String,
    pub width_studs: f64,
    pub points: Vec<Vec3>,
    pub width: Option<f64>,
    pub intermittent: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WaterPolygonFeature {
    pub id: String,
    pub kind: String,
    pub footprint: Footprint,
    pub holes: Vec<Footprint>,
    pub indices: Option<Vec<usize>>,
    pub intermittent: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WaterFeature {
    Ribbon(WaterRibbonFeature),
    Polygon(WaterPolygonFeature),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PropFeature {
    pub id: String,
    pub kind: String,
    pub position: Vec3,
    pub yaw_degrees: f64,
    pub scale: f64,
    pub species: Option<String>,
    pub height: Option<f64>,
    pub leaf_type: Option<String>,
    pub circumference: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LanduseFeature {
    pub id: String,
    pub kind: String,
    pub footprint: Footprint,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Feature {
    Road(RoadFeature),
    Rail(RailFeature),
    Building(BuildingFeature),
    Water(WaterFeature),
    Prop(PropFeature),
    Landuse(LanduseFeature),
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PipelineStats {
    pub source_feature_count: usize,
    pub normalized_feature_count: usize,
    pub dropped_feature_count: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PipelineContext {
    pub bbox: BoundingBox,
    pub features: Vec<Feature>,
    pub notes: Vec<String>,
    pub stats: PipelineStats,
}

impl PipelineContext {
    pub fn new(bbox: BoundingBox, features: Vec<Feature>) -> Self {
        let source_feature_count = features.len();

        Self {
            bbox,
            features,
            notes: Vec::new(),
            stats: PipelineStats {
                source_feature_count,
                normalized_feature_count: 0,
                dropped_feature_count: 0,
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PipelineError {
    Validation(String),
    IO(String),
    Serialization(String),
    Unimplemented(&'static str),
}

pub type PipelineResult<T> = Result<T, PipelineError>;

pub trait SourceAdapter {
    fn name(&self) -> &'static str;
    fn load(&self, bbox: BoundingBox) -> PipelineResult<Vec<Feature>>;
}

pub trait PipelineStage {
    fn name(&self) -> &'static str;
    fn run(&self, ctx: &mut PipelineContext) -> PipelineResult<()>;
}

pub struct ValidateStage;

impl PipelineStage for ValidateStage {
    fn name(&self) -> &'static str {
        "validate"
    }

    fn run(&self, ctx: &mut PipelineContext) -> PipelineResult<()> {
        if ctx.bbox.width_degrees() <= 0.0 || ctx.bbox.height_degrees() <= 0.0 {
            return Err(PipelineError::Validation(
                "bounding box must have positive width and height".to_string(),
            ));
        }

        ctx.notes.push("validated input bbox".to_string());
        Ok(())
    }
}

pub struct NormalizeStage;

impl PipelineStage for NormalizeStage {
    fn name(&self) -> &'static str {
        "normalize"
    }

    fn run(&self, ctx: &mut PipelineContext) -> PipelineResult<()> {
        ctx.stats.normalized_feature_count = ctx.features.len();
        ctx.notes.push("normalized feature collection".to_string());
        Ok(())
    }
}

pub struct TriangulateStage;

impl PipelineStage for TriangulateStage {
    fn name(&self) -> &'static str {
        "triangulate"
    }

    fn run(&self, ctx: &mut PipelineContext) -> PipelineResult<()> {
        for feature in &mut ctx.features {
            match feature {
                Feature::Building(b) => {
                    b.indices = Some(b.footprint.triangulate());
                }
                Feature::Water(WaterFeature::Polygon(p)) => {
                    p.indices = Some(p.footprint.triangulate());
                }
                _ => {}
            }
        }
        ctx.notes.push("triangulated polygon features".to_string());
        Ok(())
    }
}

pub struct SyntheticAustinAdapter;

impl SourceAdapter for SyntheticAustinAdapter {
    fn name(&self) -> &'static str {
        "synthetic-austin"
    }

    fn load(&self, bbox: BoundingBox) -> PipelineResult<Vec<Feature>> {
        let mut features = Vec::new();
        let elevation = PerlinElevationProvider::default();
        let center = bbox.center();

        // Helper to project and sample height
        let project_with_y = |lat: f64, lon: f64| {
            let mut p = Mercator::project(LatLon::new(lat, lon), center, 1.0);
            p.y = elevation.sample_height_at(LatLon::new(lat, lon)) as f64;
            p
        };

        // Add a long road that spans multiple chunks, following terrain
        features.push(Feature::Road(RoadFeature {
            id: "congress_ave".to_string(),
            kind: "primary".to_string(),
            lanes: Some(4),
            width_studs: 40.0,
            has_sidewalk: true,
            surface: None,
            elevated: None,
            tunnel: None,
            sidewalk: Some("both".to_string()),
            points: vec![
                project_with_y(center.lat - 0.005, center.lon),
                project_with_y(center.lat, center.lon),
                project_with_y(center.lat + 0.005, center.lon),
            ],
            maxspeed: None,
            lit: None,
            oneway: None,
            layer: None,
        }));

        // Add some buildings in different chunks
        let capitol_ll = LatLon::new(center.lat + 0.001, center.lon + 0.001);
        features.push(Feature::Building(BuildingFeature {
            id: "capitol".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(100.0, 100.0),
                Vec2::new(200.0, 100.0),
                Vec2::new(200.0, 200.0),
                Vec2::new(100.0, 200.0),
            ]),
            indices: None,
            base_y: elevation.sample_height_at(capitol_ll) as f64,
            height: 50.0,
            height_m: None,
            levels: Some(3),
            roof_levels: Some(1),
            min_height: None,
            usage: Some("government".to_string()),
            roof: "dome".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: None,
        }));

        // Add a landuse polygon (park)
        features.push(Feature::Landuse(LanduseFeature {
            id: "park_1".to_string(),
            kind: "grass".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(300.0, 300.0),
                Vec2::new(500.0, 300.0),
                Vec2::new(500.0, 500.0),
                Vec2::new(300.0, 500.0),
            ]),
        }));

        Ok(features)
    }
}

pub struct FileSourceAdapter {
    pub path: PathBuf,
}

impl SourceAdapter for FileSourceAdapter {
    fn name(&self) -> &'static str {
        "file-source"
    }

    fn load(&self, _bbox: BoundingBox) -> PipelineResult<Vec<Feature>> {
        let content = fs::read_to_string(&self.path)
            .map_err(|e| PipelineError::IO(format!("failed to read file: {}", e)))?;

        let features: Vec<Feature> = serde_json::from_str(&content).map_err(|e| {
            PipelineError::Serialization(format!("failed to deserialize features: {}", e))
        })?;

        Ok(features)
    }
}

/// A simple adapter for Overpass JSON data.
pub struct OverpassAdapter {
    pub path: PathBuf,
    /// How many real-world meters correspond to one Roblox stud.
    /// Must match the ExportConfig value used downstream.
    pub meters_per_stud: f64,
}

#[derive(Deserialize)]
struct OverpassMember {
    #[serde(rename = "type")]
    kind: String,
    #[serde(rename = "ref")]
    ref_id: u64,
    #[serde(default)]
    role: String,
}

#[derive(Deserialize)]
struct OverpassElement {
    #[serde(rename = "type")]
    kind: String,
    id: u64,
    lat: Option<f64>,
    lon: Option<f64>,
    nodes: Option<Vec<u64>>,
    #[serde(default)]
    members: Vec<OverpassMember>,
    tags: Option<HashMap<String, String>>,
}

#[derive(Deserialize)]
struct OverpassResponse {
    elements: Vec<OverpassElement>,
}

impl SourceAdapter for OverpassAdapter {
    fn name(&self) -> &'static str {
        "overpass-json"
    }

    fn load(&self, bbox: BoundingBox) -> PipelineResult<Vec<Feature>> {
        let content = fs::read_to_string(&self.path)
            .map_err(|e| PipelineError::IO(format!("failed to read overpass file: {}", e)))?;

        let data: OverpassResponse = serde_json::from_str(&content).map_err(|e| {
            PipelineError::Serialization(format!("failed to parse overpass json: {}", e))
        })?;

        let center = bbox.center();
        let mps = self.meters_per_stud;
        let lat_margin = bbox.height_degrees() * 0.1;
        let lon_margin = bbox.width_degrees() * 0.1;
        let clip_bbox = bbox.expanded(lat_margin.max(lon_margin));

        // ── Phase 1: build node-id → LatLon map ──────────────────────────────
        let mut node_coords: HashMap<u64, arbx_geo::LatLon> = HashMap::new();
        for el in &data.elements {
            if el.kind == "node" {
                if let (Some(lat), Some(lon)) = (el.lat, el.lon) {
                    node_coords.insert(el.id, arbx_geo::LatLon::new(lat, lon));
                }
            }
        }

        // ── Phase 2: build way-id → projected Vec2 points map ────────────────
        // For LINEAR ways (roads, waterways) we clip individual nodes to bbox.
        // For POLYGON ways (closed ring: first node == last node) we keep ALL
        // nodes so the polygon shape is preserved when it crosses the bbox edge.
        // We then use centroid-in-bbox to decide whether to emit the feature.
        let mut way_points: HashMap<u64, Vec<Vec2>> = HashMap::new();
        for el in &data.elements {
            if el.kind != "way" { continue; }
            let Some(way_nodes) = &el.nodes else { continue };
            if way_nodes.is_empty() { continue; }

            let is_closed_ring = way_nodes.first() == way_nodes.last() && way_nodes.len() > 1;

            let pts: Vec<Vec2> = if is_closed_ring {
                // Polygon way — keep all resolved nodes regardless of bbox position
                way_nodes.iter()
                    .filter_map(|id| node_coords.get(id))
                    .map(|&ll| {
                        let p = Mercator::project(ll, center, mps);
                        Vec2::new(p.x, p.z)
                    })
                    .collect()
            } else {
                // Linear way — clip each node to bbox (avoids far-away chunk creation)
                way_nodes.iter()
                    .filter_map(|id| node_coords.get(id))
                    .filter(|&&ll| clip_bbox.contains(ll))
                    .map(|&ll| {
                        let p = Mercator::project(ll, center, mps);
                        Vec2::new(p.x, p.z)
                    })
                    .collect()
            };

            if !pts.is_empty() {
                way_points.insert(el.id, pts);
            }
        }

        let mut features: Vec<Feature> = Vec::new();

        // ── Phase 3a: Process way elements using pre-resolved geometry ────────
        for el in &data.elements {
            if el.kind != "way" { continue; }
            let Some(tags) = &el.tags else { continue };

            // For roads/rails/waterways use clipped Vec3 (with y for bridge/tunnel).
            // For polygon area features use Vec2 from way_points (unclipped polygon ring).
            let is_area = tags.contains_key("building")
                || tags.contains_key("building:part")
                || tags.contains_key("landuse")
                || tags.contains_key("leisure")
                || tags.contains_key("amenity")
                || tags.get("natural").map(|v| v != "tree").unwrap_or(false)
                || tags.get("natural") == Some(&"water".to_string());

            if is_area {
                // Use unclipped polygon points; check centroid is within clip_bbox
                let Some(fp) = way_points.get(&el.id) else { continue };
                if fp.len() < 3 {
                    eprintln!("WARN: way osm_{} — {} point(s) after projection, skipping", el.id, fp.len());
                    continue;
                }
                // Centroid check: don't emit features whose footprint is entirely outside bbox
                let cx: f64 = fp.iter().map(|p| p.x).sum::<f64>() / fp.len() as f64;
                let cz: f64 = fp.iter().map(|p| p.y).sum::<f64>() / fp.len() as f64;
                let world_half_x = (bbox.max.lon - bbox.min.lon) * 111_320.0_f64 * 0.5 / mps;
                let world_half_z = (bbox.max.lat - bbox.min.lat) * 111_320.0_f64 * 0.5 / mps;
                if cx.abs() > world_half_x * 1.2 || cz.abs() > world_half_z * 1.2 {
                    continue; // centroid far outside world extent
                }
                emit_area_way(el.id, tags, fp, vec![], &mut features);
            } else {
                // Linear feature — segment-level clip interpolates bbox entry/exit
                let Some(way_nodes) = &el.nodes else { continue };
                let node_lls: Vec<LatLon> = way_nodes.iter()
                    .filter_map(|id| node_coords.get(id).copied())
                    .collect();
                let mut lin_pts: Vec<Vec3> = Vec::new();
                for i in 0..node_lls.len().saturating_sub(1) {
                    let (a, b) = (node_lls[i], node_lls[i + 1]);
                    let Some((t0, t1)) = liang_barsky(a, b, &clip_bbox) else { continue };
                    let lerp = |p1: LatLon, p2: LatLon, t: f64| LatLon::new(
                        p1.lat + t * (p2.lat - p1.lat),
                        p1.lon + t * (p2.lon - p1.lon),
                    );
                    let c1 = lerp(a, b, t0);
                    let c2 = lerp(a, b, t1);
                    let proj1 = Mercator::project(c1, center, mps);
                    if lin_pts.last().map(|p: &Vec3| (p.x - proj1.x).abs() > 0.05 || (p.z - proj1.z).abs() > 0.05).unwrap_or(true) {
                        lin_pts.push(proj1);
                    }
                    lin_pts.push(Mercator::project(c2, center, mps));
                }
                if lin_pts.len() < 2 { continue; }
                emit_linear_way(el.id, tags, lin_pts, &mut features);
            }
        }

        // ── Phase 3b: Assemble multipolygon relations ─────────────────────────
        // Tags live on the relation, not the member ways. We merge outer-role
        // member ways into a single ring following the Arnis ring-merge approach.
        for el in &data.elements {
            if el.kind != "relation" { continue; }
            let Some(tags) = &el.tags else { continue };
            let rel_type = tags.get("type").map(|s| s.as_str());
            if rel_type != Some("multipolygon") && rel_type != Some("boundary") { continue; }

            // Collect outer member way point sequences
            let mut outer_rings: Vec<Vec<Vec2>> = el.members.iter()
                .filter(|m| m.kind == "way" && (m.role == "outer" || m.role == ""))
                .filter_map(|m| way_points.get(&m.ref_id).cloned())
                .collect();

            if outer_rings.is_empty() { continue; }

            // Merge split rings (multipolygon boundaries are often split across ways)
            merge_rings(&mut outer_rings);

            // Use the largest outer ring as the footprint
            let Some(footprint) = outer_rings.into_iter().max_by_key(|r| r.len()) else { continue };
            if footprint.len() < 3 { continue; }

            // Collect inner member way point sequences (islands/holes)
            let mut inner_rings: Vec<Vec<Vec2>> = el.members.iter()
                .filter(|m| m.kind == "way" && m.role == "inner")
                .filter_map(|m| way_points.get(&m.ref_id).cloned())
                .collect();

            if !inner_rings.is_empty() {
                merge_rings(&mut inner_rings);
            }

            let holes: Vec<Footprint> = inner_rings
                .into_iter()
                .filter(|r| r.len() >= 3)
                .map(|r| Footprint::new(r))
                .collect();

            emit_area_way(el.id, tags, &footprint, holes, &mut features);
        }

        // Parse node elements for trees and similar point features
        for el in &data.elements {
            if el.kind == "node" {
                let Some(tags) = &el.tags else { continue };
                let Some(lat) = el.lat else { continue };
                let Some(lon) = el.lon else { continue };
                let ll = LatLon::new(lat, lon);
                if !clip_bbox.contains(ll) {
                    continue;
                }
                let pos = Mercator::project(ll, center, mps);
                if tags.get("highway") == Some(&"street_lamp".to_string()) {
                    features.push(Feature::Prop(PropFeature {
                        id: format!("lamp_{}", el.id),
                        kind: "street_lamp".to_string(),
                        position: pos,
                        yaw_degrees: 0.0,
                        scale: 1.0,
                        species: None,
                        height: None,
                        leaf_type: None,
                        circumference: None,
                    }));
                    continue;
                }
                if tags.get("amenity") == Some(&"bench".to_string()) {
                    features.push(Feature::Prop(PropFeature {
                        id: format!("bench_{}", el.id),
                        kind: "bench".to_string(),
                        position: pos,
                        yaw_degrees: 0.0,
                        scale: 1.0,
                        species: None,
                        height: None,
                        leaf_type: None,
                        circumference: None,
                    }));
                    continue;
                }
                if tags.get("highway") == Some(&"bus_stop".to_string())
                    || tags.get("amenity") == Some(&"bus_shelter".to_string())
                {
                    features.push(Feature::Prop(PropFeature {
                        id: format!("busstop_{}", el.id),
                        kind: "bus_stop".to_string(),
                        position: pos,
                        yaw_degrees: 0.0,
                        scale: 1.0,
                        species: None,
                        height: None,
                        leaf_type: None,
                        circumference: None,
                    }));
                    continue;
                }
                if tags.get("highway") == Some(&"traffic_signals".to_string()) {
                    features.push(Feature::Prop(PropFeature {
                        id: format!("signal_{}", el.id),
                        kind: "traffic_signal".to_string(),
                        position: pos,
                        yaw_degrees: 0.0,
                        scale: 1.0,
                        species: None,
                        height: None,
                        leaf_type: None,
                        circumference: None,
                    }));
                    continue;
                }
                if tags.get("amenity") == Some(&"waste_basket".to_string())
                    || tags.get("amenity") == Some(&"recycling".to_string())
                {
                    features.push(Feature::Prop(PropFeature {
                        id: format!("bin_{}", el.id),
                        kind: "waste_basket".to_string(),
                        position: pos,
                        yaw_degrees: 0.0,
                        scale: 1.0,
                        species: None,
                        height: None,
                        leaf_type: None,
                        circumference: None,
                    }));
                    continue;
                }
                if tags.get("emergency") == Some(&"fire_hydrant".to_string()) {
                    features.push(Feature::Prop(PropFeature {
                        id: format!("hydrant_{}", el.id),
                        kind: "fire_hydrant".to_string(),
                        position: pos,
                        yaw_degrees: 0.0,
                        scale: 1.0,
                        species: None,
                        height: None,
                        leaf_type: None,
                        circumference: None,
                    }));
                    continue;
                }
                if tags.get("natural") == Some(&"tree".to_string())
                    || tags.get("amenity") == Some(&"tree".to_string())
                {
                    let species = tags
                        .get("species")
                        .or_else(|| tags.get("genus"))
                        .or_else(|| tags.get("taxon"))
                        .map(|s| s.to_lowercase())
                        .or_else(|| {
                            // Infer from leaf type
                            match (
                                tags.get("leaf_type").map(|s| s.as_str()),
                                tags.get("leaf_cycle").map(|s| s.as_str()),
                            ) {
                                (Some("needleleaved"), _) => Some("conifer".to_string()),
                                (Some("broadleaved"), Some("evergreen")) => {
                                    Some("broadleaved_evergreen".to_string())
                                }
                                (Some("broadleaved"), _) => Some("broadleaved_deciduous".to_string()),
                                _ => None,
                            }
                        });

                    let tree_height = tags.get("height").and_then(|h| h.parse::<f64>().ok());
                    let leaf_type = tags.get("leaf_type").cloned();
                    let circumference = tags.get("circumference").and_then(|c| c.parse::<f64>().ok());

                    features.push(Feature::Prop(PropFeature {
                        id: format!("tree_{}", el.id),
                        kind: "tree".to_string(),
                        position: pos,
                        yaw_degrees: 0.0,
                        scale: 1.0,
                        species,
                        height: tree_height,
                        leaf_type,
                        circumference,
                    }));
                }
            }
        }

        // Append Overture buildings as gap-fill. OSM features were loaded first,
        // so if the chunker overwrites by position the more-detailed OSM entry wins.
        let overture_path = "rust/data/overture_buildings.geojson";
        let overture_features =
            overture::load_overture_buildings(overture_path, bbox, self.meters_per_stud);
        features.extend(overture_features);

        Ok(features)
    }
}

/// Adapter that fetches live Overpass API data for a given bounding box,
/// caches the result to disk, then delegates parsing to [`OverpassAdapter`].
pub struct LiveOverpassAdapter {
    pub bbox: BoundingBox,
    /// How many real-world meters correspond to one Roblox stud.
    pub meters_per_stud: f64,
    /// Directory used for on-disk caching of Overpass responses.
    /// Defaults to `"out/overpass"` in the CLI.
    pub cache_dir: String,
}

impl SourceAdapter for LiveOverpassAdapter {
    fn name(&self) -> &'static str {
        "live-overpass"
    }

    fn load(&self, bbox: BoundingBox) -> PipelineResult<Vec<Feature>> {
        let path = overpass_client::fetch_overpass(bbox, &self.cache_dir)?;
        let file_adapter = OverpassAdapter {
            path,
            meters_per_stud: self.meters_per_stud,
        };
        file_adapter.load(bbox)
    }
}

/// Liang-Barsky line clip. Returns (t0, t1) parametric parameters if segment
/// [p1→p2] intersects `bbox`, else None. t∈[0,1] maps to p1→p2.
fn liang_barsky(p1: LatLon, p2: LatLon, bbox: &BoundingBox) -> Option<(f64, f64)> {
    let dx = p2.lon - p1.lon;
    let dy = p2.lat - p1.lat;
    let mut t0: f64 = 0.0;
    let mut t1: f64 = 1.0;
    for (p, q) in [
        (-dx, p1.lon - bbox.min.lon),
        ( dx, bbox.max.lon - p1.lon),
        (-dy, p1.lat - bbox.min.lat),
        ( dy, bbox.max.lat - p1.lat),
    ] {
        if p == 0.0 {
            if q < 0.0 { return None; }
        } else if p < 0.0 {
            let r = q / p;
            if r > t1 { return None; }
            if r > t0 { t0 = r; }
        } else {
            let r = q / p;
            if r < t0 { return None; }
            if r < t1 { t1 = r; }
        }
    }
    Some((t0, t1))
}

fn tracks_from_tags(tags: &HashMap<String, String>) -> Option<u32> {
    tags.get("railway:tracks").and_then(|l| l.parse().ok())
}

fn road_width_from_kind(kind: &str) -> f64 {
    match kind {
        "motorway" | "motorway_link" => 28.0,
        "trunk" | "trunk_link" => 24.0,
        "primary" | "primary_link" => 20.0,
        "secondary" | "secondary_link" => 16.0,
        "tertiary" | "tertiary_link" => 12.0,
        "residential" | "living_street" => 10.0,
        "service" | "alley" => 6.0,
        "footway" | "path" | "steps" | "pedestrian" => 3.0,
        "cycleway" => 3.0,
        "track" | "unclassified" => 8.0,
        _ => 10.0,
    }
}

/// Emit a polygon area feature (building, landuse, water, leisure, amenity, natural).
/// Footprint points must already be >= 3; caller is responsible for that invariant.
fn emit_area_way(id: u64, tags: &HashMap<String, String>, fp: &[Vec2], holes: Vec<Footprint>, features: &mut Vec<Feature>) {
    if tags.contains_key("building") || tags.contains_key("building:part") {
        let levels = tags.get("building:levels").and_then(|l| l.parse::<u32>().ok());
        let roof_levels = tags.get("roof:levels").and_then(|l| l.parse::<u32>().ok());
        let min_height: Option<f64> = tags.get("min_height").and_then(|h| h.parse().ok());
        let usage = tags.get("building").cloned();
        let height: f64 = tags.get("height").and_then(|h| h.parse::<f64>().ok())
            .unwrap_or_else(|| (levels.unwrap_or(1) as f64 * 3.5) + 2.0);
        let base_y: f64 = min_height
            .or_else(|| tags.get("building:min_level").and_then(|l| l.parse::<f64>().ok()).map(|l| l * 3.5))
            .unwrap_or(0.0);
        features.push(Feature::Building(BuildingFeature {
            id: format!("osm_{}", id),
            footprint: Footprint::new(fp.to_vec()),
            indices: None,
            base_y,
            height: height - base_y,
            height_m: tags.get("height").and_then(|h| h.parse::<f64>().ok()),
            levels,
            roof_levels,
            min_height: Some(base_y),
            usage,
            roof: tags.get("roof:shape").cloned().unwrap_or_else(|| "flat".to_string()),
            colour: tags.get("building:colour").or_else(|| tags.get("building:color"))
                .map(|s| s.trim().to_lowercase()),
            material_tag: tags.get("building:material").map(|s| s.to_lowercase()),
            roof_colour: tags.get("roof:colour").or_else(|| tags.get("roof:color")).map(|s| s.to_lowercase()),
            roof_material: tags.get("roof:material").map(|s| s.to_lowercase()),
            roof_height: tags.get("roof:height").and_then(|h| h.parse::<f64>().ok()),
            name: tags.get("name").cloned(),
        }));
    } else if tags.get("natural") == Some(&"water".to_string()) {
        features.push(Feature::Water(WaterFeature::Polygon(WaterPolygonFeature {
            id: format!("osm_{}", id),
            kind: "lake".to_string(),
            footprint: Footprint::new(fp.to_vec()),
            holes,
            indices: None,
            intermittent: tags.get("intermittent").map(|s| s == "yes"),
        })));
    } else if let Some(landuse) = tags.get("landuse") {
        features.push(Feature::Landuse(LanduseFeature {
            id: format!("osm_{}", id),
            kind: landuse.clone(),
            footprint: Footprint::new(fp.to_vec()),
        }));
    } else if let Some(leisure) = tags.get("leisure") {
        let kind = match leisure.as_str() {
            "park" | "garden" | "playground" => "park",
            "pitch" | "sports_centre" | "stadium" => "pitch",
            "golf_course" => "golf_course",
            "swimming_pool" => "water",
            "nature_reserve" | "dog_park" => "park",
            _ => "park",
        };
        features.push(Feature::Landuse(LanduseFeature {
            id: format!("osm_{}", id),
            kind: kind.to_string(),
            footprint: Footprint::new(fp.to_vec()),
        }));
    } else if let Some(amenity) = tags.get("amenity") {
        let kind = match amenity.as_str() {
            "parking" | "parking_space" => "parking",
            "school" | "university" | "college" => "school",
            "hospital" | "clinic" => "hospital",
            "place_of_worship" => "religious",
            "marketplace" => "retail",
            _ => return,
        };
        features.push(Feature::Landuse(LanduseFeature {
            id: format!("osm_{}", id),
            kind: kind.to_string(),
            footprint: Footprint::new(fp.to_vec()),
        }));
    } else if let Some(natural) = tags.get("natural") {
        let kind = match natural.as_str() {
            "wood" | "tree_row" => "forest",
            "scrub" | "heath" => "scrub",
            "grassland" | "meadow" => "grass",
            "sand" | "beach" => "beach",
            "wetland" => "wetland",
            "water" => "water",
            _ => return,
        };
        features.push(Feature::Landuse(LanduseFeature {
            id: format!("osm_{}", id),
            kind: kind.to_string(),
            footprint: Footprint::new(fp.to_vec()),
        }));
    }
}

/// Emit a linear feature (road, rail, waterway ribbon).
fn emit_linear_way(id: u64, tags: &HashMap<String, String>, points: Vec<Vec3>, features: &mut Vec<Feature>) {
    if let Some(highway) = tags.get("highway") {
        let lanes = tags.get("lanes").and_then(|l| l.parse().ok());
        let has_sidewalk = tags.get("sidewalk").map(|s| s != "none").unwrap_or(false);
        let width_studs = tags.get("width").and_then(|w| w.parse::<f64>().ok())
            .unwrap_or_else(|| road_width_from_kind(highway));
        let elevated = if tags.get("bridge").map(|v| v != "no").unwrap_or(false) { Some(true) } else { None };
        let tunnel = if tags.get("tunnel").map(|v| v != "no").unwrap_or(false) { Some(true) } else { None };
        let sidewalk = tags.get("sidewalk").cloned();
        features.push(Feature::Road(RoadFeature {
            id: format!("osm_{}", id),
            kind: highway.clone(),
            lanes,
            width_studs,
            has_sidewalk,
            surface: tags.get("surface").cloned(),
            elevated,
            tunnel,
            sidewalk,
            points,
            maxspeed: tags.get("maxspeed").and_then(|s| s.replace("mph", "").trim().parse().ok()),
            lit: tags.get("lit").map(|s| s == "yes"),
            oneway: tags.get("oneway").map(|s| s == "yes" || s == "1"),
            layer: tags.get("layer").and_then(|s| s.parse().ok()),
        }));
    } else if let Some(railway) = tags.get("railway") {
        features.push(Feature::Rail(RailFeature {
            id: format!("osm_{}", id),
            kind: railway.clone(),
            lanes: tracks_from_tags(tags),
            width_studs: 4.0,
            points,
        }));
    } else if let Some(waterway) = tags.get("waterway") {
        features.push(Feature::Water(WaterFeature::Ribbon(WaterRibbonFeature {
            id: format!("osm_{}", id),
            kind: waterway.clone(),
            width_studs: 8.0,
            points,
            width: tags.get("width").and_then(|w| w.parse::<f64>().ok()),
            intermittent: tags.get("intermittent").map(|s| s == "yes"),
        })));
    }
}

/// Merge open ring segments end-to-end (Arnis ring-merge algorithm).
/// Multipolygon relation boundaries are split across multiple ways;
/// this stitches them back into closed rings.
fn merge_rings(rings: &mut Vec<Vec<Vec2>>) {
    let matches = |a: Vec2, b: Vec2| (a.x - b.x).abs() < 2.0 && (a.y - b.y).abs() < 2.0;
    let mut merged = true;
    while merged {
        merged = false;
        let mut i = 0;
        while i < rings.len() {
            let mut j = i + 1;
            while j < rings.len() {
                let (a_first, a_last) = (*rings[i].first().unwrap(), *rings[i].last().unwrap());
                let (b_first, b_last) = (*rings[j].first().unwrap(), *rings[j].last().unwrap());
                if matches(a_last, b_first) {
                    // a → b: append b (skip b[0] to avoid dup)
                    let b = rings.remove(j);
                    rings[i].extend_from_slice(&b[1..]);
                    merged = true;
                } else if matches(b_last, a_first) {
                    // b → a: prepend b to a
                    let mut b = rings.remove(j);
                    b.extend_from_slice(&rings[i][1..]);
                    rings[i] = b;
                    merged = true;
                } else if matches(a_last, b_last) {
                    // a → reverse(b)
                    let mut b = rings.remove(j);
                    b.reverse();
                    rings[i].extend_from_slice(&b[1..]);
                    merged = true;
                } else if matches(a_first, b_first) {
                    // reverse(a) → b
                    rings[i].reverse();
                    let b = rings.remove(j);
                    rings[i].extend_from_slice(&b[1..]);
                    merged = true;
                } else {
                    j += 1;
                }
            }
            i += 1;
        }
    }
}

pub fn run_pipeline(
    adapter: &dyn SourceAdapter,
    bbox: BoundingBox,
    stages: &[&dyn PipelineStage],
) -> PipelineResult<PipelineContext> {
    let features = adapter.load(bbox)?;
    let mut ctx = PipelineContext::new(bbox, features);

    for stage in stages {
        stage.run(&mut ctx)?;
    }

    Ok(ctx)
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbx_geo::{BoundingBox, Footprint, Vec2};

    struct DummyAdapter;

    impl SourceAdapter for DummyAdapter {
        fn name(&self) -> &'static str {
            "dummy"
        }

        fn load(&self, _bbox: BoundingBox) -> PipelineResult<Vec<Feature>> {
            Ok(vec![Feature::Building(BuildingFeature {
                id: "b1".to_string(),
                footprint: Footprint::new(vec![
                    Vec2::new(0.0, 0.0),
                    Vec2::new(1.0, 0.0),
                    Vec2::new(1.0, 1.0),
                ]),
                indices: None,
                base_y: 0.0,
                height: 10.0,
                height_m: None,
                levels: None,
                roof_levels: None,
                min_height: None,
                usage: None,
                roof: "flat".to_string(),
                colour: None,
                material_tag: None,
                roof_colour: None,
                roof_material: None,
                roof_height: None,
                name: None,
            })])
        }
    }

    #[test]
    fn pipeline_runs() {
        let adapter = DummyAdapter;
        let bbox = BoundingBox::new(30.0, -98.0, 31.0, -97.0);
        let stages: [&dyn PipelineStage; 2] = [&ValidateStage, &NormalizeStage];

        let ctx = run_pipeline(&adapter, bbox, &stages).expect("pipeline result");
        assert_eq!(ctx.stats.source_feature_count, 1);
        assert_eq!(ctx.stats.normalized_feature_count, 1);
        assert_eq!(ctx.notes.len(), 2);
    }

    /// Degenerate Overpass JSON (2-node way with landuse tag) must be silently
    /// dropped by the pipeline — never emitted as a LanduseFeature.
    #[test]
    fn overpass_degenerate_landuse_dropped() {
        use std::io::Write;

        // Build a minimal Overpass response with:
        //  - two nodes
        //  - one way referencing both (only 2 nodes → degenerate polygon)
        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.27, "lon": -97.74},
                {"type": "node", "id": 2, "lat": 30.28, "lon": -97.73},
                {
                    "type": "way",
                    "id": 999,
                    "nodes": [1, 2],
                    "tags": {"landuse": "grass"}
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_degenerate_landuse.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        for f in &features {
            if let Feature::Landuse(lu) = f {
                assert!(
                    lu.footprint.points.len() >= 3,
                    "emitted LanduseFeature with {} points (id={})",
                    lu.footprint.points.len(),
                    lu.id
                );
            }
        }
        // The degenerate way must have been dropped entirely.
        let landuse_count = features
            .iter()
            .filter(|f| matches!(f, Feature::Landuse(_)))
            .count();
        assert_eq!(landuse_count, 0, "expected degenerate way to be dropped");
    }
}
