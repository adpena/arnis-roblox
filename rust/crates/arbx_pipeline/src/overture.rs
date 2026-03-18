use crate::{BuildingFeature, Feature};
use arbx_geo::{BoundingBox, Footprint, LatLon, Mercator, Vec2};
use std::fs;

/// Load building features from an Overture Maps GeoJSON file.
///
/// Returns an empty vec (without error) if the file doesn't exist — the caller
/// treats Overture data as optional enrichment on top of OSM.
pub fn load_overture_buildings(
    path: &str,
    bbox: BoundingBox,
    meters_per_stud: f64,
) -> Vec<Feature> {
    let Ok(text) = fs::read_to_string(path) else {
        return vec![];
    };
    let Ok(geojson): Result<serde_json::Value, _> = serde_json::from_str(&text) else {
        return vec![];
    };

    let center = bbox.center();
    let lat_margin = bbox.height_degrees() * 0.1;
    let lon_margin = bbox.width_degrees() * 0.1;
    let clip_bbox = bbox.expanded(lat_margin.max(lon_margin));

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

        let Some(coords_outer) = geom
            .get("coordinates")
            .and_then(|c| c.as_array())
            .and_then(|rings| rings.first())
            .and_then(|ring| ring.as_array())
        else {
            continue;
        };

        let projected: Vec<Vec2> = coords_outer
            .iter()
            .filter_map(|pt| {
                let arr = pt.as_array()?;
                let lon = arr.first()?.as_f64()?;
                let lat = arr.get(1)?.as_f64()?;
                let ll = LatLon::new(lat, lon);
                if !clip_bbox.contains(ll) {
                    return None;
                }
                let p = Mercator::project(ll, center, meters_per_stud);
                Some(Vec2::new(p.x, p.z))
            })
            .collect();

        if projected.len() < 3 {
            continue;
        }

        let levels = props
            .get("num_floors")
            .and_then(|l| l.as_u64())
            .map(|l| l as u32);
        let height_m = props
            .get("height")
            .and_then(|h| h.as_f64())
            .map(|h| h as f64);
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
            "commercial" => "commercial",
            "industrial" => "industrial",
            "office" => "office",
            "education" => "school",
            "medical" => "hospital",
            "religious" => "religious",
            "civic" | "government" => "civic",
            _ => "building",
        };

        features.push(Feature::Building(BuildingFeature {
            id: format!("ov_{}", features.len()),
            footprint: Footprint::new(projected),
            indices: None,
            base_y: 0.0,
            height,
            height_m,
            levels,
            roof_levels: None,
            min_height: None,
            usage: Some(usage.to_string()),
            roof: "flat".to_string(),
            colour: None,
            material_tag: None,
        }));
    }

    features
}
