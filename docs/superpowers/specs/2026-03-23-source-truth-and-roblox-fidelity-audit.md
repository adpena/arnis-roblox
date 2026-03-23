# Source Truth And Roblox Fidelity Audit

Date: 2026-03-23

## Scope

This audit compares:

- geodata and metadata already available from OSM / Overpass / Overture / Terrarium / satellite enrichment
- the manifest fields and builder behavior currently preserved by the Arnis Roblox pipeline
- Roblox-side capabilities that can raise fidelity without violating the offline-compile / online-import boundary

The goal is to identify where fidelity is currently being lost due to coarsening, misclassification, or underuse of Roblox rendering/runtime features.

## Highest Priority Gaps

### 1. Audit correctness had become a bottleneck

Before improving fidelity further, the audit path itself needed hardening:

- scene fragment reassembly could mix stale log fragments across runs
- scene audits were reading the whole Studio log instead of the current-run log slice
- roof usage / roof shape findings were keyed to bucket presence, not actual roof coverage truth
- building material truth was not emitted from the builder through the Studio harness into scene audit reports

Those issues are now addressed in the current branch so future fidelity work is grounded in more trustworthy diagnostics.

### 2. Source truth is still being synthesized away before manifest emission

High-signal examples from current source data:

- Overture includes roof shape, roof orientation, partial-floor / min-floor / underground-floor signals, `has_parts`, and per-feature provenance
- Overpass roads and crossings include directional lanes, turn lanes, tactile paving, crossing markings, traffic-signal semantics, clearance, parking, and cycling signals
- Overpass relations include amenity / leisure / landuse area truth that is not fully requested in the live query today
- DEM authority exists, but large buildings and water polygons are still reduced to centroid samples for some vertical decisions
- satellite enrichment still collapses roofs and terrain cells down to single-sample classifications

Current pipeline losses:

- Overture loader keeps only a narrow subset of building truth before inference
- road runtime/build planning mostly consumes total lanes / width / oneway / speed / lit / layer
- water builders still tend to favor fallback widths instead of authoritative width-derived geometry
- negative layer / underpass truth is still coarsened by positive-only vertical heuristics in parts of the runtime path

### 3. Roblox capability usage is still below the fidelity ceiling

The main gap is material richness, not raw geometry count.

Current limitations:

- merged building and road meshes mostly rely on flat `Material` + `Color`
- water still reads visually closer to simplified parts than to source-authored surface classes
- several fidelity knobs in `WorldConfig` either over-promise or do not currently drive the runtime behavior they imply
- custom chunk LOD exists, but it is not yet paired strongly with Roblox native streaming / per-model streaming controls
- prefab / package-backed props remain the fastest low-risk path to visible fidelity gains, but that pipeline is still scaffolded

Promising Roblox-side opportunities:

- `MaterialVariant` for buildings / roads / water before full texture workflows
- `SurfaceAppearance` once merged mesh UV generation is available
- package-backed prefabs for trees, benches, lamps, signals, and facade kits
- Workspace streaming plus model-level LOD / streaming settings, paired with chunk ownership
- higher-quality lighting configuration and selective hero-lighting inside the high-detail radius
- `Clouds` and other low-cost atmosphere improvements

## Recommended Next Work Order

### A. Preserve more source truth in the compiler

- carry Overture roof shape / orientation / floor offsets / `has_parts` / provenance into manifest output
- expand live Overpass relation queries for amenity / leisure / landuse / generic natural relations
- preserve directional lane, turn-lane, crossing-marking, tactile-paving, cycling, parking, and clearance semantics
- preserve better per-feature elevation summaries for large buildings and water polygons
- replace single-pixel roof / terrain sampling with multi-sample voting and confidence

### B. Improve material and surface fidelity without breaking architecture

- add manifest and scene audit support for wall-vs-roof material truth and drift
- introduce a `MaterialVariant` tier for roads / roofs / walls / water
- use authoritative widths and signed topology/layer signals for roads and waterways before stylized fallbacks

### C. Strengthen runtime streaming and chunking

- keep chunk ownership and offline manifests
- pair the custom scheduler with Roblox native streaming and model-level controls
- use audit hotspots to drive chunk splitting / prefetch priority
- keep preview swaps atomic so environment changes never look like full scene rebuilds

## Working Principle

The biggest near-term wins come from preserving more truth and auditing it precisely, not from adding more stylization. The system already has enough signal to get materially closer to real-world Austin if that signal survives source-to-manifest and manifest-to-scene intact.
