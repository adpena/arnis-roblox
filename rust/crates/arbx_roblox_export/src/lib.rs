pub mod chunker;
pub mod manifest;
pub mod materials;

use arbx_geo::{BoundingBox, ChunkId, ElevationProvider, LatLon, PerlinElevationProvider, Vec3};
use arbx_pipeline::{Feature, WaterFeature as PipelineWaterFeature};

use crate::chunker::Chunker;
use crate::materials::StyleMapper;
pub use manifest::{
    BuildingShell, Chunk, ChunkManifest, Color, GroundPoint, LanduseShell, ManifestMeta,
    PropInstance, RailSegment, RoadSegment, TerrainGrid, WaterFeature,
};

#[derive(Debug, Clone, PartialEq)]
pub struct ExportConfig {
    pub world_name: String,
    pub chunk_size_studs: i32,
    pub meters_per_stud: f64,
    pub include_props: bool,
    pub style: StyleMapper,
}

impl Default for ExportConfig {
    fn default() -> Self {
        Self {
            world_name: "ExportedWorld".to_string(),
            chunk_size_studs: 256,
            meters_per_stud: 1.0,
            include_props: true,
            style: StyleMapper::default(),
        }
    }
}

impl PartialEq for StyleMapper {
    fn eq(&self, _other: &Self) -> bool {
        true // Simplification for ExportConfig PartialEq
    }
}

pub fn build_sample_manifest() -> ChunkManifest {
    build_sample_multi_chunk(1, 1)
}

pub fn build_sample_multi_chunk(count_x: i32, count_z: i32) -> ChunkManifest {
    let config = ExportConfig::default();
    let mut chunks = Vec::new();
    let elevation = PerlinElevationProvider::default();
    let center = LatLon::new(30.264, -97.750);

    for cz in 0..count_z {
        for cx in 0..count_x {
            let id = ChunkId::new(cx, cz);
            let origin = crate::chunker::chunk_origin(
                id,
                config.chunk_size_studs,
                center,
                config.meters_per_stud,
                &elevation,
            );

            chunks.push(Chunk {
                id,
                origin_studs: origin,
                terrain: Some(TerrainGrid {
                    cell_size_studs: 16,
                    width: 16, // Match 256/16
                    depth: 16,
                    heights: vec![0.0; 256], // Chunker will overwrite this if ingested, but here we just sample manually if needed
                    materials: None,
                    material: config.style.get_terrain_material("grass"),
                }),
                roads: if cx == 0 && cz == 0 {
                    vec![RoadSegment {
                        id: "road_main".to_string(),
                        kind: "primary".to_string(),
                        material: config.style.get_road_material("primary"),
                        color: config.style.get_road_color("primary"),
                        lanes: Some(2),
                        width_studs: 10.0,
                        has_sidewalk: false,
                        surface: None,
                        points: vec![
                            Vec3::new(0.0, 2.0, 64.0),
                            Vec3::new(128.0, 2.0, 64.0),
                            Vec3::new(256.0, 2.0, 64.0),
                        ],
                    }]
                } else {
                    vec![]
                },
                rails: vec![],
                buildings: if cx == 0 && cz == 0 {
                    vec![BuildingShell {
                        id: "bldg_1".to_string(),
                        footprint: vec![
                            GroundPoint::new(24.0, 24.0),
                            GroundPoint::new(80.0, 24.0),
                            GroundPoint::new(80.0, 72.0),
                            GroundPoint::new(24.0, 72.0),
                        ],
                        indices: None,
                        material: config.style.get_building_material("default"),
                        color: config.style.get_building_color("default"),
                        base_y: 2.0,
                        height: 36.0,
                        height_m: None,
                        levels: Some(3),
                        roof_levels: Some(1),
                        roof: "flat".to_string(),
                        facade_style: None,
                        rooms: Vec::new(),
                    }]
                } else {
                    vec![]
                },
                water: vec![],
                props: vec![],
                landuse: vec![],
            });
        }
    }

    // Since we want realistic terrain in the sample, let's actually run it through the chunker logic
    let mut chunker = Chunker::new(config.chunk_size_studs, config.meters_per_stud, center);

    // Ingest the sample features
    for chunk in chunks {
        for road in chunk.roads {
            // Convert relative back to world for ingest
            let world_points = road
                .points
                .into_iter()
                .map(|p| {
                    Vec3::new(
                        p.x + chunk.origin_studs.x,
                        p.y + chunk.origin_studs.y,
                        p.z + chunk.origin_studs.z,
                    )
                })
                .collect();
            chunker.ingest(
                Feature::Road(arbx_pipeline::RoadFeature {
                    id: road.id,
                    kind: road.kind,
                    lanes: road.lanes,
                    width_studs: road.width_studs,
                    has_sidewalk: false,
                    surface: None,
                    points: world_points,
                }),
                &config.style,
                &elevation,
            );
        }
        for bldg in chunk.buildings {
            let fp_points = bldg
                .footprint
                .into_iter()
                .map(|p| {
                    arbx_geo::Vec2::new(p.x + chunk.origin_studs.x, p.z + chunk.origin_studs.z)
                })
                .collect();
            chunker.ingest(
                Feature::Building(arbx_pipeline::BuildingFeature {
                    id: bldg.id,
                    footprint: arbx_geo::Footprint::new(fp_points),
                    indices: bldg.indices,
                    base_y: bldg.base_y + chunk.origin_studs.y,
                    height: bldg.height,
                    height_m: None,
                    levels: bldg.levels,
                    roof_levels: bldg.roof_levels,
                    min_height: None,
                    usage: None,
                    roof: bldg.roof,
                    colour: None,
                    material_tag: None,
                }),
                &config.style,
                &elevation,
            );
        }
    }

    let mut manifest = chunker.finish(ManifestMeta {
        world_name: "SampleAustinLikeBlock".to_string(),
        generator: "arbx_cli sample".to_string(),
        source: "synthetic-scaffold".to_string(),
        meters_per_stud: config.meters_per_stud,
        chunk_size_studs: config.chunk_size_studs,
        bbox: arbx_geo::BoundingBox::new(30.264, -97.750, 30.266, -97.748),
        total_features: 0,
        notes: vec!["Synthetic sample with Perlin terrain".to_string()],
    });

    let mut total_features = 0;
    for chunk in &manifest.chunks {
        total_features += chunk.roads.len()
            + chunk.rails.len()
            + chunk.buildings.len()
            + chunk.water.len()
            + chunk.props.len()
            + chunk.landuse.len();
    }
    manifest.meta.total_features = total_features;
    manifest
}

fn collect_xz(feature: &Feature, pts: &mut Vec<(f64, f64)>) {
    match feature {
        Feature::Road(f) => pts.extend(f.points.iter().map(|p| (p.x, p.z))),
        Feature::Rail(f) => pts.extend(f.points.iter().map(|p| (p.x, p.z))),
        Feature::Building(f) => pts.extend(f.footprint.points.iter().map(|p| (p.x, p.y))),
        Feature::Water(PipelineWaterFeature::Ribbon(r)) => {
            pts.extend(r.points.iter().map(|p| (p.x, p.z)))
        }
        Feature::Water(PipelineWaterFeature::Polygon(r)) => {
            pts.extend(r.footprint.points.iter().map(|p| (p.x, p.y)))
        }
        Feature::Prop(f) => pts.push((f.position.x, f.position.z)),
        Feature::Landuse(f) => pts.extend(f.footprint.points.iter().map(|p| (p.x, p.y))),
    }
}

fn shift_feature(feature: Feature, dx: f64, dz: f64) -> Feature {
    match feature {
        Feature::Road(mut f) => {
            for p in &mut f.points {
                p.x += dx;
                p.z += dz;
            }
            Feature::Road(f)
        }
        Feature::Rail(mut f) => {
            for p in &mut f.points {
                p.x += dx;
                p.z += dz;
            }
            Feature::Rail(f)
        }
        Feature::Building(mut f) => {
            // Vec2.x = world_x, Vec2.y = world_z (footprint is XZ plane)
            for p in &mut f.footprint.points {
                p.x += dx;
                p.y += dz;
            }
            Feature::Building(f)
        }
        Feature::Water(PipelineWaterFeature::Ribbon(mut r)) => {
            for p in &mut r.points {
                p.x += dx;
                p.z += dz;
            }
            Feature::Water(PipelineWaterFeature::Ribbon(r))
        }
        Feature::Water(PipelineWaterFeature::Polygon(mut r)) => {
            for p in &mut r.footprint.points {
                p.x += dx;
                p.y += dz;
            }
            for hole in &mut r.holes {
                for p in &mut hole.points {
                    p.x += dx;
                    p.y += dz;
                }
            }
            Feature::Water(PipelineWaterFeature::Polygon(r))
        }
        Feature::Prop(mut f) => {
            f.position.x += dx;
            f.position.z += dz;
            Feature::Prop(f)
        }
        Feature::Landuse(mut f) => {
            for p in &mut f.footprint.points {
                p.x += dx;
                p.y += dz;
            }
            Feature::Landuse(f)
        }
    }
}

pub fn export_to_chunks(
    features: Vec<Feature>,
    bbox: BoundingBox,
    config: &ExportConfig,
    elevation: &dyn ElevationProvider,
) -> ChunkManifest {
    // Compute centroid of all feature X/Z coordinates and shift to origin
    let mut xz_pts = Vec::new();
    for f in &features {
        collect_xz(f, &mut xz_pts);
    }
    let (cx, cz) = if xz_pts.is_empty() {
        (0.0f64, 0.0f64)
    } else {
        let n = xz_pts.len() as f64;
        let sx: f64 = xz_pts.iter().map(|(x, _)| *x).sum();
        let sz: f64 = xz_pts.iter().map(|(_, z)| *z).sum();
        (sx / n, sz / n)
    };
    eprintln!(
        "World centroid: ({:.1}, {:.1}) studs — shifting to origin",
        cx, cz
    );
    let features: Vec<Feature> = features
        .into_iter()
        .map(|f| shift_feature(f, -cx, -cz))
        .collect();

    let mut chunker = Chunker::new(
        config.chunk_size_studs,
        config.meters_per_stud,
        bbox.center(),
    );

    for feature in features {
        if !config.include_props {
            if let Feature::Prop(_) = feature {
                continue;
            }
        }
        chunker.ingest(feature, &config.style, elevation);
    }

    let manifest = chunker.finish(ManifestMeta {
        world_name: config.world_name.clone(),
        generator: "arbx_roblox_export".to_string(),
        source: "pipeline-export".to_string(),
        meters_per_stud: config.meters_per_stud,
        chunk_size_studs: config.chunk_size_studs,
        bbox,
        total_features: 0,
        notes: vec!["exported via chunker from features".to_string()],
    });

    let mut total_features = 0;
    for chunk in &manifest.chunks {
        total_features += chunk.roads.len();
        total_features += chunk.rails.len();
        total_features += chunk.buildings.len();
        total_features += chunk.water.len();
        total_features += chunk.props.len();
        total_features += chunk.landuse.len();
    }

    let mut manifest = manifest;
    manifest.schema_version = "0.2.0".to_string();
    manifest.meta.total_features = total_features;
    manifest
}

pub fn export_features(
    features: &[Feature],
    config: &ExportConfig,
    elevation: &dyn ElevationProvider,
) -> ChunkManifest {
    export_to_chunks(
        features.to_vec(),
        BoundingBox::new(0.0, 0.0, 1.0, 1.0),
        config,
        elevation,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbx_geo::{Footprint, Vec2};
    use arbx_pipeline::BuildingFeature;

    #[test]
    fn sample_manifest_serializes() {
        let json = build_sample_manifest().to_json_pretty();
        assert!(json.contains("\"schemaVersion\": \"0.2.0\""));
        assert!(json.contains("\"buildings\""));
        assert!(json.contains("\"roads\""));
    }

    #[test]
    fn feature_export_keeps_buildings() {
        let features = vec![Feature::Building(BuildingFeature {
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
        })];

        let elevation = PerlinElevationProvider::default();
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        assert_eq!(manifest.chunks.len(), 1);
        assert_eq!(manifest.chunks[0].buildings.len(), 1);
    }
}
