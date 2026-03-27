# KODEX.md

Kodex should read `AGENTS.md` first.

## What Kodex should optimize for

- preserve architecture boundaries
- improve determinism
- reduce per-chunk instance count
- prefer simple systems that can be benchmarked
- leave clean seams for future Arnis adapter work

## Convergence guardrails

- `arnis-roblox` owns canonical world truth, manifest semantics, and scene extraction adapters.
- `vertigo-sync` owns edit/full-bake orchestration and export-3d user-facing orchestration.
- Do not add new parallel preview/play/full-bake world-definition paths in `RunAustin.lua`, `AustinPreviewBuilder.lua`, `BootstrapAustin.server.lua`, or `AustinSpawn.lua`.
- When work is happening under an active spec or implementation plan, append dated status notes as debugging/verification slices complete so another agent can resume without reconstructing chat history.
- Keep remote Studio hosts and machine-specific paths in ignored local config or env, not in committed repo scripts.
- Treat `primary` and `tertiary` as local profile aliases only; the committed repo must stay portable across direct-dev and remote-executor machines.

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
