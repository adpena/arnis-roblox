# KODEX.md

Kodex should read `AGENTS.md` first.

## What Kodex should optimize for

- preserve architecture boundaries
- improve determinism
- reduce per-chunk instance count
- prefer simple systems that can be benchmarked
- leave clean seams for future Arnis adapter work

## Immediate tasks Kodex can safely take on

1. Replace placeholder terrain import with a real voxel writer path.
2. Add chunk unload/reload with reference counting or authoritative overwrite.
3. Add schema migrations from `0.1.0` to the first breaking revision.
4. Extend the Rust sample exporter so it can emit multiple adjacent chunks.
5. Build a stronger profiler/reporting pass in Roblox and Rust.

## What Kodex should not do early

- add interiors
- add live HTTP geodata calls to Roblox
- add flashy UI before importer correctness
- overfit the manifest to one city or one upstream source
