//! Integration tests for the full export pipeline

use arbx_geo::{BoundingBox, FlatElevationProvider};
use arbx_pipeline::{Feature, NormalizeStage, TriangulateStage, ValidateStage};
use arbx_roblox_export::{export_to_chunks, ExportConfig};

#[test]
fn full_pipeline_produces_valid_manifest() {
    let bbox = BoundingBox::new(30.26, -97.75, 30.27, -97.74);
    let adapter = arbx_pipeline::SyntheticAustinAdapter {
        meters_per_stud: 0.3,
    };

    let stages = [
        &ValidateStage as &dyn arbx_pipeline::PipelineStage,
        &NormalizeStage as &dyn arbx_pipeline::PipelineStage,
        &TriangulateStage as &dyn arbx_pipeline::PipelineStage,
    ];

    let ctx =
        arbx_pipeline::run_pipeline(&adapter, bbox, &stages).expect("Pipeline should succeed");

    let config = ExportConfig::default();
    let elevation = FlatElevationProvider { height: 0.0 };
    let manifest = export_to_chunks(ctx.features, ctx.bbox, &config, &elevation, None);

    // Verify manifest structure
    assert_eq!(manifest.schema_version, "0.4.0");
    assert!(!manifest.chunks.is_empty());
    assert!(manifest.meta.total_features > 0);

    // Verify at least one chunk has content
    let has_content = manifest.chunks.iter().any(|chunk| {
        chunk.terrain.is_some()
            || !chunk.roads.is_empty()
            || !chunk.buildings.is_empty()
            || !chunk.water.is_empty()
            || !chunk.props.is_empty()
    });
    assert!(has_content, "At least one chunk should have content");
}

#[test]
fn full_pipeline_deterministic_output() {
    let bbox = BoundingBox::new(30.26, -97.75, 30.27, -97.74);
    let adapter = arbx_pipeline::SyntheticAustinAdapter {
        meters_per_stud: 0.3,
    };

    let stages = [
        &ValidateStage as &dyn arbx_pipeline::PipelineStage,
        &NormalizeStage as &dyn arbx_pipeline::PipelineStage,
        &TriangulateStage as &dyn arbx_pipeline::PipelineStage,
    ];

    let config = ExportConfig::default();
    let elevation = FlatElevationProvider { height: 0.0 };

    // Run pipeline twice
    let ctx1 = arbx_pipeline::run_pipeline(&adapter, bbox, &stages).unwrap();
    let manifest1 = export_to_chunks(ctx1.features, ctx1.bbox, &config, &elevation, None);

    let ctx2 = arbx_pipeline::run_pipeline(&adapter, bbox, &stages).unwrap();
    let manifest2 = export_to_chunks(ctx2.features, ctx2.bbox, &config, &elevation, None);

    // Verify deterministic output
    assert_eq!(manifest1.chunks.len(), manifest2.chunks.len());
    assert_eq!(manifest1.meta.total_features, manifest2.meta.total_features);

    for (c1, c2) in manifest1.chunks.iter().zip(manifest2.chunks.iter()) {
        assert_eq!(c1.id, c2.id);
        assert_eq!(c1.origin_studs, c2.origin_studs);
        assert_eq!(c1.roads.len(), c2.roads.len());
        assert_eq!(c1.buildings.len(), c2.buildings.len());
    }
}

#[test]
fn multi_chunk_export_correct() {
    let features = vec![
        Feature::Building(arbx_pipeline::BuildingFeature {
            id: "b1".to_string(),
            footprint: arbx_geo::Footprint::new(vec![
                arbx_geo::Vec2::new(0.0, 0.0),
                arbx_geo::Vec2::new(50.0, 0.0),
                arbx_geo::Vec2::new(50.0, 50.0),
                arbx_geo::Vec2::new(0.0, 50.0),
            ]),
            indices: None,
            base_y: 0.0,
            height: 20.0,
            height_m: None,
            roof: "flat".to_string(),
            levels: Some(2),
            roof_levels: Some(1),
            min_height: None,
            usage: None,
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: None,
        }),
        Feature::Building(arbx_pipeline::BuildingFeature {
            id: "b2".to_string(),
            footprint: arbx_geo::Footprint::new(vec![
                arbx_geo::Vec2::new(300.0, 0.0),
                arbx_geo::Vec2::new(350.0, 0.0),
                arbx_geo::Vec2::new(350.0, 50.0),
                arbx_geo::Vec2::new(300.0, 50.0),
            ]),
            indices: None,
            base_y: 0.0,
            height: 30.0,
            height_m: None,
            roof: "flat".to_string(),
            levels: Some(3),
            roof_levels: Some(1),
            min_height: None,
            usage: None,
            colour: None,
            material_tag: None,
            roof_colour: None,
            roof_material: None,
            roof_height: None,
            name: None,
        }),
    ];

    let config = ExportConfig {
        chunk_size_studs: 256,
        ..Default::default()
    };
    let elevation = FlatElevationProvider { height: 0.0 };
    let bbox = BoundingBox::new(0.0, 0.0, 1.0, 1.0);

    let manifest = export_to_chunks(features, bbox, &config, &elevation, None);

    // Buildings should be in different chunks
    assert!(manifest.chunks.len() >= 2, "Should have at least 2 chunks");

    let mut buildings_in_chunks: Vec<usize> =
        manifest.chunks.iter().map(|c| c.buildings.len()).collect();
    buildings_in_chunks.sort();
    buildings_in_chunks.reverse();

    assert_eq!(
        buildings_in_chunks[0], 1,
        "First chunk should have 1 building"
    );
    assert_eq!(
        buildings_in_chunks[1], 1,
        "Second chunk should have 1 building"
    );
}
