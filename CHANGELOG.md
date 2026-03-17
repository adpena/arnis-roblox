# Changelog

## 0.3.0 - Unreleased

### Added
- **CLI Validate Command**: Added `arbx_cli validate <PATH>` command for validating manifest files against schema 0.2.0.
- **CLI Validate Tests**: Added unit tests for the validate command covering valid manifests, schema version checks, and required field validation.
- **CLI Diff Command**: Added `arbx_cli diff <PATH1> <PATH2>` command for comparing two manifest files and reporting structural differences.
- **CLI Diff Tests**: Added unit tests for the diff command covering identical manifests and version/chunk count differences.
- **CI Workflow**: Added GitHub Actions CI workflow (`.github/workflows/ci.yml`) that runs scaffold checks, Rust tests, formatting, clippy lints, and Luau linting on push and pull requests.
- **TestEZ Integration**: Added TestEZ BDD-style test framework for Roblox-side unit testing (`ReplicatedStorage.Testing.TestEZ`).
- **TestEZ Tests**: Added TestEZ-based tests for ChunkSchema and Migrations modules.
- **Building Interiors**: Added room/interior support to building schema and `RoomBuilder` for constructing interior walls, floors, ceilings, doors, and windows.
- **Rail/Power Props**: Added support for rail/power infrastructure props (`rail_signal`, `rail_crossing`, `power_pole`, `power_transformer`, `street_light`, `traffic_light`) with fallback geometry.

### Changed
- **Schema Version**: Updated `specs/chunk-manifest.schema.json` to include `rooms` array in buildings and `room` definition.
- **Schema Version**: Updated `specs/sample-chunk-manifest.json` to version 0.2.0 with `totalFeatures` and explicit material/color fields.
- **Check Scaffold**: Updated `scripts/check_scaffold.py` to expect schema version 0.2.0.
- **Test Runner**: Updated `Tests/RunAll.lua` to support both legacy tests and TestEZ-style test blocks.
- **ChunkSchema**: Updated to validate room definitions in buildings.
- **ImportService**: Updated to build rooms inside buildings after shell construction.
- **PropBuilder**: Extended to handle rail/power prop kinds with fallback geometry.

### Fixed
- **WaterPolygonFeature**: Added missing `kind` field to `WaterPolygonFeature` struct in `arbx_pipeline` crate.

### Completed Epics
- **Epic B (Rust exporter)**: All items complete
- **Epic D (Tooling)**: All items complete
- **Epic E (Fidelity)**: All items complete

## 0.2.0 - 2026-03-17

### Added
- **Schema Migration**: Added a `Migrations` module in Luau to automatically upgrade older manifests.
- **Manifest Version 0.2.0**: Added `meta.totalFeatures` requirement for improved validation.
- **Rust Exporter**: Updated to emit 0.2.0 manifests with calculated feature counts.

### Changed
- **Chunker**: Improved polyline splitting with precise boundary clipping and chunk-local coordinate normalization.
- **Builders**: Updated `BuildingBuilder.lua` to handle vertical chunk-local offsets.

## 0.1.0 - 2026-03-16

- Initial Kodex-oriented scaffold
- Rust workspace with exporter and CLI stubs
- Roblox importer/runtime skeleton
- Plugin skeleton for Studio imports
- Schema, ADRs, and performance docs
- Smoke-test harnesses and repo check script
