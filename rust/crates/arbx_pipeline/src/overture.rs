use crate::{
    clip_polygon_to_rect, infer_roof_shape, projected_bbox_bounds, BuildingFeature, Feature,
};
use arbx_geo::{BoundingBox, Footprint, LatLon, Mercator, Vec2};
use std::fs;
use std::path::{Path, PathBuf};

fn polygon_area(points: &[Vec2], meters_per_stud: f64) -> f64 {
    if points.len() < 3 {
        return 0.0;
    }

    let mut area = 0.0;
    for index in 0..points.len() {
        let current = points[index];
        let next = points[(index + 1) % points.len()];
        area += current.x * next.y - next.x * current.y;
    }
    area.abs() * 0.5 * meters_per_stud * meters_per_stud
}

fn infer_generic_usage(
    projected: &[Vec2],
    height_m: f64,
    levels: Option<u32>,
    meters_per_stud: f64,
) -> &'static str {
    let area_m2 = polygon_area(projected, meters_per_stud);
    let estimated_levels =
        levels.unwrap_or_else(|| (((height_m - 2.0).max(0.0) / 3.5).round() as u32).max(1));

    if estimated_levels >= 8 || height_m >= 28.0 {
        "office"
    } else if area_m2 <= 120.0 && height_m <= 8.0 {
        "residential"
    } else if area_m2 <= 350.0 && estimated_levels <= 3 {
        "apartments"
    } else if area_m2 >= 1_200.0 && estimated_levels <= 2 {
        "industrial"
    } else if area_m2 >= 450.0 && estimated_levels <= 3 {
        "commercial"
    } else if estimated_levels <= 3 {
        "residential"
    } else {
        "building"
    }
}

fn resolve_source_path(base_dir: &Path, path: &str) -> Option<PathBuf> {
    let as_given = PathBuf::from(path);
    if as_given.exists() {
        return Some(as_given);
    }

    let rooted = base_dir.join(path);
    if rooted.exists() {
        return Some(rooted);
    }

    if let Some(stripped) = path.strip_prefix("rust/") {
        let stripped_path = base_dir.join(stripped);
        if stripped_path.exists() {
            return Some(stripped_path);
        }
    } else {
        let rust_prefixed = base_dir.join("rust").join(path);
        if rust_prefixed.exists() {
            return Some(rust_prefixed);
        }
    }

    None
}

fn overture_stable_id(props: &serde_json::Value, fallback_index: usize) -> String {
    let sources_record_id = props
        .get("sources")
        .and_then(|value| value.as_array())
        .and_then(|sources| sources.first())
        .and_then(|source| source.get("record_id"))
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty());

    if let Some(record_id) = sources_record_id {
        return format!("ov_{}", record_id);
    }

    let overture_id = props
        .get("id")
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty());
    if let Some(overture_id) = overture_id {
        return format!("ov_{}", overture_id);
    }

    format!("ov_{}", fallback_index)
}

fn overture_primary_name(props: &serde_json::Value) -> Option<String> {
    props
        .get("names")
        .and_then(|value| value.as_object())
        .and_then(|names| names.get("primary"))
        .and_then(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn overture_ring_from_geojson(ring: &serde_json::Value) -> Option<Vec<LatLon>> {
    let ring = ring.as_array()?;
    let latlon_ring: Vec<LatLon> = ring
        .iter()
        .filter_map(|pt| {
            let arr = pt.as_array()?;
            let lon = arr.first()?.as_f64()?;
            let lat = arr.get(1)?.as_f64()?;
            Some(LatLon::new(lat, lon))
        })
        .collect();
    if latlon_ring.len() < 3 {
        return None;
    }
    Some(latlon_ring)
}

/// Load building features from an Overture Maps GeoJSON file.
///
/// Returns an empty vec (without error) if the file doesn't exist — the caller
/// treats Overture data as optional enrichment on top of OSM.
pub fn load_overture_buildings(
    path: &str,
    bbox: BoundingBox,
    meters_per_stud: f64,
) -> Vec<Feature> {
    let Ok(base_dir) = std::env::current_dir() else {
        return vec![];
    };
    let Some(resolved_path) = resolve_source_path(&base_dir, path) else {
        return vec![];
    };

    let Ok(text) = fs::read_to_string(resolved_path) else {
        return vec![];
    };
    let Ok(geojson): Result<serde_json::Value, _> = serde_json::from_str(&text) else {
        return vec![];
    };

    let center = bbox.center();
    let lat_margin = bbox.height_degrees() * 0.1;
    let lon_margin = bbox.width_degrees() * 0.1;
    let clip_bbox = bbox.expanded(lat_margin.max(lon_margin));
    let projected_bounds = projected_bbox_bounds(bbox, center, meters_per_stud);

    let mut features: Vec<Feature> = Vec::new();

    let Some(fc) = geojson.as_object() else {
        return vec![];
    };
    let Some(arr) = fc.get("features").and_then(|f| f.as_array()) else {
        return vec![];
    };

    for feat in arr {
        let Some(geom) = feat.get("geometry") else {
            continue;
        };
        let Some(props) = feat.get("properties") else {
            continue;
        };

        let geom_type = geom.get("type").and_then(|t| t.as_str()).unwrap_or("");
        if geom_type != "Polygon" {
            continue;
        }

        let Some(rings) = geom.get("coordinates").and_then(|c| c.as_array()) else {
            continue;
        };
        let Some(latlon_ring) = rings.first().and_then(overture_ring_from_geojson) else {
            continue;
        };

        let min_lat = latlon_ring
            .iter()
            .map(|ll| ll.lat)
            .fold(f64::INFINITY, f64::min);
        let max_lat = latlon_ring
            .iter()
            .map(|ll| ll.lat)
            .fold(f64::NEG_INFINITY, f64::max);
        let min_lon = latlon_ring
            .iter()
            .map(|ll| ll.lon)
            .fold(f64::INFINITY, f64::min);
        let max_lon = latlon_ring
            .iter()
            .map(|ll| ll.lon)
            .fold(f64::NEG_INFINITY, f64::max);
        if max_lat < clip_bbox.min.lat
            || min_lat > clip_bbox.max.lat
            || max_lon < clip_bbox.min.lon
            || min_lon > clip_bbox.max.lon
        {
            continue;
        }

        let projected: Vec<Vec2> = latlon_ring
            .iter()
            .map(|&ll| {
                let p = Mercator::project(ll, center, meters_per_stud);
                Vec2::new(p.x, p.z)
            })
            .collect();
        let projected = clip_polygon_to_rect(&projected, projected_bounds);

        if projected.len() < 3 {
            continue;
        }

        let holes: Vec<Footprint> = rings
            .iter()
            .skip(1)
            .filter_map(overture_ring_from_geojson)
            .map(|ring| {
                ring.iter()
                    .map(|&ll| {
                        let p = Mercator::project(ll, center, meters_per_stud);
                        Vec2::new(p.x, p.z)
                    })
                    .collect::<Vec<Vec2>>()
            })
            .map(|ring| clip_polygon_to_rect(&ring, projected_bounds))
            .filter(|ring| ring.len() >= 3)
            .map(Footprint::new)
            .collect();

        let levels = props
            .get("num_floors")
            .and_then(|l| l.as_u64())
            .map(|l| l as u32);
        let height_m = props.get("height").and_then(|h| h.as_f64());
        let height: f64 = height_m.unwrap_or_else(|| {
            let lvl = levels.unwrap_or(1);
            (lvl as f64 * 3.5) + 2.0
        });

        let class = props
            .get("class")
            .and_then(|c| c.as_str())
            .unwrap_or("building");
        let usage = match class {
            "residential" => "residential",
            "apartments" => "apartments",
            "detached" | "house" | "semidetached_house" => "house",
            "commercial" => "commercial",
            "industrial" => "industrial",
            "office" => "office",
            "education" => "school",
            "medical" => "hospital",
            "religious" => "religious",
            "civic" => "civic",
            "government" => "government",
            "retail" => "retail",
            "hotel" => "hotel",
            "parking" => "parking",
            "university" => "university",
            "school" => "school",
            "church" => "church",
            "roof" => "roof",
            _ => infer_generic_usage(&projected, height, levels, meters_per_stud),
        };
        let mut synthetic_tags = std::collections::HashMap::new();
        if let Some(levels) = levels {
            synthetic_tags.insert("building:levels".to_string(), levels.to_string());
        }
        let roof = infer_roof_shape(&synthetic_tags, Some(usage), &projected, meters_per_stud);

        let stable_id = overture_stable_id(props, features.len());
        let primary_name = overture_primary_name(props);

        features.push(Feature::Building(BuildingFeature {
            id: stable_id,
            footprint: Footprint::new(projected),
            holes,
            indices: None,
            base_y: 0.0,
            height,
            height_m,
            levels,
            roof_levels: None,
            min_height: None,
            usage: Some(usage.to_string()),
            roof,
            colour: props
                .get("facade_color")
                .and_then(|value| value.as_str())
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|value| value.to_lowercase()),
            material_tag: props
                .get("facade_material")
                .and_then(|value| value.as_str())
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|value| value.to_lowercase()),
            roof_colour: props
                .get("roof_color")
                .and_then(|value| value.as_str())
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|value| value.to_lowercase()),
            roof_material: props
                .get("roof_material")
                .and_then(|value| value.as_str())
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|value| value.to_lowercase()),
            roof_height: None,
            name: primary_name,
        }));
    }

    features
}

#[cfg(test)]
mod tests {
    use super::{load_overture_buildings, resolve_source_path};
    use crate::Feature;
    use arbx_geo::BoundingBox;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn resolve_source_path_handles_repo_root_and_rust_workdir_layouts() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("duration")
            .as_nanos();
        let repo_root = std::env::temp_dir().join(format!("arbx_pipeline_overture_{unique}"));
        let rust_dir = repo_root.join("rust");
        let data_dir = rust_dir.join("data");
        fs::create_dir_all(&data_dir).expect("create data dir");
        let fixture_name = "overture-fixture.geojson";
        let fixture_path = data_dir.join(fixture_name);
        fs::write(&fixture_path, "{}").expect("write fixture");

        let from_root = resolve_source_path(&repo_root, &format!("rust/data/{fixture_name}"))
            .expect("should resolve from repo root");
        let from_rust = resolve_source_path(&rust_dir, &format!("rust/data/{fixture_name}"))
            .expect("should resolve from rust cwd");

        assert_eq!(from_root, fixture_path);
        assert_eq!(from_rust, fixture_path);

        fs::remove_file(&fixture_path).ok();
        fs::remove_dir_all(&repo_root).ok();
    }

    #[test]
    fn overture_unknown_class_lowrise_building_gets_residential_fallbacks() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("duration")
            .as_nanos();
        let repo_root = std::env::temp_dir().join(format!("arbx_pipeline_overture_usage_{unique}"));
        let rust_dir = repo_root.join("rust");
        let data_dir = rust_dir.join("data");
        fs::create_dir_all(&data_dir).expect("create data dir");
        let fixture_path = data_dir.join("overture.geojson");
        fs::write(
            &fixture_path,
            serde_json::json!({
                "type": "FeatureCollection",
                "features": [{
                    "type": "Feature",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[
                            [-97.7500, 30.2700],
                            [-97.74995, 30.2700],
                            [-97.74995, 30.26995],
                            [-97.7500, 30.26995],
                            [-97.7500, 30.2700]
                        ]]
                    },
                    "properties": {
                        "height": 7.0
                    }
                }]
            })
            .to_string(),
        )
        .expect("write fixture");

        let features = load_overture_buildings(
            fixture_path.to_str().expect("fixture path to str"),
            BoundingBox::new(30.245, -97.765, 30.305, -97.715),
            1.0,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.usage.as_deref(), Some("residential"));
        assert_eq!(building.roof, "gabled");

        fs::remove_file(&fixture_path).ok();
        fs::remove_dir_all(&repo_root).ok();
    }

    #[test]
    fn overture_apartments_default_to_flat_roofs() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("duration")
            .as_nanos();
        let repo_root =
            std::env::temp_dir().join(format!("arbx_pipeline_overture_apartments_{unique}"));
        let rust_dir = repo_root.join("rust");
        let data_dir = rust_dir.join("data");
        fs::create_dir_all(&data_dir).expect("create data dir");
        let fixture_path = data_dir.join("overture.geojson");
        fs::write(
            &fixture_path,
            serde_json::json!({
                "type": "FeatureCollection",
                "features": [{
                    "type": "Feature",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[
                            [-97.7500, 30.2700],
                            [-97.74970, 30.2700],
                            [-97.74970, 30.26980],
                            [-97.7500, 30.26980],
                            [-97.7500, 30.2700]
                        ]]
                    },
                    "properties": {
                        "class": "apartments",
                        "height": 7.0
                    }
                }]
            })
            .to_string(),
        )
        .expect("write fixture");

        let features = load_overture_buildings(
            fixture_path.to_str().expect("fixture path to str"),
            BoundingBox::new(30.245, -97.765, 30.305, -97.715),
            1.0,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.usage.as_deref(), Some("apartments"));
        assert_eq!(building.roof, "flat");

        fs::remove_file(&fixture_path).ok();
        fs::remove_dir_all(&repo_root).ok();
    }

    #[test]
    fn overture_preserves_source_backed_id_and_primary_name() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("duration")
            .as_nanos();
        let repo_root =
            std::env::temp_dir().join(format!("arbx_pipeline_overture_identity_{unique}"));
        let rust_dir = repo_root.join("rust");
        let data_dir = rust_dir.join("data");
        fs::create_dir_all(&data_dir).expect("create data dir");
        let fixture_path = data_dir.join("overture.geojson");
        fs::write(
            &fixture_path,
            serde_json::json!({
                "type": "FeatureCollection",
                "features": [{
                    "type": "Feature",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[
                            [-97.7500, 30.2700],
                            [-97.74980, 30.2700],
                            [-97.74980, 30.26980],
                            [-97.7500, 30.26980],
                            [-97.7500, 30.2700]
                        ]]
                    },
                    "properties": {
                        "id": "0f5209b1-5016-43f0-b85c-8c5b972c3382",
                        "names": {"primary": "Texas State Capitol"},
                        "sources": [{"record_id": "w25758443@23"}],
                        "class": "government",
                        "height": 35.0,
                        "has_parts": true
                    }
                }]
            })
            .to_string(),
        )
        .expect("write fixture");

        let features = load_overture_buildings(
            fixture_path.to_str().expect("fixture path to str"),
            BoundingBox::new(30.245, -97.765, 30.305, -97.715),
            1.0,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.id, "ov_w25758443@23");
        assert_eq!(building.name.as_deref(), Some("Texas State Capitol"));

        fs::remove_file(&fixture_path).ok();
        fs::remove_dir_all(&repo_root).ok();
    }

    #[test]
    fn overture_preserves_government_usage_and_material_signals() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("duration")
            .as_nanos();
        let repo_root =
            std::env::temp_dir().join(format!("arbx_pipeline_overture_materials_{unique}"));
        let rust_dir = repo_root.join("rust");
        let data_dir = rust_dir.join("data");
        fs::create_dir_all(&data_dir).expect("create data dir");
        let fixture_path = data_dir.join("overture.geojson");
        fs::write(
            &fixture_path,
            serde_json::json!({
                "type": "FeatureCollection",
                "features": [{
                    "type": "Feature",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[
                            [-97.7500, 30.2700],
                            [-97.74980, 30.2700],
                            [-97.74980, 30.26980],
                            [-97.7500, 30.26980],
                            [-97.7500, 30.2700]
                        ]]
                    },
                    "properties": {
                        "id": "0f5209b1-5016-43f0-b85c-8c5b972c3382",
                        "names": {"primary": "Texas State Capitol"},
                        "class": "government",
                        "height": 35.0,
                        "facade_color": "#BB9B86",
                        "facade_material": "stone",
                        "roof_color": "#BB9B86",
                        "roof_material": "copper"
                    }
                }]
            })
            .to_string(),
        )
        .expect("write fixture");

        let features = load_overture_buildings(
            fixture_path.to_str().expect("fixture path to str"),
            BoundingBox::new(30.245, -97.765, 30.305, -97.715),
            1.0,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.usage.as_deref(), Some("government"));
        assert_eq!(building.material_tag.as_deref(), Some("stone"));
        assert_eq!(building.roof_material.as_deref(), Some("copper"));
        assert_eq!(building.colour.as_deref(), Some("#bb9b86"));
        assert_eq!(building.roof_colour.as_deref(), Some("#bb9b86"));

        fs::remove_file(&fixture_path).ok();
        fs::remove_dir_all(&repo_root).ok();
    }

    #[test]
    fn overture_preserves_inner_rings_as_building_holes() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("duration")
            .as_nanos();
        let repo_root = std::env::temp_dir().join(format!("arbx_pipeline_overture_holes_{unique}"));
        let rust_dir = repo_root.join("rust");
        let data_dir = rust_dir.join("data");
        fs::create_dir_all(&data_dir).expect("create data dir");
        let fixture_path = data_dir.join("overture.geojson");
        fs::write(
            &fixture_path,
            serde_json::json!({
                "type": "FeatureCollection",
                "features": [{
                    "type": "Feature",
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [
                            [
                                [-97.7500, 30.2700],
                                [-97.7496, 30.2700],
                                [-97.7496, 30.2696],
                                [-97.7500, 30.2696],
                                [-97.7500, 30.2700]
                            ],
                            [
                                [-97.7499, 30.2699],
                                [-97.7497, 30.2699],
                                [-97.7497, 30.2697],
                                [-97.7499, 30.2697],
                                [-97.7499, 30.2699]
                            ]
                        ]
                    },
                    "properties": {
                        "class": "government",
                        "height": 20.0
                    }
                }]
            })
            .to_string(),
        )
        .expect("write fixture");

        let features = load_overture_buildings(
            fixture_path.to_str().expect("fixture path to str"),
            BoundingBox::new(30.245, -97.765, 30.305, -97.715),
            1.0,
        );

        let building = features
            .into_iter()
            .find_map(|feature| match feature {
                Feature::Building(building) => Some(building),
                _ => None,
            })
            .expect("expected building feature");

        assert_eq!(building.holes.len(), 1);
        assert!(building.holes[0].points.len() >= 4);

        fs::remove_file(&fixture_path).ok();
        fs::remove_dir_all(&repo_root).ok();
    }
}
