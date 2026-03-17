pub mod chunker;
pub mod manifest;
pub mod materials;

use arbx_geo::{BoundingBox, ChunkId, ElevationProvider, PerlinElevationProvider, LatLon, Vec3};
use arbx_pipeline::Feature;

use crate::chunker::Chunker;
use crate::materials::StyleMapper;
pub use manifest::{
    BuildingShell, Chunk, ChunkManifest, Color, GroundPoint, ManifestMeta, PropInstance,
    RailSegment, RoadSegment, TerrainGrid, WaterFeature,
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
            });
        }
    }

    // Since we want realistic terrain in the sample, let's actually run it through the chunker logic
    let mut chunker = Chunker::new(config.chunk_size_studs, config.meters_per_stud, center);
    
    // Ingest the sample features
    for chunk in chunks {
        for road in chunk.roads {
            // Convert relative back to world for ingest
            let world_points = road.points.into_iter().map(|p| Vec3::new(p.x + chunk.origin_studs.x, p.y + chunk.origin_studs.y, p.z + chunk.origin_studs.z)).collect();
            chunker.ingest(Feature::Road(arbx_pipeline::RoadFeature {
                id: road.id,
                kind: road.kind,
                lanes: road.lanes,
                width_studs: road.width_studs,
                has_sidewalk: false,
                points: world_points,
            }), &config.style, &elevation);
        }
        for bldg in chunk.buildings {
            let fp_points = bldg.footprint.into_iter().map(|p| arbx_geo::Vec2::new(p.x + chunk.origin_studs.x, p.z + chunk.origin_studs.z)).collect();
            chunker.ingest(Feature::Building(arbx_pipeline::BuildingFeature {
                id: bldg.id,
                footprint: arbx_geo::Footprint::new(fp_points),
                indices: bldg.indices,
                base_y: bldg.base_y + chunk.origin_studs.y,
                height: bldg.height,
                levels: bldg.levels,
                roof_levels: bldg.roof_levels,
                min_height: None,
                usage: None,
                roof: bldg.roof,
            }), &config.style, &elevation);
        }
    }

    let mut manifest = chunker.finish(ManifestMeta {
        world_name: "SampleAustinLikeBlock".to_string(),
        generator: "arbx_cli sample".to_string(),
        source: "synthetic-scaffold".to_string(),
        meters_per_stud: config.meters_per_stud as f32,
        chunk_size_studs: config.chunk_size_studs,
        bbox: arbx_geo::BoundingBox::new(30.264, -97.750, 30.266, -97.748),
        total_features: 0,
        notes: vec![
            "Synthetic sample with Perlin terrain".to_string(),
        ],
    });

    let mut total_features = 0;
    for chunk in &manifest.chunks {
        total_features += chunk.roads.len() + chunk.rails.len() + chunk.buildings.len() + chunk.water.len() + chunk.props.len();
    }
    manifest.meta.total_features = total_features;
    manifest
}

pub fn export_to_chunks(
    features: Vec<Feature>,
    bbox: BoundingBox,
    config: &ExportConfig,
    elevation: &dyn ElevationProvider,
) -> ChunkManifest {
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
        meters_per_stud: config.meters_per_stud as f32,
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
            levels: None,
            roof_levels: None,
            min_height: None,
            usage: None,
            roof: "flat".to_string(),
        })];

        let elevation = PerlinElevationProvider::default();
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        assert_eq!(manifest.chunks.len(), 1);
        assert_eq!(manifest.chunks[0].buildings.len(), 1);
    }
}
