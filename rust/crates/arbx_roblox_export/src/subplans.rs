use arbx_geo::Vec3;

use crate::manifest::Chunk;

pub const PARTITION_VERSION: &str = "subplans.v1";

const TERRAIN_STREAMING_COST: f64 = 8.0;
const LANDUSE_STREAMING_COST: f64 = 6.0;
const ROAD_STREAMING_COST: f64 = 4.0;
const BUILDING_STREAMING_COST: f64 = 12.0;
const WATER_STREAMING_COST: f64 = 2.0;
const PROP_STREAMING_COST: f64 = 1.0;

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
    vec![
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
            id: "landuse".to_string(),
            layer: "landuse".to_string(),
            feature_count: chunk.landuse.len(),
            streaming_cost: chunk.landuse.len() as f64 * LANDUSE_STREAMING_COST,
            bounds: None,
        },
        ChunkSubplan {
            id: "roads".to_string(),
            layer: "roads".to_string(),
            feature_count: chunk.roads.len(),
            streaming_cost: chunk.roads.len() as f64 * ROAD_STREAMING_COST,
            bounds: None,
        },
        ChunkSubplan {
            id: "buildings".to_string(),
            layer: "buildings".to_string(),
            feature_count: chunk.buildings.len(),
            streaming_cost: chunk.buildings.len() as f64 * BUILDING_STREAMING_COST,
            bounds: None,
        },
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
    ]
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
