pub mod chunker;
pub mod manifest;
pub mod materials;

use arbx_geo::{BoundingBox, ChunkId, ElevationProvider, LatLon, PerlinElevationProvider, Vec3};
use arbx_pipeline::{Feature, WaterFeature as PipelineWaterFeature};

use crate::chunker::Chunker;
use crate::materials::StyleMapper;
pub use arbx_geo::satellite::SatelliteTileProvider;
pub use manifest::{
    BarrierSegment, BuildingShell, Chunk, ChunkManifest, Color, GroundPoint, LanduseShell,
    ManifestMeta, PropInstance, RailSegment, RoadSegment, TerrainGrid, WaterFeature,
};

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
                    cell_size_studs: 2,
                    width: 128, // Match 256/2
                    depth: 128,
                    heights: vec![0.0; 16384], // Chunker will overwrite this if ingested, but here we just sample manually if needed
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
                        elevated: false,
                        tunnel: false,
                        sidewalk: None,
                        points: vec![
                            Vec3::new(0.0, 2.0, 64.0),
                            Vec3::new(128.0, 2.0, 64.0),
                            Vec3::new(256.0, 2.0, 64.0),
                        ],
                        maxspeed: None,
                        lit: None,
                        oneway: None,
                        layer: None,
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
                    }]
                } else {
                    vec![]
                },
                water: vec![],
                props: vec![],
                landuse: vec![],
                barriers: vec![],
            });
        }
    }

    // Since we want realistic terrain in the sample, let's actually run it through the chunker logic
    let mut chunker = Chunker::new(
        config.chunk_size_studs,
        config.meters_per_stud,
        config.terrain_cell_size,
        center,
    );

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
                    elevated: None,
                    tunnel: None,
                    sidewalk: None,
                    points: world_points,
                    maxspeed: None,
                    lit: None,
                    oneway: None,
                    layer: None,
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
                    roof_colour: None,
                    roof_material: None,
                    roof_height: None,
                    name: None,
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
            + chunk.landuse.len()
            + chunk.barriers.len();
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
        Feature::Barrier(f) => pts.extend(f.points.iter().map(|p| (p.x, p.z))),
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
        Feature::Barrier(mut f) => {
            for p in &mut f.points {
                p.x += dx;
                p.z += dz;
            }
            Feature::Barrier(f)
        }
    }
}

pub fn export_to_chunks(
    features: Vec<Feature>,
    bbox: BoundingBox,
    config: &ExportConfig,
    elevation: &dyn ElevationProvider,
    satellite: Option<&mut SatelliteTileProvider>,
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
        let mps = config.meters_per_stud;

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

                let lat = center.lat - (world_z * mps / 111_111.0);
                let lon =
                    center.lon + (world_x * mps / (111_111.0 * center.lat.to_radians().cos()));

                if let Some(rgb) = sat.sample_pixel(arbx_geo::LatLon::new(lat, lon)) {
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

                            let lat = center.lat - (world_z * mps / 111_111.0);
                            let lon = center.lon
                                + (world_x * mps / (111_111.0 * center.lat.to_radians().cos()));

                            if let Some(rgb) = sat.sample_pixel(arbx_geo::LatLon::new(lat, lon)) {
                                materials[idx] =
                                    arbx_geo::satellite::classify_ground_material(rgb).to_string();
                            }
                        }
                    }
                }
            }
        }
    }

    let mut total_features = 0;
    for chunk in &manifest.chunks {
        total_features += chunk.roads.len();
        total_features += chunk.rails.len();
        total_features += chunk.buildings.len();
        total_features += chunk.water.len();
        total_features += chunk.props.len();
        total_features += chunk.landuse.len();
        total_features += chunk.barriers.len();
    }

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
    use arbx_geo::{Footprint, Vec2};
    use arbx_pipeline::BuildingFeature;

    #[test]
    fn sample_manifest_serializes() {
        let json = build_sample_manifest().to_json_pretty();
        assert!(json.contains("\"schemaVersion\": \"0.4.0\""));
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
}
