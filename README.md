# Arnis Roblox Scaffold for Kodex

This repository scaffold is the starting point for a serious Roblox port of the **Arnis** idea:
an offline geodata compiler in Rust that emits a Roblox-oriented chunk manifest, plus a Roblox
Studio importer/runtime that can build those chunks into a streamed world.

## What this scaffold is optimizing for

- **Architecture first**: clean separation between compile-time export and Studio/runtime import.
- **Performance discipline**: chunk everything, stream aggressively, and prefer coarse terrain plus
  simple building shells before chasing decorative fidelity.
- **Agent-friendly development**: Kodex should be able to reason about the repo without inventing
  architecture from scratch.
- **Roblox reality**: terrain, parts, meshes, streaming, and plugin/editor flows are all different
  from Minecraft and need first-class treatment.

## Repository layout

```text
.
├─ AGENTS.md
├─ KODEX.md
├─ docs/
├─ specs/
├─ scripts/
├─ rust/
└─ roblox/
```

## The intended end-state

1. A Rust pipeline ingests real-world geometry from an upstream data source adapter.
2. The pipeline normalizes and chunks that geometry into a versioned JSON manifest.
3. Roblox Studio imports the manifest into an optimized folder/model layout.
4. The runtime loads/unloads chunks deterministically and supports iteration through Studio MCP.

## Quick start

### 1) Read the architecture docs

Start with:

- `docs/architecture.md`
- `docs/build-pipeline.md`
- `docs/chunk_schema.md`
- `docs/performance-budget.md`
- `docs/studio_mcp_playbook.md`

### 2) Generate a sample manifest

```bash
cargo run --manifest-path rust/Cargo.toml -p arbx_cli -- sample --out specs/generated/sample-manifest.json
```

### 3) Run the local scaffold checks

```bash
python scripts/run_all_checks.py
```

### 4) Bring the Roblox project into Studio

- Open `roblox/default.project.json` with Rojo.
- Sync it into an empty Studio place.
- Build `roblox/plugin.project.json` into a plugin model if you want a toolbar import button.

### 5) Use the sample importer

- Import the sample manifest through the plugin, or
- enable the bootstrap script after reviewing it, or
- use Studio MCP to require `ImportService` and call `ImportManifest()` directly.

## Hard guardrails

- Do **not** fetch live OSM/Overpass/elevation data from Roblox runtime scripts.
- Do **not** let Studio-only helper code become required runtime code.
- Keep manifest schema compatibility explicit and versioned.
- Every importer-side change should preserve idempotency: importing the same chunk twice must not
  silently duplicate world content.
- Every new representation choice must be justified against the budgets in
  `docs/performance-budget.md`.

## What is deliberately incomplete

This scaffold is not pretending to be the finished product. It gives Kodex:

- project shape
- contracts
- stub crates
- importer modules
- test harnesses
- performance envelopes
- ADRs
- agent instructions

That is enough to accelerate toward the real system without locking you into bad early decisions.

## Licensing note

This scaffold contains original scaffold code and documentation only. It does **not** copy upstream
Arnis source code. See `NOTICE` for attribution and future integration notes.
