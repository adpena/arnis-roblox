# Performance Budget

These are **project budgets**, not platform guarantees.

## Philosophy

The first real performance win is usually **representation choice**, not clever code.

That means:

- terrain for macro shape
- chunk boundaries for streaming
- shell buildings before interiors
- pooled or merged props before thousands of unique parts
- deterministic rebuilds so profiling is meaningful

## Default project budgets

### Chunk geometry budget

Target starting budget per imported chunk:

- terrain: one coarse terrain patch or voxel region
- roads: <= 400 segments
- buildings: <= 150 shells
- water: <= 50 ribbons
- props: <= 250 lightweight placeholders

If a chunk exceeds these budgets, prefer:
- splitting representation
- lowering fidelity
- deferring decorative content
- adding LOD/prefab keys

### Import timing budget

For the scaffold and smoke fixtures:

- sample chunk import in Studio: **comfortably interactive**
- repeated import should not compound duplicate content
- no unbounded loops on every frame

### Runtime memory direction

- chunk lifecycle should be explicit
- no forever-growing generated folders
- repeated editor imports should reconcile or reset

## Optimization order

1. reduce total generated instances
2. reduce duplicate work
3. merge repeated geometry where sane
4. stream/unload by chunk
5. only then micro-optimize Lua loops

## Representation guidance

### Terrain
Good for:
- hills
- rivers
- broad landform changes

Bad for:
- fine building edges
- sharp curb-level detail
- arbitrary mesh fidelity

### Parts
Good for:
- simple shells
- debug visibility
- early iteration

Bad for:
- huge repeated counts without budgeting

### Meshes / editable assets
Good for:
- merged repeated geometry
- more efficient artist-approved assets

Bad for:
- huge one-shot generation without budget control

## Red flags

- a chunk import creates thousands of tiny decorative parts by default
- builders allocate fresh objects without reuse strategy
- “debug” folders accidentally ship into runtime
- import has no authoritative owner for each chunk

## Profiling and Regression

The system includes a built-in `Profiler` (`roblox/src/ServerScriptService/ImportService/Profiler.lua`) that automatically captures:
- **Import Timings**: Total time spent in `ImportManifest` and per-chunk `ImportChunk`.
- **Instance Counts**: Number of descendants created per chunk and total for the world.

### Capturing Metrics
To see a performance report after an import, pass `printReport = true` in the import options:
```lua
ImportService.ImportManifest(manifest, {
    printReport = true
})
```

### Regression Testing
The smoke test suite includes a `Performance.spec.lua` that validates that these metrics are correctly captured. In production CI or manual benchmarking, these JSON reports should be compared against a baseline to detect regressions in instance count or import latency.

For repeated Austin import/runtime checks, use:

```bash
python3 scripts/run_austin_stress.py --iterations 3 --json-out tmp/austin-stress.json
```

That script aggregates preview and runtime Austin markers from the Studio harness and is the
preferred real-world throughput check before large fidelity or importer changes.
