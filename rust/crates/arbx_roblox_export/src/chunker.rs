use std::collections::HashMap;

use arbx_geo::{ChunkId, ElevationProvider, LatLon, Vec2, Vec3};
use arbx_pipeline::{Feature, WaterFeature as PipelineWaterFeature};

use crate::manifest::{
    BuildingShell, Chunk, ChunkManifest, GroundPoint, ManifestMeta, PropInstance,
    RailSegment, RoadSegment, TerrainGrid, WaterFeature as ManifestWaterFeature,
};
use crate::materials::StyleMapper;

pub fn world_to_chunk(position: Vec3, chunk_size_studs: i32) -> ChunkId {
    let size = chunk_size_studs as f32;
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
    let size = chunk_size_studs as f32;
    let x = id.x as f32 * size;
    let z = id.z as f32 * size;

    let lat_per_stud = 1.0 / (111_111.0 * meters_per_stud);
    let lon_per_stud = 1.0 / (111_111.0 * center_latlon.lat.to_radians().cos() * meters_per_stud);

    let lat = center_latlon.lat + (z as f64 * lat_per_stud);
    let lon = center_latlon.lon + (x as f64 * lon_per_stud);

    let y_meters = elevation.sample_height_at(LatLon::new(lat, lon));
    let y_studs = y_meters as f64 / meters_per_stud;

    Vec3::new(x, y_studs as f32, z)
}

pub struct Chunker {
    chunk_size_studs: i32,
    meters_per_stud: f64,
    center_latlon: LatLon,
    chunks: HashMap<ChunkId, Chunk>,
}

impl Chunker {
    pub fn new(chunk_size_studs: i32, meters_per_stud: f64, center_latlon: LatLon) -> Self {
        Self {
            chunk_size_studs,
            meters_per_stud,
            center_latlon,
            chunks: HashMap::new(),
        }
    }

    fn ensure_chunk(&mut self, id: ChunkId, elevation: &dyn ElevationProvider, style: &StyleMapper) -> &mut Chunk {
        let chunk_size = self.chunk_size_studs;
        let meters_per_stud = self.meters_per_stud;
        let center = self.center_latlon;

        self.chunks.entry(id).or_insert_with(|| {
            let origin = chunk_origin(id, chunk_size, center, meters_per_stud, elevation);
            
            // Build terrain grid for the chunk
            let cell_size = 16;
            let grid_dim = (chunk_size / cell_size) as usize;
            let mut heights = Vec::with_capacity(grid_dim * grid_dim);
            let mut cell_materials = Vec::with_capacity(grid_dim * grid_dim);
            
            let lat_per_stud = 1.0 / (111_111.0 * meters_per_stud);
            let lon_per_stud = 1.0 / (111_111.0 * center.lat.to_radians().cos() * meters_per_stud);

            let default_material = style.get_terrain_material("grass");

            for cz in 0..grid_dim {
                for cx in 0..grid_dim {
                    let lx = (id.x as f32 * chunk_size as f32) + (cx as f32 * cell_size as f32);
                    let lz = (id.z as f32 * chunk_size as f32) + (cz as f32 * cell_size as f32);
                    
                    let lat = center.lat + (lz as f64 * lat_per_stud);
                    let lon = center.lon + (lx as f64 * lon_per_stud);
                    
                    let h_meters = elevation.sample_height_at(LatLon::new(lat, lon));
                    let h_studs = (h_meters as f64 / meters_per_stud) as f32;
                    
                    heights.push(h_studs - origin.y);
                    cell_materials.push(default_material.clone());
                }
            }

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
            }
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
                        material,
                        color,
                        lanes: f.lanes,
                        width_studs: f.width_studs,
                        points: relative_points,
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
                            indices: None,
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
                    let count = p.footprint.points.len() as f32;
                    let centroid = Vec3::new(sum_x / count, 0.0, sum_z / count);
                    let chunk_id = world_to_chunk(centroid, self.chunk_size_studs);
                    let chunk = self.ensure_chunk(chunk_id, elevation, style);
                    let origin = chunk.origin_studs;

                    let relative_footprint = p
                        .footprint
                        .points
                        .iter()
                        .map(|pt| GroundPoint::new(pt.x - origin.x, pt.y - origin.z))
                        .collect();

                    let material = style.get_terrain_material(&p.kind);
                    let color = style.get_terrain_color(&p.kind);
                    chunk.water.push(ManifestWaterFeature {
                        id: p.id,
                        kind: p.kind,
                        material,
                        color,
                        width_studs: None,
                        points: None,
                        footprint: Some(relative_footprint),
                        indices: p.indices,
                    });
                }
            },
            Feature::Building(f) => {
                let mut sum_x = 0.0;
                let mut sum_z = 0.0;
                for pt in &f.footprint.points {
                    sum_x += pt.x;
                    sum_z += pt.y;
                }
                let count = f.footprint.points.len() as f32;
                let centroid = Vec3::new(sum_x / count, f.base_y, sum_z / count);
                let chunk_id = world_to_chunk(centroid, self.chunk_size_studs);
                let chunk = self.ensure_chunk(chunk_id, elevation, style);
                let origin = chunk.origin_studs;

                let relative_footprint = f
                    .footprint
                    .points
                    .iter()
                    .map(|pt| GroundPoint::new(pt.x - origin.x, pt.y - origin.z))
                    .collect();

                let material = style.get_building_material(&f.roof);
                let material = if material == "Concrete" {
                    style.get_building_material("default")
                } else {
                    material
                };
                let color = style.get_building_color(&f.roof);
                let color = if color.is_none() {
                    style.get_building_color("default")
                } else {
                    color
                };

                chunk.buildings.push(BuildingShell {
                    id: f.id,
                    footprint: relative_footprint,
                    indices: f.indices,
                    material,
                    color,
                    base_y: f.base_y - origin.y,
                    height: f.height,
                    levels: f.levels,
                    roof_levels: f.roof_levels,
                    roof: f.roof,
                    rooms: Vec::new(),
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
                });
            }
            Feature::Landuse(f) => {
                // For simplicity, paint only the chunk containing the centroid
                let mut sum_x = 0.0;
                let mut sum_z = 0.0;
                for pt in &f.footprint.points {
                    sum_x += pt.x;
                    sum_z += pt.y;
                }
                let count = f.footprint.points.len() as f32;
                let centroid = Vec3::new(sum_x / count, 0.0, sum_z / count);
                let chunk_id = world_to_chunk(centroid, self.chunk_size_studs);
                
                let chunk_size = self.chunk_size_studs;
                let chunk = self.ensure_chunk(chunk_id, elevation, style);
                let material = style.get_terrain_material(&f.kind);

                if let Some(terrain) = &mut chunk.terrain {
                    if let Some(materials) = &mut terrain.materials {
                        let cell_size = terrain.cell_size_studs as f32;
                        let grid_dim = terrain.width;
                        
                        for cz in 0..grid_dim {
                            for cx in 0..grid_dim {
                                let lx = (chunk_id.x as f32 * chunk_size as f32) + (cx as f32 * cell_size);
                                let lz = (chunk_id.z as f32 * chunk_size as f32) + (cz as f32 * cell_size);
                                
                                if point_in_poly(Vec2::new(lx, lz), &f.footprint.points) {
                                    materials[cz * grid_dim + cx] = material.clone();
                                }
                            }
                        }
                    }
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
            let s = chunk_size as f32;

            if dx.abs() > 0.001 {
                let min_x = p1.x.min(p2.x);
                let max_x = p1.x.max(p2.x);
                let first_bound = (min_x / s).ceil() as i32;
                let last_bound = (max_x / s).floor() as i32;
                for b in first_bound..=last_bound {
                    let bx = b as f32 * s;
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
                    let bz = b as f32 * s;
                    let t = (bz - p1.z) / dz;
                    if t > 0.0 && t < 1.0 {
                        split_ts.push(t);
                    }
                }
            }

            split_ts.sort_by(|a, b| a.partial_cmp(b).unwrap());
            split_ts.dedup_by(|a, b| (*a - *b).abs() < 0.0001);

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

                let midpoint =
                    Vec3::new((sp1.x + sp2.x) * 0.5, (sp1.y + sp2.y) * 0.5, (sp1.z + sp2.z) * 0.5);
                let chunk_id = world_to_chunk(midpoint, chunk_size);

                let chunk_segments = segments_by_chunk.entry(chunk_id).or_insert_with(Vec::new);

                let mut appended = false;
                if let Some(last_seg) = chunk_segments.last_mut() {
                    if let Some(last_p) = last_seg.last() {
                        if (last_p.x - sp1.x).abs() < 0.001 && (last_p.z - sp1.z).abs() < 0.001 {
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
        }

        chunks.sort_by_key(|c| (c.id.z, c.id.x));

        ChunkManifest {
            schema_version: "0.2.0".to_string(),
            meta,
            chunks,
        }
    }
}

fn point_in_poly(p: Vec2, poly: &[Vec2]) -> bool {
    let mut inside = false;
    let mut j = poly.len() - 1;
    for i in 0..poly.len() {
        if ((poly[i].y > p.y) != (poly[j].y > p.y))
            && (p.x < (poly[j].x - poly[i].x) * (p.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x)
        {
            inside = !inside;
        }
        j = i;
    }
    inside
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
        let chunker = Chunker::new(100, 1.0, LatLon::new(0.0, 0.0));
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
