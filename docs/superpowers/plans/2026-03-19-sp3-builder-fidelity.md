# SP-3: Builder Fidelity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade every Lua builder to use the enriched manifest data from SP-1/SP-2, producing visually rich terrain, buildings, roads, water, and props.

**Architecture:** Modify existing builders in-place. No new files. Each builder gains new rendering logic that reads the new manifest fields (roofColor, roofShape, elevated, sidewalk, surfaceY, species, etc.).

**Tech Stack:** Lua (Roblox ServerScriptService builders)

**Spec:** `docs/superpowers/specs/2026-03-19-arnis-hd-pipeline-design.md` (SP-3 section)

---

### Task 1: TerrainBuilder — bilinear interpolation and slope-aware materials

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua`

**What to change:**
Currently terrain is a step function — each cell is a flat plateau. Add bilinear interpolation so voxels within a cell have smoothly varying heights. Also add slope-aware material assignment: steep slopes get Rock, moderate get Ground, flat stays as classified.

- [ ] **Step 1:** Read the current TerrainBuilder.lua fully
- [ ] **Step 2:** Add a bilinear height interpolation function that samples 4 neighboring cell heights and lerps
- [ ] **Step 3:** In the voxel fill loop, use interpolated heights instead of per-cell flat heights
- [ ] **Step 4:** Add slope calculation between adjacent cells; override material to Rock for slopes > 45°, Ground for 15-45°
- [ ] **Step 5:** Commit: "feat(lua): add bilinear terrain interpolation and slope-aware materials"

---

### Task 2: BuildingBuilder — roof colors, facade materials, improved windows

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`

**What to change:**
1. **Roof colors** — read `building.roofColor` for roof parts, distinct from wall color
2. **Facade material variety** — use `building.roofMaterial` and `building.material` for varied wall/roof materials
3. **Improved windows** — make window bands more visible with recessed glass parts instead of flat color

- [ ] **Step 1:** Read BuildingBuilder.lua fully
- [ ] **Step 2:** In roof rendering functions, apply `building.roofColor` as a separate Color3 when available; fall back to darkened wall color
- [ ] **Step 3:** In `getMaterial()`, expand the material lookup to use `building.roofMaterial` for roofs and `building.material` for walls
- [ ] **Step 4:** Improve window band rendering — make glass parts slightly recessed and use a darker tint for more contrast
- [ ] **Step 5:** Read `building.usage` to vary window spacing (office = dense windows, warehouse = sparse)
- [ ] **Step 6:** Commit: "feat(lua): add roof colors, facade material variety, improved window rendering"

---

### Task 3: RoadBuilder — lane-aware rendering and sidewalk from manifest

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua`

**What to change:**
1. **Sidewalk from manifest** — read `road.sidewalk` field ("both"/"left"/"right"/"no") instead of just `hasSidewalk` boolean
2. **Lane-aware rendering** — use `road.lanes` to compute proper width and render centerline on multi-lane roads
3. **Street lighting** — read `road.lit` and add PointLights along lit roads

- [ ] **Step 1:** Read RoadBuilder.lua fully
- [ ] **Step 2:** Replace `hasSidewalk` boolean check with `road.sidewalk` field: render sidewalk on both/left/right sides as specified
- [ ] **Step 3:** Use `road.lanes` to compute width (`lanes * laneWidth`) when `widthStuds` isn't explicitly set
- [ ] **Step 4:** Add street lighting: when `road.lit == true`, place PointLight parts along road at ~40 stud intervals
- [ ] **Step 5:** Commit: "feat(lua): lane-aware roads, directional sidewalks, street lighting"

---

### Task 4: WaterBuilder — terrain carving and island rendering

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/WaterBuilder.lua`

**What to change:**
1. **Terrain carving** — after placing water, call Terrain:FillBlock to clear/lower terrain below water surface
2. **Better island rendering** — holes/islands should be terrain-filled at water surface level

- [ ] **Step 1:** Read WaterBuilder.lua fully
- [ ] **Step 2:** After polygon water placement, carve terrain below `surfaceY` by filling with Air material for 2-4 studs below surface, then filling with Water material
- [ ] **Step 3:** For ribbon water, carve a channel along the centerline
- [ ] **Step 4:** Ensure islands (`holes` array) get terrain fill at the correct elevation
- [ ] **Step 5:** Commit: "feat(lua): carve terrain under water features, improve island rendering"

---

### Task 5: PropBuilder — expanded tree species and height-based scaling

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/PropBuilder.lua`

**What to change:**
1. **Height-based tree scaling** — use `prop.height` (real-world meters) to scale tree size, not just species lookup
2. **Canopy shape by leaf type** — use `prop.leafType` for canopy shape: `broadleaved` = sphere, `needleleaved` = cone
3. **Expanded species colors** — add more species to the color/scale lookup

- [ ] **Step 1:** Read PropBuilder.lua fully
- [ ] **Step 2:** In `buildTree()`, read `prop.height` and use it to scale the trunk height and canopy radius (convert meters to studs using 1/0.3 ≈ 3.33)
- [ ] **Step 3:** Read `prop.leafType`: if "needleleaved", render canopy as a cone (ConeHandleAdornment or scaled Part); if "broadleaved", keep sphere
- [ ] **Step 4:** Add 10+ species to `getCanopyColor()` and `getCanopyScale()` lookup tables (magnolia, pecan, cypress, mesquite, crepe_myrtle, etc.)
- [ ] **Step 5:** Commit: "feat(lua): height-based tree scaling, leaf type canopy shapes, expanded species"

---

### Task 6: Update documentation and backlog

**Files:**
- Modify: `docs/backlog.md`
- Modify: `docs/chunk_schema.md` (if any builder behavior changes affect documentation)

- [ ] **Step 1:** Mark SP-3 as complete in backlog
- [ ] **Step 2:** Update any schema docs if builder behavior assumptions changed
- [ ] **Step 3:** Commit: "docs: mark SP-3 builder fidelity complete in backlog"
