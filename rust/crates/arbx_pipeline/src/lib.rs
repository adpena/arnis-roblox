use arbx_geo::{BoundingBox, ElevationProvider, Footprint, LatLon, Mercator, PerlinElevationProvider, Vec2, Vec3};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoadFeature {
    pub id: String,
    pub kind: String,
    pub lanes: Option<u32>,
    pub width_studs: f32,
    pub points: Vec<Vec3>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RailFeature {
    pub id: String,
    pub kind: String,
    pub lanes: Option<u32>,
    pub width_studs: f32,
    pub points: Vec<Vec3>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BuildingFeature {
    pub id: String,
    pub footprint: Footprint,
    pub indices: Option<Vec<usize>>,
    pub base_y: f32,
    pub height: f32,
    pub levels: Option<u32>,
    pub roof_levels: Option<u32>,
    pub roof: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WaterRibbonFeature {
    pub id: String,
    pub kind: String,
    pub width_studs: f32,
    pub points: Vec<Vec3>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WaterPolygonFeature {
    pub id: String,
    pub kind: String,
    pub footprint: Footprint,
    pub indices: Option<Vec<usize>>,
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
    pub yaw_degrees: f32,
    pub scale: f32,
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
            p.y = elevation.sample_height_at(LatLon::new(lat, lon));
            p
        };

        // Add a long road that spans multiple chunks, following terrain
        features.push(Feature::Road(RoadFeature {
            id: "congress_ave".to_string(),
            kind: "primary".to_string(),
            lanes: Some(4),
            width_studs: 40.0,
            points: vec![
                project_with_y(center.lat - 0.005, center.lon),
                project_with_y(center.lat, center.lon),
                project_with_y(center.lat + 0.005, center.lon),
            ],
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
            base_y: elevation.sample_height_at(capitol_ll),
            height: 50.0,
            levels: Some(3),
            roof_levels: Some(1),
            roof: "dome".to_string(),
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
        
        let features: Vec<Feature> = serde_json::from_str(&content)
            .map_err(|e| PipelineError::Serialization(format!("failed to deserialize features: {}", e)))?;
        
        Ok(features)
    }
}

/// A simple adapter for Overpass JSON data.
pub struct OverpassAdapter {
    pub path: PathBuf,
}

#[derive(Deserialize)]
struct OverpassElement {
    #[serde(rename = "type")]
    kind: String,
    id: u64,
    lat: Option<f64>,
    lon: Option<f64>,
    nodes: Option<Vec<u64>>,
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
        
        let data: OverpassResponse = serde_json::from_str(&content)
            .map_err(|e| PipelineError::Serialization(format!("failed to parse overpass json: {}", e)))?;

        let mut nodes = HashMap::new();
        for el in &data.elements {
            if el.kind == "node" {
                if let (Some(lat), Some(lon)) = (el.lat, el.lon) {
                    nodes.insert(el.id, arbx_geo::LatLon::new(lat, lon));
                }
            }
        }

        let center = bbox.center();
        let mut features = Vec::new();

        for el in &data.elements {
            if el.kind == "way" {
                let Some(tags) = &el.tags else { continue };
                let Some(way_nodes) = &el.nodes else { continue };

                let points: Vec<Vec3> = way_nodes.iter()
                    .filter_map(|id| nodes.get(id))
                    .map(|&ll| Mercator::project(ll, center, 1.0))
                    .collect();

                if points.len() < 2 { continue; }

                if tags.contains_key("building") {
                    let levels = tags.get("building:levels").and_then(|l| l.parse().ok());
                    let roof_levels = tags.get("roof:levels").and_then(|l| l.parse().ok());
                    
                    let height: f32 = tags.get("height")
                        .and_then(|h| h.parse().ok())
                        .unwrap_or_else(|| {
                            // Est height from levels
                            let lvl = levels.unwrap_or(1);
                            (lvl as f32 * 3.5) + 2.0
                        });
                    
                    let footprint_points: Vec<Vec2> = points.iter()
                        .map(|p| Vec2::new(p.x, p.z))
                        .collect();

                    features.push(Feature::Building(BuildingFeature {
                        id: format!("osm_{}", el.id),
                        footprint: Footprint::new(footprint_points),
                        indices: None,
                        base_y: 0.0,
                        height,
                        levels,
                        roof_levels,
                        roof: tags.get("roof:shape").cloned().unwrap_or_else(|| "flat".to_string()),
                    }));
                } else if let Some(highway) = tags.get("highway") {
                    let lanes = tags.get("lanes").and_then(|l| l.parse().ok());
                    features.push(Feature::Road(RoadFeature {
                        id: format!("osm_{}", el.id),
                        kind: highway.clone(),
                        lanes,
                        width_studs: 12.0, // default width
                        points,
                    }));
                } else if let Some(railway) = tags.get("railway") {
                    let tracks = tracks_from_tags(tags);
                    features.push(Feature::Rail(RailFeature {
                        id: format!("osm_{}", el.id),
                        kind: railway.clone(),
                        lanes: tracks,
                        width_studs: 4.0, // default rail width
                        points,
                    }));
                } else if let Some(waterway) = tags.get("waterway") {
                    features.push(Feature::Water(WaterFeature::Ribbon(WaterRibbonFeature {
                        id: format!("osm_{}", el.id),
                        kind: waterway.clone(),
                        width_studs: 8.0,
                        points,
                    })));
                } else if tags.get("natural") == Some(&"water".to_string()) {
                    let footprint_points: Vec<Vec2> = points.iter()
                        .map(|p| Vec2::new(p.x, p.z))
                        .collect();
                    features.push(Feature::Water(WaterFeature::Polygon(WaterPolygonFeature {
                        id: format!("osm_{}", el.id),
                        kind: "lake".to_string(),
                        footprint: Footprint::new(footprint_points),
                        indices: None,
                    })));
                } else if let Some(landuse) = tags.get("landuse") {
                    let footprint_points: Vec<Vec2> = points.iter()
                        .map(|p| Vec2::new(p.x, p.z))
                        .collect();
                    features.push(Feature::Landuse(LanduseFeature {
                        id: format!("osm_{}", el.id),
                        kind: landuse.clone(),
                        footprint: Footprint::new(footprint_points),
                    }));
                } else if let Some(natural) = tags.get("natural") {
                    let footprint_points: Vec<Vec2> = points.iter()
                        .map(|p| Vec2::new(p.x, p.z))
                        .collect();
                    features.push(Feature::Landuse(LanduseFeature {
                        id: format!("osm_{}", el.id),
                        kind: natural.clone(),
                        footprint: Footprint::new(footprint_points),
                    }));
                }
            }
        }

        Ok(features)
    }
}

fn tracks_from_tags(tags: &HashMap<String, String>) -> Option<u32> {
    tags.get("railway:tracks").and_then(|l| l.parse().ok())
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
                levels: None,
                roof_levels: None,
                roof: "flat".to_string(),
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
}
