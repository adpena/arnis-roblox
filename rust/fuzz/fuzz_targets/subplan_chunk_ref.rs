#![no_main]

use arbitrary::Arbitrary;
use arbx_geo::{ChunkId, Vec3};
use arbx_roblox_export::subplans::{derive_chunk_ref, PARTITION_VERSION};
use arbx_roblox_export::{
    BuildingShell, Chunk, ChunkRef, GroundPoint, LanduseShell, PropInstance, RoadSegment,
    TerrainGrid, WaterFeature,
};
use libfuzzer_sys::fuzz_target;

const MAX_FEATURES_PER_LAYER: usize = 16;

#[derive(Arbitrary, Debug)]
struct RectInput {
    min_x: i16,
    min_z: i16,
    width: u8,
    depth: u8,
}

#[derive(Arbitrary, Debug)]
struct RoadInput {
    start_x: i16,
    start_z: i16,
    delta_x: i16,
    delta_z: i16,
    width: u8,
    has_sidewalk: bool,
}

#[derive(Arbitrary, Debug)]
struct PropInput {
    x: i16,
    z: i16,
    scale: u8,
}

#[derive(Arbitrary, Debug)]
struct ChunkInput {
    chunk_x: i8,
    chunk_z: i8,
    origin_x: i16,
    origin_y: i16,
    origin_z: i16,
    include_terrain: bool,
    landuse: Vec<RectInput>,
    buildings: Vec<RectInput>,
    roads: Vec<RoadInput>,
    water: Vec<RectInput>,
    props: Vec<PropInput>,
}

fn rect_points(input: &RectInput) -> Vec<GroundPoint> {
    let min_x = input.min_x as f64;
    let min_z = input.min_z as f64;
    let width = f64::from(input.width.max(1));
    let depth = f64::from(input.depth.max(1));

    vec![
        GroundPoint::new(min_x, min_z),
        GroundPoint::new(min_x + width, min_z),
        GroundPoint::new(min_x + width, min_z + depth),
        GroundPoint::new(min_x, min_z + depth),
    ]
}

fn build_chunk(input: ChunkInput) -> Chunk {
    let terrain = input.include_terrain.then(|| TerrainGrid {
        cell_size_studs: 4,
        width: 1,
        depth: 1,
        heights: vec![0.0],
        materials: None,
        material: "grass".to_string(),
    });

    let roads = input
        .roads
        .into_iter()
        .take(MAX_FEATURES_PER_LAYER)
        .enumerate()
        .map(|(index, road)| RoadSegment {
            id: format!("road_{index}"),
            kind: "residential".to_string(),
            subkind: None,
            material: "asphalt".to_string(),
            color: None,
            lanes: Some(2),
            width_studs: f64::from(road.width.max(1)),
            has_sidewalk: road.has_sidewalk,
            surface: None,
            elevated: false,
            tunnel: false,
            sidewalk: None,
            points: vec![
                Vec3::new(road.start_x as f64, 0.0, road.start_z as f64),
                Vec3::new(
                    (road.start_x + road.delta_x) as f64,
                    0.0,
                    (road.start_z + road.delta_z) as f64,
                ),
            ],
            maxspeed: None,
            lit: None,
            oneway: None,
            layer: None,
        })
        .collect();

    let landuse = input
        .landuse
        .into_iter()
        .take(MAX_FEATURES_PER_LAYER)
        .enumerate()
        .map(|(index, rect)| LanduseShell {
            id: format!("landuse_{index}"),
            kind: "grass".to_string(),
            material: "grass".to_string(),
            footprint: rect_points(&rect),
        })
        .collect();

    let buildings = input
        .buildings
        .into_iter()
        .take(MAX_FEATURES_PER_LAYER)
        .enumerate()
        .map(|(index, rect)| BuildingShell {
            id: format!("building_{index}"),
            footprint: rect_points(&rect),
            holes: Vec::new(),
            indices: None,
            material: "concrete".to_string(),
            wall_color: None,
            roof_color: None,
            roof_shape: Some("flat".to_string()),
            roof_material: Some("concrete".to_string()),
            usage: None,
            min_height: None,
            base_y: 0.0,
            height: 12.0,
            height_m: Some(3.6),
            levels: Some(1),
            roof_levels: Some(0),
            roof: "flat".to_string(),
            facade_style: None,
            rooms: Vec::new(),
            roof_height: None,
            name: None,
        })
        .collect();

    let water = input
        .water
        .into_iter()
        .take(MAX_FEATURES_PER_LAYER)
        .enumerate()
        .map(|(index, rect)| WaterFeature {
            id: format!("water_{index}"),
            kind: "pond".to_string(),
            material: "water".to_string(),
            color: None,
            width_studs: None,
            points: None,
            footprint: Some(rect_points(&rect)),
            holes: Vec::new(),
            indices: None,
            surface_y: Some(0.0),
            width: None,
            intermittent: None,
        })
        .collect();

    let props = input
        .props
        .into_iter()
        .take(MAX_FEATURES_PER_LAYER)
        .enumerate()
        .map(|(index, prop)| PropInstance {
            id: format!("prop_{index}"),
            kind: "tree".to_string(),
            position: Vec3::new(prop.x as f64, 0.0, prop.z as f64),
            yaw_degrees: 0.0,
            scale: f64::from(prop.scale.max(1)),
            species: None,
            height: None,
            leaf_type: None,
            circumference: None,
        })
        .collect();

    Chunk {
        id: ChunkId::new(i32::from(input.chunk_x), i32::from(input.chunk_z)),
        origin_studs: Vec3::new(
            input.origin_x as f64,
            input.origin_y as f64,
            input.origin_z as f64,
        ),
        terrain,
        roads,
        rails: Vec::new(),
        buildings,
        water,
        props,
        landuse,
        barriers: Vec::new(),
    }
}

fuzz_target!(|input: ChunkInput| {
    let chunk = build_chunk(input);
    let chunk_ref = derive_chunk_ref(&chunk);
    let chunk_ref_again = derive_chunk_ref(&chunk);

    assert_eq!(chunk_ref, chunk_ref_again);
    assert_eq!(chunk_ref.partition_version, PARTITION_VERSION);
    assert!(chunk_ref.streaming_cost.is_finite());
    assert!(chunk_ref.streaming_cost >= 0.0);

    for subplan in &chunk_ref.subplans {
        assert!(subplan.streaming_cost.is_finite());
        assert!(subplan.streaming_cost >= 0.0);
        if let Some(bounds) = &subplan.bounds {
            assert!(bounds.min_x.is_finite());
            assert!(bounds.min_y.is_finite());
            assert!(bounds.max_x.is_finite());
            assert!(bounds.max_y.is_finite());
            assert!(bounds.min_x <= bounds.max_x);
            assert!(bounds.min_y <= bounds.max_y);
        }
    }

    let json = serde_json::to_string(&chunk_ref).unwrap();
    let parsed: ChunkRef = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, chunk_ref);
});
