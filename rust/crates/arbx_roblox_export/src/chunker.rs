#[cfg(not(miri))]
use rayon::prelude::*;
use std::collections::HashMap;

use arbx_geo::{ChunkId, ElevationProvider, LatLon, Mercator, Vec3};
use arbx_pipeline::{Feature, WaterFeature as PipelineWaterFeature};

use crate::manifest::{
    BarrierSegment, BuildingShell, Chunk, ChunkManifest, GroundPoint, LanduseShell, ManifestMeta,
    PropInstance, RailSegment, RoadSegment, TerrainGrid, WaterFeature as ManifestWaterFeature,
};
use crate::materials::StyleMapper;
use crate::subplans::derive_chunk_ref;

pub fn world_to_chunk(position: Vec3, chunk_size_studs: i32) -> ChunkId {
    let size = chunk_size_studs as f64;
    let x = (position.x / size).floor() as i32;
    let z = (position.z / size).floor() as i32;
    ChunkId::new(x, z)
}

pub fn chunk_origin(
    id: ChunkId,
    chunk_size_studs: i32,
    center_latlon: LatLon,
    meters_per_stud: f64,
    elevation: &dyn ElevationProvider,
) -> Vec3 {
    let size = chunk_size_studs as f64;
    let x = id.x as f64 * size;
    let z = id.z as f64 * size;
    let latlon = Mercator::unproject(Vec3::new(x, 0.0, z), center_latlon, meters_per_stud);
    let y_meters = elevation.sample_height_at(latlon);
    let y_studs = y_meters as f64 / meters_per_stud;

    Vec3::new(x, y_studs, z)
}

fn parse_css_color(s: &str) -> Option<crate::manifest::Color> {
    use crate::manifest::Color;
    if s.starts_with('#') && s.len() == 7 {
        let r = u8::from_str_radix(&s[1..3], 16).ok()?;
        let g = u8::from_str_radix(&s[3..5], 16).ok()?;
        let b = u8::from_str_radix(&s[5..7], 16).ok()?;
        return Some(Color { r, g, b });
    }
    match s {
        "white" => Some(Color {
            r: 255,
            g: 255,
            b: 255,
        }),
        "black" => Some(Color {
            r: 30,
            g: 30,
            b: 30,
        }),
        "gray" | "grey" => Some(Color {
            r: 128,
            g: 128,
            b: 128,
        }),
        "red" => Some(Color {
            r: 180,
            g: 50,
            b: 50,
        }),
        "brown" => Some(Color {
            r: 139,
            g: 90,
            b: 43,
        }),
        "beige" => Some(Color {
            r: 245,
            g: 245,
            b: 220,
        }),
        "yellow" => Some(Color {
            r: 255,
            g: 220,
            b: 50,
        }),
        "blue" => Some(Color {
            r: 50,
            g: 100,
            b: 200,
        }),
        "green" => Some(Color {
            r: 50,
            g: 140,
            b: 50,
        }),
        "orange" => Some(Color {
            r: 230,
            g: 120,
            b: 30,
        }),
        "pink" => Some(Color {
            r: 255,
            g: 180,
            b: 180,
        }),
        "tan" => Some(Color {
            r: 210,
            g: 180,
            b: 140,
        }),
        "silver" => Some(Color {
            r: 192,
            g: 192,
            b: 192,
        }),
        "gold" => Some(Color {
            r: 212,
            g: 175,
            b: 55,
        }),
        _ => None,
    }
}

fn landuse_material(kind: &str) -> String {
    match kind {
        "park" | "garden" | "recreation_ground" | "village_green" | "leisure" => "Grass",
        "forest" | "wood" => "LeafyGrass",
        "farmland" | "orchard" | "vineyard" | "allotments" => "Mud",
        "beach" | "sand" => "Sand",
        "bare_rock" | "cliff" => "Rock",
        "residential" | "cemetery" => "Ground",
        "commercial" | "retail" | "civic" => "Concrete",
        "industrial" | "railway" => "SmoothPlastic",
        "parking" | "road" => "Asphalt",
        "grass" | "meadow" | "heath" => "Grass",
        "scrub" | "greenfield" => "LeafyGrass",
        "water" | "wetland" => "Mud",
        _ => "Ground",
    }
    .to_string()
}

fn terrain_material_priority(material: &str) -> u8 {
    match material {
        "Water" => 100,
        "Asphalt" | "Concrete" | "SmoothPlastic" => 80,
        "Rock" | "Sandstone" | "Granite" => 70,
        "Sand" | "Mud" => 60,
        "LeafyGrass" => 50,
        "Grass" => 40,
        "Ground" => 30,
        _ => 10,
    }
}

fn point_in_ring(x: f64, z: f64, ring: &[GroundPoint]) -> bool {
    if ring.len() < 3 {
        return false;
    }

    let mut inside = false;
    let mut prev = &ring[ring.len() - 1];
    for current in ring {
        let current_above = current.z > z;
        let prev_above = prev.z > z;
        if current_above != prev_above {
            let intersect_x = (prev.x - current.x) * (z - current.z)
                / ((prev.z - current.z) + f64::EPSILON)
                + current.x;
            if x < intersect_x {
                inside = !inside;
            }
        }
        prev = current;
    }

    inside
}

fn paint_terrain_polygon(
    terrain: &mut TerrainGrid,
    footprint: &[GroundPoint],
    holes: &[Vec<GroundPoint>],
    material: &str,
) {
    if footprint.len() < 3 {
        return;
    }

    let Some(materials) = terrain.materials.as_mut() else {
        return;
    };

    let mut min_x = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut min_z = f64::INFINITY;
    let mut max_z = f64::NEG_INFINITY;

    for point in footprint {
        min_x = min_x.min(point.x);
        max_x = max_x.max(point.x);
        min_z = min_z.min(point.z);
        max_z = max_z.max(point.z);
    }

    let cell_size = terrain.cell_size_studs as f64;
    let min_cx =
        ((min_x / cell_size).floor() as isize).clamp(0, terrain.width as isize - 1) as usize;
    let max_cx =
        ((max_x / cell_size).ceil() as isize).clamp(0, terrain.width as isize - 1) as usize;
    let min_cz =
        ((min_z / cell_size).floor() as isize).clamp(0, terrain.depth as isize - 1) as usize;
    let max_cz =
        ((max_z / cell_size).ceil() as isize).clamp(0, terrain.depth as isize - 1) as usize;
    let new_priority = terrain_material_priority(material);

    for cz in min_cz..=max_cz {
        for cx in min_cx..=max_cx {
            let sample_x = (cx as f64 + 0.5) * cell_size;
            let sample_z = (cz as f64 + 0.5) * cell_size;
            if !point_in_ring(sample_x, sample_z, footprint) {
                continue;
            }
            if holes
                .iter()
                .any(|hole| point_in_ring(sample_x, sample_z, hole.as_slice()))
            {
                continue;
            }

            let idx = cz * terrain.width + cx;
            if idx >= materials.len() {
                continue;
            }
            let current_priority = terrain_material_priority(materials[idx].as_str());
            if new_priority >= current_priority {
                materials[idx] = material.to_string();
            }
        }
    }
}

#[inline]
fn sample_terrain_height_for_cell(
    idx: usize,
    grid_dim: usize,
    row_lats: &[f64],
    col_lons: &[f64],
    meters_per_stud: f64,
    origin_y: f64,
    elevation: &dyn ElevationProvider,
) -> f64 {
    let cz = idx / grid_dim;
    let cx = idx % grid_dim;
    let lat = row_lats[cz];
    let lon = col_lons[cx];
    let h_meters = elevation.sample_height_at(LatLon::new(lat, lon));
    let h_studs = h_meters as f64 / meters_per_stud;
    h_studs - origin_y
}

#[cfg(miri)]
fn collect_terrain_heights(
    total_cells: usize,
    grid_dim: usize,
    row_lats: &[f64],
    col_lons: &[f64],
    meters_per_stud: f64,
    origin_y: f64,
    elevation: &dyn ElevationProvider,
) -> Vec<f64> {
    (0..total_cells)
        .map(|idx| {
            sample_terrain_height_for_cell(
                idx,
                grid_dim,
                row_lats,
                col_lons,
                meters_per_stud,
                origin_y,
                elevation,
            )
        })
        .collect()
}

pub(crate) fn build_empty_chunk(
    id: ChunkId,
    chunk_size_studs: i32,
    meters_per_stud: f64,
    terrain_cell_size: i32,
    center_latlon: LatLon,
    elevation: &dyn ElevationProvider,
    style: &StyleMapper,
) -> Chunk {
    let origin = chunk_origin(
        id,
        chunk_size_studs,
        center_latlon,
        meters_per_stud,
        elevation,
    );

    let cell_size = terrain_cell_size;
    let grid_dim = (chunk_size_studs / cell_size) as usize;
    let total_cells = grid_dim * grid_dim;

    let cell_size_f64 = cell_size as f64;
    let (center_x_meters, center_y_meters) = Mercator::latlon_to_meters(center_latlon);
    let chunk_world_x = id.x as f64 * chunk_size_studs as f64;
    let chunk_world_z = id.z as f64 * chunk_size_studs as f64;

    let row_lats: Vec<f64> = (0..grid_dim)
        .map(|cz| {
            let world_z = chunk_world_z + (cz as f64 * cell_size_f64);
            let y_meters = center_y_meters - (world_z * meters_per_stud);
            Mercator::meters_to_latlon(center_x_meters, y_meters).lat
        })
        .collect();

    let col_lons: Vec<f64> = (0..grid_dim)
        .map(|cx| {
            let world_x = chunk_world_x + (cx as f64 * cell_size_f64);
            let x_meters = center_x_meters + (world_x * meters_per_stud);
            Mercator::meters_to_latlon(x_meters, center_y_meters).lon
        })
        .collect();

    let default_material = style.get_terrain_material("grass");
    let origin_y = origin.y;
    let heights = collect_terrain_heights(
        total_cells,
        grid_dim,
        &row_lats,
        &col_lons,
        meters_per_stud,
        origin_y,
        elevation,
    );
    let cell_materials = vec![default_material.clone(); total_cells];

    Chunk {
        id,
        origin_studs: origin,
        terrain: Some(TerrainGrid {
            cell_size_studs: cell_size,
            width: grid_dim,
            depth: grid_dim,
            heights,
            materials: Some(cell_materials),
            material: default_material,
        }),
        roads: Vec::new(),
        rails: Vec::new(),
        buildings: Vec::new(),
        water: Vec::new(),
        props: Vec::new(),
        landuse: Vec::new(),
        barriers: Vec::new(),
    }
}

#[cfg(not(miri))]
fn collect_terrain_heights(
    total_cells: usize,
    grid_dim: usize,
    row_lats: &[f64],
    col_lons: &[f64],
    meters_per_stud: f64,
    origin_y: f64,
    elevation: &dyn ElevationProvider,
) -> Vec<f64> {
    (0..total_cells)
        .into_par_iter()
        .map(|idx| {
            sample_terrain_height_for_cell(
                idx,
                grid_dim,
                row_lats,
                col_lons,
                meters_per_stud,
                origin_y,
                elevation,
            )
        })
        .collect()
}

pub struct Chunker {
    chunk_size_studs: i32,
    meters_per_stud: f64,
    terrain_cell_size: i32,
    center_latlon: LatLon,
    chunks: HashMap<ChunkId, Chunk>,
}

impl Chunker {
    pub fn new(
        chunk_size_studs: i32,
        meters_per_stud: f64,
        terrain_cell_size: i32,
        center_latlon: LatLon,
    ) -> Self {
        Self {
            chunk_size_studs,
            meters_per_stud,
            terrain_cell_size,
            center_latlon,
            chunks: HashMap::new(),
        }
    }

    fn ensure_chunk(
        &mut self,
        id: ChunkId,
        elevation: &dyn ElevationProvider,
        style: &StyleMapper,
    ) -> &mut Chunk {
        let chunk_size = self.chunk_size_studs;
        let meters_per_stud = self.meters_per_stud;
        let center = self.center_latlon;

        self.chunks.entry(id).or_insert_with(|| {
            build_empty_chunk(
                id,
                chunk_size,
                meters_per_stud,
                self.terrain_cell_size,
                center,
                elevation,
                style,
            )
        })
    }

    pub fn ingest(
        &mut self,
        feature: Feature,
        style: &StyleMapper,
        elevation: &dyn ElevationProvider,
    ) {
        match feature {
            Feature::Road(f) => {
                let segments = self.split_polyline(f.points, self.chunk_size_studs);
                for (chunk_id, points) in segments {
                    let chunk = self.ensure_chunk(chunk_id, elevation, style);
                    let origin = chunk.origin_studs;
                    let relative_points = points
                        .into_iter()
                        .map(|p| Vec3::new(p.x - origin.x, p.y - origin.y, p.z - origin.z))
                        .collect();

                    let material = style.get_road_material(&f.kind);
                    let color = style.get_road_color(&f.kind);
                    chunk.roads.push(RoadSegment {
                        id: f.id.clone(),
                        kind: f.kind.clone(),
                        subkind: f.subkind.clone(),
                        material,
                        color,
                        lanes: f.lanes,
                        width_studs: f.width_studs,
                        has_sidewalk: f.has_sidewalk,
                        surface: f.surface.clone(),
                        elevated: f.elevated.unwrap_or(false),
                        tunnel: f.tunnel.unwrap_or(false),
                        sidewalk: f.sidewalk.clone(),
                        points: relative_points,
                        maxspeed: f.maxspeed,
                        lit: f.lit,
                        oneway: f.oneway,
                        layer: f.layer,
                    });
                }
            }
            Feature::Rail(f) => {
                let segments = self.split_polyline(f.points, self.chunk_size_studs);
                for (chunk_id, points) in segments {
                    let chunk = self.ensure_chunk(chunk_id, elevation, style);
                    let origin = chunk.origin_studs;
                    let relative_points = points
                        .into_iter()
                        .map(|p| Vec3::new(p.x - origin.x, p.y - origin.y, p.z - origin.z))
                        .collect();

                    let material = style.get_road_material(&f.kind);
                    let color = style.get_road_color(&f.kind);
                    chunk.rails.push(RailSegment {
                        id: f.id.clone(),
                        kind: f.kind.clone(),
                        material,
                        color,
                        lanes: f.lanes,
                        width_studs: f.width_studs,
                        points: relative_points,
                    });
                }
            }
            Feature::Water(f) => match f {
                PipelineWaterFeature::Ribbon(r) => {
                    let segments = self.split_polyline(r.points, self.chunk_size_studs);
                    for (chunk_id, points) in segments {
                        let chunk = self.ensure_chunk(chunk_id, elevation, style);
                        let origin = chunk.origin_studs;
                        let relative_points = points
                            .into_iter()
                            .map(|p| Vec3::new(p.x - origin.x, p.y - origin.y, p.z - origin.z))
                            .collect();

                        let material = style.get_terrain_material(&r.kind);
                        let color = style.get_terrain_color(&r.kind);
                        chunk.water.push(ManifestWaterFeature {
                            id: r.id.clone(),
                            kind: r.kind.clone(),
                            material,
                            color,
                            width_studs: Some(r.width_studs),
                            points: Some(relative_points),
                            footprint: None,
                            holes: vec![],
                            indices: None,
                            surface_y: None,
                            width: r.width,
                            intermittent: r.intermittent,
                        });
                    }
                }
                PipelineWaterFeature::Polygon(p) => {
                    let mut sum_x = 0.0;
                    let mut sum_z = 0.0;
                    for pt in &p.footprint.points {
                        sum_x += pt.x;
                        sum_z += pt.y;
                    }
                    let count = p.footprint.points.len() as f64;
                    let centroid = Vec3::new(sum_x / count, 0.0, sum_z / count);

                    // Sample DEM at polygon centroid to derive water surfaceY.
                    // Must read self fields before the mutable borrow from ensure_chunk.
                    let mps = self.meters_per_stud;
                    let center = self.center_latlon;
                    let centroid_latlon = Mercator::unproject(centroid, center, mps);
                    let surface_h = elevation.sample_height_at(centroid_latlon);

                    let chunk_id = world_to_chunk(centroid, self.chunk_size_studs);
                    let chunk = self.ensure_chunk(chunk_id, elevation, style);
                    let origin = chunk.origin_studs;

                    let surface_y = Some(surface_h as f64 / mps - origin.y);

                    let relative_footprint: Vec<GroundPoint> = p
                        .footprint
                        .points
                        .iter()
                        .map(|pt| GroundPoint::new(pt.x - origin.x, pt.y - origin.z))
                        .collect();

                    let relative_holes: Vec<Vec<GroundPoint>> = p
                        .holes
                        .iter()
                        .map(|hole| {
                            hole.points
                                .iter()
                                .map(|pt| GroundPoint::new(pt.x - origin.x, pt.y - origin.z))
                                .collect()
                        })
                        .collect();

                    let material = style.get_terrain_material(&p.kind);
                    let color = style.get_terrain_color(&p.kind);
                    paint_terrain_polygon(
                        chunk.terrain.as_mut().expect("terrain grid"),
                        &relative_footprint,
                        &relative_holes,
                        &material,
                    );
                    chunk.water.push(ManifestWaterFeature {
                        id: p.id,
                        kind: p.kind,
                        material,
                        color,
                        width_studs: None,
                        points: None,
                        footprint: Some(relative_footprint),
                        holes: relative_holes,
                        indices: p.indices,
                        surface_y,
                        width: None,
                        intermittent: p.intermittent,
                    });
                }
            },
            Feature::Building(f) => {
                let scale = 1.0 / self.meters_per_stud;
                let mut sum_x = 0.0;
                let mut sum_z = 0.0;
                for pt in &f.footprint.points {
                    sum_x += pt.x;
                    sum_z += pt.y;
                }
                let count = f.footprint.points.len() as f64;
                let centroid = Vec3::new(sum_x / count, f.base_y, sum_z / count);
                let chunk_id = world_to_chunk(centroid, self.chunk_size_studs);
                let chunk = self.ensure_chunk(chunk_id, elevation, style);
                let origin = chunk.origin_studs;

                let relative_footprint: Vec<GroundPoint> = f
                    .footprint
                    .points
                    .iter()
                    .map(|pt| GroundPoint::new(pt.x - origin.x, pt.y - origin.z))
                    .collect();
                let relative_holes: Vec<Vec<GroundPoint>> = f
                    .holes
                    .iter()
                    .map(|hole| {
                        hole.points
                            .iter()
                            .map(|pt| GroundPoint::new(pt.x - origin.x, pt.y - origin.z))
                            .collect()
                    })
                    .collect();

                let style_key = f.usage.as_deref().unwrap_or("default");
                let material = style.get_building_material(style_key);
                let color = if let Some(css) = f.colour.as_deref().and_then(parse_css_color) {
                    Some(css)
                } else {
                    style.get_building_color(style_key)
                };
                let material_override = f.material_tag.as_deref().map(|m| match m {
                    "brick" => "Brick",
                    "masonry" => "Brick",
                    "concrete" => "Concrete",
                    "glass" => "Glass",
                    "metal" | "steel" => "Metal",
                    "wood" => "WoodPlanks",
                    "stone" | "granite" | "limestone" => "Limestone",
                    "sandstone" => "Sandstone",
                    "marble" => "Marble",
                    _ => "Concrete",
                });
                let material = material_override.map(|s| s.to_string()).unwrap_or(material);

                // Resolve roof color: prefer explicit OSM roof:colour, fall back to style
                let roof_color = f.roof_colour.as_deref().and_then(parse_css_color);

                chunk.buildings.push(BuildingShell {
                    id: f.id,
                    footprint: relative_footprint,
                    holes: relative_holes,
                    indices: f.indices,
                    material,
                    wall_color: color,
                    roof_color,
                    roof_shape: Some(f.roof.clone()),
                    roof_material: f.roof_material.clone(),
                    usage: f.usage.clone(),
                    min_height: f.min_height.map(|height| height * scale),
                    base_y: f.base_y - origin.y,
                    height: f.height * scale,
                    height_m: f.height_m,
                    levels: f.levels,
                    roof_levels: f.roof_levels,
                    facade_style: None,
                    roof: f.roof,
                    rooms: Vec::new(),
                    roof_height: f.roof_height.map(|height| height * scale),
                    name: f.name.clone(),
                });
            }
            Feature::Prop(f) => {
                let chunk_id = world_to_chunk(f.position, self.chunk_size_studs);
                let chunk = self.ensure_chunk(chunk_id, elevation, style);
                let origin = chunk.origin_studs;
                chunk.props.push(PropInstance {
                    id: f.id,
                    kind: f.kind,
                    position: Vec3::new(
                        f.position.x - origin.x,
                        f.position.y - origin.y,
                        f.position.z - origin.z,
                    ),
                    yaw_degrees: f.yaw_degrees,
                    scale: f.scale,
                    species: f.species,
                    height: f.height,
                    leaf_type: f.leaf_type,
                    circumference: f.circumference,
                });
            }
            Feature::Landuse(f) => {
                if f.footprint.points.len() < 3 {
                    return;
                }
                let cx: f64 = f.footprint.points.iter().map(|p| p.x).sum::<f64>()
                    / f.footprint.points.len() as f64;
                let cz: f64 = f.footprint.points.iter().map(|p| p.y).sum::<f64>()
                    / f.footprint.points.len() as f64;
                let chunk_id = world_to_chunk(Vec3::new(cx, 0.0, cz), self.chunk_size_studs);
                let chunk = self.ensure_chunk(chunk_id, elevation, style);
                let origin = chunk.origin_studs;
                let material = landuse_material(&f.kind);
                let footprint: Vec<GroundPoint> = f
                    .footprint
                    .points
                    .iter()
                    .map(|p| GroundPoint::new(p.x - origin.x, p.y - origin.z))
                    .collect();
                paint_terrain_polygon(
                    chunk.terrain.as_mut().expect("terrain grid"),
                    &footprint,
                    &[],
                    &material,
                );
                chunk.landuse.push(LanduseShell {
                    id: f.id.clone(),
                    kind: f.kind.clone(),
                    material,
                    footprint,
                });
            }
            Feature::Barrier(f) => {
                let segments = self.split_polyline(f.points, self.chunk_size_studs);
                for (chunk_id, points) in segments {
                    let chunk = self.ensure_chunk(chunk_id, elevation, style);
                    let origin = chunk.origin_studs;
                    let relative_points = points
                        .into_iter()
                        .map(|p| Vec3::new(p.x - origin.x, p.y - origin.y, p.z - origin.z))
                        .collect();
                    chunk.barriers.push(BarrierSegment {
                        id: f.id.clone(),
                        kind: f.kind.clone(),
                        points: relative_points,
                    });
                }
            }
        }
    }

    fn split_polyline(&self, points: Vec<Vec3>, chunk_size: i32) -> Vec<(ChunkId, Vec<Vec3>)> {
        if points.len() < 2 {
            return Vec::new();
        }

        let mut segments_by_chunk: HashMap<ChunkId, Vec<Vec<Vec3>>> = HashMap::new();

        for i in 0..points.len() - 1 {
            let p1 = points[i];
            let p2 = points[i + 1];

            // 1. Find all split points along the segment
            let mut split_ts = vec![0.0, 1.0];
            let dx = p2.x - p1.x;
            let dz = p2.z - p1.z;
            let s = chunk_size as f64;

            if dx.abs() > 0.001 {
                let min_x = p1.x.min(p2.x);
                let max_x = p1.x.max(p2.x);
                let first_bound = (min_x / s).ceil() as i32;
                let last_bound = (max_x / s).floor() as i32;
                for b in first_bound..=last_bound {
                    let bx = b as f64 * s;
                    let t = (bx - p1.x) / dx;
                    if t > 0.0 && t < 1.0 {
                        split_ts.push(t);
                    }
                }
            }

            if dz.abs() > 0.001 {
                let min_z = p1.z.min(p2.z);
                let max_z = p1.z.max(p2.z);
                let first_bound = (min_z / s).ceil() as i32;
                let last_bound = (max_z / s).floor() as i32;
                for b in first_bound..=last_bound {
                    let bz = b as f64 * s;
                    let t = (bz - p1.z) / dz;
                    if t > 0.0 && t < 1.0 {
                        split_ts.push(t);
                    }
                }
            }

            split_ts.sort_by(|a, b| a.partial_cmp(b).unwrap());
            split_ts.dedup_by(|a, b| (*a - *b).abs() < 0.001);

            // 2. Create sub-segments and assign to chunks
            for j in 0..split_ts.len() - 1 {
                let t_start = split_ts[j];
                let t_end = split_ts[j + 1];

                let sp1 = Vec3::new(
                    p1.x + t_start * dx,
                    p1.y + t_start * (p2.y - p1.y),
                    p1.z + t_start * dz,
                );
                let sp2 = Vec3::new(
                    p1.x + t_end * dx,
                    p1.y + t_end * (p2.y - p1.y),
                    p1.z + t_end * dz,
                );

                let midpoint = Vec3::new(
                    (sp1.x + sp2.x) * 0.5,
                    (sp1.y + sp2.y) * 0.5,
                    (sp1.z + sp2.z) * 0.5,
                );
                let chunk_id = world_to_chunk(midpoint, chunk_size);

                let chunk_segments = segments_by_chunk.entry(chunk_id).or_default();

                let mut appended = false;
                if let Some(last_seg) = chunk_segments.last_mut() {
                    if let Some(last_p) = last_seg.last() {
                        if (last_p.x - sp1.x).abs() < 0.05 && (last_p.z - sp1.z).abs() < 0.05 {
                            // Snap sp2 onto the exact last point to close the sub-millimetre gap
                            // that float arithmetic can leave at chunk-boundary split points.
                            let snap = *last_p;
                            let _ = snap; // sp1 is already close enough; just chain sp2
                            last_seg.push(sp2);
                            appended = true;
                        }
                    }
                }

                if !appended {
                    chunk_segments.push(vec![sp1, sp2]);
                }
            }
        }

        let mut result = Vec::new();
        for (chunk_id, segments) in segments_by_chunk {
            for points in segments {
                result.push((chunk_id, points));
            }
        }
        result
    }

    pub fn finish(self, meta: ManifestMeta) -> ChunkManifest {
        let mut chunks: Vec<Chunk> = self.chunks.into_values().collect();

        // Ensure deterministic output
        for chunk in &mut chunks {
            chunk.roads.sort_by(|a, b| a.id.cmp(&b.id));
            chunk.rails.sort_by(|a, b| a.id.cmp(&b.id));
            chunk.buildings.sort_by(|a, b| a.id.cmp(&b.id));
            chunk.water.sort_by(|a, b| a.id.cmp(&b.id));
            chunk.props.sort_by(|a, b| a.id.cmp(&b.id));
            chunk.landuse.sort_by(|a, b| a.id.cmp(&b.id));
            chunk.barriers.sort_by(|a, b| a.id.cmp(&b.id));
        }

        chunks.sort_by_key(|c| (c.id.z, c.id.x));
        let chunk_refs = chunks.iter().map(derive_chunk_ref).collect();

        ChunkManifest {
            schema_version: "0.4.0".to_string(),
            meta,
            chunks,
            chunk_refs,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbx_geo::LatLon;

    #[test]
    fn world_to_chunk_maps_positions() {
        let id = world_to_chunk(Vec3::new(300.0, 0.0, 100.0), 256);
        assert_eq!(id.x, 1);
        assert_eq!(id.z, 0);
    }

    #[test]
    fn split_polyline_across_chunks() {
        let chunker = Chunker::new(100, 1.0, 4, LatLon::new(0.0, 0.0));
        let points = vec![
            Vec3::new(50.0, 0.0, 50.0),  // Chunk (0,0)
            Vec3::new(150.0, 0.0, 50.0), // Chunk (1,0)
            Vec3::new(250.0, 0.0, 50.0), // Chunk (2,0)
        ];
        let segments = chunker.split_polyline(points, 100);

        // Should have 3 segments, one for each chunk
        assert_eq!(segments.len(), 3);

        // Check chunk IDs
        let mut ids: Vec<ChunkId> = segments.iter().map(|(id, _)| *id).collect();
        ids.sort_by_key(|id| id.x);
        assert_eq!(ids[0], ChunkId::new(0, 0));
        assert_eq!(ids[1], ChunkId::new(1, 0));
        assert_eq!(ids[2], ChunkId::new(2, 0));
    }
}
