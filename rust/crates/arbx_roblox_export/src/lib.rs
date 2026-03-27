pub mod chunker;
pub mod manifest;
pub mod manifest_store;
pub mod materials;
pub mod subplans;

use arbx_geo::{
    BoundingBox, ChunkId, ElevationProvider, LatLon, Mercator, PerlinElevationProvider, Vec3,
};
use arbx_pipeline::Feature;

use crate::chunker::{build_empty_chunk, Chunker};
use crate::materials::StyleMapper;
pub use arbx_geo::satellite::SatelliteTileProvider;
pub use manifest::{
    BarrierSegment, BuildingShell, Chunk, ChunkManifest, Color, GroundPoint, LanduseShell,
    ManifestMeta, PropInstance, RailSegment, RoadSegment, TerrainGrid, WaterFeature,
};
pub use manifest_store::{
    read_manifest_sqlite_all, read_manifest_sqlite_subset, write_manifest_sqlite,
    ManifestStoreResult, StoredChunkRecord, StoredManifestMeta, StoredManifestSubset,
};
use subplans::derive_chunk_ref;
pub use subplans::{ChunkRef, ChunkSubplan, SubplanBounds, PARTITION_VERSION};

#[derive(Debug, Clone, PartialEq)]
pub struct ExportConfig {
    pub world_name: String,
    pub chunk_size_studs: i32,
    pub meters_per_stud: f64,
    pub terrain_cell_size: i32,
    pub include_props: bool,
    pub style: StyleMapper,
}

impl Default for ExportConfig {
    fn default() -> Self {
        Self {
            world_name: "ExportedWorld".to_string(),
            chunk_size_studs: 256,
            meters_per_stud: 0.3,
            terrain_cell_size: 2, // 2-stud cells = 128×128 grid = sub-meter precision
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

fn chunk_total_feature_count(chunk: &Chunk) -> usize {
    usize::from(chunk.terrain.is_some())
        + chunk.roads.len()
        + chunk.rails.len()
        + chunk.buildings.len()
        + chunk.water.len()
        + chunk.props.len()
        + chunk.landuse.len()
        + chunk.barriers.len()
}

pub fn build_sample_manifest() -> ChunkManifest {
    build_sample_multi_chunk(1, 1)
}

pub fn build_sample_multi_chunk(count_x: i32, count_z: i32) -> ChunkManifest {
    let config = ExportConfig::default();
    let mut chunks = Vec::with_capacity((count_x.max(0) * count_z.max(0)) as usize);
    let elevation = PerlinElevationProvider::default();
    let center = LatLon::new(30.264, -97.750);

    for cz in 0..count_z {
        for cx in 0..count_x {
            let id = ChunkId::new(cx, cz);
            let mut chunk = build_empty_chunk(
                id,
                config.chunk_size_studs,
                config.meters_per_stud,
                config.terrain_cell_size,
                center,
                &elevation,
                &config.style,
            );

            if cx == 0 && cz == 0 {
                chunk.roads.push(RoadSegment {
                    id: "road_main".to_string(),
                    kind: "primary".to_string(),
                    subkind: None,
                    material: config.style.get_road_material("primary"),
                    color: config.style.get_road_color("primary"),
                    lanes: Some(2),
                    width_studs: 10.0,
                    has_sidewalk: false,
                    surface: None,
                    elevated: false,
                    tunnel: false,
                    sidewalk: None,
                    points: vec![
                        Vec3::new(0.0, 2.0, 64.0),
                        Vec3::new(128.0, 2.0, 64.0),
                        Vec3::new(240.0, 2.0, 64.0),
                    ],
                    maxspeed: None,
                    lit: None,
                    oneway: None,
                    layer: None,
                });
                chunk.buildings.push(BuildingShell {
                    id: "bldg_1".to_string(),
                    footprint: vec![
                        GroundPoint::new(24.0, 24.0),
                        GroundPoint::new(80.0, 24.0),
                        GroundPoint::new(80.0, 72.0),
                        GroundPoint::new(24.0, 72.0),
                    ],
                    holes: vec![],
                    indices: None,
                    material: config.style.get_building_material("default"),
                    wall_color: config.style.get_building_color("default"),
                    roof_color: None,
                    roof_shape: Some("flat".to_string()),
                    roof_material: None,
                    usage: None,
                    min_height: None,
                    base_y: 2.0,
                    height: 36.0,
                    height_m: None,
                    levels: Some(3),
                    roof_levels: Some(1),
                    roof: "flat".to_string(),
                    facade_style: None,
                    rooms: Vec::new(),
                    roof_height: None,
                    name: None,
                });
            }

            chunks.push(chunk);
        }
    }

    chunks.sort_by_key(|chunk| (chunk.id.z, chunk.id.x));
    let chunk_refs = chunks.iter().map(derive_chunk_ref).collect();
    let total_features = chunks.iter().map(chunk_total_feature_count).sum();

    ChunkManifest {
        schema_version: "0.4.0".to_string(),
        meta: ManifestMeta {
            world_name: "SampleAustinLikeBlock".to_string(),
            generator: "arbx_cli sample".to_string(),
            source: "synthetic-scaffold".to_string(),
            meters_per_stud: config.meters_per_stud,
            chunk_size_studs: config.chunk_size_studs,
            bbox: arbx_geo::BoundingBox::new(30.264, -97.750, 30.266, -97.748),
            total_features,
            notes: vec!["Synthetic sample with Perlin terrain".to_string()],
        },
        chunks,
        chunk_refs,
    }
}

pub fn export_to_chunks(
    features: Vec<Feature>,
    bbox: BoundingBox,
    config: &ExportConfig,
    elevation: &dyn ElevationProvider,
    satellite: Option<&mut SatelliteTileProvider>,
) -> ChunkManifest {
    let mut chunker = Chunker::new(
        config.chunk_size_studs,
        config.meters_per_stud,
        config.terrain_cell_size,
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

    let mut manifest = chunker.finish(ManifestMeta {
        world_name: config.world_name.clone(),
        generator: "arbx_roblox_export".to_string(),
        source: "pipeline-export".to_string(),
        meters_per_stud: config.meters_per_stud,
        chunk_size_studs: config.chunk_size_studs,
        bbox,
        total_features: 0,
        notes: vec!["exported via chunker from features".to_string()],
    });

    // Post-pass: enrich buildings and terrain cells from satellite imagery
    if let Some(sat) = satellite {
        let center = bbox.center();

        for chunk in &mut manifest.chunks {
            let origin = chunk.origin_studs;

            // Enrich building roof colors from satellite
            for building in &mut chunk.buildings {
                // Skip if already has roof color from OSM tags
                if building.roof_color.is_some() {
                    continue;
                }

                // Compute chunk-relative centroid of the building footprint
                let fp_center_x = building.footprint.iter().map(|p| p.x).sum::<f64>()
                    / building.footprint.len() as f64;
                let fp_center_z = building.footprint.iter().map(|p| p.z).sum::<f64>()
                    / building.footprint.len() as f64;

                // Convert chunk-relative stud coordinates back to world studs then to lat/lon
                let world_x = fp_center_x + origin.x;
                let world_z = fp_center_z + origin.z;

                let latlon = Mercator::unproject(
                    Vec3::new(world_x, 0.0, world_z),
                    center,
                    config.meters_per_stud,
                );

                if let Some(rgb) = sat.sample_pixel(latlon) {
                    let (r, g, b) = arbx_geo::satellite::roof_pixel_to_color(rgb);
                    building.roof_color = Some(Color::new(r, g, b));

                    // Also set roof material if not supplied by OSM
                    if building.roof_material.is_none() {
                        building.roof_material =
                            Some(arbx_geo::satellite::classify_roof_material(rgb).to_string());
                    }
                }
            }

            // Enrich terrain per-cell materials from satellite ground classification
            if let Some(terrain) = &mut chunk.terrain {
                if let Some(materials) = &mut terrain.materials {
                    let cell_size = terrain.cell_size_studs as f64;
                    let default_mat = terrain.material.clone();
                    for cz in 0..terrain.depth {
                        for cx in 0..terrain.width {
                            let idx = cz * terrain.width + cx;
                            // Only override cells that still carry the chunk default material
                            if materials[idx] != default_mat {
                                continue;
                            }

                            let world_x = (cx as f64 * cell_size) + origin.x;
                            let world_z = (cz as f64 * cell_size) + origin.z;

                            let latlon = Mercator::unproject(
                                Vec3::new(world_x, 0.0, world_z),
                                center,
                                config.meters_per_stud,
                            );

                            if let Some(rgb) = sat.sample_pixel(latlon) {
                                materials[idx] =
                                    arbx_geo::satellite::classify_ground_material(rgb).to_string();
                            }
                        }
                    }
                }
            }
        }
    }

    let total_features = manifest.chunks.iter().map(chunk_total_feature_count).sum();

    manifest.schema_version = "0.4.0".to_string();
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
        None,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbx_geo::{FlatElevationProvider, Footprint, Vec2};
    use arbx_pipeline::{BuildingFeature, LanduseFeature};
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn sample_manifest_serializes() {
        let manifest = ChunkManifest {
            schema_version: "0.4.0".to_string(),
            meta: ManifestMeta {
                world_name: "SerializationSmoke".to_string(),
                generator: "unit-test".to_string(),
                source: "unit-test".to_string(),
                meters_per_stud: 0.3,
                chunk_size_studs: 256,
                bbox: BoundingBox::new(30.264, -97.750, 30.266, -97.748),
                total_features: 2,
                notes: vec!["serialization smoke".to_string()],
            },
            chunks: vec![Chunk {
                id: ChunkId::new(0, 0),
                origin_studs: Vec3::new(0.0, 0.0, 0.0),
                terrain: None,
                roads: vec![RoadSegment {
                    id: "road_smoke".to_string(),
                    kind: "primary".to_string(),
                    subkind: None,
                    material: "Asphalt".to_string(),
                    color: None,
                    lanes: Some(2),
                    width_studs: 10.0,
                    has_sidewalk: false,
                    surface: None,
                    elevated: false,
                    tunnel: false,
                    sidewalk: None,
                    points: vec![Vec3::new(0.0, 0.0, 0.0), Vec3::new(16.0, 0.0, 0.0)],
                    maxspeed: None,
                    lit: None,
                    oneway: None,
                    layer: None,
                }],
                rails: vec![],
                buildings: vec![BuildingShell {
                    id: "building_smoke".to_string(),
                    footprint: vec![
                        GroundPoint::new(0.0, 0.0),
                        GroundPoint::new(8.0, 0.0),
                        GroundPoint::new(8.0, 8.0),
                        GroundPoint::new(0.0, 8.0),
                    ],
                    holes: vec![],
                    indices: None,
                    material: "Concrete".to_string(),
                    wall_color: None,
                    roof_color: None,
                    roof_shape: Some("flat".to_string()),
                    roof_material: None,
                    usage: None,
                    min_height: None,
                    base_y: 0.0,
                    height: 12.0,
                    height_m: None,
                    levels: Some(1),
                    roof_levels: None,
                    roof: "flat".to_string(),
                    facade_style: None,
                    rooms: Vec::new(),
                    roof_height: None,
                    name: None,
                }],
                water: vec![],
                props: vec![],
                landuse: vec![],
                barriers: vec![],
            }],
            chunk_refs: vec![],
        };
        let json = manifest.to_json_pretty();
        assert!(json.contains("\"schemaVersion\": \"0.4.0\""));
        assert!(json.contains("\"buildings\""));
        assert!(json.contains("\"roads\""));
    }

    #[test]
    fn sample_multi_chunk_creates_requested_chunk_grid() {
        let manifest = build_sample_multi_chunk(2, 2);
        assert_eq!(manifest.chunks.len(), 4);
        assert_eq!(manifest.chunk_refs.len(), 4);
        assert_eq!(manifest.meta.total_features, 6);
    }

    #[test]
    fn manifest_meta_total_features_matches_chunk_ref_feature_counts() {
        let manifest = build_sample_multi_chunk(2, 2);
        let expected_total_features: usize = manifest
            .chunk_refs
            .iter()
            .map(|chunk_ref| chunk_ref.feature_count)
            .sum();

        assert_eq!(manifest.meta.total_features, expected_total_features);
    }

    fn unique_temp_db_path(test_name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "arbx_manifest_store_{test_name}_{}_{}.sqlite",
            std::process::id(),
            nanos
        ))
    }

    #[test]
    fn manifest_store_round_trips_requested_chunks() {
        let manifest = build_sample_multi_chunk(2, 2);
        let db_path = unique_temp_db_path("round_trip");

        crate::manifest_store::write_manifest_sqlite(&manifest, &db_path).unwrap();
        let subset = crate::manifest_store::read_manifest_sqlite_subset(
            &db_path,
            &["0_0".to_string(), "1_1".to_string()],
        )
        .unwrap();

        assert_eq!(subset.meta.schema_version, manifest.schema_version);
        assert_eq!(subset.meta.world_name, manifest.meta.world_name);
        assert_eq!(subset.chunks.len(), 2);
        assert_eq!(subset.chunks[0].chunk_id, "0_0");
        assert_eq!(subset.chunks[1].chunk_id, "1_1");
        assert!(subset.chunks[0].chunk_json.contains("\"id\": \"0_0\""));
        assert!(subset.chunks[1].chunk_json.contains("\"id\": \"1_1\""));

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn manifest_store_preserves_chunk_ref_streaming_metadata() {
        let manifest = build_sample_multi_chunk(2, 2);
        let db_path = unique_temp_db_path("streaming_metadata");

        crate::manifest_store::write_manifest_sqlite(&manifest, &db_path).unwrap();
        let subset =
            crate::manifest_store::read_manifest_sqlite_subset(&db_path, &["0_0".to_string()])
                .unwrap();

        let chunk = &subset.chunks[0];
        assert!(chunk.feature_count >= 2);
        assert!(chunk.streaming_cost >= 20.0);
        assert_eq!(chunk.partition_version, PARTITION_VERSION);
        assert!(
            chunk.subplans_json.contains("\"streamingCost\""),
            "expected serialized subplans JSON to keep streaming metadata"
        );

        let _ = std::fs::remove_file(db_path);
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
        })];

        let elevation = PerlinElevationProvider::default();
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        assert_eq!(manifest.chunks.len(), 1);
        assert_eq!(manifest.chunks[0].buildings.len(), 1);
    }

    #[test]
    fn building_export_does_not_synthesize_whole_footprint_rooms() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "osm_test_building".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(20.0, 0.0),
                Vec2::new(20.0, 10.0),
                Vec2::new(0.0, 10.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 12.0,
            height_m: None,
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
            name: Some("Regression Test Building".to_string()),
        })];

        let elevation = PerlinElevationProvider::default();
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let building = &manifest.chunks[0].buildings[0];

        assert!(
            building.rooms.is_empty(),
            "exporter should not fabricate room slabs from the outer building footprint"
        );
    }

    #[test]
    fn building_export_uses_usage_palette_without_forcing_facade_style() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "osm_usage_test".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(16.0, 0.0),
                Vec2::new(16.0, 16.0),
                Vec2::new(0.0, 16.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 8.0,
            height_m: None,
            levels: Some(2),
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
        })];

        let elevation = PerlinElevationProvider::default();
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let building = &manifest.chunks[0].buildings[0];

        assert_eq!(
            building.material, "Concrete",
            "usage-driven palette should determine the default shell material"
        );
        assert_eq!(
            building.wall_color,
            ExportConfig::default()
                .style
                .get_building_color("residential"),
            "usage-driven palette should determine the default shell color"
        );
        assert_eq!(
            building.facade_style, None,
            "exporter should not force a procedural facade style for generic OSM buildings"
        );
    }

    #[test]
    fn building_export_scales_meter_vertical_dimensions_but_preserves_authoritative_base_y() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "scaled_verticals".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(20.0, 0.0),
                Vec2::new(20.0, 20.0),
                Vec2::new(0.0, 20.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 30.0,
            height: 9.0,
            height_m: Some(12.0),
            levels: Some(3),
            roof_levels: None,
            min_height: Some(3.0),
            usage: Some("office".to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: Some(1.5),
            name: None,
        })];

        let elevation = FlatElevationProvider { height: 0.0 };
        let manifest = export_features(
            &features,
            &ExportConfig {
                meters_per_stud: 0.5,
                ..ExportConfig::default()
            },
            &elevation,
        );
        let building = &manifest.chunks[0].buildings[0];

        assert_eq!(building.base_y, 30.0);
        assert_eq!(building.min_height, Some(6.0));
        assert_eq!(building.height, 18.0);
        assert_eq!(building.height_m, Some(12.0));
        assert_eq!(building.roof_height, Some(3.0));
    }

    #[test]
    fn building_export_preserves_holes_in_manifest_shell() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "osm_courtyard_test".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(40.0, 0.0),
                Vec2::new(40.0, 40.0),
                Vec2::new(0.0, 40.0),
            ]),
            holes: vec![Footprint::new(vec![
                Vec2::new(10.0, 10.0),
                Vec2::new(30.0, 10.0),
                Vec2::new(30.0, 30.0),
                Vec2::new(10.0, 30.0),
            ])],
            indices: None,
            base_y: 0.0,
            height: 12.0,
            height_m: None,
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
            name: Some("Courtyard Test".to_string()),
        })];

        let elevation = PerlinElevationProvider::default();
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let building = &manifest.chunks[0].buildings[0];

        assert_eq!(
            building.holes.len(),
            1,
            "expected courtyard hole to survive export"
        );
        assert!(
            building.holes[0].len() >= 4,
            "expected exported courtyard hole to keep its polygon points"
        );
    }

    #[test]
    fn export_preserves_bbox_centered_world_coordinates() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "world_space_truth".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(-640.0, -1536.0),
                Vec2::new(-608.0, -1536.0),
                Vec2::new(-608.0, -1504.0),
                Vec2::new(-640.0, -1504.0),
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
        })];

        let elevation = FlatElevationProvider { height: 0.0 };
        let bbox = arbx_geo::BoundingBox::new(30.245, -97.765, 30.305, -97.715);
        let manifest = export_to_chunks(features, bbox, &ExportConfig::default(), &elevation, None);

        let chunk = manifest
            .chunks
            .iter()
            .find(|candidate| !candidate.buildings.is_empty())
            .expect("expected exported chunk with building");
        let building = &chunk.buildings[0];
        let world_points: Vec<(f64, f64)> = building
            .footprint
            .iter()
            .map(|point| {
                (
                    chunk.origin_studs.x + point.x,
                    chunk.origin_studs.z + point.z,
                )
            })
            .collect();

        let expected = [
            (-640.0, -1536.0),
            (-608.0, -1536.0),
            (-608.0, -1504.0),
            (-640.0, -1504.0),
        ];

        assert_eq!(world_points.len(), expected.len());
        for ((actual_x, actual_z), (expected_x, expected_z)) in
            world_points.iter().zip(expected.iter())
        {
            assert!(
                (actual_x - expected_x).abs() <= 1e-6,
                "expected exported world x {expected_x}, got {actual_x}"
            );
            assert!(
                (actual_z - expected_z).abs() <= 1e-6,
                "expected exported world z {expected_z}, got {actual_z}"
            );
        }
    }

    #[test]
    fn building_export_prefers_explicit_material_tag_even_with_explicit_colour() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "osm_material_override".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(12.0, 0.0),
                Vec2::new(12.0, 12.0),
                Vec2::new(0.0, 12.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 8.0,
            height_m: None,
            levels: Some(2),
            roof_levels: None,
            min_height: None,
            usage: Some("yes".to_string()),
            roof: "flat".to_string(),
            colour: Some("#d8d1c4".to_string()),
            material_tag: Some("brick".to_string()),
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: None,
        })];

        let elevation = FlatElevationProvider { height: 0.0 };
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let building = &manifest.chunks[0].buildings[0];

        assert_eq!(
            building.material, "Brick",
            "explicit OSM building:material should win even when a building colour is present"
        );
    }

    #[test]
    fn building_export_uses_opaque_office_usage_palette_for_manifest_material() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "osm_office_usage_test".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(16.0, 0.0),
                Vec2::new(16.0, 16.0),
                Vec2::new(0.0, 16.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 18.0,
            height_m: None,
            levels: Some(5),
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
        })];

        let elevation = FlatElevationProvider { height: 0.0 };
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let building = &manifest.chunks[0].buildings[0];

        assert_eq!(building.material, "Concrete");
    }

    #[test]
    fn building_export_maps_explicit_masonry_material_to_brick() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "osm_masonry_override".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(16.0, 0.0),
                Vec2::new(16.0, 16.0),
                Vec2::new(0.0, 16.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 18.0,
            height_m: None,
            levels: Some(5),
            roof_levels: None,
            min_height: None,
            usage: Some("office".to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: Some("masonry".to_string()),
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: None,
        })];

        let elevation = FlatElevationProvider { height: 0.0 };
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let building = &manifest.chunks[0].buildings[0];

        assert_eq!(building.material, "Brick");
    }

    #[test]
    fn building_export_uses_opaque_hospital_usage_palette_for_manifest_material() {
        let features = vec![Feature::Building(BuildingFeature {
            id: "osm_hospital_usage_test".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(20.0, 0.0),
                Vec2::new(20.0, 20.0),
                Vec2::new(0.0, 20.0),
            ]),
            holes: vec![],
            indices: None,
            base_y: 0.0,
            height: 20.0,
            height_m: None,
            levels: Some(6),
            roof_levels: None,
            min_height: None,
            usage: Some("hospital".to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: None,
        })];

        let elevation = FlatElevationProvider { height: 0.0 };
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let building = &manifest.chunks[0].buildings[0];

        assert_eq!(building.material, "Concrete");
    }

    #[test]
    fn export_paints_terrain_materials_from_landuse_semantics() {
        let features = vec![Feature::Landuse(LanduseFeature {
            id: "park_semantics".to_string(),
            kind: "forest".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(0.0, 0.0),
                Vec2::new(48.0, 0.0),
                Vec2::new(48.0, 48.0),
                Vec2::new(0.0, 48.0),
            ]),
        })];

        let elevation = FlatElevationProvider { height: 0.0 };
        let manifest = export_features(&features, &ExportConfig::default(), &elevation);
        let terrain = manifest.chunks[0]
            .terrain
            .as_ref()
            .expect("expected terrain grid");
        let materials = terrain
            .materials
            .as_ref()
            .expect("expected terrain materials");

        assert!(
            materials.iter().any(|material| material == "LeafyGrass"),
            "landuse semantics should paint the terrain grid, not leave every cell at the default material"
        );
    }
}
