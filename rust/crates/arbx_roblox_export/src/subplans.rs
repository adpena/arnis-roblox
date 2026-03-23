use arbx_geo::Vec3;

use crate::manifest::Chunk;

pub const PARTITION_VERSION: &str = "subplans.v1";

const TERRAIN_STREAMING_COST: f64 = 8.0;
const LANDUSE_STREAMING_COST: f64 = 6.0;
const ROAD_STREAMING_COST: f64 = 4.0;
const BUILDING_STREAMING_COST: f64 = 12.0;
const WATER_STREAMING_COST: f64 = 2.0;
const PROP_STREAMING_COST: f64 = 1.0;
const BUILDING_SPATIAL_SPLIT_THRESHOLD: usize = 8;
const LANDUSE_SPATIAL_SPLIT_AREA_THRESHOLD: f64 = 16_384.0;
const LANDUSE_SPATIAL_SPLIT_MAX_DEPTH: usize = 2;

#[derive(Clone, Copy)]
struct Bounds2D {
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubplanBounds {
    pub min_x: f64,
    pub min_y: f64,
    pub max_x: f64,
    pub max_y: f64,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChunkSubplan {
    pub id: String,
    pub layer: String,
    pub feature_count: usize,
    pub streaming_cost: f64,
    pub bounds: Option<SubplanBounds>,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChunkRef {
    pub id: String,
    pub origin_studs: Vec3,
    pub feature_count: usize,
    pub streaming_cost: f64,
    pub partition_version: String,
    pub subplans: Vec<ChunkSubplan>,
}

pub fn derive_chunk_ref(chunk: &Chunk) -> ChunkRef {
    let subplans = derive_coarse_subplans(chunk);
    ChunkRef {
        id: chunk.id.label(),
        origin_studs: chunk.origin_studs,
        feature_count: chunk_feature_count(chunk),
        streaming_cost: chunk_streaming_cost(chunk),
        partition_version: PARTITION_VERSION.to_string(),
        subplans,
    }
}

pub fn derive_coarse_subplans(chunk: &Chunk) -> Vec<ChunkSubplan> {
    let mut subplans = vec![
        ChunkSubplan {
            id: "terrain".to_string(),
            layer: "terrain".to_string(),
            feature_count: usize::from(chunk.terrain.is_some()),
            streaming_cost: if chunk.terrain.is_some() {
                TERRAIN_STREAMING_COST
            } else {
                0.0
            },
            bounds: None,
        },
        ChunkSubplan {
            id: "roads".to_string(),
            layer: "roads".to_string(),
            feature_count: chunk.roads.len(),
            streaming_cost: chunk.roads.len() as f64 * ROAD_STREAMING_COST,
            bounds: None,
        },
    ];

    let landuse_subplans = derive_landuse_subplans(chunk);
    if landuse_subplans.is_empty() {
        subplans.insert(
            1,
            ChunkSubplan {
                id: "landuse".to_string(),
                layer: "landuse".to_string(),
                feature_count: chunk.landuse.len(),
                streaming_cost: chunk.landuse.len() as f64 * LANDUSE_STREAMING_COST,
                bounds: None,
            },
        );
    } else {
        for (index, subplan) in landuse_subplans.into_iter().enumerate() {
            subplans.insert(1 + index, subplan);
        }
    }

    let building_subplans = derive_building_subplans(chunk);
    if building_subplans.is_empty() {
        subplans.push(ChunkSubplan {
            id: "buildings".to_string(),
            layer: "buildings".to_string(),
            feature_count: chunk.buildings.len(),
            streaming_cost: chunk.buildings.len() as f64 * BUILDING_STREAMING_COST,
            bounds: None,
        });
    } else {
        subplans.extend(building_subplans);
    }

    subplans.extend([
        ChunkSubplan {
            id: "water".to_string(),
            layer: "water".to_string(),
            feature_count: chunk.water.len(),
            streaming_cost: chunk.water.len() as f64 * WATER_STREAMING_COST,
            bounds: None,
        },
        ChunkSubplan {
            id: "props".to_string(),
            layer: "props".to_string(),
            feature_count: chunk.props.len(),
            streaming_cost: chunk.props.len() as f64 * PROP_STREAMING_COST,
            bounds: None,
        },
    ]);

    subplans
}

fn derive_landuse_subplans(chunk: &Chunk) -> Vec<ChunkSubplan> {
    if chunk.landuse.is_empty() {
        return Vec::new();
    }

    let mut should_split = false;
    let mut min_x = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut min_z = f64::INFINITY;
    let mut max_z = f64::NEG_INFINITY;

    for landuse in &chunk.landuse {
        let Some((feature_min_x, feature_min_z, feature_max_x, feature_max_z)) =
            ground_point_bounds(&landuse.footprint)
        else {
            continue;
        };
        min_x = min_x.min(feature_min_x);
        min_z = min_z.min(feature_min_z);
        max_x = max_x.max(feature_max_x);
        max_z = max_z.max(feature_max_z);

        if polygon_area(&landuse.footprint) >= LANDUSE_SPATIAL_SPLIT_AREA_THRESHOLD {
            should_split = true;
        }
    }

    if !should_split || min_x == f64::INFINITY || min_z == f64::INFINITY {
        return Vec::new();
    }

    let mut subplans = Vec::new();
    let bounds = Bounds2D {
        min_x,
        min_y: min_z,
        max_x,
        max_y: max_z,
    };
    push_landuse_quadrants(chunk, "landuse", bounds, 0, &mut subplans);
    subplans
}

fn push_landuse_quadrants(
    chunk: &Chunk,
    id_prefix: &str,
    bounds: Bounds2D,
    depth: usize,
    subplans: &mut Vec<ChunkSubplan>,
) {
    let split_x = (bounds.min_x + bounds.max_x) * 0.5;
    let split_y = (bounds.min_y + bounds.max_y) * 0.5;
    let quadrants = [
        (
            "nw",
            Bounds2D {
                min_x: bounds.min_x,
                min_y: split_y,
                max_x: split_x,
                max_y: bounds.max_y,
            },
        ),
        (
            "ne",
            Bounds2D {
                min_x: split_x,
                min_y: split_y,
                max_x: bounds.max_x,
                max_y: bounds.max_y,
            },
        ),
        (
            "sw",
            Bounds2D {
                min_x: bounds.min_x,
                min_y: bounds.min_y,
                max_x: split_x,
                max_y: split_y,
            },
        ),
        (
            "se",
            Bounds2D {
                min_x: split_x,
                min_y: bounds.min_y,
                max_x: bounds.max_x,
                max_y: split_y,
            },
        ),
    ];

    for (suffix, child_bounds) in quadrants {
        let child_id = format!("{id_prefix}:{suffix}");
        push_landuse_subplan(chunk, &child_id, child_bounds, depth + 1, subplans);
    }
}

fn push_landuse_subplan(
    chunk: &Chunk,
    id: &str,
    bounds: Bounds2D,
    depth: usize,
    subplans: &mut Vec<ChunkSubplan>,
) {
    let feature_count = chunk
        .landuse
        .iter()
        .filter(|landuse| {
            ground_point_bounds(&landuse.footprint).is_some_and(
                |(feature_min_x, feature_min_z, feature_max_x, feature_max_z)| {
                    rects_intersect(
                        Bounds2D {
                            min_x: feature_min_x,
                            min_y: feature_min_z,
                            max_x: feature_max_x,
                            max_y: feature_max_z,
                        },
                        bounds,
                    )
                },
            )
        })
        .count();

    if feature_count == 0 {
        return;
    }

    let bounds_area = (bounds.max_x - bounds.min_x).abs() * (bounds.max_y - bounds.min_y).abs();
    if depth < LANDUSE_SPATIAL_SPLIT_MAX_DEPTH
        && bounds_area > LANDUSE_SPATIAL_SPLIT_AREA_THRESHOLD
        && (bounds.max_x - bounds.min_x).abs() > 1e-6
        && (bounds.max_y - bounds.min_y).abs() > 1e-6
    {
        push_landuse_quadrants(chunk, id, bounds, depth, subplans);
        return;
    }

    subplans.push(ChunkSubplan {
        id: id.to_string(),
        layer: "landuse".to_string(),
        feature_count,
        streaming_cost: feature_count as f64 * LANDUSE_STREAMING_COST,
        bounds: Some(SubplanBounds {
            min_x: bounds.min_x,
            min_y: bounds.min_y,
            max_x: bounds.max_x,
            max_y: bounds.max_y,
        }),
    });
}

fn derive_building_subplans(chunk: &Chunk) -> Vec<ChunkSubplan> {
    if chunk.buildings.len() < BUILDING_SPATIAL_SPLIT_THRESHOLD {
        return Vec::new();
    }

    let mut centers = Vec::with_capacity(chunk.buildings.len());
    for building in &chunk.buildings {
        let Some((center_x, center_z)) = building_center(building) else {
            return Vec::new();
        };
        centers.push((center_x, center_z));
    }

    let (split_x, split_z) = split_planes(&centers);
    let mut buckets = [0usize; 4];
    for (center_x, center_z) in &centers {
        buckets[quadrant_index(*center_x, *center_z, split_x, split_z)] += 1;
    }

    let min_x = centers
        .iter()
        .map(|(x, _)| *x)
        .fold(f64::INFINITY, f64::min);
    let max_x = centers
        .iter()
        .map(|(x, _)| *x)
        .fold(f64::NEG_INFINITY, f64::max);
    let min_z = centers
        .iter()
        .map(|(_, z)| *z)
        .fold(f64::INFINITY, f64::min);
    let max_z = centers
        .iter()
        .map(|(_, z)| *z)
        .fold(f64::NEG_INFINITY, f64::max);
    let pad = 0.001_f64;
    let quadrants = [
        ("buildings:nw", min_x - pad, split_x, split_z, max_z + pad),
        ("buildings:ne", split_x, max_x + pad, split_z, max_z + pad),
        ("buildings:sw", min_x - pad, split_x, min_z - pad, split_z),
        ("buildings:se", split_x, max_x + pad, min_z - pad, split_z),
    ];

    quadrants
        .into_iter()
        .zip(buckets)
        .filter_map(|((id, min_x, max_x, min_y, max_y), count)| {
            if count == 0 {
                return None;
            }

            Some(ChunkSubplan {
                id: id.to_string(),
                layer: "buildings".to_string(),
                feature_count: count,
                streaming_cost: count as f64 * BUILDING_STREAMING_COST,
                bounds: Some(SubplanBounds {
                    min_x,
                    min_y,
                    max_x,
                    max_y,
                }),
            })
        })
        .collect()
}

fn ground_point_bounds(points: &[crate::manifest::GroundPoint]) -> Option<(f64, f64, f64, f64)> {
    if points.is_empty() {
        return None;
    }

    let mut min_x = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut min_z = f64::INFINITY;
    let mut max_z = f64::NEG_INFINITY;
    for point in points {
        min_x = min_x.min(point.x);
        max_x = max_x.max(point.x);
        min_z = min_z.min(point.z);
        max_z = max_z.max(point.z);
    }

    Some((min_x, min_z, max_x, max_z))
}

fn polygon_area(points: &[crate::manifest::GroundPoint]) -> f64 {
    if points.len() < 3 {
        return 0.0;
    }

    let mut area = 0.0;
    for index in 0..points.len() {
        let current = &points[index];
        let next = &points[(index + 1) % points.len()];
        area += current.x * next.z - next.x * current.z;
    }
    area.abs() * 0.5
}

fn rects_intersect(a: Bounds2D, b: Bounds2D) -> bool {
    a.min_x < b.max_x && a.max_x > b.min_x && a.min_y < b.max_y && a.max_y > b.min_y
}

fn building_center(building: &crate::manifest::BuildingShell) -> Option<(f64, f64)> {
    if building.footprint.is_empty() {
        return None;
    }

    let mut min_x = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut min_z = f64::INFINITY;
    let mut max_z = f64::NEG_INFINITY;
    for point in &building.footprint {
        min_x = min_x.min(point.x);
        max_x = max_x.max(point.x);
        min_z = min_z.min(point.z);
        max_z = max_z.max(point.z);
    }

    Some(((min_x + max_x) * 0.5, (min_z + max_z) * 0.5))
}

fn split_planes(centers: &[(f64, f64)]) -> (f64, f64) {
    let mut xs: Vec<f64> = centers.iter().map(|(x, _)| *x).collect();
    let mut zs: Vec<f64> = centers.iter().map(|(_, z)| *z).collect();
    xs.sort_by(f64::total_cmp);
    zs.sort_by(f64::total_cmp);

    let split_x = midpoint_between(&xs);
    let split_z = midpoint_between(&zs);
    (split_x, split_z)
}

fn midpoint_between(sorted_values: &[f64]) -> f64 {
    let high_index = sorted_values.len() / 2;
    let low_index = high_index.saturating_sub(1);
    let low = sorted_values[low_index];
    let high = sorted_values[high_index];
    if low == high {
        low
    } else {
        (low + high) * 0.5
    }
}

fn quadrant_index(center_x: f64, center_z: f64, split_x: f64, split_z: f64) -> usize {
    let east = center_x >= split_x;
    let north = center_z >= split_z;
    match (north, east) {
        (true, false) => 0,
        (true, true) => 1,
        (false, false) => 2,
        (false, true) => 3,
    }
}

fn chunk_feature_count(chunk: &Chunk) -> usize {
    chunk.roads.len()
        + chunk.rails.len()
        + chunk.buildings.len()
        + chunk.water.len()
        + chunk.props.len()
        + chunk.landuse.len()
        + chunk.barriers.len()
        + usize::from(chunk.terrain.is_some())
}

fn chunk_streaming_cost(chunk: &Chunk) -> f64 {
    chunk.roads.len() as f64 * ROAD_STREAMING_COST
        + chunk.rails.len() as f64 * 3.0
        + chunk.buildings.len() as f64 * BUILDING_STREAMING_COST
        + chunk.water.len() as f64 * WATER_STREAMING_COST
        + chunk.props.len() as f64 * PROP_STREAMING_COST
        + chunk.landuse.len() as f64 * LANDUSE_STREAMING_COST
        + chunk.barriers.len() as f64 * 2.0
        + if chunk.terrain.is_some() {
            TERRAIN_STREAMING_COST
        } else {
            0.0
        }
}
