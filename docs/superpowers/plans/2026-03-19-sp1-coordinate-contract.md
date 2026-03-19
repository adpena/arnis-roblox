# SP-1: Coordinate Contract & Scale — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the coordinate system so all layers agree on ground level, scale is human-proportional, and the Rust exporter is the single elevation authority.

**Architecture:** Change `meters_per_stud` from 1.0 to 0.3 everywhere, increase terrain resolution from 16-stud to 4-stud cells with 2-stud voxels, remove all Lua-side ground snapping from builders so they use manifest values directly, add `elevated`/`tunnel` flags to roads and `surfaceY` to water. Schema bumps from 0.3.0 to 0.4.0 with migration.

**Tech Stack:** Rust (arbx_roblox_export, arbx_pipeline), Lua (Roblox ImportService builders), JSON schema

**Spec:** `docs/superpowers/specs/2026-03-19-arnis-hd-pipeline-design.md`

---

### Task 1: Rust — Change default scale to 0.3 m/stud

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs:29`

- [ ] **Step 1: Update the default meters_per_stud**

In `rust/crates/arbx_roblox_export/src/lib.rs`, change line 29:

```rust
// Before:
meters_per_stud: 1.0,
// After:
meters_per_stud: 0.3,
```

- [ ] **Step 2: Run Rust tests to see what breaks**

Run: `cd rust && cargo test 2>&1 | head -80`

Expected: Some tests may fail due to changed coordinate values. Note which ones fail — we'll fix them in Task 8.

- [ ] **Step 3: Commit**

```bash
git add rust/crates/arbx_roblox_export/src/lib.rs
git commit -m "chore(rust): change default meters_per_stud from 1.0 to 0.3"
```

---

### Task 2: Rust — Increase terrain cell size from 16 to 4

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/chunker.rs:121`

- [ ] **Step 1: Change cell_size in ensure_chunk()**

In `rust/crates/arbx_roblox_export/src/chunker.rs`, change line 121:

```rust
// Before:
let cell_size = 16;
// After:
let cell_size = 4;
```

This changes the terrain grid from 16x16 (256 cells) to 64x64 (4,096 cells) per chunk.

- [ ] **Step 2: Update sample manifest terrain dimensions**

In `rust/crates/arbx_roblox_export/src/lib.rs`, update the manual sample terrain (lines 66-73):

```rust
// Before:
terrain: Some(TerrainGrid {
    cell_size_studs: 16,
    width: 16, // Match 256/16
    depth: 16,
    heights: vec![0.0; 256],
// After:
terrain: Some(TerrainGrid {
    cell_size_studs: 4,
    width: 64, // Match 256/4
    depth: 64,
    heights: vec![0.0; 4096],
```

- [ ] **Step 3: Commit**

```bash
git add rust/crates/arbx_roblox_export/src/chunker.rs rust/crates/arbx_roblox_export/src/lib.rs
git commit -m "chore(rust): increase terrain grid from 16-stud to 4-stud cells (64x64)"
```

---

### Task 3: Rust — Add new schema fields to manifest structs

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/manifest.rs`

- [ ] **Step 1: Add `elevated` and `tunnel` to RoadSegment**

In `rust/crates/arbx_roblox_export/src/manifest.rs`, after line 49 (`pub surface: Option<String>,`):

```rust
pub elevated: bool,
pub tunnel: bool,
pub sidewalk: Option<String>,
```

- [ ] **Step 2: Rename `color` to `wall_color` and add `roof_color` on BuildingShell**

In `rust/crates/arbx_roblox_export/src/manifest.rs`, change lines 69-70:

```rust
// Before:
pub color: Option<Color>,
// After:
pub wall_color: Option<Color>,
pub roof_color: Option<Color>,
pub roof_shape: Option<String>,
pub roof_material: Option<String>,
pub usage: Option<String>,
pub min_height: Option<f64>,
```

- [ ] **Step 3: Add `surface_y` to WaterFeature**

In `rust/crates/arbx_roblox_export/src/manifest.rs`, after line 104 (`pub indices: Option<Vec<usize>>,`):

```rust
pub surface_y: Option<f64>,
```

- [ ] **Step 4: Fix all compilation errors from struct field renames**

Search the codebase for all references to `BuildingShell { ... color:` and `RoadSegment { ... }` construction sites. Update:
- `rust/crates/arbx_roblox_export/src/chunker.rs` — the `ingest()` function for roads (~line 204) and buildings (~line 393)
- `rust/crates/arbx_roblox_export/src/lib.rs` — the sample manifest building (~line 95)

For roads in chunker.rs `ingest()` (~line 204), add the new fields:

```rust
chunk.roads.push(RoadSegment {
    id: f.id.clone(),
    kind: f.kind.clone(),
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
});
```

For buildings in chunker.rs `ingest()` (~line 393), rename `color` and add new fields:

```rust
chunk.buildings.push(BuildingShell {
    id: f.id,
    footprint: relative_footprint,
    indices: f.indices,
    material,
    wall_color: color,
    roof_color: None, // Will be populated by SP-4 satellite pipeline
    roof_shape: Some(f.roof.clone()),
    roof_material: f.material_tag.clone(),
    usage: f.usage.clone(),
    min_height: f.min_height,
    base_y: f.base_y - origin.y,
    height: f.height,
    height_m: f.height_m,
    levels: f.levels,
    roof_levels: f.roof_levels,
    facade_style,
    roof: f.roof,
    rooms,
});
```

For water polygon in chunker.rs (~line 299), add `surface_y`:

```rust
chunk.water.push(ManifestWaterFeature {
    // ... existing fields ...
    surface_y: None, // Will be computed from DEM in SP-2
});
```

For water ribbon in chunker.rs (~line 253), add `surface_y: None`.

For sample manifest building in lib.rs (~line 95):

```rust
wall_color: None,
roof_color: None,
roof_shape: Some("flat".to_string()),
roof_material: None,
usage: None,
min_height: None,
```

- [ ] **Step 5: Run `cargo check` to verify compilation**

Run: `cd rust && cargo check 2>&1`
Expected: No errors. Warnings about unused fields are OK for now.

- [ ] **Step 6: Commit**

```bash
git add rust/crates/arbx_roblox_export/src/manifest.rs rust/crates/arbx_roblox_export/src/chunker.rs rust/crates/arbx_roblox_export/src/lib.rs
git commit -m "feat(rust): add elevated/tunnel/sidewalk to roads, wallColor/roofColor to buildings, surfaceY to water"
```

---

### Task 4: Rust — Update JSON serialization for new fields

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/manifest.rs` (write_json implementations)

- [ ] **Step 1: Update RoadSegment::write_json**

In `manifest.rs`, in the `impl RoadSegment` `write_json` method (~line 351), after the `surface` field serialization (after line 383), add:

```rust
out.push_str(",\n");
write_key(out, indent + 2, "elevated");
out.push_str(if self.elevated { "true" } else { "false" });
out.push_str(",\n");
write_key(out, indent + 2, "tunnel");
out.push_str(if self.tunnel { "true" } else { "false" });
if let Some(ref s) = self.sidewalk {
    out.push_str(",\n");
    write_key(out, indent + 2, "sidewalk");
    write_string(out, s);
}
```

- [ ] **Step 2: Update BuildingShell::write_json**

In `manifest.rs`, in the `impl BuildingShell` `write_json` method (~line 427):

Replace the `color` serialization (lines 436-440):
```rust
// Before:
if let Some(color) = self.color {
    out.push_str(",\n");
    write_key(out, indent + 2, "color");
    write_color(out, color);
}
// After:
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
if let Some(ref shape) = self.roof_shape {
    out.push_str(",\n");
    write_key(out, indent + 2, "roofShape");
    write_string(out, shape);
}
if let Some(ref mat) = self.roof_material {
    out.push_str(",\n");
    write_key(out, indent + 2, "roofMaterial");
    write_string(out, mat);
}
if let Some(ref usage) = self.usage {
    out.push_str(",\n");
    write_key(out, indent + 2, "usage");
    write_string(out, usage);
}
if let Some(mh) = self.min_height {
    out.push_str(",\n");
    write_key(out, indent + 2, "minHeight");
    write_number(out, mh);
}
```

- [ ] **Step 3: Update WaterFeature::write_json**

In `manifest.rs`, in `impl WaterFeature` `write_json` (~line 541), after the `indices` serialization, add:

```rust
if let Some(sy) = self.surface_y {
    out.push_str(",\n");
    write_key(out, indent + 2, "surfaceY");
    write_number(out, sy);
}
```

- [ ] **Step 4: Run `cargo check`**

Run: `cd rust && cargo check 2>&1`
Expected: Clean compilation.

- [ ] **Step 5: Commit**

```bash
git add rust/crates/arbx_roblox_export/src/manifest.rs
git commit -m "feat(rust): serialize new schema 0.4.0 fields in JSON output"
```

---

### Task 5: Rust — Add new fields to pipeline Feature structs

**Files:**
- Modify: `rust/crates/arbx_pipeline/src/lib.rs`

- [ ] **Step 1: Add `elevated`, `tunnel`, `sidewalk` to RoadFeature**

In `rust/crates/arbx_pipeline/src/lib.rs`, after line 19 (`pub surface: Option<String>,`):

```rust
pub elevated: Option<bool>,
pub tunnel: Option<bool>,
pub sidewalk: Option<String>,
```

- [ ] **Step 2: Fix compilation errors in OverpassAdapter**

In the same file, in `emit_linear_way()` (~line 776), update the `RoadFeature` construction to include the new fields:

```rust
features.push(Feature::Road(RoadFeature {
    id: format!("osm_{}", id),
    kind: highway.clone(),
    lanes,
    width_studs,
    has_sidewalk,
    surface: tags.get("surface").cloned(),
    elevated: if tags.get("bridge").map(|v| v != "no").unwrap_or(false) { Some(true) } else { None },
    tunnel: if tags.get("tunnel").map(|v| v != "no").unwrap_or(false) { Some(true) } else { None },
    sidewalk: tags.get("sidewalk").cloned(),
    points: pts,
}));
```

Also remove the old `y_offset` bridge/tunnel hack (lines 782-785). The Y offset is no longer baked into point positions — the `elevated`/`tunnel` flags replace it:

```rust
// DELETE these lines:
// let y_offset: f64 = if tags.get("bridge").map(|v| v != "no").unwrap_or(false) { 8.0 }
//     else if tags.get("tunnel").map(|v| v != "no").unwrap_or(false) { -8.0 }
//     else { 0.0 };
// let pts = points.into_iter().map(|mut p| { p.y += y_offset; p }).collect();

// REPLACE with:
let pts = points;
```

- [ ] **Step 3: Fix SyntheticAustinAdapter road construction**

In `SyntheticAustinAdapter::load()` (~line 230), add the new fields:

```rust
features.push(Feature::Road(RoadFeature {
    // ... existing fields ...
    elevated: None,
    tunnel: None,
    sidewalk: Some("both".to_string()),
    // ... existing points ...
}));
```

- [ ] **Step 4: Fix DummyAdapter in tests**

In the test module (~line 887), add new fields to the test RoadFeature if any exist, and update BuildingFeature construction if needed.

- [ ] **Step 5: Run `cargo check` across workspace**

Run: `cd rust && cargo check --workspace 2>&1`
Expected: Clean compilation across all crates.

- [ ] **Step 6: Commit**

```bash
git add rust/crates/arbx_pipeline/src/lib.rs
git commit -m "feat(rust): add elevated/tunnel/sidewalk fields to RoadFeature, remove Y-offset bridge hack"
```

---

### Task 6: Rust — Bump schema version to 0.4.0

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs:351`
- Modify: `rust/crates/arbx_roblox_export/src/chunker.rs:572`

- [ ] **Step 1: Update schema_version in finish() and export_to_chunks()**

In `chunker.rs` line 572:
```rust
// Before:
schema_version: "0.3.0".to_string(),
// After:
schema_version: "0.4.0".to_string(),
```

In `lib.rs` line 351:
```rust
// Before:
manifest.schema_version = "0.3.0".to_string();
// After:
manifest.schema_version = "0.4.0".to_string();
```

- [ ] **Step 2: Commit**

```bash
git add rust/crates/arbx_roblox_export/src/chunker.rs rust/crates/arbx_roblox_export/src/lib.rs
git commit -m "chore(rust): bump schema version to 0.4.0"
```

---

### Task 7: Rust — Fix all Rust tests

**Files:**
- Modify: `rust/crates/arbx_roblox_export/tests/integration.rs`
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs` (test module)

- [ ] **Step 1: Run all tests and capture failures**

Run: `cd rust && cargo test --workspace 2>&1`

Note: Tests will fail because schema version changed to "0.4.0", scale changed to 0.3, and terrain dimensions changed.

- [ ] **Step 2: Fix integration test schema version assertions**

In `rust/crates/arbx_roblox_export/tests/integration.rs`, update schema version checks:

```rust
// Before:
assert_eq!(manifest.schema_version, "0.3.0");
// After:
assert_eq!(manifest.schema_version, "0.4.0");
```

Also update any JSON string assertions:
```rust
// Before:
assert!(json.contains("\"schemaVersion\": \"0.3.0\""));
// After:
assert!(json.contains("\"schemaVersion\": \"0.4.0\""));
```

- [ ] **Step 3: Fix terrain dimension assertions**

Any test asserting `terrain.width == 16` or `heights.len() == 256` should change to `terrain.width == 64` and `heights.len() == 4096`.

- [ ] **Step 4: Fix coordinate value assertions**

Tests asserting specific stud-space coordinates will change because 0.3 m/stud produces ~3.33x larger stud values. Update expected values based on the new scale. For sample data, the assertion values will be different but the relationships should hold (e.g., building still inside its chunk).

- [ ] **Step 5: Fix pipeline tests (OverpassAdapter)**

In `arbx_pipeline/src/lib.rs` test module, update `OverpassAdapter` construction:
```rust
// Before:
meters_per_stud: 1.0,
// After:
meters_per_stud: 0.3,
```

Note: The OverpassAdapter test creates its own adapter with explicit `meters_per_stud`, so this may already be 1.0 and should remain as-is if the test is testing a specific scale. Only change if the test is meant to use the default.

- [ ] **Step 6: Run all tests and verify pass**

Run: `cd rust && cargo test --workspace 2>&1`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A rust/
git commit -m "test(rust): update tests for schema 0.4.0, 0.3 m/stud scale, 64x64 terrain"
```

---

### Task 8: Lua — Bump schema version to 0.4.0

**Files:**
- Modify: `roblox/src/ReplicatedStorage/Shared/Version.lua`

- [ ] **Step 1: Update SchemaVersion**

In `roblox/src/ReplicatedStorage/Shared/Version.lua`, change:

```lua
-- Before:
SchemaVersion = "0.3.0",
-- After:
SchemaVersion = "0.4.0",
```

- [ ] **Step 2: Commit**

```bash
git add roblox/src/ReplicatedStorage/Shared/Version.lua
git commit -m "chore(lua): bump SchemaVersion to 0.4.0"
```

---

### Task 9: Lua — Write 0.3.0 to 0.4.0 migration

**Files:**
- Modify: `roblox/src/ReplicatedStorage/Shared/Migrations.lua`

- [ ] **Step 1: Add migration chain entry**

In `Migrations.lua`, after line 20 (`current = "0.3.0"`), add:

```lua
    if current == "0.3.0" then
        migrated = Migrations.migrate_030_to_040(migrated)
        current = "0.4.0"
    end
```

- [ ] **Step 2: Write the migration function**

Add before the `return Migrations` line at the bottom:

```lua
function Migrations.migrate_030_to_040(manifest)
    -- Scale factor: old manifests used meters_per_stud=1.0, new uses 0.3
    -- All spatial stud coordinates must be multiplied by (old_mps / new_mps) = 1.0/0.3
    local oldMps = manifest.meta.metersPerStud or 1.0
    local newMps = 0.3
    local scaleFactor = oldMps / newMps

    -- Only scale if actually changing from a different mps
    if math.abs(scaleFactor - 1.0) < 0.001 then
        -- Already at correct scale, just add new field defaults
        return manifest
    end

    manifest.meta.metersPerStud = newMps
    manifest.meta.chunkSizeStuds = manifest.meta.chunkSizeStuds * scaleFactor

    for _, chunk in ipairs(manifest.chunks or {}) do
        -- Scale chunk origin
        chunk.originStuds.x = chunk.originStuds.x * scaleFactor
        chunk.originStuds.y = chunk.originStuds.y * scaleFactor
        chunk.originStuds.z = chunk.originStuds.z * scaleFactor

        -- Scale terrain heights (grid dimensions stay the same)
        if chunk.terrain then
            chunk.terrain.cellSizeStuds = chunk.terrain.cellSizeStuds * scaleFactor
            for i, h in ipairs(chunk.terrain.heights) do
                chunk.terrain.heights[i] = h * scaleFactor
            end
        end

        -- Scale roads
        for _, road in ipairs(chunk.roads or {}) do
            road.widthStuds = road.widthStuds * scaleFactor
            for _, pt in ipairs(road.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
            -- Default new fields
            if road.elevated == nil then road.elevated = false end
            if road.tunnel == nil then road.tunnel = false end
        end

        -- Scale rails
        for _, rail in ipairs(chunk.rails or {}) do
            rail.widthStuds = rail.widthStuds * scaleFactor
            for _, pt in ipairs(rail.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
        end

        -- Scale buildings
        for _, building in ipairs(chunk.buildings or {}) do
            building.baseY = building.baseY * scaleFactor
            building.height = building.height * scaleFactor
            -- height_m stays in meters (NOT scaled)
            -- levels, roofLevels stay as counts (NOT scaled)
            for _, pt in ipairs(building.footprint or {}) do
                pt.x = pt.x * scaleFactor
                pt.z = pt.z * scaleFactor
            end
            -- Rename color -> wallColor if present
            if building.color and not building.wallColor then
                building.wallColor = building.color
                building.color = nil
            end
            -- Scale rooms
            for _, room in ipairs(building.rooms or {}) do
                room.floorY = room.floorY * scaleFactor
                room.height = room.height * scaleFactor
                for _, pt in ipairs(room.footprint or {}) do
                    pt.x = pt.x * scaleFactor
                    pt.z = pt.z * scaleFactor
                end
            end
        end

        -- Scale water
        for _, water in ipairs(chunk.water or {}) do
            if water.widthStuds then
                water.widthStuds = water.widthStuds * scaleFactor
            end
            for _, pt in ipairs(water.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
            if water.footprint then
                for _, pt in ipairs(water.footprint) do
                    pt.x = pt.x * scaleFactor
                    pt.z = pt.z * scaleFactor
                end
            end
            if water.holes then
                for _, hole in ipairs(water.holes) do
                    for _, pt in ipairs(hole) do
                        pt.x = pt.x * scaleFactor
                        pt.z = pt.z * scaleFactor
                    end
                end
            end
        end

        -- Scale props
        for _, prop in ipairs(chunk.props or {}) do
            prop.position.x = prop.position.x * scaleFactor
            prop.position.y = prop.position.y * scaleFactor
            prop.position.z = prop.position.z * scaleFactor
            -- yawDegrees and scale are NOT scaled
        end

        -- Scale landuse
        for _, lu in ipairs(chunk.landuse or {}) do
            for _, pt in ipairs(lu.footprint or {}) do
                pt.x = pt.x * scaleFactor
                pt.z = pt.z * scaleFactor
            end
        end

        -- Scale barriers
        for _, barrier in ipairs(chunk.barriers or {}) do
            for _, pt in ipairs(barrier.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
        end
    end

    return manifest
end
```

- [ ] **Step 3: Commit**

```bash
git add roblox/src/ReplicatedStorage/Shared/Migrations.lua
git commit -m "feat(lua): add 0.3.0 -> 0.4.0 migration with scale transform"
```

---

### Task 10: Lua — Update ChunkSchema validation for new fields

**Files:**
- Modify: `roblox/src/ReplicatedStorage/Shared/ChunkSchema.lua`

- [ ] **Step 1: Add terrain array length validation**

In `ChunkSchema.lua`, after line 99 (`assertType(terrain.material, "string"...`), add:

```lua
            assert(
                #terrain.heights == terrain.width * terrain.depth,
                prefix .. ".terrain.heights length must equal width * depth"
            )
            if terrain.materials ~= nil then
                assertType(terrain.materials, "table", prefix .. ".terrain.materials must be a table")
                assert(
                    #terrain.materials == terrain.width * terrain.depth,
                    prefix .. ".terrain.materials length must equal width * depth"
                )
            end
```

Remove the duplicate materials validation that currently exists on lines 100-102.

- [ ] **Step 2: Add road elevated/tunnel validation**

In `ChunkSchema.lua`, after the road surface validation (~line 115), add:

```lua
            if road.elevated ~= nil then
                assertType(road.elevated, "boolean", prefix .. ".roads[].elevated must be a boolean")
            end
            if road.tunnel ~= nil then
                assertType(road.tunnel, "boolean", prefix .. ".roads[].tunnel must be a boolean")
            end
            if road.sidewalk ~= nil then
                assertType(road.sidewalk, "string", prefix .. ".roads[].sidewalk must be a string")
            end
```

- [ ] **Step 3: Add building wallColor/roofColor/usage/minHeight validation**

In `ChunkSchema.lua`, after the facadeStyle validation (~line 152), add:

```lua
            if building.wallColor ~= nil then
                assertType(building.wallColor, "table", prefix .. ".buildings[].wallColor must be a table")
            end
            if building.roofColor ~= nil then
                assertType(building.roofColor, "table", prefix .. ".buildings[].roofColor must be a table")
            end
            if building.roofShape ~= nil then
                assertType(building.roofShape, "string", prefix .. ".buildings[].roofShape must be a string")
            end
            if building.roofMaterial ~= nil then
                assertType(building.roofMaterial, "string", prefix .. ".buildings[].roofMaterial must be a string")
            end
            if building.usage ~= nil then
                assertType(building.usage, "string", prefix .. ".buildings[].usage must be a string")
            end
            if building.minHeight ~= nil then
                assertType(building.minHeight, "number", prefix .. ".buildings[].minHeight must be a number")
            end
```

- [ ] **Step 4: Add water surfaceY validation**

In `ChunkSchema.lua`, in the water validation section (~line 174), add:

```lua
            if water.surfaceY ~= nil then
                assertType(water.surfaceY, "number", prefix .. ".water[].surfaceY must be a number")
            end
```

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ReplicatedStorage/Shared/ChunkSchema.lua
git commit -m "feat(lua): validate new 0.4.0 schema fields and terrain array lengths"
```

---

### Task 11: Lua — Remove hardcoded scale from BuildingBuilder

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`

- [ ] **Step 1: Simplify getBuildingHeight()**

In `BuildingBuilder.lua`, replace the `getBuildingHeight` function (lines 385-438) with:

```lua
local function getBuildingHeight(building)
    -- In schema 0.4.0, building.height is already in studs at the correct scale.
    -- No conversion needed. Only fall back to levels-based estimate if height is missing/zero.
    if building.height and building.height > 0 then
        return math.max(4, building.height)
    elseif building.levels and building.levels > 0 then
        -- ~14 studs per floor at 0.3 m/stud (~4.2m real floor height)
        return math.max(4, building.levels * 14)
    else
        -- Last resort: default 10m building = ~33 studs
        return 33
    end
end
```

This removes the `METERS_PER_STUD = 0.3` constant and the `height_m / METERS_PER_STUD` division. The exporter now produces `height` in correct stud-space.

- [ ] **Step 2: Update color field references**

Search `BuildingBuilder.lua` for references to `building.color` and update to `building.wallColor`:

```lua
-- Wherever building.color appears in the file, change to:
building.wallColor
```

- [ ] **Step 3: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua
git commit -m "fix(lua): remove hardcoded METERS_PER_STUD from BuildingBuilder, use manifest height directly"
```

---

### Task 12: Lua — Remove ground-snap from RoadBuilder

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua`

- [ ] **Step 1: Replace classifySegment heuristic with manifest flag**

In `RoadBuilder.lua`, replace the `classifySegment` function (lines 100-128) with:

```lua
local function classifySegment(road, p1, p2, chunk)
    -- In schema 0.4.0, elevated/tunnel flags are authoritative from the exporter.
    -- No ground sampling or heuristic delta checks needed.
    if road.elevated then
        return "bridge", p1, p2
    elseif road.tunnel then
        return "tunnel", p1, p2
    else
        -- Ground road: use manifest Y directly (already correct from DEM)
        return "ground", p1, p2
    end
end
```

This removes the `GroundSampler.sampleWorldHeight` calls during road import and the `BRIDGE_THRESHOLD` heuristic.

- [ ] **Step 2: Verify no other GroundSampler calls remain in road import path**

Search `RoadBuilder.lua` for remaining `GroundSampler.sampleWorldHeight` calls. The pillar placement code (~line 249) may still need ground height for pillar length calculation — this is acceptable as it's computing pillar geometry, not road placement. Leave that call.

- [ ] **Step 3: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua
git commit -m "fix(lua): replace bridge/tunnel heuristic with manifest elevated/tunnel flags"
```

---

### Task 13: Lua — Remove ground-snap from WaterBuilder

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/WaterBuilder.lua`

- [ ] **Step 1: Replace resolveWaterSurfaceY with manifest surfaceY**

In `WaterBuilder.lua`, replace `resolveWaterSurfaceY` function (lines 17-32) with:

```lua
local function resolveWaterSurfaceY(water, fallbackY, chunk, worldX, worldZ)
    -- In schema 0.4.0, surfaceY is authoritative for polygon water.
    -- For ribbon water, per-point Y is authoritative.
    if water.surfaceY then
        return water.surfaceY
    end
    -- Fallback for pre-0.4.0 or ribbon water: use the provided Y
    return fallbackY
end
```

- [ ] **Step 2: Replace estimatePolygonSurfaceY with manifest surfaceY**

In `WaterBuilder.lua`, update the polygon water section (~line 146) to use `surfaceY` directly:

```lua
-- Before (estimating from ground sampling):
-- local surfaceY = estimatePolygonSurfaceY(chunk, footprintPoints)
-- After:
local surfaceY = water.surfaceY or estimatePolygonSurfaceY(chunk, footprintPoints)
```

Keep `estimatePolygonSurfaceY` as a fallback for old manifests but prefer the manifest value.

- [ ] **Step 3: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/WaterBuilder.lua
git commit -m "fix(lua): use manifest surfaceY for water placement, remove snap threshold"
```

---

### Task 14: Lua — Remove ground-snap from PropBuilder

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/PropBuilder.lua`

- [ ] **Step 1: Simplify resolveBaseY**

In `PropBuilder.lua`, replace the `resolveBaseY` function (lines 40-51) with:

```lua
local function resolveBaseY(chunk, worldX, fallbackY, worldZ)
    -- In schema 0.4.0, prop Y is authoritative from the exporter.
    -- Use manifest value directly. GroundSampler is available for runtime
    -- queries but not used during import.
    return fallbackY
end
```

This removes the snap threshold check and GroundSampler call during import.

- [ ] **Step 2: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/PropBuilder.lua
git commit -m "fix(lua): use manifest Y for prop placement, remove ground snap"
```

---

### Task 15: Lua — Update TerrainBuilder voxel size

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua`

- [ ] **Step 1: Change VOXEL_SIZE from 4 to 2**

In `TerrainBuilder.lua`, change line 29:

```lua
-- Before:
local VOXEL_SIZE = 4
-- After:
local VOXEL_SIZE = 2
```

- [ ] **Step 2: Add chunked WriteVoxels for large regions**

The smaller voxel size with higher terrain resolution can produce large 3D arrays. In the TerrainBuilder, after computing the voxel region bounds, add a check to split into sub-regions if needed.

Find the `WriteVoxels` call in the file and wrap it with a strip-based approach:

```lua
-- Replace the single WriteVoxels call with strip-based writing
local MAX_VOXELS_PER_CALL = 500000
local totalVoxels = dimX * dimY * dimZ

if totalVoxels > MAX_VOXELS_PER_CALL then
    -- Write in Z strips to stay under the limit
    local stripDepth = math.max(1, math.floor(MAX_VOXELS_PER_CALL / (dimX * dimY)))
    for zStart = 0, dimZ - 1, stripDepth do
        local zEnd = math.min(zStart + stripDepth, dimZ)
        local stripRegion = Region3.new(
            Vector3.new(rMinX, rMinY, rMinZ + zStart * VOXEL_SIZE),
            Vector3.new(rMaxX, rMaxY, rMinZ + zEnd * VOXEL_SIZE)
        )
        -- Build strip-sized material and occupancy arrays
        -- ... (extract the relevant slice from the full arrays)
        Workspace.Terrain:WriteVoxels(stripRegion, VOXEL_SIZE, stripMaterials, stripOccupancy)
    end
else
    Workspace.Terrain:WriteVoxels(region, VOXEL_SIZE, materials, occupancy)
end
```

Note: The exact implementation depends on how the current TerrainBuilder structures the 3D arrays. Read the full file and adapt. The key requirement is that no single `WriteVoxels` call exceeds ~500K voxels.

- [ ] **Step 3: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua
git commit -m "fix(lua): reduce voxel size to 2 studs, add chunked WriteVoxels for large regions"
```

---

### Task 16: Lua — Remove MetersPerStud from WorldConfig

**Files:**
- Modify: `roblox/src/ReplicatedStorage/Shared/WorldConfig.lua`

- [ ] **Step 1: Remove the hardcoded MetersPerStud**

In `WorldConfig.lua`, remove line 2:

```lua
-- DELETE:
MetersPerStud = 1.0,
```

If any code reads `WorldConfig.MetersPerStud`, it should instead read from the manifest's `meta.metersPerStud` at import time. Search the codebase for `WorldConfig.MetersPerStud` and update any references.

- [ ] **Step 2: Commit**

```bash
git add roblox/src/ReplicatedStorage/Shared/WorldConfig.lua
git commit -m "fix(lua): remove hardcoded MetersPerStud from WorldConfig"
```

---

### Task 17: Lua — Update GroundSampler default cell size

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/GroundSampler.lua`

- [ ] **Step 1: Change DEFAULT_CELL_SIZE from 16 to 4**

In `GroundSampler.lua`, change line 6:

```lua
-- Before:
local DEFAULT_CELL_SIZE = 16
-- After:
local DEFAULT_CELL_SIZE = 4
```

This matches the new terrain grid cell size from the Rust exporter. The GroundSampler still reads `terrainGrid.cellSizeStuds` from the manifest (line 18), so this default only applies as a fallback.

- [ ] **Step 2: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/GroundSampler.lua
git commit -m "fix(lua): update GroundSampler default cell size to 4 studs"
```

---

### Task 18: Lua — Update test fixtures and sample data

**Files:**
- Modify: `roblox/src/ServerScriptService/Tests/ChunkSchema.spec.lua`
- Modify: `roblox/src/ServerScriptService/Tests/Migrations.spec.lua`
- Modify: `roblox/src/ServerStorage/SampleData/SampleManifest.lua`
- Modify: `roblox/src/ServerStorage/SampleData/SampleMultiChunkManifest.lua`

- [ ] **Step 1: Update ChunkSchema.spec.lua version expectations**

In `ChunkSchema.spec.lua`, update any assertions checking for `"0.3.0"` to `"0.4.0"`:

```lua
-- Before:
Assert.equal(manifest.schemaVersion, "0.3.0")
-- After:
Assert.equal(manifest.schemaVersion, "0.4.0")
```

- [ ] **Step 2: Add migration test for 0.3.0 → 0.4.0**

In `Migrations.spec.lua`, add a new test case:

```lua
it("should migrate 0.3.0 to 0.4.0 with scale transform", function()
    local manifest030 = {
        schemaVersion = "0.3.0",
        meta = {
            worldName = "Test",
            generator = "test",
            source = "test",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 1,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 10, z = 0 },
                terrain = {
                    cellSizeStuds = 16,
                    width = 16,
                    depth = 16,
                    heights = {},
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {
                    {
                        id = "b1",
                        material = "Concrete",
                        footprint = {
                            { x = 10, z = 10 },
                            { x = 20, z = 10 },
                            { x = 20, z = 20 },
                        },
                        baseY = 5,
                        height = 30,
                        roof = "flat",
                        rooms = {},
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    -- Fill heights
    for i = 1, 256 do
        manifest030.chunks[1].terrain.heights[i] = 0.0
    end

    local migrated = Migrations.migrate(manifest030, "0.4.0")

    -- Scale factor should be 1.0/0.3 ≈ 3.333
    local sf = 1.0 / 0.3

    Assert.equal(migrated.schemaVersion, "0.4.0")
    Assert.equal(migrated.meta.metersPerStud, 0.3)
    Assert.near(migrated.chunks[1].originStuds.y, 10 * sf, 0.1)
    Assert.near(migrated.chunks[1].buildings[1].baseY, 5 * sf, 0.1)
    Assert.near(migrated.chunks[1].buildings[1].height, 30 * sf, 0.1)
    Assert.near(migrated.chunks[1].buildings[1].footprint[1].x, 10 * sf, 0.1)
end)
```

- [ ] **Step 3: Update SampleManifest.lua**

Update `SampleManifest.lua` to use `schemaVersion = "0.4.0"`, `metersPerStud = 0.3`, and add new fields (`elevated = false`, `tunnel = false` on roads, `wallColor` instead of `color` on buildings). Also update terrain to `cellSizeStuds = 4`, `width = 64`, `depth = 64`.

- [ ] **Step 4: Update SampleMultiChunkManifest.lua similarly**

Same changes as SampleManifest.lua.

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/Tests/ roblox/src/ServerStorage/SampleData/
git commit -m "test(lua): update fixtures for schema 0.4.0 scale and new fields"
```

---

### Task 19: Update JSON schema spec

**Files:**
- Modify: `specs/chunk-manifest.schema.json`

- [ ] **Step 1: Bump schema version**

Change the `const` value for `schemaVersion` from `"0.3.0"` to `"0.4.0"`.

- [ ] **Step 2: Add new road properties**

In the road item schema, add:
```json
"elevated": { "type": "boolean", "default": false },
"tunnel": { "type": "boolean", "default": false },
"sidewalk": { "type": "string", "enum": ["both", "left", "right", "no"] }
```

- [ ] **Step 3: Add new building properties**

In the building item schema, add:
```json
"wallColor": { "$ref": "#/$defs/Color" },
"roofColor": { "$ref": "#/$defs/Color" },
"roofShape": { "type": "string" },
"roofMaterial": { "type": "string" },
"usage": { "type": "string" },
"minHeight": { "type": "number" }
```

Remove or rename the existing `color` property to `wallColor`.

- [ ] **Step 4: Add water surfaceY**

```json
"surfaceY": { "type": "number" }
```

- [ ] **Step 5: Commit**

```bash
git add specs/chunk-manifest.schema.json
git commit -m "feat(spec): update JSON schema to 0.4.0 with new fields"
```

---

### Task 20: Integration verification

- [ ] **Step 1: Run full Rust test suite**

Run: `cd rust && cargo test --workspace 2>&1`
Expected: All tests pass.

- [ ] **Step 2: Generate a sample manifest and inspect**

Run: `cd rust && cargo run --bin arbx_cli -- sample --pretty 2>&1 | head -50`

Verify:
- `schemaVersion` is `"0.4.0"`
- `metersPerStud` is `0.3`
- Terrain has `cellSizeStuds: 4`, `width: 64`, `depth: 64`
- Buildings have `wallColor` (not `color`)
- Roads have `elevated` and `tunnel` fields

- [ ] **Step 3: Verify a building height is correct**

In the sample output, a building with `height: 100` at 0.3 m/stud represents a 30m building (~10 stories). Verify the numbers are proportional.

- [ ] **Step 4: Commit any remaining fixes**

```bash
git add -A
git commit -m "chore: SP-1 coordinate contract integration verification"
```
