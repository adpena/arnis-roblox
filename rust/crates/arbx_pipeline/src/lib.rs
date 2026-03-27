pub mod overpass_client;
pub mod overture;

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
    pub subkind: Option<String>,
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
    pub holes: Vec<Footprint>,
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

/// Compile-time specification for a simple node → prop mapping.
struct NodePropSpec {
    tag_key: &'static str,
    tag_value: &'static str,
    kind: &'static str,
    id_prefix: &'static str,
    extract_height: bool,
}

const NODE_PROP_SPECS: &[NodePropSpec] = &[
    NodePropSpec {
        tag_key: "highway",
        tag_value: "street_lamp",
        kind: "street_lamp",
        id_prefix: "lamp",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "bench",
        kind: "bench",
        id_prefix: "bench",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "highway",
        tag_value: "bus_stop",
        kind: "bus_stop",
        id_prefix: "busstop",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "bus_shelter",
        kind: "bus_stop",
        id_prefix: "busstop",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "highway",
        tag_value: "traffic_signals",
        kind: "traffic_signal",
        id_prefix: "signal",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "waste_basket",
        kind: "waste_basket",
        id_prefix: "bin",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "recycling",
        kind: "waste_basket",
        id_prefix: "bin",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "emergency",
        tag_value: "fire_hydrant",
        kind: "fire_hydrant",
        id_prefix: "hydrant",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "highway",
        tag_value: "crossing",
        kind: "crossing",
        id_prefix: "crossing",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "fountain",
        kind: "fountain",
        id_prefix: "fountain",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "post_box",
        kind: "post_box",
        id_prefix: "postbox",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "drinking_water",
        kind: "drinking_water",
        id_prefix: "water",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "barrier",
        tag_value: "bollard",
        kind: "bollard",
        id_prefix: "bollard",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "vending_machine",
        kind: "vending_machine",
        id_prefix: "vending",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "telephone",
        kind: "telephone",
        id_prefix: "phone",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "parking_meter",
        kind: "parking_meter",
        id_prefix: "pmeter",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "parking_entrance",
        kind: "parking_meter",
        id_prefix: "pmeter",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "amenity",
        tag_value: "bicycle_parking",
        kind: "bicycle_parking",
        id_prefix: "bikepark",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "power",
        tag_value: "tower",
        kind: "power_tower",
        id_prefix: "ptower",
        extract_height: true,
    },
    NodePropSpec {
        tag_key: "power",
        tag_value: "pole",
        kind: "power_pole",
        id_prefix: "ppole",
        extract_height: true,
    },
    NodePropSpec {
        tag_key: "man_made",
        tag_value: "surveillance",
        kind: "surveillance",
        id_prefix: "camera",
        extract_height: false,
    },
    NodePropSpec {
        tag_key: "man_made",
        tag_value: "flagpole",
        kind: "flagpole",
        id_prefix: "flag",
        extract_height: true,
    },
];

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LanduseFeature {
    pub id: String,
    pub kind: String,
    pub footprint: Footprint,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BarrierFeature {
    pub id: String,
    pub kind: String,
    pub points: Vec<Vec3>,
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
    Barrier(BarrierFeature),
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
                    if b.holes.is_empty() {
                        b.indices = Some(b.footprint.triangulate());
                    } else {
                        b.indices = None;
                    }
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

/// Post-load pipeline stage that samples a DEM at each feature's XZ position
/// and sets the correct Y value.  Features with Y already significantly
/// non-zero (e.g. from adapter-level bridge detection) are left untouched.
///
/// This is better than per-adapter enrichment because it works uniformly for
/// every adapter (Overpass, File, Synthetic, future Mapbox, etc.).
pub struct ElevationEnrichmentStage<'a> {
    pub elevation: &'a dyn ElevationProvider,
    pub meters_per_stud: f64,
    pub bbox_center: LatLon,
}

impl<'a> PipelineStage for ElevationEnrichmentStage<'a> {
    fn name(&self) -> &'static str {
        "elevation-enrichment"
    }

    fn run(&self, ctx: &mut PipelineContext) -> PipelineResult<()> {
        let mps = self.meters_per_stud;
        let center = self.bbox_center;

        // Helper: reverse-project stud-space XZ back to LatLon, sample DEM,
        // return height in studs.
        let sample_y = |x: f64, z: f64| -> f64 {
            let ll = Mercator::unproject(Vec3::new(x, 0.0, z), center, mps);
            let h = self.elevation.sample_height_at(ll);
            h as f64 / mps
        };

        let mut enriched = 0usize;

        for feature in &mut ctx.features {
            match feature {
                Feature::Road(f) => {
                    // Skip bridges — they float above terrain; the builder
                    // applies a fixed offset above the terrain surface.
                    if f.elevated == Some(true) {
                        continue;
                    }
                    for p in &mut f.points {
                        if p.y.abs() < 0.01 {
                            p.y = sample_y(p.x, p.z);
                            enriched += 1;
                        }
                    }
                }
                Feature::Rail(f) => {
                    for p in &mut f.points {
                        if p.y.abs() < 0.01 {
                            p.y = sample_y(p.x, p.z);
                            enriched += 1;
                        }
                    }
                }
                Feature::Building(f) => {
                    if f.base_y.abs() < 0.01 {
                        // Sample at footprint centroid
                        let n = f.footprint.points.len() as f64;
                        let cx = f.footprint.points.iter().map(|p| p.x).sum::<f64>() / n;
                        let cz = f.footprint.points.iter().map(|p| p.y).sum::<f64>() / n;
                        f.base_y = sample_y(cx, cz);
                        enriched += 1;
                    }
                }
                Feature::Prop(f) => {
                    if f.position.y.abs() < 0.01 {
                        f.position.y = sample_y(f.position.x, f.position.z);
                        enriched += 1;
                    }
                }
                Feature::Water(WaterFeature::Ribbon(r)) => {
                    for p in &mut r.points {
                        if p.y.abs() < 0.01 {
                            p.y = sample_y(p.x, p.z);
                            enriched += 1;
                        }
                    }
                }
                Feature::Water(WaterFeature::Polygon(_)) => {
                    // Water polygon surfaceY is computed in the chunker where
                    // the chunk origin is known. Nothing to enrich here.
                }
                Feature::Barrier(f) => {
                    for p in &mut f.points {
                        if p.y.abs() < 0.01 {
                            p.y = sample_y(p.x, p.z);
                            enriched += 1;
                        }
                    }
                }
                Feature::Landuse(_) => {
                    // 2-D footprint only — no Y to enrich.
                }
            }
        }

        ctx.notes.push(format!(
            "enriched {} feature Y positions from DEM",
            enriched,
        ));
        Ok(())
    }
}

pub struct SyntheticAustinAdapter {
    pub meters_per_stud: f64,
}

impl SourceAdapter for SyntheticAustinAdapter {
    fn name(&self) -> &'static str {
        "synthetic-austin"
    }

    fn load(&self, bbox: BoundingBox) -> PipelineResult<Vec<Feature>> {
        let mut features = Vec::new();
        let elevation = PerlinElevationProvider::default();
        let center = bbox.center();
        let mps = self.meters_per_stud;

        // Helper to project and sample height
        let project_with_y = |lat: f64, lon: f64| {
            let mut p = Mercator::project(LatLon::new(lat, lon), center, mps);
            p.y = elevation.sample_height_at(LatLon::new(lat, lon)) as f64;
            p
        };

        // Add a long road that spans multiple chunks, following terrain
        features.push(Feature::Road(RoadFeature {
            id: "congress_ave".to_string(),
            kind: "primary".to_string(),
            subkind: None,
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
            holes: vec![],
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
        let projected_bounds = projected_bbox_bounds(bbox, center, mps);
        let mut relation_managed_area_way_ids: std::collections::HashSet<u64> =
            std::collections::HashSet::new();

        // ── Phase 1: build node-id → LatLon map ──────────────────────────────
        let mut node_coords: HashMap<u64, arbx_geo::LatLon> = HashMap::new();
        for el in &data.elements {
            if el.kind == "node" {
                if let (Some(lat), Some(lon)) = (el.lat, el.lon) {
                    node_coords.insert(el.id, arbx_geo::LatLon::new(lat, lon));
                }
            }
        }

        for el in &data.elements {
            if el.kind != "relation" {
                continue;
            }
            let Some(tags) = &el.tags else { continue };
            let rel_type = tags.get("type").map(|s| s.as_str());
            if rel_type != Some("multipolygon") && rel_type != Some("boundary") {
                continue;
            }
            let relation_manages_area = tags.contains_key("building")
                || tags.contains_key("building:part")
                || tags.contains_key("landuse")
                || tags.contains_key("leisure")
                || tags.contains_key("amenity")
                || tags.get("natural").map(|v| v != "tree").unwrap_or(false)
                || tags.get("natural") == Some(&"water".to_string());
            if !relation_manages_area {
                continue;
            }
            for member in &el.members {
                if member.kind == "way" && (member.role == "outer" || member.role.is_empty()) {
                    relation_managed_area_way_ids.insert(member.ref_id);
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
            if el.kind != "way" {
                continue;
            }
            let Some(way_nodes) = &el.nodes else { continue };
            if way_nodes.is_empty() {
                continue;
            }

            let is_closed_ring = way_nodes.first() == way_nodes.last() && way_nodes.len() > 1;

            let pts: Vec<Vec2> = if is_closed_ring {
                // Polygon way — keep all resolved nodes regardless of bbox position
                way_nodes
                    .iter()
                    .filter_map(|id| node_coords.get(id))
                    .map(|&ll| {
                        let p = Mercator::project(ll, center, mps);
                        Vec2::new(p.x, p.z)
                    })
                    .collect()
            } else {
                // Linear way — clip each node to bbox (avoids far-away chunk creation)
                way_nodes
                    .iter()
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
            if el.kind != "way" {
                continue;
            }
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
                if relation_managed_area_way_ids.contains(&el.id) {
                    continue;
                }
                // Use unclipped polygon points; check centroid is within clip_bbox
                let Some(fp) = way_points.get(&el.id) else {
                    continue;
                };
                let clipped_fp = clip_polygon_to_rect(fp, projected_bounds);
                if clipped_fp.len() < 3 {
                    eprintln!(
                        "WARN: way osm_{} — {} point(s) after projection, skipping",
                        el.id,
                        clipped_fp.len()
                    );
                    continue;
                }
                let clipped_holes = vec![];
                emit_area_way(
                    &format!("osm_{}", el.id),
                    tags,
                    &clipped_fp,
                    clipped_holes,
                    mps,
                    &mut features,
                );
            } else {
                // Linear feature — segment-level clip interpolates bbox entry/exit
                let Some(way_nodes) = &el.nodes else { continue };
                let node_lls: Vec<LatLon> = way_nodes
                    .iter()
                    .filter_map(|id| node_coords.get(id).copied())
                    .collect();
                let mut lin_pts: Vec<Vec3> = Vec::new();
                for i in 0..node_lls.len().saturating_sub(1) {
                    let (a, b) = (node_lls[i], node_lls[i + 1]);
                    let Some((t0, t1)) = liang_barsky(a, b, &bbox) else {
                        continue;
                    };
                    let lerp = |p1: LatLon, p2: LatLon, t: f64| {
                        LatLon::new(
                            p1.lat + t * (p2.lat - p1.lat),
                            p1.lon + t * (p2.lon - p1.lon),
                        )
                    };
                    let c1 = lerp(a, b, t0);
                    let c2 = lerp(a, b, t1);
                    let proj1 = Mercator::project(c1, center, mps);
                    if lin_pts
                        .last()
                        .map(|p: &Vec3| {
                            (p.x - proj1.x).abs() > 0.05 || (p.z - proj1.z).abs() > 0.05
                        })
                        .unwrap_or(true)
                    {
                        lin_pts.push(proj1);
                    }
                    lin_pts.push(Mercator::project(c2, center, mps));
                }
                if lin_pts.len() < 2 {
                    continue;
                }
                emit_linear_way(el.id, tags, lin_pts, self.meters_per_stud, &mut features);
            }
        }

        // ── Phase 3b: Assemble multipolygon relations ─────────────────────────
        // Tags live on the relation, not the member ways. We merge outer-role
        // member ways into a single ring following the Arnis ring-merge approach.
        for el in &data.elements {
            if el.kind != "relation" {
                continue;
            }
            let Some(tags) = &el.tags else { continue };
            let rel_type = tags.get("type").map(|s| s.as_str());
            if rel_type != Some("multipolygon") && rel_type != Some("boundary") {
                continue;
            }

            // Collect outer member way point sequences
            let mut outer_rings: Vec<Vec<Vec2>> = el
                .members
                .iter()
                .filter(|m| m.kind == "way" && (m.role == "outer" || m.role.is_empty()))
                .filter_map(|m| way_points.get(&m.ref_id).cloned())
                .collect();

            if outer_rings.is_empty() {
                continue;
            }

            // Merge split rings (multipolygon boundaries are often split across ways)
            merge_rings(&mut outer_rings);

            let is_building_relation =
                tags.contains_key("building") || tags.contains_key("building:part");
            if is_building_relation {
                let mut inner_rings: Vec<Vec<Vec2>> = el
                    .members
                    .iter()
                    .filter(|m| m.kind == "way" && m.role == "inner")
                    .filter_map(|m| way_points.get(&m.ref_id).cloned())
                    .collect();

                if !inner_rings.is_empty() {
                    merge_rings(&mut inner_rings);
                }

                let hole_candidates: Vec<Footprint> = inner_rings
                    .into_iter()
                    .filter(|r| r.len() >= 3)
                    .map(Footprint::new)
                    .collect();
                let single_outer_ring = outer_rings.len() == 1;

                for (outer_index, outer_ring) in outer_rings.into_iter().enumerate() {
                    if outer_ring.len() < 3 {
                        continue;
                    }
                    let outer_footprint = Footprint::new(outer_ring.clone());
                    let holes_for_outer: Vec<Footprint> = hole_candidates
                        .iter()
                        .filter(|hole| building_hole_belongs_to_outer(&outer_footprint, hole))
                        .filter_map(|hole| {
                            let clipped_hole = clip_polygon_to_rect(&hole.points, projected_bounds);
                            (clipped_hole.len() >= 3).then(|| Footprint::new(clipped_hole))
                        })
                        .collect();
                    let clipped_outer =
                        clip_polygon_to_rect(&outer_footprint.points, projected_bounds);
                    if clipped_outer.len() < 3 {
                        continue;
                    }
                    let emitted_id = if single_outer_ring {
                        format!("osm_{}", el.id)
                    } else {
                        format!("osm_{}_outer_{}", el.id, outer_index + 1)
                    };
                    emit_area_way(
                        &emitted_id,
                        tags,
                        &clipped_outer,
                        holes_for_outer,
                        mps,
                        &mut features,
                    );
                }
                continue;
            }

            // Use the largest outer ring as the footprint
            let Some(footprint) = outer_rings.into_iter().max_by_key(|r| r.len()) else {
                continue;
            };
            let clipped_footprint = clip_polygon_to_rect(&footprint, projected_bounds);
            if clipped_footprint.len() < 3 {
                continue;
            }

            // Collect inner member way point sequences (islands/holes)
            let mut inner_rings: Vec<Vec<Vec2>> = el
                .members
                .iter()
                .filter(|m| m.kind == "way" && m.role == "inner")
                .filter_map(|m| way_points.get(&m.ref_id).cloned())
                .collect();

            if !inner_rings.is_empty() {
                merge_rings(&mut inner_rings);
            }

            let holes: Vec<Footprint> = inner_rings
                .into_iter()
                .filter_map(|r| {
                    let clipped = clip_polygon_to_rect(&r, projected_bounds);
                    (clipped.len() >= 3).then(|| Footprint::new(clipped))
                })
                .collect();

            emit_area_way(
                &format!("osm_{}", el.id),
                tags,
                &clipped_footprint,
                holes,
                mps,
                &mut features,
            );
        }

        // Parse node elements for trees and similar point features
        for el in &data.elements {
            if el.kind == "node" {
                let Some(tags) = &el.tags else { continue };
                let Some(lat) = el.lat else { continue };
                let Some(lon) = el.lon else { continue };
                let ll = LatLon::new(lat, lon);
                if !bbox.contains(ll) {
                    continue;
                }
                let pos = Mercator::project(ll, center, mps);

                // Table-driven prop extraction — covers all simple tag → prop mappings.
                let mut matched = false;
                for spec in NODE_PROP_SPECS {
                    if tags.get(spec.tag_key) == Some(&spec.tag_value.to_string()) {
                        features.push(Feature::Prop(PropFeature {
                            id: format!("{}_{}", spec.id_prefix, el.id),
                            kind: spec.kind.to_string(),
                            position: pos,
                            yaw_degrees: 0.0,
                            scale: 1.0,
                            species: None,
                            height: if spec.extract_height {
                                tags.get("height").and_then(|h| h.parse().ok())
                            } else {
                                None
                            },
                            leaf_type: None,
                            circumference: None,
                        }));
                        matched = true;
                        break;
                    }
                }
                if matched {
                    continue;
                }

                // Tree detection — special case with species/leaf_type/circumference enrichment.
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
                                (Some("broadleaved"), _) => {
                                    Some("broadleaved_deciduous".to_string())
                                }
                                _ => None,
                            }
                        });

                    let tree_height = tags.get("height").and_then(|h| h.parse::<f64>().ok());
                    let leaf_type = tags.get("leaf_type").cloned();
                    let circumference = tags
                        .get("circumference")
                        .and_then(|c| c.parse::<f64>().ok());

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

        // Append Overture buildings as gap-fill only when OSM does not already
        // describe substantially the same structure.
        let overture_path = "rust/data/overture_buildings.geojson";
        let overture_features =
            overture::load_overture_buildings(overture_path, bbox, self.meters_per_stud);
        merge_overture_gap_fill(&mut features, overture_features);

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

pub(crate) fn projected_bbox_bounds(
    bbox: BoundingBox,
    center: LatLon,
    meters_per_stud: f64,
) -> (f64, f64, f64, f64) {
    let corners = [
        Mercator::project(
            LatLon::new(bbox.min.lat, bbox.min.lon),
            center,
            meters_per_stud,
        ),
        Mercator::project(
            LatLon::new(bbox.min.lat, bbox.max.lon),
            center,
            meters_per_stud,
        ),
        Mercator::project(
            LatLon::new(bbox.max.lat, bbox.min.lon),
            center,
            meters_per_stud,
        ),
        Mercator::project(
            LatLon::new(bbox.max.lat, bbox.max.lon),
            center,
            meters_per_stud,
        ),
    ];
    let mut min_x = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut min_z = f64::INFINITY;
    let mut max_z = f64::NEG_INFINITY;
    for point in corners {
        min_x = min_x.min(point.x);
        max_x = max_x.max(point.x);
        min_z = min_z.min(point.z);
        max_z = max_z.max(point.z);
    }
    (min_x, max_x, min_z, max_z)
}

pub(crate) fn clip_polygon_to_rect(points: &[Vec2], bounds: (f64, f64, f64, f64)) -> Vec<Vec2> {
    fn clip_edge(
        points: &[Vec2],
        inside: impl Fn(Vec2) -> bool,
        intersect: impl Fn(Vec2, Vec2) -> Vec2,
    ) -> Vec<Vec2> {
        if points.is_empty() {
            return Vec::new();
        }

        let mut output = Vec::new();
        let mut previous = *points.last().expect("non-empty points");
        let mut previous_inside = inside(previous);
        for &current in points {
            let current_inside = inside(current);
            match (previous_inside, current_inside) {
                (true, true) => output.push(current),
                (true, false) => output.push(intersect(previous, current)),
                (false, true) => {
                    output.push(intersect(previous, current));
                    output.push(current);
                }
                (false, false) => {}
            }
            previous = current;
            previous_inside = current_inside;
        }
        output
    }

    fn intersect_vertical(previous: Vec2, current: Vec2, x: f64) -> Vec2 {
        let dx = current.x - previous.x;
        if dx.abs() < f64::EPSILON {
            return Vec2::new(x, current.y);
        }
        let t = (x - previous.x) / dx;
        Vec2::new(x, previous.y + t * (current.y - previous.y))
    }

    fn intersect_horizontal(previous: Vec2, current: Vec2, y: f64) -> Vec2 {
        let dy = current.y - previous.y;
        if dy.abs() < f64::EPSILON {
            return Vec2::new(current.x, y);
        }
        let t = (y - previous.y) / dy;
        Vec2::new(previous.x + t * (current.x - previous.x), y)
    }

    let (min_x, max_x, min_z, max_z) = bounds;
    let mut clipped = points.to_vec();
    clipped = clip_edge(
        &clipped,
        |p| p.x >= min_x,
        |a, b| intersect_vertical(a, b, min_x),
    );
    clipped = clip_edge(
        &clipped,
        |p| p.x <= max_x,
        |a, b| intersect_vertical(a, b, max_x),
    );
    clipped = clip_edge(
        &clipped,
        |p| p.y >= min_z,
        |a, b| intersect_horizontal(a, b, min_z),
    );
    clipped = clip_edge(
        &clipped,
        |p| p.y <= max_z,
        |a, b| intersect_horizontal(a, b, max_z),
    );

    if clipped.len() >= 2 && clipped.first() == clipped.last() {
        clipped.pop();
    }

    clipped
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
        (dx, bbox.max.lon - p1.lon),
        (-dy, p1.lat - bbox.min.lat),
        (dy, bbox.max.lat - p1.lat),
    ] {
        if p == 0.0 {
            if q < 0.0 {
                return None;
            }
        } else if p < 0.0 {
            let r = q / p;
            if r > t1 {
                return None;
            }
            if r > t0 {
                t0 = r;
            }
        } else {
            let r = q / p;
            if r < t0 {
                return None;
            }
            if r < t1 {
                t1 = r;
            }
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

fn parse_osm_width_to_studs(raw: &str, meters_per_stud: f64) -> Option<f64> {
    if meters_per_stud <= f64::EPSILON {
        return None;
    }

    let normalized = raw
        .split(';')
        .next()
        .map(str::trim)
        .map(str::to_lowercase)
        .filter(|value| !value.is_empty())?;

    let (numeric, meters_per_unit) = if let Some(value) = normalized.strip_suffix("feet") {
        (value.trim(), 0.3048)
    } else if let Some(value) = normalized.strip_suffix("foot") {
        (value.trim(), 0.3048)
    } else if let Some(value) = normalized.strip_suffix("ft") {
        (value.trim(), 0.3048)
    } else if let Some(value) = normalized.strip_suffix('\'') {
        (value.trim(), 0.3048)
    } else if let Some(value) = normalized.strip_suffix('m') {
        (value.trim(), 1.0)
    } else {
        (normalized.as_str(), 1.0)
    };

    numeric
        .parse::<f64>()
        .ok()
        .map(|value| (value * meters_per_unit) / meters_per_stud)
}

fn normalize_usage_value(value: &str) -> String {
    match value.trim().to_lowercase().as_str() {
        "semidetached_house" => "house".to_string(),
        "terraced_house" => "terrace".to_string(),
        "public" => "civic".to_string(),
        other => other.to_string(),
    }
}

fn infer_building_usage(tags: &HashMap<String, String>) -> Option<String> {
    let explicit_building_usage = tags.get("building").and_then(|building| {
        let normalized = normalize_usage_value(building);
        if normalized != "yes" && normalized != "building" {
            Some(normalized)
        } else {
            None
        }
    });

    if let Some(office) = tags.get("office") {
        let normalized = office.trim().to_lowercase();
        if normalized == "government" {
            return Some("government".to_string());
        }
        return Some("office".to_string());
    }

    if let Some(government) = tags.get("government") {
        let normalized = government.trim().to_lowercase();
        if normalized == "yes"
            || normalized == "government"
            || normalized == "state"
            || normalized == "legislative"
            || normalized == "executive"
            || normalized == "judicial"
        {
            return Some("government".to_string());
        }
    }

    if let Some(tourism) = tags.get("tourism") {
        let normalized = tourism.trim().to_lowercase();
        if normalized == "hotel" || normalized == "motel" || normalized == "hostel" {
            return Some("hotel".to_string());
        }
    }

    if let Some(amenity) = tags.get("amenity") {
        let normalized = amenity.trim().to_lowercase();
        let inferred = match normalized.as_str() {
            "restaurant" | "bar" | "cafe" | "fast_food" | "pub" | "food_court" | "biergarten" => {
                "restaurant"
            }
            "parking" | "parking_entrance" | "parking_space" => "parking",
            "place_of_worship" => "religious",
            "school" | "college" | "university" | "library" | "kindergarten" => "school",
            "hospital" | "clinic" | "doctors" | "dentist" | "pharmacy" | "veterinary" => "hospital",
            "bank" => "bank",
            "fuel" | "car_wash" | "car_rental" | "vehicle_inspection" => "garage",
            "fire_station" | "police" | "courthouse" | "townhall" | "post_office"
            | "community_centre" | "social_centre" | "arts_centre" | "theatre" | "cinema"
            | "studio" => "civic",
            _ => "",
        };
        if !inferred.is_empty() {
            return Some(inferred.to_string());
        }
    }

    let shop = tags
        .get("shop")
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty());
    if let Some(ref normalized) = shop {
        if normalized == "supermarket" {
            return Some("supermarket".to_string());
        }
        if normalized != "yes" {
            return Some("retail".to_string());
        }
    }

    if let Some(man_made) = tags.get("man_made") {
        let normalized = man_made.trim().to_lowercase();
        if matches!(
            normalized.as_str(),
            "storage_tank" | "silo" | "works" | "water_tower" | "tower" | "mast"
        ) {
            return Some("industrial".to_string());
        }
    }

    if let Some(landuse) = tags.get("landuse") {
        let normalized = landuse.trim().to_lowercase();
        let inferred = match normalized.as_str() {
            "commercial" | "retail" => "commercial",
            "industrial" | "depot" => "industrial",
            _ => "",
        };
        if !inferred.is_empty() {
            return Some(inferred.to_string());
        }
    }

    if let Some(name) = tags.get("name") {
        let normalized = name.trim().to_lowercase();
        let inferred = if normalized.contains("capitol")
            || normalized.contains("legislative")
            || normalized.contains("governor")
            || normalized.contains("state office")
        {
            "government"
        } else if normalized.contains("supreme court")
            || normalized.contains("courthouse")
            || normalized.contains("court building")
        {
            "civic"
        } else {
            ""
        };
        if !inferred.is_empty() {
            return Some(inferred.to_string());
        }
    }

    if shop.is_some() {
        return Some("retail".to_string());
    }

    if let Some(building_usage) = explicit_building_usage {
        return Some(building_usage);
    }

    if tags.contains_key("building") {
        return Some("building".to_string());
    }

    tags.get("building:part")
        .map(|value| normalize_usage_value(value))
}

fn polygon_area(points: &[Vec2]) -> f64 {
    if points.len() < 3 {
        return 0.0;
    }

    let mut area = 0.0;
    for index in 0..points.len() {
        let current = points[index];
        let next = points[(index + 1) % points.len()];
        area += current.x * next.y - next.x * current.y;
    }
    area.abs() * 0.5
}

fn polygon_centroid(points: &[Vec2]) -> Option<Vec2> {
    if points.is_empty() {
        return None;
    }

    let mut twice_area = 0.0;
    let mut centroid_x = 0.0;
    let mut centroid_y = 0.0;

    for index in 0..points.len() {
        let current = points[index];
        let next = points[(index + 1) % points.len()];
        let cross = current.x * next.y - next.x * current.y;
        twice_area += cross;
        centroid_x += (current.x + next.x) * cross;
        centroid_y += (current.y + next.y) * cross;
    }

    if twice_area.abs() <= f64::EPSILON {
        let mut sum_x = 0.0;
        let mut sum_y = 0.0;
        for point in points {
            sum_x += point.x;
            sum_y += point.y;
        }
        let count = points.len() as f64;
        return Some(Vec2::new(sum_x / count, sum_y / count));
    }

    let factor = 1.0 / (3.0 * twice_area);
    Some(Vec2::new(centroid_x * factor, centroid_y * factor))
}

fn point_in_polygon(point: Vec2, polygon: &[Vec2]) -> bool {
    if polygon.len() < 3 {
        return false;
    }

    let mut inside = false;
    let mut previous = polygon[polygon.len() - 1];
    for current in polygon {
        let current_above = current.y > point.y;
        let previous_above = previous.y > point.y;
        if current_above != previous_above {
            let intersect_x = (previous.x - current.x) * (point.y - current.y)
                / ((previous.y - current.y) + f64::EPSILON)
                + current.x;
            if point.x < intersect_x {
                inside = !inside;
            }
        }
        previous = *current;
    }

    inside
}

fn buildings_substantially_overlap(
    existing: &BuildingFeature,
    candidate: &BuildingFeature,
) -> bool {
    let Some((existing_min, existing_max)) = existing.footprint.aabb() else {
        return false;
    };
    let Some((candidate_min, candidate_max)) = candidate.footprint.aabb() else {
        return false;
    };

    let overlap_min_x = existing_min.x.max(candidate_min.x);
    let overlap_min_y = existing_min.y.max(candidate_min.y);
    let overlap_max_x = existing_max.x.min(candidate_max.x);
    let overlap_max_y = existing_max.y.min(candidate_max.y);
    if overlap_max_x <= overlap_min_x || overlap_max_y <= overlap_min_y {
        return false;
    }

    let existing_area = polygon_area(&existing.footprint.points);
    let candidate_area = polygon_area(&candidate.footprint.points);
    if existing_area <= f64::EPSILON || candidate_area <= f64::EPSILON {
        return false;
    }

    let overlap_area = (overlap_max_x - overlap_min_x) * (overlap_max_y - overlap_min_y);
    let overlap_ratio = overlap_area / existing_area.min(candidate_area);
    if overlap_ratio < 0.85 {
        return false;
    }

    let Some(existing_centroid) = polygon_centroid(&existing.footprint.points) else {
        return false;
    };
    let Some(candidate_centroid) = polygon_centroid(&candidate.footprint.points) else {
        return false;
    };

    let centroid_dx = existing_centroid.x - candidate_centroid.x;
    let centroid_dy = existing_centroid.y - candidate_centroid.y;
    let centroid_distance = (centroid_dx * centroid_dx + centroid_dy * centroid_dy).sqrt();
    let max_centroid_distance = existing_area.min(candidate_area).sqrt() * 0.15;
    if centroid_distance > max_centroid_distance.max(8.0) {
        return false;
    }

    point_in_polygon(candidate_centroid, &existing.footprint.points)
        || point_in_polygon(existing_centroid, &candidate.footprint.points)
}

fn should_preserve_named_overture_parent(
    overlapping: &[&BuildingFeature],
    candidate: &BuildingFeature,
) -> bool {
    if candidate.name.is_none() || overlapping.is_empty() {
        return false;
    }

    let candidate_area = polygon_area(&candidate.footprint.points);
    if candidate_area <= f64::EPSILON {
        return false;
    }

    overlapping.iter().all(|existing| {
        existing.name.is_none() && polygon_area(&existing.footprint.points) < candidate_area * 0.98
    })
}

fn merge_overture_gap_fill(features: &mut Vec<Feature>, overture_features: Vec<Feature>) {
    let mut canonical_buildings: Vec<BuildingFeature> = features
        .iter()
        .filter_map(|feature| match feature {
            Feature::Building(building) => Some(building.clone()),
            _ => None,
        })
        .collect();

    for feature in overture_features {
        if let Feature::Building(candidate) = &feature {
            let overlapping: Vec<&BuildingFeature> = canonical_buildings
                .iter()
                .filter(|existing| buildings_substantially_overlap(existing, candidate))
                .collect();
            if !overlapping.is_empty()
                && !should_preserve_named_overture_parent(&overlapping, candidate)
            {
                continue;
            }
            canonical_buildings.push(candidate.clone());
        }
        features.push(feature);
    }
}

fn refine_generic_building_usage(
    footprint: &[Vec2],
    height_m: f64,
    levels: Option<u32>,
    meters_per_stud: f64,
) -> Option<String> {
    let area_m2 = polygon_area(footprint) * meters_per_stud * meters_per_stud;
    let estimated_levels =
        levels.unwrap_or_else(|| (((height_m - 2.0).max(0.0) / 3.5).round() as u32).max(1));

    if estimated_levels >= 8 || height_m >= 28.0 {
        return Some("office".to_string());
    }
    if area_m2 <= 120.0 && height_m <= 8.0 {
        return Some("residential".to_string());
    }
    if area_m2 <= 350.0 && estimated_levels <= 3 {
        return Some("apartments".to_string());
    }
    if area_m2 >= 1_200.0 && estimated_levels <= 2 {
        return Some("warehouse".to_string());
    }
    if area_m2 >= 450.0 && estimated_levels <= 3 {
        return Some("commercial".to_string());
    }
    if estimated_levels <= 3 {
        return Some("residential".to_string());
    }

    None
}

pub(crate) fn infer_roof_shape(
    tags: &HashMap<String, String>,
    usage: Option<&str>,
    footprint: &[Vec2],
    meters_per_stud: f64,
) -> String {
    if let Some(roof_shape) = tags.get("roof:shape") {
        return roof_shape.trim().to_lowercase();
    }

    let levels = tags
        .get("building:levels")
        .and_then(|l| l.parse::<u32>().ok())
        .unwrap_or(1);
    let usage = usage.unwrap_or("building");
    let area_m2 = polygon_area(footprint) * meters_per_stud * meters_per_stud;
    let simple_outline = footprint.len() <= 4;
    let (span_x, span_y) = if footprint.is_empty() {
        (0.0, 0.0)
    } else {
        let mut min_x = f64::INFINITY;
        let mut max_x = f64::NEG_INFINITY;
        let mut min_y = f64::INFINITY;
        let mut max_y = f64::NEG_INFINITY;
        for point in footprint {
            min_x = min_x.min(point.x);
            max_x = max_x.max(point.x);
            min_y = min_y.min(point.y);
            max_y = max_y.max(point.y);
        }
        (
            (max_x - min_x) * meters_per_stud,
            (max_y - min_y) * meters_per_stud,
        )
    };
    let short_span_m = span_x.min(span_y);
    let long_span_m = span_x.max(span_y);
    let aspect_ratio = if short_span_m > f64::EPSILON {
        long_span_m / short_span_m
    } else {
        f64::INFINITY
    };

    match usage {
        "house" | "detached" | "terrace" | "shed" | "barn" | "garage" => "gabled".to_string(),
        "residential" => {
            if simple_outline && levels <= 2 && area_m2 <= 220.0 && aspect_ratio <= 4.5 {
                "gabled".to_string()
            } else {
                "flat".to_string()
            }
        }
        "apartments" | "dormitory" => "flat".to_string(),
        "school" => "flat".to_string(),
        "church" | "cathedral" | "religious" | "temple" => {
            if simple_outline && levels <= 1 && area_m2 <= 60.0 && aspect_ratio <= 4.5 {
                "gabled".to_string()
            } else {
                "flat".to_string()
            }
        }
        "mosque" => "dome".to_string(),
        "warehouse" | "industrial" | "factory" => {
            if simple_outline && levels <= 2 && aspect_ratio <= 6.0 {
                "gabled".to_string()
            } else {
                "flat".to_string()
            }
        }
        _ => "flat".to_string(),
    }
}

/// Emit a polygon area feature (building, landuse, water, leisure, amenity, natural).
/// Footprint points must already be >= 3; caller is responsible for that invariant.
fn emit_area_way(
    id: &str,
    tags: &HashMap<String, String>,
    fp: &[Vec2],
    holes: Vec<Footprint>,
    meters_per_stud: f64,
    features: &mut Vec<Feature>,
) {
    if tags.contains_key("building") || tags.contains_key("building:part") {
        let levels = tags
            .get("building:levels")
            .and_then(|l| l.parse::<u32>().ok());
        let roof_levels = tags.get("roof:levels").and_then(|l| l.parse::<u32>().ok());
        let min_height: Option<f64> = tags.get("min_height").and_then(|h| h.parse().ok());
        let raw_usage = infer_building_usage(tags);
        let height: f64 = tags
            .get("height")
            .and_then(|h| h.parse::<f64>().ok())
            .unwrap_or_else(|| (levels.unwrap_or(1) as f64 * 3.5) + 2.0);
        let usage = match raw_usage.as_deref() {
            Some("building") | Some("yes") | None => {
                refine_generic_building_usage(fp, height, levels, meters_per_stud).or(raw_usage)
            }
            _ => raw_usage,
        };
        let base_y: f64 = min_height
            .or_else(|| {
                tags.get("building:min_level")
                    .and_then(|l| l.parse::<f64>().ok())
                    .map(|l| l * 3.5)
            })
            .unwrap_or(0.0);
        let visible_height = (height - base_y).max(0.0);
        features.push(Feature::Building(BuildingFeature {
            id: id.to_string(),
            footprint: Footprint::new(fp.to_vec()),
            holes,
            indices: None,
            base_y,
            height: visible_height,
            height_m: tags.get("height").and_then(|h| h.parse::<f64>().ok()),
            levels,
            roof_levels,
            min_height: Some(base_y),
            roof: infer_roof_shape(tags, usage.as_deref(), fp, meters_per_stud),
            usage,
            colour: tags
                .get("building:colour")
                .or_else(|| tags.get("building:color"))
                .map(|s| s.trim().to_lowercase()),
            material_tag: tags
                .get("building:material")
                .or_else(|| tags.get("material"))
                .map(|s| s.to_lowercase()),
            roof_colour: tags
                .get("roof:colour")
                .or_else(|| tags.get("roof:color"))
                .map(|s| s.to_lowercase()),
            roof_material: tags.get("roof:material").map(|s| s.to_lowercase()),
            roof_height: tags.get("roof:height").and_then(|h| h.parse::<f64>().ok()),
            name: tags.get("name").cloned(),
        }));
    } else if tags.get("natural") == Some(&"water".to_string()) {
        features.push(Feature::Water(WaterFeature::Polygon(WaterPolygonFeature {
            id: id.to_string(),
            kind: "water".to_string(),
            footprint: Footprint::new(fp.to_vec()),
            holes,
            indices: None,
            intermittent: tags.get("intermittent").map(|s| s == "yes"),
        })));
    } else if let Some(landuse) = tags.get("landuse") {
        features.push(Feature::Landuse(LanduseFeature {
            id: id.to_string(),
            kind: landuse.clone(),
            footprint: Footprint::new(fp.to_vec()),
        }));
    } else if let Some(leisure) = tags.get("leisure") {
        if leisure == "swimming_pool" {
            features.push(Feature::Water(WaterFeature::Polygon(WaterPolygonFeature {
                id: id.to_string(),
                kind: "swimming_pool".to_string(),
                footprint: Footprint::new(fp.to_vec()),
                holes,
                indices: None,
                intermittent: None,
            })));
            return;
        }

        let kind = match leisure.as_str() {
            "park" | "garden" | "playground" => "park",
            "pitch" | "sports_centre" | "stadium" => "pitch",
            "golf_course" => "golf_course",
            "nature_reserve" | "dog_park" => "park",
            _ => "park",
        };
        features.push(Feature::Landuse(LanduseFeature {
            id: id.to_string(),
            kind: kind.to_string(),
            footprint: Footprint::new(fp.to_vec()),
        }));
    } else if let Some(amenity) = tags.get("amenity") {
        if amenity == "fountain" {
            features.push(Feature::Water(WaterFeature::Polygon(WaterPolygonFeature {
                id: id.to_string(),
                kind: "fountain".to_string(),
                footprint: Footprint::new(fp.to_vec()),
                holes,
                indices: None,
                intermittent: None,
            })));
            return;
        }

        let kind = match amenity.as_str() {
            "parking" | "parking_space" => "parking",
            "school" | "university" | "college" => "school",
            "hospital" | "clinic" => "hospital",
            "place_of_worship" => "religious",
            "marketplace" => "retail",
            _ => return,
        };
        features.push(Feature::Landuse(LanduseFeature {
            id: id.to_string(),
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
fn emit_linear_way(
    id: u64,
    tags: &HashMap<String, String>,
    points: Vec<Vec3>,
    meters_per_stud: f64,
    features: &mut Vec<Feature>,
) {
    fn canonical_sidewalk_value(raw: &str) -> Option<String> {
        let normalized = raw.trim().to_ascii_lowercase();
        match normalized.as_str() {
            "" => None,
            "none" | "no" | "false" => Some("no".to_string()),
            "both" | "left" | "right" | "separate" => Some(normalized),
            "yes" => Some("both".to_string()),
            _ => Some(normalized),
        }
    }

    // Steps must be detected before the general highway branch so they get
    // the correct fixed width and no sidewalk, rather than the generic road path.
    if tags.get("highway").map(|s| s.as_str()) == Some("steps") {
        features.push(Feature::Road(RoadFeature {
            id: format!("osm_{}", id),
            kind: "steps".to_string(),
            subkind: None,
            lanes: None,
            width_studs: 6.0,
            has_sidewalk: false,
            surface: tags.get("surface").cloned(),
            elevated: None,
            tunnel: None,
            sidewalk: None,
            points,
            maxspeed: None,
            lit: tags.get("lit").map(|s| s == "yes"),
            oneway: None,
            layer: tags.get("layer").and_then(|s| s.parse().ok()),
        }));
        return;
    }
    if let Some(highway) = tags.get("highway") {
        let subkind = match highway.as_str() {
            "footway" => tags.get("footway").cloned(),
            "cycleway" => tags.get("cycleway").cloned(),
            "path" => tags.get("path").cloned(),
            "pedestrian" => tags.get("crossing").cloned(),
            _ => None,
        };
        let lanes = tags.get("lanes").and_then(|l| l.parse().ok());
        let sidewalk = tags
            .get("sidewalk")
            .and_then(|value| canonical_sidewalk_value(value));
        let has_sidewalk = matches!(sidewalk.as_deref(), Some("both" | "left" | "right"));
        let width_studs = tags
            .get("width")
            .and_then(|w| parse_osm_width_to_studs(w, meters_per_stud))
            .unwrap_or_else(|| road_width_from_kind(highway));
        let elevated = if tags.get("bridge").map(|v| v != "no").unwrap_or(false) {
            Some(true)
        } else {
            None
        };
        let tunnel = if tags.get("tunnel").map(|v| v != "no").unwrap_or(false) {
            Some(true)
        } else {
            None
        };
        features.push(Feature::Road(RoadFeature {
            id: format!("osm_{}", id),
            kind: highway.clone(),
            subkind,
            lanes,
            width_studs,
            has_sidewalk,
            surface: tags.get("surface").cloned(),
            elevated,
            tunnel,
            sidewalk,
            points,
            maxspeed: tags
                .get("maxspeed")
                .and_then(|s| s.replace("mph", "").trim().parse().ok()),
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
    } else if let Some(barrier) = tags.get("barrier") {
        features.push(Feature::Barrier(BarrierFeature {
            id: format!("osm_{}", id),
            kind: barrier.clone(),
            points,
        }));
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

fn ring_centroid(points: &[Vec2]) -> Vec2 {
    if points.is_empty() {
        return Vec2::new(0.0, 0.0);
    }
    let mut sum_x = 0.0;
    let mut sum_y = 0.0;
    for point in points {
        sum_x += point.x;
        sum_y += point.y;
    }
    Vec2::new(sum_x / points.len() as f64, sum_y / points.len() as f64)
}

fn point_in_ring(point: Vec2, ring: &[Vec2]) -> bool {
    if ring.len() < 3 {
        return false;
    }
    let mut inside = false;
    let mut prev = *ring.last().unwrap();
    for current in ring {
        let intersects = ((current.y > point.y) != (prev.y > point.y))
            && (point.x
                < (prev.x - current.x) * (point.y - current.y)
                    / ((prev.y - current.y) + f64::EPSILON)
                    + current.x);
        if intersects {
            inside = !inside;
        }
        prev = *current;
    }
    inside
}

fn building_hole_belongs_to_outer(outer: &Footprint, hole: &Footprint) -> bool {
    let centroid = ring_centroid(&hole.points);
    point_in_ring(centroid, &outer.points)
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
                holes: vec![],
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

    #[test]
    fn triangulate_stage_skips_hole_bearing_buildings() {
        let bbox = BoundingBox::new(30.0, -98.0, 31.0, -97.0);
        let mut ctx = PipelineContext {
            bbox,
            features: vec![Feature::Building(BuildingFeature {
                id: "courtyard".to_string(),
                footprint: Footprint::new(vec![
                    Vec2::new(0.0, 0.0),
                    Vec2::new(10.0, 0.0),
                    Vec2::new(10.0, 10.0),
                    Vec2::new(0.0, 10.0),
                ]),
                holes: vec![Footprint::new(vec![
                    Vec2::new(3.0, 3.0),
                    Vec2::new(7.0, 3.0),
                    Vec2::new(7.0, 7.0),
                    Vec2::new(3.0, 7.0),
                ])],
                indices: None,
                base_y: 0.0,
                height: 12.0,
                height_m: Some(12.0),
                levels: Some(3),
                roof_levels: None,
                min_height: None,
                usage: Some("government".to_string()),
                roof: "flat".to_string(),
                colour: None,
                material_tag: None,
                roof_colour: None,
                roof_material: None,
                roof_height: None,
                name: Some("Courtyard".to_string()),
            })],
            notes: vec![],
            stats: PipelineStats::default(),
        };

        TriangulateStage.run(&mut ctx).expect("triangulate stage");

        let building = ctx
            .features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");
        assert_eq!(building.indices, None);
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

    #[test]
    fn overpass_building_multipolygon_emits_all_outer_rings() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.7498},
                {"type": "node", "id": 3, "lat": 30.2698, "lon": -97.7498},
                {"type": "node", "id": 4, "lat": 30.2698, "lon": -97.7500},
                {"type": "node", "id": 5, "lat": 30.2700, "lon": -97.7495},
                {"type": "node", "id": 6, "lat": 30.2700, "lon": -97.7493},
                {"type": "node", "id": 7, "lat": 30.2698, "lon": -97.7493},
                {"type": "node", "id": 8, "lat": 30.2698, "lon": -97.7495},
                {"type": "way", "id": 101, "nodes": [1, 2, 3, 4, 1]},
                {"type": "way", "id": 102, "nodes": [5, 6, 7, 8, 5]},
                {
                    "type": "relation",
                    "id": 999,
                    "members": [
                        {"type": "way", "ref": 101, "role": "outer"},
                        {"type": "way", "ref": 102, "role": "outer"}
                    ],
                    "tags": {
                        "type": "multipolygon",
                        "building": "yes",
                        "name": "Twin Wings"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_building_multi_outer.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let buildings: Vec<&BuildingFeature> = features
            .iter()
            .filter_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .collect();

        assert_eq!(
            buildings.len(),
            2,
            "expected one building feature per outer ring"
        );
        assert_ne!(
            buildings[0].id, buildings[1].id,
            "expected multi-outer relation buildings to get unique ids"
        );
        for building in buildings {
            assert!(
                building.footprint.points.len() >= 4,
                "expected each emitted building ring to preserve its footprint"
            );
            assert_eq!(building.name.as_deref(), Some("Twin Wings"));
            assert!(
                building.holes.is_empty(),
                "multi-outer building relation should not invent holes when the source has none"
            );
        }
    }

    #[test]
    fn overpass_building_multipolygon_preserves_inner_rings() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.7496},
                {"type": "node", "id": 3, "lat": 30.2696, "lon": -97.7496},
                {"type": "node", "id": 4, "lat": 30.2696, "lon": -97.7500},
                {"type": "node", "id": 5, "lat": 30.2699, "lon": -97.7499},
                {"type": "node", "id": 6, "lat": 30.2699, "lon": -97.7497},
                {"type": "node", "id": 7, "lat": 30.2697, "lon": -97.7497},
                {"type": "node", "id": 8, "lat": 30.2697, "lon": -97.7499},
                {"type": "way", "id": 101, "nodes": [1, 2, 3, 4, 1]},
                {"type": "way", "id": 102, "nodes": [5, 6, 7, 8, 5]},
                {
                    "type": "relation",
                    "id": 1001,
                    "members": [
                        {"type": "way", "ref": 101, "role": "outer"},
                        {"type": "way", "ref": 102, "role": "inner"}
                    ],
                    "tags": {
                        "type": "multipolygon",
                        "building": "yes",
                        "name": "Courtyard Hall"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_building_inner_ring.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let buildings: Vec<&BuildingFeature> = features
            .iter()
            .filter_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .collect();

        assert_eq!(buildings.len(), 1, "expected one building feature");
        assert_eq!(buildings[0].name.as_deref(), Some("Courtyard Hall"));
        assert_eq!(
            buildings[0].holes.len(),
            1,
            "expected building multipolygon inner ring to survive as a building hole"
        );
        assert!(
            buildings[0].holes[0].points.len() >= 4,
            "expected inner ring footprint to retain its polygon points"
        );
    }

    #[test]
    fn overpass_building_relation_does_not_duplicate_tagged_member_way_buildings() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.7496},
                {"type": "node", "id": 3, "lat": 30.2696, "lon": -97.7496},
                {"type": "node", "id": 4, "lat": 30.2696, "lon": -97.7500},
                {
                    "type": "way",
                    "id": 101,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {"building": "yes"}
                },
                {
                    "type": "relation",
                    "id": 1002,
                    "members": [
                        {"type": "way", "ref": 101, "role": "outer"}
                    ],
                    "tags": {
                        "type": "multipolygon",
                        "building": "yes",
                        "name": "Single Source Of Truth Hall"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_building_relation_member_dedupe.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let buildings: Vec<&BuildingFeature> = features
            .iter()
            .filter_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .collect();

        assert_eq!(
            buildings.len(),
            1,
            "building geometry should come from the relation once, not from both the member way and the relation"
        );
        assert_eq!(
            buildings[0].name.as_deref(),
            Some("Single Source Of Truth Hall")
        );
    }

    #[test]
    fn overpass_single_outer_building_relation_preserves_relation_identity() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.7496},
                {"type": "node", "id": 3, "lat": 30.2696, "lon": -97.7496},
                {"type": "node", "id": 4, "lat": 30.2696, "lon": -97.7500},
                {"type": "way", "id": 101, "nodes": [1, 2, 3, 4, 1]},
                {
                    "type": "relation",
                    "id": 1002,
                    "members": [
                        {"type": "way", "ref": 101, "role": "outer"}
                    ],
                    "tags": {
                        "type": "multipolygon",
                        "building": "yes",
                        "name": "Identity Hall"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_relation_identity_preserved.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let building = features
            .iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.id, "osm_1002");
        assert_eq!(building.name.as_deref(), Some("Identity Hall"));
    }

    #[test]
    fn emit_area_way_uses_generic_material_tag_for_building_parts_when_specific_tag_is_missing() {
        let mut tags = HashMap::new();
        tags.insert("building:part".to_string(), "roof".to_string());
        tags.insert("material".to_string(), "glass".to_string());

        let mut features = Vec::new();
        emit_area_way(
            "osm_roof_part",
            &tags,
            &[
                Vec2::new(0.0, 0.0),
                Vec2::new(10.0, 0.0),
                Vec2::new(10.0, 10.0),
                Vec2::new(0.0, 10.0),
            ],
            vec![],
            1.0,
            &mut features,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building");

        assert_eq!(building.usage.as_deref(), Some("roof"));
        assert_eq!(building.material_tag.as_deref(), Some("glass"));
    }

    #[test]
    fn emit_area_way_uses_generic_material_tag_for_full_buildings_when_specific_tag_is_missing() {
        let mut tags = HashMap::new();
        tags.insert("building".to_string(), "yes".to_string());
        tags.insert("material".to_string(), "stone".to_string());

        let mut features = Vec::new();
        emit_area_way(
            "osm_full_building",
            &tags,
            &[
                Vec2::new(0.0, 0.0),
                Vec2::new(10.0, 0.0),
                Vec2::new(10.0, 10.0),
                Vec2::new(0.0, 10.0),
            ],
            vec![],
            1.0,
            &mut features,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building");

        assert_eq!(building.material_tag.as_deref(), Some("stone"));
    }

    #[test]
    fn emit_area_way_clamps_visible_height_when_min_height_exceeds_total_height() {
        let mut tags = HashMap::new();
        tags.insert("building".to_string(), "yes".to_string());
        tags.insert("height".to_string(), "5".to_string());
        tags.insert("min_height".to_string(), "12".to_string());

        let mut features = Vec::new();
        emit_area_way(
            "osm_clamped_building",
            &tags,
            &[
                Vec2::new(0.0, 0.0),
                Vec2::new(10.0, 0.0),
                Vec2::new(10.0, 10.0),
                Vec2::new(0.0, 10.0),
            ],
            vec![],
            1.0,
            &mut features,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building");

        assert_eq!(building.base_y, 12.0);
        assert_eq!(building.height, 0.0);
        assert_eq!(building.min_height, Some(12.0));
    }

    #[test]
    fn overpass_non_building_relation_does_not_suppress_inner_tagged_building_way() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.7496},
                {"type": "node", "id": 3, "lat": 30.2696, "lon": -97.7496},
                {"type": "node", "id": 4, "lat": 30.2696, "lon": -97.7500},
                {"type": "node", "id": 11, "lat": 30.2702, "lon": -97.7502},
                {"type": "node", "id": 12, "lat": 30.2702, "lon": -97.7494},
                {"type": "node", "id": 13, "lat": 30.2694, "lon": -97.7494},
                {"type": "node", "id": 14, "lat": 30.2694, "lon": -97.7502},
                {
                    "type": "way",
                    "id": 25758443,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {
                        "building": "government",
                        "office": "government",
                        "name": "Texas State Capitol"
                    }
                },
                {
                    "type": "way",
                    "id": 5000,
                    "nodes": [11, 12, 13, 14, 11],
                    "tags": {
                        "leisure": "park",
                        "name": "Capitol Square"
                    }
                },
                {
                    "type": "relation",
                    "id": 13105661,
                    "members": [
                        {"type": "way", "ref": 5000, "role": "outer"},
                        {"type": "way", "ref": 25758443, "role": "inner"}
                    ],
                    "tags": {
                        "type": "multipolygon",
                        "leisure": "park",
                        "name": "Capitol Square"
                    }
                }
            ]
        });

        let tmp_path =
            std::env::temp_dir().join("arbx_test_non_building_relation_keeps_inner_building.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let capitol = features
            .iter()
            .find_map(|feature| match feature {
                Feature::Building(building) if building.id == "osm_25758443" => Some(building),
                _ => None,
            })
            .expect("expected tagged inner building way to survive non-building relation");

        assert_eq!(capitol.name.as_deref(), Some("Texas State Capitol"));
        assert_eq!(capitol.usage.as_deref(), Some("government"));
    }

    #[test]
    fn overpass_building_yes_infers_semantic_usage_from_tags() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.7498},
                {"type": "node", "id": 3, "lat": 30.2698, "lon": -97.7498},
                {"type": "node", "id": 4, "lat": 30.2698, "lon": -97.7500},
                {"type": "node", "id": 5, "lat": 30.2700, "lon": -97.7495},
                {"type": "node", "id": 6, "lat": 30.2700, "lon": -97.7493},
                {"type": "node", "id": 7, "lat": 30.2698, "lon": -97.7493},
                {"type": "node", "id": 8, "lat": 30.2698, "lon": -97.7495},
                {
                    "type": "way",
                    "id": 101,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {
                        "building": "yes",
                        "amenity": "restaurant"
                    }
                },
                {
                    "type": "way",
                    "id": 102,
                    "nodes": [5, 6, 7, 8, 5],
                    "tags": {
                        "building": "yes",
                        "shop": "clothes"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_building_usage_inference.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let buildings: Vec<&BuildingFeature> = features
            .iter()
            .filter_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .collect();

        assert_eq!(buildings.len(), 2);
        assert_eq!(buildings[0].usage.as_deref(), Some("restaurant"));
        assert_eq!(buildings[1].usage.as_deref(), Some("retail"));
    }

    #[test]
    fn overpass_small_residential_buildings_infer_non_flat_roofs_when_missing_tags() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.7499},
                {"type": "node", "id": 3, "lat": 30.2699, "lon": -97.7499},
                {"type": "node", "id": 4, "lat": 30.2699, "lon": -97.7500},
                {
                    "type": "way",
                    "id": 103,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {
                        "building": "house"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_building_roof_inference.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let building = features
            .iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.usage.as_deref(), Some("house"));
        assert_ne!(
            building.roof, "flat",
            "small residential footprints without explicit roof tags should not collapse to flat roofs"
        );
    }

    #[test]
    fn overpass_generic_small_lowrise_buildings_refine_to_residential_shells() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2700, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2700, "lon": -97.74995},
                {"type": "node", "id": 3, "lat": 30.26995, "lon": -97.74995},
                {"type": "node", "id": 4, "lat": 30.26995, "lon": -97.7500},
                {
                    "type": "way",
                    "id": 104,
                    "nodes": [1, 2, 3, 4, 1],
                    "tags": {
                        "building": "yes"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_generic_small_building.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let building = features
            .iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.usage.as_deref(), Some("residential"));
        assert_ne!(building.roof, "flat");
    }

    fn projected_bbox_extents(bbox: BoundingBox, meters_per_stud: f64) -> (f64, f64, f64, f64) {
        let center = bbox.center();
        let corners = [
            LatLon::new(bbox.min.lat, bbox.min.lon),
            LatLon::new(bbox.min.lat, bbox.max.lon),
            LatLon::new(bbox.max.lat, bbox.min.lon),
            LatLon::new(bbox.max.lat, bbox.max.lon),
        ];
        let mut min_x = f64::INFINITY;
        let mut max_x = f64::NEG_INFINITY;
        let mut min_z = f64::INFINITY;
        let mut max_z = f64::NEG_INFINITY;
        for corner in corners {
            let projected = Mercator::project(corner, center, meters_per_stud);
            min_x = min_x.min(projected.x);
            max_x = max_x.max(projected.x);
            min_z = min_z.min(projected.z);
            max_z = max_z.max(projected.z);
        }
        (min_x, max_x, min_z, max_z)
    }

    #[test]
    fn overpass_linear_features_clip_to_exact_bbox_for_final_geometry() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2350, "lon": -97.7400},
                {"type": "node", "id": 2, "lat": 30.3150, "lon": -97.7400},
                {
                    "type": "way",
                    "id": 501,
                    "nodes": [1, 2],
                    "tags": {"highway": "primary"}
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_exact_bbox_linear_clip.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let road = features
            .iter()
            .find_map(|feature| match feature {
                Feature::Road(road) => Some(road),
                _ => None,
            })
            .expect("expected clipped road feature");

        let (min_x, max_x, min_z, max_z) = projected_bbox_extents(bbox, 1.0);
        for point in &road.points {
            assert!(
                point.x >= min_x - 1e-6 && point.x <= max_x + 1e-6,
                "road x={} escaped bbox [{}, {}]",
                point.x,
                min_x,
                max_x
            );
            assert!(
                point.z >= min_z - 1e-6 && point.z <= max_z + 1e-6,
                "road z={} escaped bbox [{}, {}]",
                point.z,
                min_z,
                max_z
            );
        }
    }

    #[test]
    fn overpass_area_features_clip_to_exact_bbox_for_final_geometry() {
        use std::io::Write;

        let json = serde_json::json!({
            "elements": [
                {"type": "node", "id": 1, "lat": 30.2600, "lon": -97.7500},
                {"type": "node", "id": 2, "lat": 30.2600, "lon": -97.7000},
                {"type": "node", "id": 3, "lat": 30.2900, "lon": -97.7000},
                {"type": "node", "id": 4, "lat": 30.2900, "lon": -97.7500},
                {"type": "way", "id": 601, "nodes": [1, 2, 3, 4, 1]},
                {
                    "type": "relation",
                    "id": 602,
                    "members": [
                        {"type": "way", "ref": 601, "role": "outer"}
                    ],
                    "tags": {
                        "type": "multipolygon",
                        "landuse": "residential"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_exact_bbox_area_clip.json");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(json.to_string().as_bytes()).unwrap();

        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let adapter = OverpassAdapter {
            path: tmp_path.clone(),
            meters_per_stud: 1.0,
        };

        let features = adapter.load(bbox).expect("load should succeed");

        let _ = std::fs::remove_file(&tmp_path);

        let landuse = features
            .iter()
            .find_map(|feature| match feature {
                Feature::Landuse(landuse) => Some(landuse),
                _ => None,
            })
            .expect("expected clipped landuse feature");

        let (min_x, max_x, min_z, max_z) = projected_bbox_extents(bbox, 1.0);
        for point in &landuse.footprint.points {
            assert!(
                point.x >= min_x - 1e-6 && point.x <= max_x + 1e-6,
                "landuse x={} escaped bbox [{}, {}]",
                point.x,
                min_x,
                max_x
            );
            assert!(
                point.y >= min_z - 1e-6 && point.y <= max_z + 1e-6,
                "landuse z={} escaped bbox [{}, {}]",
                point.y,
                min_z,
                max_z
            );
        }
    }

    #[test]
    fn overture_gap_fill_skips_buildings_already_covered_by_osm() {
        let osm_building = Feature::Building(BuildingFeature {
            id: "osm_1".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(60.0, 0.0),
                Vec2::new(60.0, 40.0),
                Vec2::new(0.0, 40.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 30.0,
            height_m: Some(9.0),
            levels: Some(2),
            roof_levels: None,
            min_height: None,
            usage: Some("commercial".to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: Some("OSM Truth".to_string()),
        });

        let overture_duplicate = Feature::Building(BuildingFeature {
            id: "ov_dup".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(1.5, 1.0),
                Vec2::new(61.0, 1.0),
                Vec2::new(61.0, 40.5),
                Vec2::new(1.5, 40.5),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 28.0,
            height_m: Some(8.5),
            levels: Some(2),
            roof_levels: None,
            min_height: None,
            usage: Some("commercial".to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: Some("Overture Duplicate".to_string()),
        });

        let overture_gap_fill = Feature::Building(BuildingFeature {
            id: "ov_keep".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(120.0, 0.0),
                Vec2::new(150.0, 0.0),
                Vec2::new(150.0, 24.0),
                Vec2::new(120.0, 24.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 20.0,
            height_m: Some(6.0),
            levels: Some(1),
            roof_levels: None,
            min_height: None,
            usage: Some("residential".to_string()),
            roof: "hipped".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: Some("Gap Fill".to_string()),
        });

        let mut features = vec![osm_building];
        merge_overture_gap_fill(&mut features, vec![overture_duplicate, overture_gap_fill]);

        let building_ids: Vec<&str> = features
            .iter()
            .filter_map(|feature| match feature {
                Feature::Building(building) => Some(building.id.as_str()),
                _ => None,
            })
            .collect();

        assert_eq!(building_ids, vec!["osm_1", "ov_keep"]);
    }

    #[test]
    fn overture_gap_fill_keeps_named_parent_when_only_anonymous_parts_overlap() {
        let anonymous_part = Feature::Building(BuildingFeature {
            id: "osm_part_a".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(2.0, 1.0),
                Vec2::new(38.0, 1.0),
                Vec2::new(38.0, 19.0),
                Vec2::new(2.0, 19.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 20.0,
            height_m: Some(6.0),
            levels: Some(1),
            roof_levels: None,
            min_height: None,
            usage: Some("office".to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: None,
        });

        let overture_named_parent = Feature::Building(BuildingFeature {
            id: "ov_capitol_parent".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(40.0, 0.0),
                Vec2::new(40.0, 20.0),
                Vec2::new(0.0, 20.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 28.0,
            height_m: Some(8.5),
            levels: Some(2),
            roof_levels: None,
            min_height: None,
            usage: Some("government".to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: Some("Texas State Capitol".to_string()),
        });

        let mut features = vec![anonymous_part];
        merge_overture_gap_fill(&mut features, vec![overture_named_parent]);

        let building_ids: Vec<&str> = features
            .iter()
            .filter_map(|feature| match feature {
                Feature::Building(building) => Some(building.id.as_str()),
                _ => None,
            })
            .collect();

        assert!(
            building_ids.contains(&"ov_capitol_parent"),
            "named parent building should survive even when anonymous contained parts already exist"
        );
    }

    #[test]
    fn overture_buildings_clip_to_exact_bbox_for_final_geometry() {
        use std::io::Write;

        let geojson = serde_json::json!({
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[
                            [-97.7500, 30.2600],
                            [-97.7000, 30.2600],
                            [-97.7000, 30.2900],
                            [-97.7500, 30.2900],
                            [-97.7500, 30.2600]
                        ]]
                    },
                    "properties": {
                        "height": 12.0,
                        "class": "commercial"
                    }
                }
            ]
        });

        let tmp_path = std::env::temp_dir().join("arbx_test_exact_bbox_overture_clip.geojson");
        let mut f = std::fs::File::create(&tmp_path).unwrap();
        f.write_all(geojson.to_string().as_bytes()).unwrap();

        let bbox = BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let features =
            overture::load_overture_buildings(tmp_path.to_str().expect("path to str"), bbox, 1.0);

        let _ = std::fs::remove_file(&tmp_path);

        let building = features
            .iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected clipped overture building");

        let (min_x, max_x, min_z, max_z) = projected_bbox_extents(bbox, 1.0);
        for point in &building.footprint.points {
            assert!(
                point.x >= min_x - 1e-6 && point.x <= max_x + 1e-6,
                "overture building x={} escaped bbox [{}, {}]",
                point.x,
                min_x,
                max_x
            );
            assert!(
                point.y >= min_z - 1e-6 && point.y <= max_z + 1e-6,
                "overture building z={} escaped bbox [{}, {}]",
                point.y,
                min_z,
                max_z
            );
        }
    }

    #[test]
    fn emit_linear_way_preserves_footway_sidewalk_subkind() {
        let mut features = Vec::new();
        let tags = HashMap::from([
            ("highway".to_string(), "footway".to_string()),
            ("footway".to_string(), "sidewalk".to_string()),
            ("surface".to_string(), "paving_stones".to_string()),
        ]);
        emit_linear_way(
            42,
            &tags,
            vec![Vec3::new(0.0, 0.0, 0.0), Vec3::new(10.0, 0.0, 0.0)],
            0.3,
            &mut features,
        );

        let road = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Road(road) => Some(road),
                _ => None,
            })
            .expect("expected footway sidewalk road feature");

        assert_eq!(road.kind, "footway");
        assert_eq!(road.subkind.as_deref(), Some("sidewalk"));
        assert_eq!(road.surface.as_deref(), Some("paving_stones"));
        assert!(!road.has_sidewalk);
    }

    #[test]
    fn emit_linear_way_normalizes_sidewalk_no_and_separate() {
        let mut features = Vec::new();
        let tags_no = HashMap::from([
            ("highway".to_string(), "residential".to_string()),
            ("sidewalk".to_string(), "no".to_string()),
        ]);
        emit_linear_way(
            77,
            &tags_no,
            vec![Vec3::new(0.0, 0.0, 0.0), Vec3::new(10.0, 0.0, 0.0)],
            0.3,
            &mut features,
        );

        let tags_separate = HashMap::from([
            ("highway".to_string(), "primary".to_string()),
            ("sidewalk".to_string(), "separate".to_string()),
        ]);
        emit_linear_way(
            78,
            &tags_separate,
            vec![Vec3::new(0.0, 0.0, 0.0), Vec3::new(10.0, 0.0, 0.0)],
            0.3,
            &mut features,
        );

        let mut roads = features.into_iter().filter_map(|feature| match feature {
            Feature::Road(road) => Some(road),
            _ => None,
        });

        let road_no = roads.next().expect("expected road with sidewalk=no");
        assert_eq!(road_no.sidewalk.as_deref(), Some("no"));
        assert!(
            !road_no.has_sidewalk,
            "sidewalk=no must not imply attached sidewalks"
        );

        let road_separate = roads.next().expect("expected road with sidewalk=separate");
        assert_eq!(road_separate.sidewalk.as_deref(), Some("separate"));
        assert!(
            !road_separate.has_sidewalk,
            "sidewalk=separate must not imply attached sidewalks on the road ribbon"
        );
    }

    #[test]
    fn infer_building_usage_promotes_named_government_landmarks() {
        let governor_mansion = HashMap::from([
            ("building".to_string(), "yes".to_string()),
            ("name".to_string(), "Governor's Mansion".to_string()),
            ("heritage".to_string(), "2".to_string()),
        ]);
        assert_eq!(
            infer_building_usage(&governor_mansion).as_deref(),
            Some("government")
        );

        let capitol_extension = HashMap::from([
            ("building".to_string(), "yes".to_string()),
            ("name".to_string(), "Capitol Extention".to_string()),
            ("underground".to_string(), "yes".to_string()),
        ]);
        assert_eq!(
            infer_building_usage(&capitol_extension).as_deref(),
            Some("government")
        );

        let supreme_court = HashMap::from([
            ("building".to_string(), "yes".to_string()),
            (
                "name".to_string(),
                "Texas Supreme Court Building".to_string(),
            ),
        ]);
        assert_eq!(
            infer_building_usage(&supreme_court).as_deref(),
            Some("civic")
        );

        let state_office = HashMap::from([
            ("building".to_string(), "office".to_string()),
            ("office".to_string(), "government".to_string()),
            ("government".to_string(), "yes".to_string()),
            (
                "name".to_string(),
                "George H.W. Bush State Office Building".to_string(),
            ),
        ]);
        assert_eq!(
            infer_building_usage(&state_office).as_deref(),
            Some("government")
        );
    }

    #[test]
    fn emit_area_way_keeps_government_office_usage() {
        let tags = HashMap::from([
            ("building".to_string(), "office".to_string()),
            ("office".to_string(), "government".to_string()),
            ("government".to_string(), "yes".to_string()),
            (
                "name".to_string(),
                "George H.W. Bush State Office Building".to_string(),
            ),
            ("building:levels".to_string(), "14".to_string()),
            ("height".to_string(), "51".to_string()),
        ]);
        let footprint = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(20.0, 0.0),
            Vec2::new(20.0, 10.0),
            Vec2::new(0.0, 10.0),
        ];
        let mut features = Vec::new();

        emit_area_way(
            "osm_test_government_office",
            &tags,
            &footprint,
            Vec::new(),
            1.0,
            &mut features,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected emitted building feature");
        assert_eq!(building.usage.as_deref(), Some("government"));
    }

    #[test]
    fn infer_building_usage_prefers_specific_amenity_over_generic_shop_yes() {
        let studio_tags = HashMap::from([
            ("building:part".to_string(), "yes".to_string()),
            ("amenity".to_string(), "studio".to_string()),
            ("shop".to_string(), "yes".to_string()),
            (
                "name".to_string(),
                "Downtown Austin Space Activation".to_string(),
            ),
        ]);
        assert_eq!(infer_building_usage(&studio_tags).as_deref(), Some("civic"));

        let restaurant_tags = HashMap::from([
            ("building".to_string(), "yes".to_string()),
            ("amenity".to_string(), "restaurant".to_string()),
            ("shop".to_string(), "yes".to_string()),
            ("name".to_string(), "Corner Bistro".to_string()),
        ]);
        assert_eq!(
            infer_building_usage(&restaurant_tags).as_deref(),
            Some("restaurant")
        );
    }

    #[test]
    fn emit_linear_way_converts_explicit_width_meters_to_studs() {
        let mut features = Vec::new();
        let tags = HashMap::from([
            ("highway".to_string(), "footway".to_string()),
            ("width".to_string(), "3.6".to_string()),
        ]);

        emit_linear_way(
            99,
            &tags,
            vec![Vec3::new(0.0, 0.0, 0.0), Vec3::new(12.0, 0.0, 0.0)],
            0.3,
            &mut features,
        );

        let road = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Road(road) => Some(road),
                _ => None,
            })
            .expect("expected explicit-width road feature");

        assert!(
            (road.width_studs - 12.0).abs() < 1e-6,
            "expected 3.6m width to convert to 12 studs at 0.3 m/stud, got {}",
            road.width_studs
        );
    }

    #[test]
    fn infer_roof_shape_avoids_blanket_hipped_defaults_for_generic_residential() {
        let tags = HashMap::new();
        let small_house_fp = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(12.0, 0.0),
            Vec2::new(12.0, 10.0),
            Vec2::new(0.0, 10.0),
        ];
        let large_residential_fp = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(36.0, 0.0),
            Vec2::new(36.0, 24.0),
            Vec2::new(0.0, 24.0),
        ];

        let small_roof = infer_roof_shape(&tags, Some("residential"), &small_house_fp, 0.3);
        let large_roof = infer_roof_shape(&tags, Some("apartments"), &large_residential_fp, 0.3);

        assert_eq!(small_roof, "gabled");
        assert_eq!(large_roof, "flat");
    }

    #[test]
    fn infer_roof_shape_keeps_complex_generic_residential_simple() {
        let tags = HashMap::new();
        let complex_lowrise_fp = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(18.0, 0.0),
            Vec2::new(18.0, 6.0),
            Vec2::new(12.0, 6.0),
            Vec2::new(12.0, 14.0),
            Vec2::new(0.0, 14.0),
        ];

        let roof = infer_roof_shape(&tags, Some("residential"), &complex_lowrise_fp, 0.3);

        assert_eq!(roof, "flat");
    }

    #[test]
    fn infer_roof_shape_keeps_large_school_roofs_flat_by_default() {
        let tags = HashMap::new();
        let school_fp = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(48.0, 0.0),
            Vec2::new(48.0, 22.0),
            Vec2::new(0.0, 22.0),
        ];

        let roof = infer_roof_shape(&tags, Some("school"), &school_fp, 0.3);

        assert_eq!(roof, "flat");
    }

    #[test]
    fn infer_roof_shape_keeps_large_religious_roofs_flat_without_explicit_tags() {
        let tags = HashMap::new();
        let religious_fp = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(40.0, 0.0),
            Vec2::new(40.0, 26.0),
            Vec2::new(0.0, 26.0),
        ];

        let roof = infer_roof_shape(&tags, Some("religious"), &religious_fp, 0.3);

        assert_eq!(roof, "flat");
    }

    #[test]
    fn infer_roof_shape_preserves_small_simple_religious_gables() {
        let tags = HashMap::new();
        let chapel_fp = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(12.0, 0.0),
            Vec2::new(12.0, 8.0),
            Vec2::new(0.0, 8.0),
        ];

        let roof = infer_roof_shape(&tags, Some("church"), &chapel_fp, 0.3);

        assert_eq!(roof, "gabled");
    }

    #[test]
    fn emit_area_way_preserves_swimming_pool_as_water_polygon() {
        let mut features = Vec::new();
        let tags = HashMap::from([("leisure".to_string(), "swimming_pool".to_string())]);
        let footprint = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(12.0, 0.0),
            Vec2::new(12.0, 8.0),
            Vec2::new(0.0, 8.0),
        ];

        emit_area_way(
            "pool_way",
            &tags,
            &footprint,
            Vec::new(),
            0.3,
            &mut features,
        );

        assert_eq!(features.len(), 1, "expected exactly one emitted feature");
        match &features[0] {
            Feature::Water(WaterFeature::Polygon(pool)) => {
                assert_eq!(pool.id, "pool_way");
                assert_eq!(pool.kind, "swimming_pool");
                assert_eq!(pool.footprint.points.len(), 4);
            }
            other => panic!("expected swimming pool water polygon, got {:?}", other),
        }
    }

    #[test]
    fn emit_area_way_preserves_fountain_as_water_polygon() {
        let mut features = Vec::new();
        let tags = HashMap::from([("amenity".to_string(), "fountain".to_string())]);
        let footprint = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(6.0, 0.0),
            Vec2::new(6.0, 6.0),
            Vec2::new(0.0, 6.0),
        ];

        emit_area_way(
            "fountain_way",
            &tags,
            &footprint,
            Vec::new(),
            0.3,
            &mut features,
        );

        assert_eq!(features.len(), 1, "expected exactly one emitted feature");
        match &features[0] {
            Feature::Water(WaterFeature::Polygon(water)) => {
                assert_eq!(water.id, "fountain_way");
                assert_eq!(water.kind, "fountain");
                assert_eq!(water.footprint.points.len(), 4);
            }
            other => panic!("expected fountain water polygon, got {:?}", other),
        }
    }

    #[test]
    fn emit_area_way_keeps_natural_water_as_canonical_water_kind() {
        let mut features = Vec::new();
        let tags = HashMap::from([("natural".to_string(), "water".to_string())]);
        let footprint = vec![
            Vec2::new(0.0, 0.0),
            Vec2::new(20.0, 0.0),
            Vec2::new(20.0, 10.0),
            Vec2::new(0.0, 10.0),
        ];

        emit_area_way(
            "water_way",
            &tags,
            &footprint,
            Vec::new(),
            0.3,
            &mut features,
        );

        assert_eq!(features.len(), 1, "expected exactly one emitted feature");
        match &features[0] {
            Feature::Water(WaterFeature::Polygon(water)) => {
                assert_eq!(water.id, "water_way");
                assert_eq!(water.kind, "water");
                assert_eq!(water.footprint.points.len(), 4);
            }
            other => panic!("expected natural water polygon, got {:?}", other),
        }
    }

    struct CoordinateFingerprintElevation;

    impl ElevationProvider for CoordinateFingerprintElevation {
        fn sample_height_at(&self, latlon: LatLon) -> f32 {
            ((latlon.lat * 10_000.0) + (latlon.lon * 10_000.0)) as f32
        }
    }

    #[test]
    fn elevation_enrichment_uses_exact_mercator_inverse_for_building_base_y() {
        let bbox = BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let center = bbox.center();
        let meters_per_stud = 0.3;
        let source_ll = LatLon::new(30.305, -97.715);
        let projected = Mercator::project(source_ll, center, meters_per_stud);
        let mut ctx = PipelineContext::new(
            bbox,
            vec![Feature::Building(BuildingFeature {
                id: "mercator_inverse_truth".to_string(),
                footprint: Footprint::new(vec![
                    Vec2::new(projected.x, projected.z),
                    Vec2::new(projected.x + 20.0, projected.z),
                    Vec2::new(projected.x + 20.0, projected.z + 20.0),
                    Vec2::new(projected.x, projected.z + 20.0),
                ]),
                holes: vec![],
                indices: None,
                base_y: 0.0,
                height: 12.0,
                height_m: Some(12.0),
                levels: Some(3),
                roof_levels: None,
                min_height: None,
                usage: Some("residential".to_string()),
                roof: "flat".to_string(),
                colour: None,
                material_tag: None,
                roof_colour: None,
                roof_material: None,
                roof_height: None,
                name: None,
            })],
        );

        let enrichment = ElevationEnrichmentStage {
            elevation: &CoordinateFingerprintElevation,
            meters_per_stud,
            bbox_center: center,
        };
        enrichment.run(&mut ctx).expect("enrichment should succeed");

        let enriched = match &ctx.features[0] {
            Feature::Building(building) => building,
            _ => panic!("expected building"),
        };

        let centroid_x = projected.x + 10.0;
        let centroid_z = projected.z + 10.0;
        let expected_ll = Mercator::unproject(
            Vec3::new(centroid_x, 0.0, centroid_z),
            center,
            meters_per_stud,
        );
        let expected_y =
            CoordinateFingerprintElevation.sample_height_at(expected_ll) as f64 / meters_per_stud;

        assert!(
            (enriched.base_y - expected_y).abs() < 1e-6,
            "expected exact Mercator inverse DEM sample {}, got {}",
            expected_y,
            enriched.base_y
        );
    }
}
