# Play/Preview/Export Convergence Design

## Goal

Make edit preview, play mode, and baked export consume the same canonical full-bake world truth so that
preview-quality rendering is reproducible in play and in exported artifacts without flicker, shell corruption,
minimap drift, runtime-only regressions, or format drift between Roblox and 3D export outputs.

## Problem Statement

The current system has one compiler pipeline but multiple materially different consumers:

- edit preview via `AustinPreviewBuilder`
- play/runtime via `RunAustin` + `BootstrapAustin`
- future full-bake/export via separate planning work and a parallel `vsync export-3d` target

Those paths differ in enough ways that the user can see better geometry, terrain, and material presentation in
preview than in play, and better world truth in preview than in any export-ready runtime path. The result is a
recurring class of bugs:

- runtime spawn lands in a bad local envelope
- startup import and streaming reconciliation disagree
- minimap transforms drift across layers
- gameplay systems perturb the camera/audio/bootstrap path
- preview, play, and export do not consume the same manifest family or anchor semantics
- harness and MCP can observe or capture the world before it is actually settled

The fix is not more isolated patches. The fix is convergence on one canonical world contract plus explicit,
small policy differences per mode.

## Non-Goals

- Rewriting the compiler or Roblox importer from scratch
- Adding interiors or new fidelity features before the shell/runtime path is stable
- Solving full-planet streaming in one pass
- Merging `arnis-roblox` domain logic into `vertigo-sync`
- Making the bounded dev/harness slice the canonical world source

## Repo Boundary

### `arnis-roblox`

Owns:

- canonical compiled world artifacts and chunk semantics
- preview/runtime/full-bake world consumers
- importer/builders, terrain/building/material truth
- minimap payload generation and runtime rendering
- spawn/bootstrap/gameplay/runtime streaming policy
- baked Roblox place/file generation
- export adapters for baked-scene extraction and scene IR population

### `vertigo-sync`

Owns:

- file sync and edit-session orchestration
- authoritative readiness state machine
- target-based readiness query/event APIs
- edit-session correctness contract consumed by harness tooling
- authoritative full-bake orchestration
- `export-3d` CLI surface
- `.glb` and `.fbx` emission from one canonical scene IR

### MCP / harness tooling

Owns:

- automation
- observation
- screenshots and log capture

It must not be part of correctness.

## Core Design

### 1. One Canonical Full-Bake World Source

Preview, play, baked Roblox place export, and `vsync export-3d` all derive their content from one canonical
full-bake world source. Bounded preview and bounded dev-play fixtures may still exist, but they must be
deterministic projections of the same source and selection math. They are accelerators only, never the source
of truth.

For any shared envelope contract `(manifest source, anchor, radius, allowed subplans/layers)`, preview and play
must resolve the same chunk IDs and the same per-chunk source-feature identities before policy-specific runtime
differences are applied. The same rule extends to baked export: export must reflect the same world truth after
full bake, not a preview-only approximation.

The system distinguishes:

- **content truth**: chunks, subplans, geometry, terrain, materials, minimap polygons, signatures
- **policy**: radius, interaction/collision mode, gameplay enabled, camera/spawn policy, debug helpers,
  export packaging

Policy may vary by consumer. Content truth may not.

The canonical source must be a full-bake contract, not the current preview-only manifest family.

### 2. Consumer Modes On Top Of One World Contract

The canonical world contract is consumed by four modes:

1. `preview`
2. `play`
3. `full_bake_place`
4. `export_3d`

Those modes are allowed to vary only in explicit policy:

- load envelope size
- interaction/collision conveniences
- gameplay systems enabled
- readiness targets and orchestration
- artifact serialization

They are not allowed to redefine:

- manifest family
- chunk identity
- anchor semantics
- terrain/building/material interpretation
- scene graph truth after full bake

### 3. Canonical Export Path

Export must come from the same canonical full-bake world, not from a separate offline converter and not from the
current preview-only path.

Required outputs:

- baked Roblox place/file
- `.glb`
- `.fbx`

Rules:

- `vertigo-sync` owns the general orchestration and `export-3d` CLI.
- `arnis-roblox` owns world-specific bake hooks and scene extraction adapters.
- `.glb` and `.fbx` must be emitted from one canonical scene IR so the two formats cannot drift by design.
- baked Roblox file export must reflect the same full-bake world truth as the 3D exports.

The intended mental model is:

`compiler -> canonical full-bake world -> preview/play/place export/glb/fbx`

### 4. Canonical Runtime Bootstrap

Play mode must become a strict state machine instead of a loose pile of startup side effects:

1. load manifest source
2. resolve canonical runtime anchor
3. import startup envelope
4. verify world root settled and registered
5. place player spawn
6. start streaming
7. start minimap
8. enable gameplay systems
9. mark gameplay-ready

Duplicate bootstrap entry is a bug. It must be removed, not tolerated.

The bootstrap state machine must be externally observable so tests and tools do not infer readiness from logs.
At minimum, the runtime path must publish stable attributes or equivalent signals for:

- `loading_manifest`
- `importing_startup`
- `world_ready`
- `streaming_ready`
- `gameplay_ready`
- `failed`

### 5. Canonical Chunk Registration

Startup import and streaming reconciliation must use the same chunk signatures, registration metadata, and
loaded-chunk identity rules. A startup-imported chunk must look identical to the streaming system as a chunk
loaded later.

This is required to prevent runtime from unloading or degrading just-imported content.

### 6. Canonical Minimap Transform

The minimap needs one world-to-map transform for all layers. Static layers should be north-up and derived from
canonical chunk payloads. Runtime should only handle visibility/compositing and player marker updates.

No static layer should reraster every frame. No layer should use a different rotation basis than the others.

### 7. Gameplay Isolation

Jetpack, vehicles, audio, and other gameplay systems must be downstream consumers of runtime readiness. They
cannot be allowed to destabilize bootstrap, spawn, or world rendering.

If a gameplay subsystem fails, the world must still render and the player must still spawn correctly.

Gameplay validation is a separate concern from world-truth validation. The play harness must support:

- world-fidelity play mode with gameplay systems disabled or inert
- gameplay validation mode for vehicles, jetpack, parachute, audio, and camera behavior

### 8. Harness Truthfulness

`arnis-roblox` must emit authoritative runtime hooks and signals for world-ready and gameplay-ready. External
tooling may consume those hooks, but `arnis-roblox` does not own MCP or screenshot orchestration.

`vertigo-sync` readiness is the authoritative gate for edit targets; runtime bootstrap readiness emitted by
`arnis-roblox` is the authoritative gate for play.

Screenshots, probes, and assertions taken before those gates are not trustworthy.

## Execution Strategy

### Phase 1: Converge World Truth

- unify preview/runtime fixture derivation
- add preview/play/export parity tests for the same shared envelope contract
- verify same chunk IDs, same source-feature IDs, and same minimap payload payloads before policy-specific runtime differences
- promote the canonical source to the full-bake/runtime world contract
- keep bounded slices as derived local-dev accelerators only

### Phase 2: Fix Runtime Bootstrap

- remove duplicate bootstrap entry
- enforce bootstrap state machine ordering
- ensure gameplay systems start after world-ready

### Phase 3: Fix Building/Terrain Presentation

- audit shell-mesh parity between preview and play
- lock roof-only, wall closure, and terrain-material truth with regression tests
- ensure no runtime path replaces imported truth with partial placeholders

### Phase 4: Fix Minimap Canonicalization

- single transform for all layers
- precomputed static chunk payloads
- north-up map
- incremental compositing only

### Phase 5: Fix Harness / MCP Observation

- emit explicit runtime-ready hooks from `arnis-roblox`
- make external tooling consume readiness before capture or probe
- tie visual regression probes to canonical readiness

### Phase 6: Add Canonical Baked Export

- route full-bake orchestration through `vertigo-sync`
- build one canonical scene IR from the baked world
- emit baked Roblox place/file, `.glb`, and `.fbx` from the same world truth
- verify exported scene IDs/materials/chunk ownership against the canonical full-bake world

### Phase 7: Prepare for Planetary Streaming

- stable chunk/tile IDs everywhere
- bounded-memory indexes and telemetry
- contracts that can scale to larger-radius world serving without changing world truth

## Required Invariants

The work is only correct if these remain true:

- preview and play for the same envelope resolve the same chunk content truth
- preview, play, baked Roblox file export, `.glb`, and `.fbx` all derive from the same canonical full-bake world truth
- the same source input and config produce the same manifest and equivalent scene graph
- repeated imports remain idempotent
- startup import and streaming agree on loaded chunk identity
- minimap layer transforms are identical across roads, landuse, and background payloads
- gameplay failures do not corrupt spawn or world rendering
- external tooling acts only after authoritative readiness signals
- memory guardrails remain enforced in dev/testing

## Verification Requirements

Each phase must add or strengthen automation:

- unit/spec tests for spawn, minimap transforms, roof/wall truth, terrain-material truth
- import parity tests for preview vs play
- full-bake/export parity tests for place vs scene IR vs `.glb`/`.fbx`
- runtime contract tests for bootstrap ordering and observable `world_ready` / `gameplay_ready` state
- external-tooling checks for blocked assets, duplicate bootstrap, empty world roots, and overhead roof counts
- post-ready visual regression snapshots for preview and play

## Recommended Initial Task Order

1. Canonical preview/play/export parity contract
2. Runtime bootstrap state machine and duplicate-bootstrap removal
3. Building/terrain truth fixes in play
4. Minimap canonicalization and redraw stability
5. Gameplay isolation and forbidden-asset cleanup
6. Canonical baked Roblox place + `.glb` + `.fbx` export path
7. Harness/MCP readiness-safe observation
8. Planetary-streaming scalability hardening

## Success Criteria

This effort is complete when:

- play mode looks materially the same as edit preview for the same bounded envelope
- baked Roblox place export and `.glb`/`.fbx` exports materially match that same world truth
- no duplicate bootstrap remains
- spawn is deterministic and street-valid
- minimap is aligned, smooth, and intuitive
- no blocked assets occur in standard play
- harness proofs are taken only after readiness and are visually trustworthy
- dev play/edit stay under the configured memory guardrail
- the same contracts can scale outward to larger-radius and future planetary streaming
