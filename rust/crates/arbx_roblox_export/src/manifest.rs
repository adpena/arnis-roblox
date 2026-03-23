use std::fmt::Write as _;

use arbx_geo::{BoundingBox, ChunkId, Footprint, Vec3};

use crate::subplans::ChunkRef;

#[derive(Debug, Clone, Copy, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Color {
    pub const fn new(r: u8, g: u8, b: u8) -> Self {
        Self { r, g, b }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct GroundPoint {
    pub x: f64,
    pub z: f64,
}

impl GroundPoint {
    pub const fn new(x: f64, z: f64) -> Self {
        Self { x, z }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct TerrainGrid {
    pub cell_size_studs: i32,
    pub width: usize,
    pub depth: usize,
    pub heights: Vec<f64>,
    pub materials: Option<Vec<String>>,
    pub material: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RoadSegment {
    pub id: String,
    pub kind: String,
    pub subkind: Option<String>,
    pub material: String,
    pub color: Option<Color>,
    pub lanes: Option<u32>,
    pub width_studs: f64,
    pub has_sidewalk: bool,
    pub surface: Option<String>,
    pub elevated: bool,
    pub tunnel: bool,
    pub sidewalk: Option<String>,
    pub points: Vec<Vec3>,
    pub maxspeed: Option<u32>,
    pub lit: Option<bool>,
    pub oneway: Option<bool>,
    pub layer: Option<i32>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RailSegment {
    pub id: String,
    pub kind: String,
    pub material: String,
    pub color: Option<Color>,
    pub lanes: Option<u32>,
    pub width_studs: f64,
    pub points: Vec<Vec3>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BuildingShell {
    pub id: String,
    pub footprint: Vec<GroundPoint>,
    pub holes: Vec<Vec<GroundPoint>>,
    pub indices: Option<Vec<usize>>,
    pub material: String,
    pub wall_color: Option<Color>,
    pub roof_color: Option<Color>,
    pub roof_shape: Option<String>,
    pub roof_material: Option<String>,
    pub usage: Option<String>,
    pub min_height: Option<f64>,
    pub base_y: f64,
    pub height: f64,
    pub height_m: Option<f64>,
    pub levels: Option<u32>,
    pub roof_levels: Option<u32>,
    pub roof: String,
    pub facade_style: Option<String>,
    pub rooms: Vec<Room>,
    pub roof_height: Option<f64>,
    pub name: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Room {
    pub id: String,
    pub name: String,
    pub footprint: Vec<GroundPoint>,
    pub floor_y: f64,
    pub height: f64,
    pub wall_material: Option<String>,
    pub floor_material: Option<String>,
    pub has_door: bool,
    pub has_window: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WaterFeature {
    pub id: String,
    pub kind: String,
    pub material: String,
    pub color: Option<Color>,
    pub width_studs: Option<f64>,
    pub points: Option<Vec<Vec3>>,
    pub footprint: Option<Vec<GroundPoint>>,
    pub holes: Vec<Vec<GroundPoint>>,
    pub indices: Option<Vec<usize>>,
    pub surface_y: Option<f64>,
    pub width: Option<f64>,
    pub intermittent: Option<bool>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LanduseShell {
    pub id: String,
    pub kind: String,
    pub material: String,
    pub footprint: Vec<GroundPoint>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PropInstance {
    pub id: String,
    pub kind: String,
    pub position: Vec3,
    pub yaw_degrees: f64,
    pub scale: f64,
    pub species: Option<String>,
    pub height: Option<f64>,
    pub leaf_type: Option<String>,
    pub circumference: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BarrierSegment {
    pub id: String,
    pub kind: String,
    pub points: Vec<Vec3>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ManifestMeta {
    pub world_name: String,
    pub generator: String,
    pub source: String,
    pub meters_per_stud: f64,
    pub chunk_size_studs: i32,
    pub bbox: BoundingBox,
    pub total_features: usize,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Chunk {
    pub id: ChunkId,
    pub origin_studs: Vec3,
    pub terrain: Option<TerrainGrid>,
    pub roads: Vec<RoadSegment>,
    pub rails: Vec<RailSegment>,
    pub buildings: Vec<BuildingShell>,
    pub water: Vec<WaterFeature>,
    pub props: Vec<PropInstance>,
    pub landuse: Vec<LanduseShell>,
    pub barriers: Vec<BarrierSegment>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChunkManifest {
    pub schema_version: String,
    pub meta: ManifestMeta,
    pub chunks: Vec<Chunk>,
    pub chunk_refs: Vec<ChunkRef>,
}

impl ChunkManifest {
    pub fn to_json_pretty(&self) -> String {
        let mut out = String::new();
        self.write_json(&mut out, 0);
        out.push('\n');
        out
    }

    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");

        write_key(out, indent + 2, "schemaVersion");
        write_string(out, &self.schema_version);
        out.push_str(",\n");

        write_key(out, indent + 2, "meta");
        self.write_meta(out, indent + 2);
        out.push_str(",\n");

        write_key(out, indent + 2, "chunks");
        out.push_str("[\n");
        for (i, chunk) in self.chunks.iter().enumerate() {
            chunk.write_json(out, indent + 4);
            if i + 1 != self.chunks.len() {
                out.push(',');
            }
            out.push('\n');
        }
        write_indent(out, indent + 2);
        out.push_str("],\n");

        write_key(out, indent + 2, "chunkRefs");
        out.push_str("[\n");
        for (i, chunk_ref) in self.chunk_refs.iter().enumerate() {
            chunk_ref.write_json(out, indent + 4);
            if i + 1 != self.chunk_refs.len() {
                out.push(',');
            }
            out.push('\n');
        }
        write_indent(out, indent + 2);
        out.push_str("]\n");

        write_indent(out, indent);
        out.push('}');
    }

    fn write_meta(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");

        write_key(out, indent + 2, "worldName");
        write_string(out, &self.meta.world_name);
        out.push_str(",\n");

        write_key(out, indent + 2, "generator");
        write_string(out, &self.meta.generator);
        out.push_str(",\n");

        write_key(out, indent + 2, "source");
        write_string(out, &self.meta.source);
        out.push_str(",\n");

        write_key(out, indent + 2, "metersPerStud");
        write_number(out, self.meta.meters_per_stud);
        out.push_str(",\n");

        write_key(out, indent + 2, "chunkSizeStuds");
        write!(out, "{}", self.meta.chunk_size_studs).unwrap();
        out.push_str(",\n");

        write_key(out, indent + 2, "bbox");
        write_bbox(out, self.meta.bbox, indent + 2);
        out.push_str(",\n");

        write_key(out, indent + 2, "totalFeatures");
        write!(out, "{}", self.meta.total_features).unwrap();
        out.push_str(",\n");

        write_key(out, indent + 2, "notes");
        out.push_str("[\n");
        for (i, note) in self.meta.notes.iter().enumerate() {
            write_indent(out, indent + 4);
            write_string(out, note);
            if i + 1 != self.meta.notes.len() {
                out.push(',');
            }
            out.push('\n');
        }
        write_indent(out, indent + 2);
        out.push_str("]\n");

        write_indent(out, indent);
        out.push('}');
    }
}

impl ChunkRef {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");

        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");

        write_key(out, indent + 2, "originStuds");
        write_vec3(out, self.origin_studs, indent + 2);
        out.push_str(",\n");

        write_key(out, indent + 2, "featureCount");
        write!(out, "{}", self.feature_count).unwrap();
        out.push_str(",\n");

        write_key(out, indent + 2, "streamingCost");
        write_number(out, self.streaming_cost);
        out.push_str(",\n");

        write_key(out, indent + 2, "partitionVersion");
        write_string(out, &self.partition_version);
        out.push_str(",\n");

        write_key(out, indent + 2, "subplans");
        write_array(out, indent + 2, &self.subplans, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl crate::subplans::ChunkSubplan {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");

        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");

        write_key(out, indent + 2, "layer");
        write_string(out, &self.layer);
        out.push_str(",\n");

        write_key(out, indent + 2, "featureCount");
        write!(out, "{}", self.feature_count).unwrap();
        out.push_str(",\n");

        write_key(out, indent + 2, "streamingCost");
        write_number(out, self.streaming_cost);

        if let Some(bounds) = &self.bounds {
            out.push_str(",\n");
            write_key(out, indent + 2, "bounds");
            bounds.write_json(out, indent + 2);
        }

        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl crate::subplans::SubplanBounds {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");

        write_key(out, indent + 2, "minX");
        write_number(out, self.min_x);
        out.push_str(",\n");

        write_key(out, indent + 2, "minY");
        write_number(out, self.min_y);
        out.push_str(",\n");

        write_key(out, indent + 2, "maxX");
        write_number(out, self.max_x);
        out.push_str(",\n");

        write_key(out, indent + 2, "maxY");
        write_number(out, self.max_y);
        out.push('\n');

        write_indent(out, indent);
        out.push('}');
    }
}

impl Chunk {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");

        write_key(out, indent + 2, "id");
        write_string(out, &self.id.label());
        out.push_str(",\n");

        write_key(out, indent + 2, "originStuds");
        write_vec3(out, self.origin_studs, indent + 2);

        if let Some(terrain) = &self.terrain {
            out.push_str(",\n");
            write_key(out, indent + 2, "terrain");
            terrain.write_json(out, indent + 2);
        }

        out.push_str(",\n");
        write_key(out, indent + 2, "roads");
        write_array(out, indent + 2, &self.roads, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push_str(",\n");
        write_key(out, indent + 2, "rails");
        write_array(out, indent + 2, &self.rails, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push_str(",\n");
        write_key(out, indent + 2, "buildings");
        write_array(out, indent + 2, &self.buildings, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push_str(",\n");
        write_key(out, indent + 2, "water");
        write_array(out, indent + 2, &self.water, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push_str(",\n");
        write_key(out, indent + 2, "props");
        write_array(out, indent + 2, &self.props, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push_str(",\n");
        write_key(out, indent + 2, "landuse");
        write_array(out, indent + 2, &self.landuse, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push_str(",\n");
        write_key(out, indent + 2, "barriers");
        write_array(out, indent + 2, &self.barriers, |item, out, indent| {
            item.write_json(out, indent)
        });

        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl BarrierSegment {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "kind");
        write_string(out, &self.kind);
        out.push_str(",\n");
        write_key(out, indent + 2, "points");
        write_vec3_array(out, &self.points, indent + 2);
        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl TerrainGrid {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");

        write_key(out, indent + 2, "cellSizeStuds");
        write!(out, "{}", self.cell_size_studs).unwrap();
        out.push_str(",\n");

        write_key(out, indent + 2, "width");
        write!(out, "{}", self.width).unwrap();
        out.push_str(",\n");

        write_key(out, indent + 2, "depth");
        write!(out, "{}", self.depth).unwrap();
        out.push_str(",\n");

        write_key(out, indent + 2, "heights");
        out.push('[');
        for (i, value) in self.heights.iter().enumerate() {
            write_number(out, *value);
            if i + 1 != self.heights.len() {
                out.push_str(", ");
            }
        }
        out.push_str("],\n");

        if let Some(materials) = &self.materials {
            write_key(out, indent + 2, "materials");
            out.push('[');
            for (i, mat) in materials.iter().enumerate() {
                write_string(out, mat);
                if i + 1 != materials.len() {
                    out.push_str(", ");
                }
            }
            out.push_str("],\n");
        }

        write_key(out, indent + 2, "material");
        write_string(out, &self.material);
        out.push('\n');

        write_indent(out, indent);
        out.push('}');
    }
}

impl RoadSegment {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "kind");
        write_string(out, &self.kind);
        out.push_str(",\n");
        if let Some(ref s) = self.subkind {
            write_key(out, indent + 2, "subkind");
            write_string(out, s);
            out.push_str(",\n");
        }
        write_key(out, indent + 2, "material");
        write_string(out, &self.material);
        if let Some(color) = self.color {
            out.push_str(",\n");
            write_key(out, indent + 2, "color");
            write_color(out, color);
        }
        if let Some(lanes) = self.lanes {
            out.push_str(",\n");
            write_key(out, indent + 2, "lanes");
            write!(out, "{}", lanes).unwrap();
        }
        out.push_str(",\n");
        write_key(out, indent + 2, "widthStuds");
        write_number(out, self.width_studs);
        out.push_str(",\n");
        write_key(out, indent + 2, "hasSidewalk");
        out.push_str(if self.has_sidewalk { "true" } else { "false" });
        if let Some(ref s) = self.surface {
            out.push_str(",\n");
            write_key(out, indent + 2, "surface");
            write_string(out, s);
        }
        if self.elevated {
            out.push_str(",\n");
            write_key(out, indent + 2, "elevated");
            out.push_str("true");
        }
        if self.tunnel {
            out.push_str(",\n");
            write_key(out, indent + 2, "tunnel");
            out.push_str("true");
        }
        if let Some(ref s) = self.sidewalk {
            out.push_str(",\n");
            write_key(out, indent + 2, "sidewalk");
            write_string(out, s);
        }
        if let Some(ms) = self.maxspeed {
            out.push_str(",\n");
            write_key(out, indent + 2, "maxspeed");
            write!(out, "{}", ms).unwrap();
        }
        if let Some(lit) = self.lit {
            out.push_str(",\n");
            write_key(out, indent + 2, "lit");
            out.push_str(if lit { "true" } else { "false" });
        }
        if let Some(oneway) = self.oneway {
            out.push_str(",\n");
            write_key(out, indent + 2, "oneway");
            out.push_str(if oneway { "true" } else { "false" });
        }
        if let Some(layer) = self.layer {
            out.push_str(",\n");
            write_key(out, indent + 2, "layer");
            write!(out, "{}", layer).unwrap();
        }
        out.push_str(",\n");
        write_key(out, indent + 2, "points");
        write_vec3_array(out, &self.points, indent + 2);
        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl RailSegment {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "kind");
        write_string(out, &self.kind);
        out.push_str(",\n");
        write_key(out, indent + 2, "material");
        write_string(out, &self.material);
        if let Some(color) = self.color {
            out.push_str(",\n");
            write_key(out, indent + 2, "color");
            write_color(out, color);
        }
        if let Some(lanes) = self.lanes {
            out.push_str(",\n");
            write_key(out, indent + 2, "lanes");
            write!(out, "{}", lanes).unwrap();
        }
        out.push_str(",\n");
        write_key(out, indent + 2, "widthStuds");
        write_number(out, self.width_studs);
        out.push_str(",\n");
        write_key(out, indent + 2, "points");
        write_vec3_array(out, &self.points, indent + 2);
        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl BuildingShell {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "material");
        write_string(out, &self.material);
        if let Some(color) = self.wall_color {
            out.push_str(",\n");
            write_key(out, indent + 2, "wallColor");
            write_color(out, color);
        }
        if let Some(color) = self.roof_color {
            out.push_str(",\n");
            write_key(out, indent + 2, "roofColor");
            write_color(out, color);
        }
        if let Some(ref s) = self.roof_shape {
            out.push_str(",\n");
            write_key(out, indent + 2, "roofShape");
            write_string(out, s);
        }
        if let Some(ref s) = self.roof_material {
            out.push_str(",\n");
            write_key(out, indent + 2, "roofMaterial");
            write_string(out, s);
        }
        if let Some(ref s) = self.usage {
            out.push_str(",\n");
            write_key(out, indent + 2, "usage");
            write_string(out, s);
        }
        if let Some(h) = self.min_height {
            out.push_str(",\n");
            write_key(out, indent + 2, "minHeight");
            write_number(out, h);
        }
        out.push_str(",\n");
        write_key(out, indent + 2, "footprint");
        write_ground_points(out, &self.footprint, indent + 2);
        if !self.holes.is_empty() {
            out.push_str(",\n");
            write_key(out, indent + 2, "holes");
            write_array(out, indent + 2, &self.holes, |hole, out, indent| {
                write_ground_points(out, hole, indent);
            });
        }
        if let Some(idx) = &self.indices {
            out.push_str(",\n");
            write_key(out, indent + 2, "indices");
            write_indices(out, idx);
        }
        out.push_str(",\n");
        write_key(out, indent + 2, "baseY");
        write_number(out, self.base_y);
        out.push_str(",\n");
        write_key(out, indent + 2, "height");
        write_number(out, self.height);

        if let Some(h) = self.height_m {
            out.push_str(",\n");
            write_key(out, indent + 2, "height_m");
            write_number(out, h);
        }

        if let Some(lvl) = self.levels {
            out.push_str(",\n");
            write_key(out, indent + 2, "levels");
            write!(out, "{}", lvl).unwrap();
        }

        if let Some(rlvl) = self.roof_levels {
            out.push_str(",\n");
            write_key(out, indent + 2, "roofLevels");
            write!(out, "{}", rlvl).unwrap();
        }

        if let Some(style) = &self.facade_style {
            out.push_str(",\n");
            write_key(out, indent + 2, "facadeStyle");
            write_string(out, style);
        }

        out.push_str(",\n");
        write_key(out, indent + 2, "roof");
        write_string(out, &self.roof);

        if !self.rooms.is_empty() {
            out.push_str(",\n");
            write_key(out, indent + 2, "rooms");
            write_array(out, indent + 2, &self.rooms, |item, out, indent| {
                item.write_json(out, indent)
            });
        }

        if let Some(rh) = self.roof_height {
            out.push_str(",\n");
            write_key(out, indent + 2, "roofHeight");
            write_number(out, rh);
        }

        if let Some(ref n) = self.name {
            out.push_str(",\n");
            write_key(out, indent + 2, "name");
            write_string(out, n);
        }

        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl Room {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "name");
        write_string(out, &self.name);
        out.push_str(",\n");
        write_key(out, indent + 2, "footprint");
        write_ground_points(out, &self.footprint, indent + 2);
        out.push_str(",\n");
        write_key(out, indent + 2, "floorY");
        write_number(out, self.floor_y);
        out.push_str(",\n");
        write_key(out, indent + 2, "height");
        write_number(out, self.height);

        if let Some(wm) = &self.wall_material {
            out.push_str(",\n");
            write_key(out, indent + 2, "wallMaterial");
            write_string(out, wm);
        }
        if let Some(fm) = &self.floor_material {
            out.push_str(",\n");
            write_key(out, indent + 2, "floorMaterial");
            write_string(out, fm);
        }

        out.push_str(",\n");
        write_key(out, indent + 2, "hasDoor");
        out.push_str(if self.has_door { "true" } else { "false" });
        out.push_str(",\n");
        write_key(out, indent + 2, "hasWindow");
        out.push_str(if self.has_window { "true" } else { "false" });

        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl WaterFeature {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "kind");
        write_string(out, &self.kind);
        out.push_str(",\n");
        write_key(out, indent + 2, "material");
        write_string(out, &self.material);
        if let Some(color) = self.color {
            out.push_str(",\n");
            write_key(out, indent + 2, "color");
            write_color(out, color);
        }

        if let Some(width) = self.width_studs {
            out.push_str(",\n");
            write_key(out, indent + 2, "widthStuds");
            write_number(out, width);
        }

        if let Some(points) = &self.points {
            out.push_str(",\n");
            write_key(out, indent + 2, "points");
            write_vec3_array(out, points, indent + 2);
        }

        if let Some(fp) = &self.footprint {
            out.push_str(",\n");
            write_key(out, indent + 2, "footprint");
            write_ground_points(out, fp, indent + 2);
        }

        if !self.holes.is_empty() {
            out.push_str(",\n");
            write_key(out, indent + 2, "holes");
            write_array(out, indent + 2, &self.holes, |hole, out, indent| {
                write_ground_points(out, hole, indent);
            });
        }

        if let Some(idx) = &self.indices {
            out.push_str(",\n");
            write_key(out, indent + 2, "indices");
            write_indices(out, idx);
        }

        if let Some(sy) = self.surface_y {
            out.push_str(",\n");
            write_key(out, indent + 2, "surfaceY");
            write_number(out, sy);
        }

        if let Some(w) = self.width {
            out.push_str(",\n");
            write_key(out, indent + 2, "width");
            write_number(out, w);
        }

        if let Some(intermittent) = self.intermittent {
            out.push_str(",\n");
            write_key(out, indent + 2, "intermittent");
            out.push_str(if intermittent { "true" } else { "false" });
        }

        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl PropInstance {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "kind");
        write_string(out, &self.kind);
        out.push_str(",\n");
        write_key(out, indent + 2, "position");
        write_vec3(out, self.position, indent + 2);
        out.push_str(",\n");
        write_key(out, indent + 2, "yawDegrees");
        write_number(out, self.yaw_degrees);
        out.push_str(",\n");
        write_key(out, indent + 2, "scale");
        write_number(out, self.scale);
        if let Some(ref s) = self.species {
            out.push_str(",\n");
            write_key(out, indent + 2, "species");
            write_string(out, s);
        }
        if let Some(h) = self.height {
            out.push_str(",\n");
            write_key(out, indent + 2, "height");
            write_number(out, h);
        }
        if let Some(ref lt) = self.leaf_type {
            out.push_str(",\n");
            write_key(out, indent + 2, "leafType");
            write_string(out, lt);
        }
        if let Some(c) = self.circumference {
            out.push_str(",\n");
            write_key(out, indent + 2, "circumference");
            write_number(out, c);
        }
        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

impl LanduseShell {
    fn write_json(&self, out: &mut String, indent: usize) {
        write_indent(out, indent);
        out.push_str("{\n");
        write_key(out, indent + 2, "id");
        write_string(out, &self.id);
        out.push_str(",\n");
        write_key(out, indent + 2, "kind");
        write_string(out, &self.kind);
        out.push_str(",\n");
        write_key(out, indent + 2, "material");
        write_string(out, &self.material);
        out.push_str(",\n");
        write_key(out, indent + 2, "footprint");
        write_ground_points(out, &self.footprint, indent + 2);
        out.push('\n');
        write_indent(out, indent);
        out.push('}');
    }
}

pub fn footprint_to_ground_points(footprint: &Footprint) -> Vec<GroundPoint> {
    footprint
        .points
        .iter()
        .map(|p| GroundPoint::new(p.x, p.y))
        .collect()
}

fn write_array<T>(
    out: &mut String,
    indent: usize,
    items: &[T],
    mut write_item: impl FnMut(&T, &mut String, usize),
) {
    out.push_str("[\n");
    for (i, item) in items.iter().enumerate() {
        write_item(item, out, indent + 2);
        if i + 1 != items.len() {
            out.push(',');
        }
        out.push('\n');
    }
    write_indent(out, indent);
    out.push(']');
}

fn write_bbox(out: &mut String, bbox: BoundingBox, indent: usize) {
    write_indent(out, indent);
    out.push_str("{\n");
    write_key(out, indent + 2, "minLat");
    write!(out, "{:.6}", bbox.min.lat).unwrap();
    out.push_str(",\n");
    write_key(out, indent + 2, "minLon");
    write!(out, "{:.6}", bbox.min.lon).unwrap();
    out.push_str(",\n");
    write_key(out, indent + 2, "maxLat");
    write!(out, "{:.6}", bbox.max.lat).unwrap();
    out.push_str(",\n");
    write_key(out, indent + 2, "maxLon");
    write!(out, "{:.6}", bbox.max.lon).unwrap();
    out.push('\n');
    write_indent(out, indent);
    out.push('}');
}

fn write_ground_points(out: &mut String, points: &[GroundPoint], indent: usize) {
    out.push_str("[\n");
    for (i, point) in points.iter().enumerate() {
        write_indent(out, indent + 2);
        out.push_str("{ ");
        write_key_inline(out, "x");
        write_number(out, point.x);
        out.push_str(", ");
        write_key_inline(out, "z");
        write_number(out, point.z);
        out.push_str(" }");
        if i + 1 != points.len() {
            out.push(',');
        }
        out.push('\n');
    }
    write_indent(out, indent);
    out.push(']');
}

fn write_indices(out: &mut String, indices: &[usize]) {
    out.push('[');
    for (i, val) in indices.iter().enumerate() {
        write!(out, "{}", val).unwrap();
        if i + 1 != indices.len() {
            out.push_str(", ");
        }
    }
    out.push(']');
}

fn write_vec3_array(out: &mut String, points: &[Vec3], indent: usize) {
    out.push_str("[\n");
    for (i, point) in points.iter().enumerate() {
        write_vec3(out, *point, indent + 2);
        if i + 1 != points.len() {
            out.push(',');
        }
        out.push('\n');
    }
    write_indent(out, indent);
    out.push(']');
}

fn write_vec3(out: &mut String, point: Vec3, indent: usize) {
    write_indent(out, indent);
    out.push_str("{ ");
    write_key_inline(out, "x");
    write_number(out, point.x);
    out.push_str(", ");
    write_key_inline(out, "y");
    write_number(out, point.y);
    out.push_str(", ");
    write_key_inline(out, "z");
    write_number(out, point.z);
    out.push_str(" }");
}

fn write_color(out: &mut String, color: Color) {
    write!(
        out,
        "{{ \"r\": {}, \"g\": {}, \"b\": {} }}",
        color.r, color.g, color.b
    )
    .unwrap();
}

fn write_key(out: &mut String, indent: usize, key: &str) {
    write_indent(out, indent);
    write_string(out, key);
    out.push_str(": ");
}

fn write_key_inline(out: &mut String, key: &str) {
    write_string(out, key);
    out.push_str(": ");
}

fn write_number(out: &mut String, value: f64) {
    if value.fract() == 0.0 {
        write!(out, "{:.0}", value).unwrap();
    } else {
        write!(out, "{:.4}", value).unwrap();
    }
}

fn write_string(out: &mut String, value: &str) {
    out.push('"');
    for ch in value.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            _ => out.push(ch),
        }
    }
    out.push('"');
}

fn write_indent(out: &mut String, indent: usize) {
    for _ in 0..indent {
        out.push(' ');
    }
}
