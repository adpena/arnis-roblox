use arbx_geo::{BoundingBox, FlatElevationProvider, Footprint, LatLon, Vec2, Vec3};
use arbx_pipeline::{
    BarrierFeature, BuildingFeature, Feature, LanduseFeature, PropFeature, RailFeature,
    RoadFeature, WaterFeature, WaterPolygonFeature,
};
use arbx_roblox_export::chunker::Chunker;
use arbx_roblox_export::manifest::{ChunkManifest, ManifestMeta};
use arbx_roblox_export::materials::StyleMapper;

fn build_test_manifest() -> ChunkManifest {
    let elevation = FlatElevationProvider { height: 0.0 };
    let style = StyleMapper::default();
    let mut chunker = Chunker::new(256, 0.3, 2, LatLon::new(30.2672, -97.7431));

    let features = vec![
        Feature::Road(RoadFeature {
            id: "road_main".to_string(),
            kind: "primary".to_string(),
            lanes: Some(2),
            width_studs: 12.0,
            has_sidewalk: true,
            surface: Some("asphalt".to_string()),
            elevated: Some(false),
            tunnel: Some(false),
            sidewalk: Some("both".to_string()),
            points: vec![
                Vec3::new(32.0, 0.0, 72.0),
                Vec3::new(96.0, 0.0, 72.0),
                Vec3::new(160.0, 0.0, 72.0),
            ],
            maxspeed: Some(35),
            lit: Some(true),
            oneway: Some(false),
            layer: Some(0),
        }),
        Feature::Building(BuildingFeature {
            id: "building_main".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(96.0, 96.0),
                Vec2::new(144.0, 96.0),
                Vec2::new(144.0, 148.0),
                Vec2::new(96.0, 148.0),
            ]),
            indices: None,
            base_y: 0.0,
            height: 36.0,
            height_m: Some(10.8),
            levels: Some(3),
            roof_levels: Some(1),
            min_height: None,
            usage: Some("office".to_string()),
            roof: "flat".to_string(),
            colour: Some("#c0ffee".to_string()),
            material_tag: Some("brick".to_string()),
            roof_colour: Some("#223344".to_string()),
            roof_material: Some("Slate".to_string()),
            roof_height: Some(2.0),
            name: Some("Tower One".to_string()),
        }),
        Feature::Water(WaterFeature::Polygon(WaterPolygonFeature {
            id: "water_pond".to_string(),
            kind: "water".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(172.0, 120.0),
                Vec2::new(220.0, 120.0),
                Vec2::new(220.0, 176.0),
                Vec2::new(172.0, 176.0),
            ]),
            holes: vec![Footprint::new(vec![
                Vec2::new(188.0, 136.0),
                Vec2::new(204.0, 136.0),
                Vec2::new(204.0, 152.0),
                Vec2::new(188.0, 152.0),
            ])],
            indices: None,
            intermittent: Some(false),
        })),
        Feature::Prop(PropFeature {
            id: "tree_oak".to_string(),
            kind: "tree".to_string(),
            position: Vec3::new(48.0, 0.0, 180.0),
            yaw_degrees: 90.0,
            scale: 1.25,
            species: Some("oak".to_string()),
            height: Some(8.5),
            leaf_type: Some("broadleaved".to_string()),
            circumference: Some(1.2),
        }),
        Feature::Landuse(LanduseFeature {
            id: "park_green".to_string(),
            kind: "park".to_string(),
            footprint: Footprint::new(vec![
                Vec2::new(24.0, 24.0),
                Vec2::new(120.0, 24.0),
                Vec2::new(120.0, 120.0),
                Vec2::new(24.0, 120.0),
            ]),
        }),
    ];

    for feature in features {
        chunker.ingest(feature, &style, &elevation);
    }

    chunker.finish(ManifestMeta {
        world_name: "SubplanFixture".to_string(),
        generator: "subplans-test".to_string(),
        source: "synthetic".to_string(),
        meters_per_stud: 0.3,
        chunk_size_studs: 256,
        bbox: BoundingBox::new(30.2670, -97.7440, 30.2680, -97.7430),
        total_features: 5,
        notes: vec!["subplan fixture".to_string()],
    })
}

fn build_test_manifest_with_rails_and_barriers() -> ChunkManifest {
    let elevation = FlatElevationProvider { height: 0.0 };
    let style = StyleMapper::default();
    let mut chunker = Chunker::new(256, 0.3, 2, LatLon::new(30.2672, -97.7431));

    for feature in [
        Feature::Road(RoadFeature {
            id: "road_main".to_string(),
            kind: "primary".to_string(),
            lanes: Some(2),
            width_studs: 12.0,
            has_sidewalk: false,
            surface: None,
            elevated: Some(false),
            tunnel: Some(false),
            sidewalk: None,
            points: vec![Vec3::new(24.0, 0.0, 48.0), Vec3::new(200.0, 0.0, 48.0)],
            maxspeed: None,
            lit: None,
            oneway: None,
            layer: None,
        }),
        Feature::Rail(RailFeature {
            id: "rail_main".to_string(),
            kind: "rail".to_string(),
            lanes: Some(1),
            width_studs: 8.0,
            points: vec![Vec3::new(24.0, 0.0, 80.0), Vec3::new(200.0, 0.0, 80.0)],
        }),
        Feature::Barrier(BarrierFeature {
            id: "wall_main".to_string(),
            kind: "wall".to_string(),
            points: vec![Vec3::new(24.0, 0.0, 112.0), Vec3::new(200.0, 0.0, 112.0)],
        }),
    ] {
        chunker.ingest(feature, &style, &elevation);
    }

    chunker.finish(ManifestMeta {
        world_name: "SubplanConsistencyFixture".to_string(),
        generator: "subplans-test".to_string(),
        source: "synthetic".to_string(),
        meters_per_stud: 0.3,
        chunk_size_studs: 256,
        bbox: BoundingBox::new(30.2670, -97.7440, 30.2680, -97.7430),
        total_features: 3,
        notes: vec!["subplan consistency fixture".to_string()],
    })
}

fn chunk_ref<'a>(
    manifest: &'a ChunkManifest,
    chunk_id: &str,
) -> &'a arbx_roblox_export::ChunkRef {
    manifest
        .chunk_refs
        .iter()
        .find(|entry| entry.id == chunk_id)
        .expect("chunkRef should exist for chunk")
}

#[test]
fn subplans_partition_version_and_order_are_deterministic() {
    let manifest_a = build_test_manifest();
    let manifest_b = build_test_manifest();

    let chunk_ref_a = chunk_ref(&manifest_a, "0_0");
    let chunk_ref_b = chunk_ref(&manifest_b, "0_0");

    assert_eq!(chunk_ref_a.partition_version, "subplans.v1");
    assert_eq!(chunk_ref_a.partition_version, chunk_ref_b.partition_version);

    let ordered_layers_a: Vec<_> = chunk_ref_a
        .subplans
        .iter()
        .map(|subplan| {
            (
                subplan.id.clone(),
                subplan.layer.clone(),
            )
        })
        .collect();
    let ordered_layers_b: Vec<_> = chunk_ref_b
        .subplans
        .iter()
        .map(|subplan| {
            (
                subplan.id.clone(),
                subplan.layer.clone(),
            )
        })
        .collect();

    assert_eq!(
        ordered_layers_a,
        vec![
            ("terrain".to_string(), "terrain".to_string()),
            ("landuse".to_string(), "landuse".to_string()),
            ("roads".to_string(), "roads".to_string()),
            ("buildings".to_string(), "buildings".to_string()),
            ("water".to_string(), "water".to_string()),
            ("props".to_string(), "props".to_string()),
        ]
    );
    assert_eq!(ordered_layers_a, ordered_layers_b);
}

#[test]
fn subplans_layer_feature_counts_and_streaming_costs_match_canonical_chunk_contents() {
    let manifest = build_test_manifest();
    let chunk_ref = chunk_ref(&manifest, "0_0");

    let per_layer: Vec<_> = chunk_ref
        .subplans
        .iter()
        .map(|subplan| {
            (
                subplan.layer.clone(),
                subplan.feature_count as u64,
                subplan.streaming_cost,
            )
        })
        .collect();

    assert_eq!(
        per_layer,
        vec![
            ("terrain".to_string(), 1, 8.0),
            ("landuse".to_string(), 1, 6.0),
            ("roads".to_string(), 1, 4.0),
            ("buildings".to_string(), 1, 12.0),
            ("water".to_string(), 1, 2.0),
            ("props".to_string(), 1, 1.0),
        ]
    );
}

#[test]
fn subplans_emission_preserves_canonical_counts_identity_and_semantics() {
    let manifest = build_test_manifest();
    let chunks = &manifest.chunks;
    assert_eq!(chunks.len(), 1);

    let chunk = &chunks[0];
    assert!(chunk.terrain.is_some(), "terrain should remain canonical");
    assert_eq!(chunk.roads.len(), 1);
    assert_eq!(chunk.buildings.len(), 1);
    assert_eq!(chunk.water.len(), 1);
    assert_eq!(chunk.props.len(), 1);
    assert_eq!(chunk.landuse.len(), 1);

    assert_eq!(chunk.roads[0].id, "road_main");
    assert_eq!(chunk.buildings[0].id, "building_main");
    assert_eq!(chunk.water[0].id, "water_pond");
    assert_eq!(chunk.props[0].id, "tree_oak");
    assert_eq!(chunk.landuse[0].id, "park_green");

    assert_eq!(
        chunk.water[0].holes.len(),
        1,
        "water holes should remain intact"
    );
    assert_eq!(
        chunk.landuse[0].material,
        "Grass",
        "landuse material semantics should remain intact"
    );
    assert_eq!(
        chunk.buildings[0].roof_material.as_deref(),
        Some("Slate"),
        "building material semantics should remain intact"
    );

    let canonical_json: serde_json::Value =
        serde_json::from_str(&manifest.to_json_pretty()).expect("manifest JSON should parse");
    assert!(
        canonical_json.get("chunkRefs").is_some(),
        "compiled JSON artifact should export additive chunkRefs metadata for the current pipeline"
    );
    assert_eq!(
        canonical_json["chunkRefs"][0]["partitionVersion"],
        "subplans.v1"
    );
    assert!(
        canonical_json["chunkRefs"][0].get("shards").is_none(),
        "compile-time JSON chunkRefs should not serialize Lua shard names"
    );

    let chunk_ref = chunk_ref(&manifest, "0_0");
    assert_eq!(chunk_ref.partition_version, "subplans.v1");
}

#[test]
fn subplans_chunk_ref_aggregate_hints_cover_authored_chunk_content_even_when_subplans_omit_layers() {
    let manifest = build_test_manifest_with_rails_and_barriers();
    let chunk_ref = chunk_ref(&manifest, "0_0");

    let feature_count_from_subplans: usize =
        chunk_ref.subplans.iter().map(|subplan| subplan.feature_count).sum();
    let streaming_cost_from_subplans: f64 =
        chunk_ref.subplans.iter().map(|subplan| subplan.streaming_cost).sum();

    assert_eq!(chunk_ref.feature_count, 4);
    assert_eq!(chunk_ref.streaming_cost, 17.0);
    assert!(
        chunk_ref.feature_count > feature_count_from_subplans,
        "chunkRef featureCount should remain an aggregate authored-content hint"
    );
    assert!(
        chunk_ref.streaming_cost > streaming_cost_from_subplans,
        "chunkRef streamingCost should remain an aggregate authored-content hint"
    );

    let ordered_layers: Vec<_> = chunk_ref
        .subplans
        .iter()
        .map(|subplan| subplan.layer.as_str())
        .collect();
    assert_eq!(
        ordered_layers,
        vec!["terrain", "landuse", "roads", "buildings", "water", "props"],
        "coarse-subplan contract should not grow new rails/barriers layers in v1"
    );
}
