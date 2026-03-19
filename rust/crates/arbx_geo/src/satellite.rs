use crate::LatLon;
use image::{DynamicImage, GenericImageView};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Copy)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    pub fn brightness(&self) -> f32 {
        self.r as f32 * 0.299 + self.g as f32 * 0.587 + self.b as f32 * 0.114
    }
}

/// Maximum number of decoded satellite tiles held in memory at once.
/// Each z17 tile is ~256×256 RGBA = ~256KB decoded. 64 tiles ≈ 16MB.
const MAX_CACHED_TILES: usize = 64;

pub struct SatelliteTileProvider {
    zoom: u32,
    cache_dir: PathBuf,
    tiles: HashMap<(u32, u32), DynamicImage>,
}

impl SatelliteTileProvider {
    pub fn new(cache_dir: &str) -> Self {
        let cache_path = PathBuf::from(cache_dir);
        fs::create_dir_all(&cache_path).ok();
        Self {
            zoom: 17,
            cache_dir: cache_path,
            tiles: HashMap::new(),
        }
    }

    /// Sample a single pixel color at a lat/lon coordinate
    pub fn sample_pixel(&mut self, latlon: LatLon) -> Option<Rgb> {
        let zoom = self.zoom;
        let (tx, ty) = latlon_to_tile(latlon, zoom);
        let tile = self.get_or_fetch_tile(tx, ty)?;
        let (px, py) = latlon_to_pixel_in_tile(latlon, zoom, tx, ty);
        let px = px.min(tile.width() - 1);
        let py = py.min(tile.height() - 1);
        let pixel = tile.get_pixel(px, py);
        Some(Rgb { r: pixel[0], g: pixel[1], b: pixel[2] })
    }

    /// Sample dominant color at centroid of a polygon given as LatLon points
    pub fn sample_polygon_centroid(&mut self, points: &[LatLon]) -> Option<Rgb> {
        if points.is_empty() { return None; }
        let n = points.len() as f64;
        let lat = points.iter().map(|p| p.lat).sum::<f64>() / n;
        let lon = points.iter().map(|p| p.lon).sum::<f64>() / n;
        self.sample_pixel(LatLon::new(lat, lon))
    }

    fn get_or_fetch_tile(&mut self, tx: u32, ty: u32) -> Option<&DynamicImage> {
        if !self.tiles.contains_key(&(tx, ty)) {
            // Evict oldest tiles if cache is full (simple strategy: clear half)
            if self.tiles.len() >= MAX_CACHED_TILES {
                let keys: Vec<_> = self.tiles.keys().copied().take(MAX_CACHED_TILES / 2).collect();
                for k in keys {
                    self.tiles.remove(&k);
                }
            }
            let img = self.fetch_tile(tx, ty)?;
            self.tiles.insert((tx, ty), img);
        }
        self.tiles.get(&(tx, ty))
    }

    fn fetch_tile(&self, tx: u32, ty: u32) -> Option<DynamicImage> {
        let cache_file = self.cache_dir.join(format!("sat_z{}_{tx}_{ty}.jpg", self.zoom));
        if cache_file.exists() {
            return image::open(&cache_file).ok();
        }

        // Use ESRI World Imagery (free, no API key, good quality)
        // NOTE: ESRI tile URL format uses z/y/x (not z/x/y like Mapbox)
        let url = format!(
            "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{}/{}/{}",
            self.zoom, ty, tx
        );

        eprintln!("[satellite] fetching tile z{}/{}/{}", self.zoom, tx, ty);
        // Be polite: 200ms delay between tile fetches
        std::thread::sleep(std::time::Duration::from_millis(200));

        let cache_str = cache_file.to_str()?;
        let output = std::process::Command::new("curl")
            .args([
                "-sL",
                "--fail",
                "--user-agent", "arnis-roblox/1.0 (open-source educational project)",
                "--retry", "2",
                "--retry-delay", "3",
                "-o", cache_str,
                &url,
            ])
            .output()
            .ok()?;

        if !output.status.success() {
            eprintln!("[satellite] WARN: tile fetch failed z{}/{}/{}", self.zoom, tx, ty);
            let _ = fs::remove_file(&cache_file);
            return None;
        }

        image::open(&cache_file).ok()
    }
}

// --- Material classification from pixel colors ---

/// Classify roof material from satellite pixel
pub fn classify_roof_material(rgb: Rgb) -> &'static str {
    let b = rgb.brightness();
    let r = rgb.r as f32;
    let g = rgb.g as f32;
    let blue = rgb.b as f32;

    if b < 80.0 { return "Asphalt"; }
    if b > 200.0 && (r - g).abs() < 30.0 { return "Metal"; }
    if r > 150.0 && g < 120.0 && blue < 120.0 { return "Brick"; }
    if r > 100.0 && g > 80.0 && blue < 80.0 { return "WoodPlanks"; }
    if g > r && g > blue && g > 120.0 { return "Slate"; }
    if b > 160.0 { return "Concrete"; }
    "Concrete"
}

/// Classify ground cover material from satellite pixel
pub fn classify_ground_material(rgb: Rgb) -> &'static str {
    let green_dom = (rgb.g as f32 - rgb.r as f32) / 255.0;
    let b = rgb.brightness();

    if green_dom > 0.15 { return "Grass"; }
    if green_dom > 0.05 { return "LeafyGrass"; }
    if b > 200.0 { return "Concrete"; }
    if b > 160.0 { return "Pavement"; }
    if b > 100.0 { return "Asphalt"; }
    if b > 60.0 { return "Ground"; }
    "Rock"
}

/// Convert satellite roof pixel to a Color3-equivalent RGB tuple
pub fn roof_pixel_to_color(rgb: Rgb) -> (u8, u8, u8) {
    // Slightly desaturate for a natural look
    let avg = rgb.brightness() as u8;
    let r = ((rgb.r as u16 + avg as u16) / 2) as u8;
    let g = ((rgb.g as u16 + avg as u16) / 2) as u8;
    let b = ((rgb.b as u16 + avg as u16) / 2) as u8;
    (r, g, b)
}

// --- Tile math (standard Web Mercator) ---

fn latlon_to_tile(ll: LatLon, zoom: u32) -> (u32, u32) {
    let n = 2u64.pow(zoom) as f64;
    let x = ((ll.lon + 180.0) / 360.0 * n) as u32;
    let lat_rad = ll.lat.to_radians();
    let y = ((1.0 - (lat_rad.tan() + 1.0 / lat_rad.cos()).ln() / std::f64::consts::PI) / 2.0 * n) as u32;
    (x, y)
}

fn latlon_to_pixel_in_tile(ll: LatLon, zoom: u32, tx: u32, ty: u32) -> (u32, u32) {
    let n = 2u64.pow(zoom) as f64;
    let x_frac = (ll.lon + 180.0) / 360.0 * n - tx as f64;
    let lat_rad = ll.lat.to_radians();
    let y_frac = (1.0 - (lat_rad.tan() + 1.0 / lat_rad.cos()).ln() / std::f64::consts::PI) / 2.0 * n - ty as f64;
    ((x_frac * 256.0) as u32, (y_frac * 256.0) as u32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brightness_formula_is_correct() {
        let white = Rgb { r: 255, g: 255, b: 255 };
        let black = Rgb { r: 0, g: 0, b: 0 };
        assert!((white.brightness() - 255.0).abs() < 1.0);
        assert_eq!(black.brightness(), 0.0);
    }

    #[test]
    fn classify_roof_dark_is_asphalt() {
        let dark = Rgb { r: 30, g: 30, b: 30 };
        assert_eq!(classify_roof_material(dark), "Asphalt");
    }

    #[test]
    fn classify_roof_bright_neutral_is_metal() {
        let bright_neutral = Rgb { r: 210, g: 210, b: 210 };
        assert_eq!(classify_roof_material(bright_neutral), "Metal");
    }

    #[test]
    fn classify_roof_red_is_brick() {
        let reddish = Rgb { r: 180, g: 90, b: 80 };
        assert_eq!(classify_roof_material(reddish), "Brick");
    }

    #[test]
    fn classify_ground_green_dominant_is_grass() {
        let green = Rgb { r: 60, g: 120, b: 50 };
        assert_eq!(classify_ground_material(green), "Grass");
    }

    #[test]
    fn classify_ground_bright_grey_is_concrete() {
        let bright = Rgb { r: 210, g: 210, b: 210 };
        assert_eq!(classify_ground_material(bright), "Concrete");
    }

    #[test]
    fn roof_pixel_to_color_desaturates() {
        let rgb = Rgb { r: 200, g: 100, b: 50 };
        let (r, g, b) = roof_pixel_to_color(rgb);
        // Result should be between source channel and brightness average
        assert!(r > 0 && g > 0 && b > 0);
        // Desaturation: channels should be closer together than input
        let in_range = (200u16 - 50) as f32;
        let out_range = (r as i16 - b as i16).unsigned_abs() as f32;
        assert!(out_range < in_range);
    }

    #[test]
    fn tile_math_austin_tx() {
        // Austin, TX: ~30.27N, -97.74W
        let ll = LatLon::new(30.27, -97.74);
        let (tx, ty) = latlon_to_tile(ll, 17);
        // At zoom 17, tile counts are 2^17 = 131072
        assert!(tx < 131072);
        assert!(ty < 131072);
        // Pixel within tile should be in [0, 255]
        let (px, py) = latlon_to_pixel_in_tile(ll, 17, tx, ty);
        assert!(px < 256);
        assert!(py < 256);
    }
}
