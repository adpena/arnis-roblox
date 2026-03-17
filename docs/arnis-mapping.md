# Arnis Mapping Notes

This project is inspired by Arnis's modular goals: keep data retrieval, processing, and world
generation separated.

## Conceptual mapping

### Upstream / Arnis side concepts
- data acquisition
- geospatial normalization
- terrain/elevation handling
- feature categorization
- world-writing abstraction

### This scaffold's equivalent layers
- `arbx_pipeline` for project-owned domain stages
- `arbx_roblox_export` for manifest emission
- `roblox/src/ServerScriptService/ImportService` for Studio/runtime world building

## Important philosophy

When integrating real Arnis-derived logic later:

- keep Arnis-specific logic behind an adapter
- keep Roblox-specific representation decisions out of the adapter
- do not let upstream tags or structs leak directly into the whole codebase
