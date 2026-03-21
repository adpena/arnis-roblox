use arbx_geo::{BoundingBox, FlatElevationProvider, Footprint, LatLon, Vec2, Vec3};
use arbx_pipeline::{
    BuildingFeature, Feature, LanduseFeature, PropFeature, RoadFeature, WaterFeature,
    WaterPolygonFeature,
};
use arbx_roblox_export::chunker::Chunker;
use arbx_roblox_export::manifest::ManifestMeta;
use arbx_roblox_export::materials::StyleMapper;

fn build_test_manifest_json() -> serde_json::Value {
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

    let manifest = chunker.finish(ManifestMeta {
        world_name: "SubplanFixture".to_string(),
        generator: "subplans-test".to_string(),
        source: "synthetic".to_string(),
        meters_per_stud: 0.3,
        chunk_size_studs: 256,
        bbox: BoundingBox::new(30.2670, -97.7440, 30.2680, -97.7430),
        total_features: 5,
        notes: vec!["subplan fixture".to_string()],
    });

    serde_json::from_str(&manifest.to_json_pretty()).expect("manifest JSON should parse")
}

fn chunk_ref<'a>(manifest: &'a serde_json::Value, chunk_id: &str) -> &'a serde_json::Value {
    manifest["chunkRefs"]
        .as_array()
        .expect("manifest should include chunkRefs")
        .iter()
        .find(|entry| entry["id"] == chunk_id)
        .expect("chunkRef should exist for chunk")
}

#[test]
fn subplans_partition_version_and_order_are_deterministic() {
    let manifest_a = build_test_manifest_json();
    let manifest_b = build_test_manifest_json();

    let chunk_ref_a = chunk_ref(&manifest_a, "0_0");
    let chunk_ref_b = chunk_ref(&manifest_b, "0_0");

    assert_eq!(chunk_ref_a["partitionVersion"], "subplans.v1");
    assert_eq!(chunk_ref_a["partitionVersion"], chunk_ref_b["partitionVersion"]);

    let subplans_a = chunk_ref_a["subplans"]
        .as_array()
        .expect("chunkRef should include ordered coarse subplans");
    let subplans_b = chunk_ref_b["subplans"]
        .as_array()
        .expect("chunkRef should include ordered coarse subplans");

    let ordered_layers_a: Vec<_> = subplans_a
        .iter()
        .map(|subplan| {
            (
                subplan["id"].as_str().unwrap().to_string(),
                subplan["layer"].as_str().unwrap().to_string(),
            )
        })
        .collect();
    let ordered_layers_b: Vec<_> = subplans_b
        .iter()
        .map(|subplan| {
            (
                subplan["id"].as_str().unwrap().to_string(),
                subplan["layer"].as_str().unwrap().to_string(),
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
    let manifest = build_test_manifest_json();
    let chunk_ref = chunk_ref(&manifest, "0_0");
    let subplans = chunk_ref["subplans"]
        .as_array()
        .expect("chunkRef should include subplans");

    let per_layer: Vec<_> = subplans
        .iter()
        .map(|subplan| {
            (
                subplan["layer"].as_str().unwrap().to_string(),
                subplan["featureCount"].as_u64().unwrap(),
                subplan["streamingCost"].as_f64().unwrap(),
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
    let manifest = build_test_manifest_json();
    let chunks = manifest["chunks"]
        .as_array()
        .expect("manifest should include chunks");
    assert_eq!(chunks.len(), 1);

    let chunk = &chunks[0];
    assert!(chunk.get("terrain").is_some(), "terrain should remain canonical");
    assert_eq!(chunk["roads"].as_array().unwrap().len(), 1);
    assert_eq!(chunk["buildings"].as_array().unwrap().len(), 1);
    assert_eq!(chunk["water"].as_array().unwrap().len(), 1);
    assert_eq!(chunk["props"].as_array().unwrap().len(), 1);
    assert_eq!(chunk["landuse"].as_array().unwrap().len(), 1);

    assert_eq!(chunk["roads"][0]["id"], "road_main");
    assert_eq!(chunk["buildings"][0]["id"], "building_main");
    assert_eq!(chunk["water"][0]["id"], "water_pond");
    assert_eq!(chunk["props"][0]["id"], "tree_oak");
    assert_eq!(chunk["landuse"][0]["id"], "park_green");

    assert_eq!(
        chunk["water"][0]["holes"].as_array().unwrap().len(),
        1,
        "water holes should remain intact"
    );
    assert_eq!(
        chunk["landuse"][0]["material"],
        "Grass",
        "landuse material semantics should remain intact"
    );
    assert_eq!(
        chunk["buildings"][0]["roofMaterial"],
        "Slate",
        "building material semantics should remain intact"
    );

    let chunk_ref = chunk_ref(&manifest, "0_0");
    assert_eq!(chunk_ref["partitionVersion"], "subplans.v1");
}
