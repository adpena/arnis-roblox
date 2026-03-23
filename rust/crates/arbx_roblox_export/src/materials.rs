use crate::manifest::Color;
use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Clone, Deserialize)]
pub struct StyleEntry {
    pub material: String,
    pub color: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StyleMapper {
    pub terrain: HashMap<String, StyleEntry>,
    pub roads: HashMap<String, StyleEntry>,
    pub buildings: HashMap<String, StyleEntry>,
    pub props: HashMap<String, StyleEntry>,
}

impl Default for StyleMapper {
    fn default() -> Self {
        let mut terrain = HashMap::new();
        terrain.insert(
            "default".to_string(),
            StyleEntry {
                material: "Grass".to_string(),
                color: "#5ea044".to_string(),
            },
        );
        terrain.insert(
            "sand".to_string(),
            StyleEntry {
                material: "Sand".to_string(),
                color: "#d7c39a".to_string(),
            },
        );
        terrain.insert(
            "water".to_string(),
            StyleEntry {
                material: "Water".to_string(),
                color: "#0064c8".to_string(),
            },
        );
        terrain.insert(
            "swimming_pool".to_string(),
            StyleEntry {
                material: "Water".to_string(),
                color: "#3aa7d8".to_string(),
            },
        );

        let mut roads = HashMap::new();
        roads.insert(
            "default".to_string(),
            StyleEntry {
                material: "Asphalt".to_string(),
                color: "#333333".to_string(),
            },
        );
        roads.insert(
            "primary".to_string(),
            StyleEntry {
                material: "Asphalt".to_string(),
                color: "#444444".to_string(),
            },
        );
        roads.insert(
            "service".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#888888".to_string(),
            },
        );

        let mut buildings = HashMap::new();
        buildings.insert(
            "default".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#aaaaaa".to_string(),
            },
        );
        buildings.insert(
            "industrial".to_string(),
            StyleEntry {
                material: "Metal".to_string(),
                color: "#777777".to_string(),
            },
        );
        buildings.insert(
            "residential".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#ccaa88".to_string(),
            },
        );
        buildings.insert(
            "house".to_string(),
            StyleEntry {
                material: "WoodPlanks".to_string(),
                color: "#c29a73".to_string(),
            },
        );
        buildings.insert(
            "detached".to_string(),
            StyleEntry {
                material: "WoodPlanks".to_string(),
                color: "#c29a73".to_string(),
            },
        );
        buildings.insert(
            "apartments".to_string(),
            StyleEntry {
                material: "Brick".to_string(),
                color: "#c8a188".to_string(),
            },
        );
        buildings.insert(
            "terrace".to_string(),
            StyleEntry {
                material: "Brick".to_string(),
                color: "#b0674f".to_string(),
            },
        );
        buildings.insert(
            "dormitory".to_string(),
            StyleEntry {
                material: "Brick".to_string(),
                color: "#b57f64".to_string(),
            },
        );
        buildings.insert(
            "commercial".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#c9c4bc".to_string(),
            },
        );
        buildings.insert(
            "retail".to_string(),
            StyleEntry {
                material: "SmoothPlastic".to_string(),
                color: "#d8d2c8".to_string(),
            },
        );
        buildings.insert(
            "restaurant".to_string(),
            StyleEntry {
                material: "Brick".to_string(),
                color: "#c58a68".to_string(),
            },
        );
        buildings.insert(
            "office".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#c6c1b8".to_string(),
            },
        );
        buildings.insert(
            "bank".to_string(),
            StyleEntry {
                material: "Marble".to_string(),
                color: "#ddd8d0".to_string(),
            },
        );
        buildings.insert(
            "hotel".to_string(),
            StyleEntry {
                material: "Marble".to_string(),
                color: "#d7cfbf".to_string(),
            },
        );
        buildings.insert(
            "supermarket".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#c7c0b7".to_string(),
            },
        );
        buildings.insert(
            "hospital".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#d9dedf".to_string(),
            },
        );
        buildings.insert(
            "school".to_string(),
            StyleEntry {
                material: "Brick".to_string(),
                color: "#b67d63".to_string(),
            },
        );
        buildings.insert(
            "university".to_string(),
            StyleEntry {
                material: "Limestone".to_string(),
                color: "#ddd3c0".to_string(),
            },
        );
        buildings.insert(
            "civic".to_string(),
            StyleEntry {
                material: "Limestone".to_string(),
                color: "#d7d0c4".to_string(),
            },
        );
        buildings.insert(
            "government".to_string(),
            StyleEntry {
                material: "Limestone".to_string(),
                color: "#d8d1c4".to_string(),
            },
        );
        buildings.insert(
            "courthouse".to_string(),
            StyleEntry {
                material: "Marble".to_string(),
                color: "#e0d9d0".to_string(),
            },
        );
        buildings.insert(
            "warehouse".to_string(),
            StyleEntry {
                material: "Metal".to_string(),
                color: "#90969a".to_string(),
            },
        );
        buildings.insert(
            "factory".to_string(),
            StyleEntry {
                material: "Metal".to_string(),
                color: "#858b8f".to_string(),
            },
        );
        buildings.insert(
            "parking".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#bdb8b0".to_string(),
            },
        );
        buildings.insert(
            "garage".to_string(),
            StyleEntry {
                material: "Metal".to_string(),
                color: "#8e8b84".to_string(),
            },
        );
        buildings.insert(
            "shed".to_string(),
            StyleEntry {
                material: "WoodPlanks".to_string(),
                color: "#9c7956".to_string(),
            },
        );
        buildings.insert(
            "religious".to_string(),
            StyleEntry {
                material: "Limestone".to_string(),
                color: "#d8cfbf".to_string(),
            },
        );
        buildings.insert(
            "church".to_string(),
            StyleEntry {
                material: "Cobblestone".to_string(),
                color: "#9c9387".to_string(),
            },
        );
        buildings.insert(
            "cathedral".to_string(),
            StyleEntry {
                material: "Cobblestone".to_string(),
                color: "#999087".to_string(),
            },
        );
        buildings.insert(
            "mosque".to_string(),
            StyleEntry {
                material: "Marble".to_string(),
                color: "#ddd6cb".to_string(),
            },
        );
        buildings.insert(
            "temple".to_string(),
            StyleEntry {
                material: "Sandstone".to_string(),
                color: "#d2ba8d".to_string(),
            },
        );
        buildings.insert(
            "building".to_string(),
            StyleEntry {
                material: "Concrete".to_string(),
                color: "#bdb8b0".to_string(),
            },
        );

        // Add specific facade styles that the builder will recognize
        buildings.insert(
            "facade_modern".to_string(),
            StyleEntry {
                material: "SmoothPlastic".to_string(),
                color: "#ffffff".to_string(),
            },
        );
        buildings.insert(
            "facade_brick".to_string(),
            StyleEntry {
                material: "Brick".to_string(),
                color: "#aa4444".to_string(),
            },
        );

        let mut props = HashMap::new();
        props.insert(
            "tree".to_string(),
            StyleEntry {
                material: "Grass".to_string(),
                color: "#329632".to_string(),
            },
        );
        props.insert(
            "light".to_string(),
            StyleEntry {
                material: "Metal".to_string(),
                color: "#cccccc".to_string(),
            },
        );

        Self {
            terrain,
            roads,
            buildings,
            props,
        }
    }
}

impl StyleMapper {
    pub fn load_json(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|e| format!("Failed to parse palette: {}", e))
    }

    fn get_entry<'a>(map: &'a HashMap<String, StyleEntry>, key: &str) -> &'a StyleEntry {
        map.get(key)
            .or_else(|| map.get("default"))
            .unwrap_or_else(|| map.values().next().expect("empty style map"))
    }

    pub fn get_terrain_material(&self, tag: &str) -> String {
        Self::get_entry(&self.terrain, tag).material.clone()
    }

    pub fn get_terrain_color(&self, tag: &str) -> Option<Color> {
        parse_hex(&Self::get_entry(&self.terrain, tag).color)
    }

    pub fn get_road_material(&self, kind: &str) -> String {
        Self::get_entry(&self.roads, kind).material.clone()
    }

    pub fn get_road_color(&self, kind: &str) -> Option<Color> {
        parse_hex(&Self::get_entry(&self.roads, kind).color)
    }

    pub fn get_building_material(&self, kind: &str) -> String {
        Self::get_entry(&self.buildings, kind).material.clone()
    }

    pub fn get_building_color(&self, kind: &str) -> Option<Color> {
        parse_hex(&Self::get_entry(&self.buildings, kind).color)
    }

    pub fn get_prop_material(&self, kind: &str) -> String {
        Self::get_entry(&self.props, kind).material.clone()
    }

    pub fn get_prop_color(&self, kind: &str) -> Option<Color> {
        parse_hex(&Self::get_entry(&self.props, kind).color)
    }
}

fn parse_hex(hex: &str) -> Option<Color> {
    let hex = hex.trim_start_matches('#');
    if hex.len() != 6 {
        return None;
    }
    let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
    let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
    let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
    Some(Color::new(r, g, b))
}

pub fn road_material(kind: &str) -> &'static str {
    match kind {
        "primary" => "Asphalt",
        "secondary" => "Concrete",
        "service" => "Concrete",
        _ => "Asphalt",
    }
}

pub fn building_material(kind: &str) -> &'static str {
    match kind {
        "industrial" => "Metal",
        "residential" => "Concrete",
        _ => "Concrete",
    }
}

pub fn terrain_material(tag: &str) -> &'static str {
    match tag {
        "sand" => "Sand",
        "water" => "Water",
        _ => "Grass",
    }
}
