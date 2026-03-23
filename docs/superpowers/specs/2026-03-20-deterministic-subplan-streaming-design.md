# Deterministic Subplan Streaming — Design Spec

**Date:** 2026-03-20
**Status:** Draft
**Primary goal:** Make chunk streaming smarter across edit mode, play mode, and future world traversal by adding deterministic per-chunk subplans without changing source truth.

## Problem Statement

The current scheduler is materially better than before, but it is still operating at the wrong granularity.

We now have measured evidence that:

1. Canonical chunk ordering matters, and better priority logic already reduces first-visible stalls.
2. A small number of pathological chunks still dominate import time once scheduling is sane.
3. Those hot chunks are not uniformly expensive. Specific layers inside them are driving the stall.
4. Treating a chunk as one indivisible work unit makes the importer choose between two bad options:
   - front-load a pathological chunk and stall the scene
   - defer a pathological chunk and leave an obviously incomplete hole
5. Future globe-scale traversal will need a stable streaming contract that is finer than a full chunk but still deterministic and source-auditable.

We need a way to split heavy chunks into stable work packets for scheduling, profiling, caching, and future streaming without redefining chunk ownership or mutating world truth.

## Goals

- Preserve canonical chunk ownership and determinism.
- Add deterministic subplans that let the scheduler reason about heavy chunks at a finer granularity.
- Improve first-believable-scene time in Studio preview and play mode without dropping content.
- Preserve fidelity:
  - no geometry simplification just because a chunk is hot
  - no semantic loss
  - no unstable runtime-only chunk splitting
- Lay clean groundwork for future seamless world streaming.
- Keep source-to-manifest and manifest-to-scene auditing explainable.

## Non-Goals

- No replacement of the canonical chunk manifest with a fully dynamic runtime partitioner.
- No “skip expensive layers forever” behavior.
- No builder-side fidelity regressions disguised as performance optimizations.
- No attempt to solve infinite streaming in this step.
- No networked replication design in this step.

## Recommended Approach

Use a hybrid model:

1. **Canonical chunks remain fixed**
   - chunk ids, geometry ownership, and source auditability stay exactly as they are.

2. **Offline compile emits deterministic subplans**
   - subplans are scheduling metadata attached to chunks
   - they do not change geometry or semantics
   - subplan generation must derive only from canonical chunk contents plus an explicit partition algorithm version

3. **Runtime and edit mode schedule `chunk + subplan`**
   - schedulers operate on finer work packets inside a chunk
   - import remains deterministic because the work graph is predeclared

4. **Local learned cost history reorders legal work**
   - runtime/editor can adapt to actual machine performance and recent timing
   - learned history can reorder or budget work
   - learned history cannot rewrite or suppress source truth

This is the right architecture because it combines stable offline contracts with adaptive runtime scheduling, which is exactly what we need for higher fidelity now and globe-scale streaming later.

## Alternatives Considered

### 1. Runtime-only learned splitting

Pros:
- fast to prototype
- adaptive to real hardware

Cons:
- unstable boundaries
- weaker auditing
- harder cache invalidation
- poor foundation for future world streaming

Rejected as the primary design.

### 2. Offline-only subplans

Pros:
- deterministic
- easy to audit
- easy to cache

Cons:
- too rigid for real runtime/editor conditions
- cannot react to machine pressure or recent hotspots

Rejected as the only design.

### 3. Hybrid deterministic subplans with local learned ordering

Pros:
- deterministic work graph
- adaptive execution
- stable future streaming contract
- preserves source truth

Cons:
- more plumbing

Recommended.

## Architecture

### A. Canonical Chunks Stay Canonical

Chunks continue to be the unit of:

- source ownership
- manifest identity
- idempotent import ownership
- scene reconciliation
- source-to-scene audit mapping

Subplans do not replace chunks. They are subordinate scheduling metadata attached to a chunk.

Important rule:

- importing all subplans for a chunk must be equivalent to importing the whole chunk
- no geometry may move between chunks because of subplan generation
- the same source input must produce the same chunk/subplan graph

### B. Subplans

Each chunk may expose a deterministic list of subplans.

Always-available coarse subplans:

- `terrain`
- `roads`
- `buildings`
- `landuse`
- `water`
- `props`

Optional fine subplans:

- only emitted for hot layers in hot chunks
- deterministic and reproducible
- emitted only by an explicit partition function whose inputs are:
  - canonical manifest chunk contents
  - fixed threshold constants
  - partition algorithm version
- preferably spatial, for example:
  - `buildings:nw`
  - `buildings:ne`
  - `buildings:sw`
  - `buildings:se`
- non-spatial partitions are allowed when spatial slicing would destroy locality, but they must remain deterministic

Subplans are not allowed to be arbitrary runtime-created fragments.

Canonical subplan ordering must also be deterministic:

1. coarse layers in fixed order:
   - `terrain`
   - `landuse`
   - `roads`
   - `buildings`
   - `water`
   - `props`
2. fine subplans for a layer sorted by stable spatial label or stable partition index
3. stable id tie-break for any remaining ambiguity

### B1. Deterministic Partition Function

Subplan emission needs an explicit contract, not just a claim of determinism.

Required partition inputs:

- partition algorithm version
- chunk id
- canonical chunk geometry and metadata
- fixed compile-time thresholds

Required partition rules:

- a layer receives only coarse subplans unless it exceeds a fixed threshold
- fine subplans must be reproducible from the same canonical chunk contents
- the partition algorithm version must be recorded in the generated index metadata
- any threshold or algorithm change that would alter emitted subplans is a versioned contract change for the scheduling layer

Recommended first-pass thresholds:

- emit coarse layer subplans for every chunk
- emit fine subplans only for `roads`, `buildings`, or `landuse` when their baked `streamingCost` exceeds a fixed per-layer threshold
- do not emit fine `terrain` subplans in the first pass because terrain writes remain globally ordered and already have strong spatial locality

### B2. Boundary-Spanning Features

Boundary-spanning features must follow a strict ownership rule.

Required rule:

- features are assigned whole to exactly one fine subplan
- features are never clipped at subplan boundaries in the first pass
- features are never duplicated across sibling subplans

Recommended assignment strategy:

- buildings: assign by footprint centroid
- roads / rails / waterways: assign by midpoint along the canonical polyline
- area features such as landuse: assign by polygon centroid

This rule avoids seam drift, duplicate decorations, and feature-count inflation while preserving deterministic ownership.

### C. Subplan Metadata

Each subplan should carry enough metadata to support scheduling, profiling, and audit interpretation:

- `id`
- `layer`
- `featureCount`
- `streamingCost`
- `bounds` when spatially sliced
- optional `sourceMix`
  - OSM / Overture / derived feature counts
- optional `estimatedMemoryCost`

Important rule:

- these fields are scheduling hints, not alternate truth

### D. Runtime and Edit Scheduling

Schedulers should use a deterministic-first, adaptive-second policy.

Recommended order within a visible ring:

1. distance and visibility ring
2. forward/look bias
3. subplan class priority
4. baked `streamingCost`
5. learned local cost
6. memory-pressure budget
7. stable id tie-break

The default “believable scene” order should prefer:

1. `terrain`
2. primary `roads`
3. core `buildings`
4. `landuse`
5. `water`
6. `props`
7. heavy detail subplans

This preserves fidelity while making the scene feel coherent earlier.

### D1. Dependency DAG and Overwrite Protocol

Idempotency requires an explicit dependency graph because some builders mutate shared surfaces.

Required coarse-layer dependency order:

1. `terrain`
2. `landuse`
3. `roads`
4. `buildings`
5. `water`
6. `props`

Important first-pass rule:

- only `roads` may own road terrain imprinting
- building-associated props remain in `props`, not `buildings`
- no subplan may mutate content owned by a sibling layer

Fine subplans may reorder within a layer, but they must respect the coarse-layer DAG.

Overwrite/reconcile rule:

- re-importing a subplan must clear and rebuild only that subplan's owned scene region or owned instance set
- a subplan must never clear sibling-owned content
- mixed mode is allowed during rollout:
  - whole-chunk import remains supported
  - subplan import is equivalent only when all layer dependencies for that subplan have been satisfied

### E. Learned Local Cache

Persist local scheduling observations keyed by:

- manifest hash
- chunk id
- subplan id
- quality profile
- platform / machine class
- memory tier

Stored values may include:

- EWMA import time
- failure / retry counts
- recent peak instance count
- recent peak memory estimate

Allowed effects:

- reorder subplans inside a legal priority band
- lower batch size under pressure
- defer known hot subplans within a ring

Forbidden effects:

- permanently suppress a subplan
- rewrite contents
- create new dynamic ownership boundaries

Audit boundary:

- adaptive ordering is intentionally non-authoritative
- every run that uses learned scheduling must record the executed `chunk + subplan` order in profiling output so performance and scene completion are reproducible
- fidelity audits compare final loaded scene truth, not transient learned execution order

### F. Infinite-World Groundwork

This design becomes the future streaming work graph.

Offline compiler responsibilities:

- define canonical chunks
- define legal subplans inside those chunks
- attach coarse and fine scheduling hints

Runtime responsibilities:

- decide what to stream now
- decide which subplans to defer briefly
- decide how aggressively to batch under current pressure

This keeps world traversal scalable without sacrificing source fidelity.

## Manifest Contract

Recommended additive index-level contract:

```lua
chunkRefs = {
    {
        id = "-2_-2",
        originStuds = {x = -512, y = 0, z = -512},
        featureCount = 142,
        streamingCost = 981.5,
        partitionVersion = "subplans.v1",
        shards = {"AustinManifestIndex_3632"},
        subplans = {
            {id = "terrain", layer = "terrain", featureCount = 1, streamingCost = 40.0},
            {id = "roads", layer = "roads", featureCount = 58, streamingCost = 210.0},
            {id = "buildings:nw", layer = "buildings", featureCount = 19, streamingCost = 330.0, bounds = {...}},
            {id = "buildings:ne", layer = "buildings", featureCount = 17, streamingCost = 220.0, bounds = {...}},
            {id = "landuse", layer = "landuse", featureCount = 31, streamingCost = 140.0},
        },
    },
}
```

Notes:

- the example above follows the current array-of-`chunkRefs` loader contract; it is not a new keyed-map format
- subplans can live in the sharded index instead of the main geometry payload
- this keeps the runtime contract additive and avoids duplicating geometry
- fine subplans should be emitted only when a layer crosses deterministic thresholds
- `partitionVersion` is additive index metadata, not a replacement for `schemaVersion`
- if subplan metadata shape changes incompatibly, the scheduling-layer version must be updated and migration notes must be added beside the schema docs

## Builder and Importer Contract

Import code needs a clean interface for subplans.

Recommended shape:

- chunk import remains supported for compatibility inside the importer
- scheduler preferably calls a new “import subplan” path
- importer remains idempotent:
  - re-importing a subplan reconciles only its owned instances
  - importing all subplans equals importing the full chunk
  - importing a dependent subplan before its prerequisites must fail closed, not guess

Subplan ownership should be explicit:

- terrain subplans own terrain writes
- road subplans own road meshes, markings, sidewalks, curbs, crossings, and their imprinting
- building subplans own building shells, roofs, and facade layers
- landuse, water, and props follow the same rule

First-pass ownership clarification:

- building-associated props remain owned by `props`, even if the current implementation happens to build some of them near buildings
- moving such props into `buildings` is a later explicit contract change, not part of the first-pass subplan rollout

If a current builder cannot safely reconcile at subplan granularity, that builder must be split or refactored before subplan streaming is enabled for that layer.

## Profiling and Audit

The fidelity/performance loop should become more precise, not less.

Required new measurements:

- chunk total import time
- subplan import time
- first-believable-scene time
- per-layer first-visible completion
- memory / instance footprint by subplan where available
- repeated-run timing drift
- executed subplan order
- dependency wait time between subplans

Audit invariants:

- source-to-manifest counts and semantics must not change because of subplans
- manifest-to-scene counts must remain equal after all subplans load
- subplans are a scheduling layer only

## Error Handling

If a subplan fails:

- fail the chunk visibly in profiling and logs
- do not silently downgrade fidelity
- allow retry
- keep failure attached to the exact `chunk + subplan`

If a subplan definition is missing or malformed:

- fail closed
- do not guess a runtime-generated partition

## Testing Strategy

### Rust-side tests

- deterministic subplan emission for the same input
- threshold tests for when fine subplans appear
- stable spatial partition bounds
- boundary-spanning feature ownership tests
- manifest/index serialization tests
- partition-version invalidation tests

### Roblox-side tests

- scheduler ordering tests using subplans
- idempotent subplan import tests
- subplan import equivalence to whole-chunk import
- dependency DAG enforcement tests
- subplan permutation tests within a legal layer order
- subplan failure and retry tests
- runtime/edit preview tests proving no missing content after all subplans complete

### Harness tests

- first-believable-scene timing comparison before/after subplans
- no-fidelity-regression checks
- hotspot chunk regression tests for known pathological Austin chunks
- crash/resume tests across partial subplan completion
- mixed-mode tests for whole-chunk plus subplan rollout
- executed-order capture tests

## Rollout Plan

1. Add additive manifest/index support for subplans.
2. Add `partitionVersion` and scheduling-layer migration notes.
3. Emit coarse subplans for every chunk.
4. Add scheduler support for `chunk + subplan`.
5. Enforce the coarse-layer dependency DAG in the importer.
6. Enable subplans first in preview and runtime for one safe layer or chunk class.
7. Add fine subplans only for measured pathological layers/chunks.
8. Persist learned local cost cache.
9. Expand harness profiling and fidelity checks.

## Open Questions

1. Should building-associated props remain attached to building subplans, or move to dedicated prop subplans where source identity allows it?
2. Should fine subplans be quadrants only, or allow deterministic stripe partitions for corridor-shaped road knots?
3. Should subplan cache include machine class / memory tier, or is manifest hash plus profile enough for first pass?

## Recommendation

Implement hybrid deterministic subplans:

- fixed canonical chunks
- additive deterministic subplan metadata
- adaptive runtime/editor ordering on top

This is the cleanest path to smarter hotspot handling now and globe-scale streaming later, while keeping the pipeline deterministic, auditable, and fidelity-first.
