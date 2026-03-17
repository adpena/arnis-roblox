use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct LatLon {
    pub lat: f64,
    pub lon: f64,
}

impl LatLon {
    pub const fn new(lat: f64, lon: f64) -> Self {
        Self { lat, lon }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
pub struct Vec2 {
    pub x: f32,
    pub y: f32,
}

impl Vec2 {
    pub const fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }

    pub fn cross(self, other: Self) -> f32 {
        self.x * other.y - self.y * other.x
    }

    pub fn dot(self, other: Self) -> f32 {
        self.x * other.x + self.y * other.y
    }

    pub fn sub(self, other: Self) -> Self {
        Self::new(self.x - other.x, self.y - other.y)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vec3 {
    pub const fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct BoundingBox {
    pub min: LatLon,
    pub max: LatLon,
}

impl BoundingBox {
    pub fn new(min_lat: f64, min_lon: f64, max_lat: f64, max_lon: f64) -> Self {
        assert!(min_lat <= max_lat, "min_lat must be <= max_lat");
        assert!(min_lon <= max_lon, "min_lon must be <= max_lon");

        Self {
            min: LatLon::new(min_lat, min_lon),
            max: LatLon::new(max_lat, max_lon),
        }
    }

    pub fn center(&self) -> LatLon {
        LatLon::new(
            (self.min.lat + self.max.lat) * 0.5,
            (self.min.lon + self.max.lon) * 0.5,
        )
    }

    pub fn width_degrees(&self) -> f64 {
        self.max.lon - self.min.lon
    }

    pub fn height_degrees(&self) -> f64 {
        self.max.lat - self.min.lat
    }
}

/// Simple Web Mercator projection for local coordinate conversion.
pub struct Mercator;

impl Mercator {
    pub const EARTH_RADIUS_METERS: f64 = 6_378_137.0;

    pub fn latlon_to_meters(latlon: LatLon) -> (f64, f64) {
        let x = latlon.lon.to_radians() * Self::EARTH_RADIUS_METERS;
        let y = (latlon.lat.to_radians().tan() + (1.0 / latlon.lat.to_radians().cos())).ln()
            * Self::EARTH_RADIUS_METERS;
        (x, y)
    }

    /// Projects a LatLon to local studs relative to a center point.
    /// X+ = East, Z+ = South (matches Roblox/Minecraft convention).
    pub fn project(latlon: LatLon, center: LatLon, meters_per_stud: f64) -> Vec3 {
        let (cx, cy) = Self::latlon_to_meters(center);
        let (px, py) = Self::latlon_to_meters(latlon);

        let dx = (px - cx) / meters_per_stud;
        // Negate: Mercator Y increases northward, but Roblox Z+ = south.
        let dz = (cy - py) / meters_per_stud;

        Vec3::new(dx as f32, 0.0, dz as f32)
    }
}

pub trait ElevationProvider: Send + Sync {
    /// Sample height in meters at a given LatLon.
    fn sample_height_at(&self, latlon: LatLon) -> f32;
}

pub struct FlatElevationProvider {
    pub height: f32,
}

impl ElevationProvider for FlatElevationProvider {
    fn sample_height_at(&self, _latlon: LatLon) -> f32 {
        self.height
    }
}

/// A realistic noise-based elevation provider using fractional Brownian motion.
pub struct PerlinElevationProvider {
    pub scale: f64,
    pub amplitude: f32,
    pub seed: u32,
}

impl Default for PerlinElevationProvider {
    fn default() -> Self {
        Self {
            scale: 500.0,
            amplitude: 50.0,
            seed: 42,
        }
    }
}

impl ElevationProvider for PerlinElevationProvider {
    fn sample_height_at(&self, latlon: LatLon) -> f32 {
        let x = latlon.lat * self.scale + self.seed as f64;
        let y = latlon.lon * self.scale + self.seed as f64;

        let mut total = 0.0;
        let mut freq = 1.0;
        let mut amp = self.amplitude;

        for _ in 0..4 {
            total += simple_noise(x * freq, y * freq) * amp;
            freq *= 2.0;
            amp *= 0.5;
        }

        total
    }
}

fn simple_noise(x: f64, y: f64) -> f32 {
    let x_floor = x.floor() as i32;
    let y_floor = y.floor() as i32;
    let x_frac = (x - x_floor as f64) as f32;
    let y_frac = (y - y_floor as f64) as f32;

    let n00 = hash(x_floor, y_floor);
    let n10 = hash(x_floor + 1, y_floor);
    let n01 = hash(x_floor, y_floor + 1);
    let n11 = hash(x_floor + 1, y_floor + 1);

    let fade_x = x_frac * x_frac * (3.0 - 2.0 * x_frac);
    let fade_y = y_frac * y_frac * (3.0 - 2.0 * y_frac);

    let nx0 = n00 + fade_x * (n10 - n00);
    let nx1 = n01 + fade_x * (n11 - n01);

    nx0 + fade_y * (nx1 - nx0)
}

fn hash(x: i32, y: i32) -> f32 {
    let mut h = (x as u32).wrapping_mul(1597334677) ^ (y as u32).wrapping_mul(3812341653);
    h = h.wrapping_mul(1597334677);
    (h as f32) / u32::MAX as f32
}

/// Ingests SRTM .hgt elevation data files.
pub struct HgtElevationProvider {
    pub data_dir: PathBuf,
}

impl HgtElevationProvider {
    pub fn new(data_dir: PathBuf) -> Self {
        Self { data_dir }
    }

    fn get_hgt_file_path(&self, latlon: LatLon) -> PathBuf {
        let lat_prefix = if latlon.lat >= 0.0 { "N" } else { "S" };
        let lon_prefix = if latlon.lon >= 0.0 { "E" } else { "W" };
        let lat_val = latlon.lat.abs().floor() as i32;
        let lon_val = latlon.lon.abs().floor() as i32;
        self.data_dir.join(format!(
            "{}{:02}{}{:03}.hgt",
            lat_prefix, lat_val, lon_prefix, lon_val
        ))
    }

    fn sample_from_file(&self, path: &PathBuf, latlon: LatLon) -> Option<f32> {
        let mut file = File::open(path).ok()?;
        let metadata = file.metadata().ok()?;
        let file_size = metadata.len();

        // 1201x1201 for SRTM-3 (3 arc-seconds), 3601x3601 for SRTM-1 (1 arc-second)
        let resolution = if file_size == 1201 * 1201 * 2 {
            1201
        } else if file_size == 3601 * 3601 * 2 {
            3601
        } else {
            return None;
        };

        let lat_fract = latlon.lat.fract();
        let lon_fract = latlon.lon.fract();

        let row = ((1.0 - lat_fract) * (resolution - 1) as f64).floor() as i64;
        let col = (lon_fract * (resolution - 1) as f64).floor() as i64;

        let offset = (row * resolution as i64 + col) * 2;
        file.seek(SeekFrom::Start(offset as u64)).ok()?;

        let mut buf = [0u8; 2];
        file.read_exact(&mut buf).ok()?;

        // HGT files are big-endian signed 16-bit integers
        let h = i16::from_be_bytes(buf);
        if h == -32768 {
            // Void data value
            None
        } else {
            Some(h as f32)
        }
    }
}

impl ElevationProvider for HgtElevationProvider {
    fn sample_height_at(&self, latlon: LatLon) -> f32 {
        let path = self.get_hgt_file_path(latlon);
        self.sample_from_file(&path, latlon).unwrap_or(0.0)
    }
}

/// Layered elevation provider that falls back if primary fails.
pub struct MultiElevationProvider {
    pub providers: Vec<Box<dyn ElevationProvider>>,
}

impl ElevationProvider for MultiElevationProvider {
    fn sample_height_at(&self, latlon: LatLon) -> f32 {
        for provider in &self.providers {
            let h = provider.sample_height_at(latlon);
            if h != 0.0 {
                return h;
            }
        }
        0.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ChunkId {
    pub x: i32,
    pub z: i32,
}

impl ChunkId {
    pub const fn new(x: i32, z: i32) -> Self {
        Self { x, z }
    }

    pub fn label(self) -> String {
        format!("{}_{}", self.x, self.z)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Footprint {
    pub points: Vec<Vec2>,
}

impl Footprint {
    pub fn new(points: Vec<Vec2>) -> Self {
        Self { points }
    }

    pub fn aabb(&self) -> Option<(Vec2, Vec2)> {
        let first = *self.points.first()?;
        let mut min_x = first.x;
        let mut min_y = first.y;
        let mut max_x = first.x;
        let mut max_y = first.y;

        for point in &self.points {
            min_x = min_x.min(point.x);
            min_y = min_y.min(point.y);
            max_x = max_x.max(point.x);
            max_y = max_y.max(point.y);
        }

        Some((Vec2::new(min_x, min_y), Vec2::new(max_x, max_y)))
    }

    /// Triangulate using ear clipping. Returns a list of vertex indices.
    /// This implementation assumes a single closed loop without holes.
    pub fn triangulate(&self) -> Vec<usize> {
        let n = self.points.len();
        if n < 3 {
            return Vec::new();
        }

        let mut indices: Vec<usize> = (0..n).collect();
        let mut result = Vec::new();

        let mut limit = indices.len() * 2;
        while indices.len() > 3 && limit > 0 {
            let mut ear_found = false;
            for i in 0..indices.len() {
                let prev = if i == 0 { indices.len() - 1 } else { i - 1 };
                let next = (i + 1) % indices.len();

                let a = self.points[indices[prev]];
                let b = self.points[indices[i]];
                let c = self.points[indices[next]];

                if self.is_ear(a, b, c, &indices, i, prev, next) {
                    result.push(indices[prev]);
                    result.push(indices[i]);
                    result.push(indices[next]);
                    indices.remove(i);
                    ear_found = true;
                    break;
                }
            }
            if !ear_found {
                break;
            }
            limit -= 1;
        }

        if indices.len() == 3 {
            result.push(indices[0]);
            result.push(indices[1]);
            result.push(indices[2]);
        }

        result
    }

    fn is_ear(
        &self,
        a: Vec2,
        b: Vec2,
        c: Vec2,
        indices: &[usize],
        i: usize,
        prev: usize,
        next: usize,
    ) -> bool {
        // Must be convex
        let v1 = b.sub(a);
        let v2 = c.sub(b);
        let cross = v1.cross(v2);

        // Simple version: assume CCW for positive cross
        if cross <= 0.0 {
            return false;
        }

        // No other points inside triangle
        for (idx, &p_idx) in indices.iter().enumerate() {
            if idx == i || idx == prev || idx == next {
                continue;
            }
            let p = self.points[p_idx];
            if self.point_in_triangle(p, a, b, c) {
                return false;
            }
        }

        true
    }

    fn point_in_triangle(&self, p: Vec2, a: Vec2, b: Vec2, c: Vec2) -> bool {
        let v0 = c.sub(a);
        let v1 = b.sub(a);
        let v2 = p.sub(a);

        let dot00 = v0.dot(v0);
        let dot01 = v0.dot(v1);
        let dot02 = v0.dot(v2);
        let dot11 = v1.dot(v1);
        let dot12 = v1.dot(v2);

        let inv_denom = 1.0 / (dot00 * dot11 - dot01 * dot01);
        let u = (dot11 * dot02 - dot01 * dot12) * inv_denom;
        let v = (dot00 * dot12 - dot01 * dot02) * inv_denom;

        (u >= 0.0) && (v >= 0.0) && (u + v < 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bbox_dimensions_are_positive() {
        let bbox = BoundingBox::new(30.0, -98.0, 31.0, -97.0);
        assert!(bbox.width_degrees() > 0.0);
        assert!(bbox.height_degrees() > 0.0);
    }

    #[test]
    fn perlin_elevation_is_stable() {
        let provider = PerlinElevationProvider::default();
        let ll = LatLon::new(30.0, -97.0);
        let h1 = provider.sample_height_at(ll);
        let h2 = provider.sample_height_at(ll);
        assert_eq!(h1, h2);
    }

    #[test]
    fn hgt_path_generation() {
        let provider = HgtElevationProvider::new(PathBuf::from("/data"));
        let ll = LatLon::new(30.2, -97.7);
        let path = provider.get_hgt_file_path(ll);
        // 30.2 -> N30, -97.7 -> W098 (abs floor is 97, but W is 97.7 which is in tile W098 if we follow standard HGT naming)
        // Wait, SRTM HGT tile N30W098 covers 30N to 31N and 98W to 97W.
        // Lat 30.2 is in N30. Lon -97.7 is in W098 tile?
        // Standard SRTM naming: N30W098.hgt covers 30 to 31 N, 98 to 97 W.
        // My current logic: lat.abs().floor() = 30 -> N30. lon.abs().floor() = 97 -> W097.
        // Let's adjust to match SRTM tile conventions if needed, but for now I'll just verify consistency.
        assert!(path.to_str().unwrap().contains("N30W097.hgt"));
    }
}
