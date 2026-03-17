# Acceptance Criteria

## Milestone 1: sample importer works

- Rust sample exporter writes a valid manifest.
- Roblox importer accepts the manifest.
- Roads, terrain, and building shells appear in Studio.
- Re-import does not silently duplicate content.
- Smoke tests pass.

## Milestone 2: chunk lifecycle exists

- chunks can be loaded and unloaded
- chunk ownership is tracked authoritatively
- import and unload timings are reported

## Milestone 3: source adapter path exists

- upstream adapter boundary is implemented
- exporter can emit more than the canned sample
- schema migration notes exist for breaking changes

## Milestone 4: production hardening

- perf regressions are measurable
- asset/prefab strategy documented
- plugin/editor flow is optional but smooth
