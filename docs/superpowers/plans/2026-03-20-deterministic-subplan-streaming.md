# Deterministic Subplan Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic per-chunk subplans to the manifest/index and importer so preview/runtime streaming can schedule heavy chunks more intelligently without changing source truth or regressing fidelity.

**Architecture:** Keep canonical chunks fixed, emit additive deterministic subplan metadata offline, enforce a coarse-layer dependency DAG in the importer, and let preview/runtime schedule `chunk + subplan` with a persisted learned-cost cache layered on top. Profile and audit the executed subplan order so adaptive scheduling remains reproducible and safe.

**Tech Stack:** Rust (`arbx_pipeline`, `arbx_roblox_export`, `arbx_cli`), Luau importer/runtime/preview modules, Python manifest generation and verification scripts, Bash Studio harness.

---

### Task 1: Add additive subplan metadata to generated chunk indexes

**Files:**
- Modify: `scripts/json_manifest_to_sharded_lua.py`
- Modify: `scripts/refresh_preview_from_sample_data.py`
- Modify: `scripts/verify_generated_austin_assets.py`
- Modify: `scripts/tests/test_json_manifest_to_sharded_lua.py`
- Modify: `scripts/tests/test_refresh_preview_from_sample_data.py`
- Modify: `scripts/tests/test_generated_austin_assets.py`
- Modify: `docs/chunk_schema.md`
- Modify: `specs/chunk-manifest.schema.json`

- [ ] **Step 1: Write the failing generator/verifier tests**

Add tests asserting generated `chunkRefs` can carry:
- `partitionVersion`
- `subplans`
- per-subplan `id`, `layer`, `featureCount`, `streamingCost`
- optional `bounds`

Also add verifier tests asserting:
- missing `partitionVersion` is rejected when `subplans` exist
- malformed subplan tables are rejected

- [ ] **Step 2: Run the Python tests to verify they fail**

Run:

```bash
python3 -m unittest scripts.tests.test_json_manifest_to_sharded_lua scripts.tests.test_refresh_preview_from_sample_data scripts.tests.test_generated_austin_assets -v
```

Expected: FAIL because subplan metadata is not emitted, preserved, or verified yet.

- [ ] **Step 3: Extend the generator to emit additive subplan metadata**

In `scripts/json_manifest_to_sharded_lua.py`:
- keep the current `chunkRefs` array contract
- add serialization support for `partitionVersion` and `subplans`
- treat Rust-emitted subplan metadata as authoritative
- do not derive a second partition function in Python
- continue deriving only fallback `featureCount` / `streamingCost` when subplans are absent, as the current generator already does for chunk-level hints

- [ ] **Step 4: Preserve subplans through preview refresh**

In `scripts/refresh_preview_from_sample_data.py`:
- parse `partitionVersion`
- parse `subplans`
- preserve those fields when writing preview `chunkRefs`
- keep the current array-of-refs structure and `originStuds` object shape intact

- [ ] **Step 5: Extend verification and docs**

In `scripts/verify_generated_austin_assets.py`:
- fail if `subplans` exist without `partitionVersion`
- fail if subplan shape is incomplete

In docs/schema:
- document additive index-level subplan metadata
- note that this is scheduling metadata only, not manifest truth
- add scheduling-layer migration notes for `partitionVersion` / subplan-contract changes alongside the schema docs

- [ ] **Step 6: Re-run the Python tests**

Run:

```bash
python3 -m unittest scripts.tests.test_json_manifest_to_sharded_lua scripts.tests.test_refresh_preview_from_sample_data scripts.tests.test_generated_austin_assets -v
python3 scripts/verify_generated_austin_assets.py
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/json_manifest_to_sharded_lua.py scripts/refresh_preview_from_sample_data.py scripts/verify_generated_austin_assets.py scripts/tests/test_json_manifest_to_sharded_lua.py scripts/tests/test_refresh_preview_from_sample_data.py scripts/tests/test_generated_austin_assets.py docs/chunk_schema.md specs/chunk-manifest.schema.json
git commit -m "feat: add deterministic subplan metadata to chunk refs"
```

### Task 2: Emit deterministic coarse subplans from Rust-side manifest logic

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/lib.rs`
- Modify: `rust/crates/arbx_roblox_export/src/chunker.rs`
- Modify: `rust/crates/arbx_cli/src/main.rs`
- Create: `rust/crates/arbx_roblox_export/src/subplans.rs`
- Create: `rust/crates/arbx_roblox_export/tests/subplans.rs`
- Test: `rust/crates/arbx_roblox_export/tests/subplans.rs`

- [ ] **Step 1: Write the failing Rust subplan tests**

Add tests asserting:
- same input chunk yields the same `partitionVersion`
- same input chunk yields the same ordered coarse subplans
- per-layer `featureCount` reflects canonical chunk contents
- per-layer `streamingCost` is stable for the same input

- [ ] **Step 2: Run the Rust tests to verify they fail**

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_roblox_export subplans -- --nocapture
```

Expected: FAIL because no subplan emission exists yet.

- [ ] **Step 3: Implement additive Rust-side subplan models**

In `subplans.rs`:
- define serializable index-side subplan types
- define `partitionVersion = "subplans.v1"`
- implement coarse-layer subplan derivation from canonical chunk data only

Keep the implementation separate from runtime-only learned scheduling.

- [ ] **Step 4: Wire subplans into export/index generation**

In `chunker.rs` / `lib.rs`:
- attach coarse subplans to exported chunk refs or equivalent index-side intermediate
- keep canonical chunk geometry untouched
- do not emit fine subplans yet

In `arbx_cli`:
- ensure exported Austin artifacts include the new metadata through the normal compile/export path
- ensure there is exactly one authoritative partition function: Rust-side subplan derivation

- [ ] **Step 5: Add source-to-manifest mistransformation guards**

Add Rust-side tests asserting:
- subplan emission does not change source-to-manifest counts
- subplan emission does not change source identity preservation
- subplan emission does not change holes/material semantics already tracked by the audit suite

Use existing Austin-focused audit fixtures or minimal synthetic fixtures where possible.

- [ ] **Step 6: Re-run the Rust tests**

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_roblox_export subplans -- --nocapture
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add rust/crates/arbx_roblox_export/src/lib.rs rust/crates/arbx_roblox_export/src/chunker.rs rust/crates/arbx_roblox_export/src/subplans.rs rust/crates/arbx_roblox_export/tests/subplans.rs rust/crates/arbx_cli/src/main.rs
git commit -m "feat: emit deterministic coarse subplans"
```

### Task 3: Teach the loader and index handle about subplans

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/ManifestLoader.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ChunkPriority.lua`
- Create: `roblox/src/ServerScriptService/Tests/ManifestSubplans.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/ChunkSubplanPriority.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/ManifestSubplans.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/ChunkSubplanPriority.spec.lua`

- [ ] **Step 1: Write the failing Luau tests**

Add specs asserting:
- `ManifestLoader` preserves `partitionVersion` and `subplans`
- `FreezeHandleForChunkIds` keeps subplan metadata
- `ChunkPriority` can sort `chunk + subplan` work items in canonical order before adaptive costs are applied

- [ ] **Step 2: Run the focused Studio specs to verify they fail**

Run: Studio test harness focused on the two new specs  
Expected: FAIL because subplans are not surfaced or scheduled yet.

- [ ] **Step 3: Extend `ManifestLoader`**

Add support for:
- `partitionVersion`
- `subplans`
- preserving them when chunk refs are rebuilt from shards
- preserving them when handles are frozen to selected chunk ids

Keep compatibility with chunk refs that have no subplans.

- [ ] **Step 4: Extend `ChunkPriority` to score subplan work items**

Add helpers for:
- canonical subplan ordering
- chunk+subplan priority scoring
- stable tie-breaks

Do not add learned persistence yet.

- [ ] **Step 5: Re-run the Studio specs**

Run: Studio test harness focused on the two new specs  
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/ManifestLoader.lua roblox/src/ServerScriptService/ImportService/ChunkPriority.lua roblox/src/ServerScriptService/Tests/ManifestSubplans.spec.lua roblox/src/ServerScriptService/Tests/ChunkSubplanPriority.spec.lua
git commit -m "feat: load and rank deterministic subplans"
```

### Task 4: Add importer-side subplan execution with dependency DAG enforcement

**Files:**
- Modify: `roblox/src/ServerScriptService/ImportService/init.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/ImportPlanCache.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RoadChunkPlan.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/LanduseBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/WaterBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/Builders/PropBuilder.lua`
- Create: `roblox/src/ServerScriptService/Tests/SubplanImportDag.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/SubplanImportEquivalence.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/SubplanImportRetry.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/SubplanImportDag.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/SubplanImportEquivalence.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/SubplanImportRetry.spec.lua`

- [ ] **Step 1: Write the failing importer specs**

Add specs asserting:
- importing `roads` before `landuse` fails closed
- importing all coarse subplans in legal order matches whole-chunk import for counts/ownership
- re-importing a subplan only reconciles its owned layer content
- failed `chunk + subplan` work items stay attached to that exact work id and can be retried cleanly

- [ ] **Step 2: Run the focused Studio specs to verify they fail**

Run: Studio test harness focused on the new subplan importer specs  
Expected: FAIL because the importer has no subplan API or DAG enforcement.

- [ ] **Step 3: Add a subplan-aware importer API**

In `ImportService/init.lua`:
- add a new path to import one coarse subplan for a chunk
- keep whole-chunk import intact
- enforce the first-pass DAG:
  - `terrain`
  - `landuse`
  - `roads`
  - `buildings`
  - `water`
  - `props`

- [ ] **Step 4: Keep ownership explicit and fail closed**

Ensure first-pass ownership rules:
- road imprinting stays in `roads`
- building-associated props stay in `props`
- water remains owned by `water`
- props remain owned by `props`
- importing a subplan before prerequisites errors loudly

Adjust plan/prepared caching as needed so subplan-level execution does not reuse stale whole-chunk prepared state incorrectly.

- [ ] **Step 5: Add retry-safe failure handling**

Add importer/runtime bookkeeping so:
- failures stay attached to exact `chunk + subplan`
- failed work items are visible in profiling output
- a retry can rerun that exact work item without clearing sibling-owned content

- [ ] **Step 5: Re-run the importer specs**

Run: Studio test harness focused on the new subplan importer specs  
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/init.lua roblox/src/ServerScriptService/ImportService/ImportPlanCache.lua roblox/src/ServerScriptService/ImportService/RoadChunkPlan.lua roblox/src/ServerScriptService/ImportService/Builders/TerrainBuilder.lua roblox/src/ServerScriptService/ImportService/Builders/LanduseBuilder.lua roblox/src/ServerScriptService/ImportService/Builders/RoadBuilder.lua roblox/src/ServerScriptService/ImportService/Builders/BuildingBuilder.lua roblox/src/ServerScriptService/ImportService/Builders/WaterBuilder.lua roblox/src/ServerScriptService/ImportService/Builders/PropBuilder.lua roblox/src/ServerScriptService/Tests/SubplanImportDag.spec.lua roblox/src/ServerScriptService/Tests/SubplanImportEquivalence.spec.lua roblox/src/ServerScriptService/Tests/SubplanImportRetry.spec.lua
git commit -m "feat: add deterministic subplan import execution"
```

### Task 5: Stage rollout for one safe layer or chunk class

**Files:**
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Modify: `roblox/src/ServerScriptService/BootstrapAustin.server.lua`
- Create: `roblox/src/ServerScriptService/Tests/SubplanRolloutGate.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/SubplanRolloutGate.spec.lua`

- [ ] **Step 1: Write the failing rollout-gate spec**

Add a spec asserting:
- subplan scheduling is behind an explicit feature gate or allowlist
- rollout can be restricted to one safe coarse layer or one allowlisted hot chunk class
- chunks without the allowlist still use whole-chunk scheduling

- [ ] **Step 2: Run the spec to verify it fails**

Run: Studio test harness focused on `SubplanRolloutGate.spec.lua`  
Expected: FAIL because rollout is not explicitly staged.

- [ ] **Step 3: Implement staged enablement**

Add a rollout mechanism so preview/runtime can:
- enable subplans only for one safe first-pass layer or allowlisted chunk ids
- keep whole-chunk behavior elsewhere
- surface rollout state clearly in profiling output

- [ ] **Step 4: Re-run the rollout-gate spec**

Run: Studio test harness focused on `SubplanRolloutGate.spec.lua`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua roblox/src/ServerScriptService/ImportService/StreamingService.lua roblox/src/ServerScriptService/BootstrapAustin.server.lua roblox/src/ServerScriptService/Tests/SubplanRolloutGate.spec.lua
git commit -m "feat: add staged subplan rollout gate"
```

### Task 6: Switch preview and runtime schedulers to `chunk + subplan`

**Files:**
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Modify: `roblox/src/ServerScriptService/BootstrapAustin.server.lua`
- Modify: `roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/SubplanStreaming.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/SubplanStreaming.spec.lua`

- [ ] **Step 1: Write the failing scheduling spec**

Add a spec asserting:
- preview/runtime schedule coarse subplans instead of whole chunks when subplans are present
- legal DAG order is preserved
- first scene completes terrain/roads/buildings earlier for a pathological chunk

- [ ] **Step 2: Run the spec to verify it fails**

Run: Studio test harness focused on `SubplanStreaming.spec.lua`  
Expected: FAIL because preview/runtime still schedule whole chunks only.

- [ ] **Step 3: Update preview scheduler**

In `AustinPreviewBuilder.lua`:
- schedule work items as `chunk + subplan`
- keep forward bias, observed cost, and ring priority
- record timing per subplan as well as per chunk

- [ ] **Step 4: Update runtime streaming scheduler**

In `StreamingService.lua`:
- schedule `chunk + subplan`
- preserve preferred look vector and movement-derived bias
- keep whole-chunk fallback when:
  - no subplans exist
  - rollout gate excludes the chunk/layer
  - prerequisite DAG state is incomplete

- [ ] **Step 5: Add memory-pressure-aware budgeting**

Teach preview/runtime schedulers to:
- reduce batch size under measured pressure
- defer known expensive subplans within a legal ring/order band
- record the pressure decision in profiling output

Do not allow pressure handling to:
- suppress a subplan permanently
- bypass the dependency DAG
- change canonical subplan ownership

- [ ] **Step 6: Re-run the scheduling spec**

Run: Studio test harness focused on `SubplanStreaming.spec.lua`  
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua roblox/src/ServerScriptService/ImportService/StreamingService.lua roblox/src/ServerScriptService/BootstrapAustin.server.lua roblox/src/ServerScriptService/Tests/StreamingPriority.spec.lua roblox/src/ServerScriptService/Tests/SubplanStreaming.spec.lua
git commit -m "feat: schedule chunk subplans in preview and runtime"
```

### Task 7: Persist learned subplan cost history safely

**Files:**
- Create: `roblox/src/ServerScriptService/ImportService/SubplanCostCache.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Create: `roblox/src/ServerScriptService/Tests/SubplanCostCache.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/SubplanCostCache.spec.lua`

- [ ] **Step 1: Write the failing cache spec**

Add a spec asserting:
- learned cost keys include:
  - manifest hash
  - chunk id
  - subplan id
  - quality profile
  - platform/memory tier
- invalid manifest hashes do not reuse old timings
- replay metadata records executed order separately from learned order
- memory-pressure-driven deferrals stay within legal scheduling bands and are recorded for replay/debug

- [ ] **Step 2: Run the spec to verify it fails**

Run: Studio test harness focused on `SubplanCostCache.spec.lua`  
Expected: FAIL because persisted learned cache does not exist.

- [ ] **Step 3: Implement a local learned-cost cache**

In `SubplanCostCache.lua`:
- store EWMA import times and lightweight counters
- support reading/writing a local cache payload
- never allow the cache to suppress a subplan permanently

Wire preview/runtime to:
- consult this cache
- record executed subplan order in profiling output

- [ ] **Step 4: Re-run the cache spec**

Run: Studio test harness focused on `SubplanCostCache.spec.lua`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add roblox/src/ServerScriptService/ImportService/SubplanCostCache.lua roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua roblox/src/ServerScriptService/ImportService/StreamingService.lua roblox/src/ServerScriptService/Tests/SubplanCostCache.spec.lua
git commit -m "feat: persist learned subplan scheduling costs"
```

### Task 8: Expand profiling, harness artifacts, and regression checks

**Files:**
- Modify: `scripts/run_studio_harness.sh`
- Modify: `scripts/scene_fidelity_audit.py`
- Modify: `scripts/tests/test_scene_fidelity_audit.py`
- Modify: `roblox/src/ServerScriptService/ImportService/SceneAudit.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/RunAustin.lua`
- Create: `scripts/tests/test_subplan_harness_artifacts.py`
- Test: `scripts/tests/test_subplan_harness_artifacts.py`

- [ ] **Step 1: Write the failing harness/artifact tests**

Add tests asserting harness artifacts include:
- executed subplan order
- per-subplan timing
- first-believable-scene timing
- chunk/subplan hotspot summaries
- per-layer first-visible completion
- repeated-run drift
- subplan memory / instance footprint where available

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
python3 -m unittest scripts.tests.test_scene_fidelity_audit scripts.tests.test_subplan_harness_artifacts -v
```

Expected: FAIL because current artifacts are chunk-level only.

- [ ] **Step 3: Add subplan profiling output**

In Luau and harness code:
- emit structured markers for `chunk + subplan`
- record dependency wait time
- record executed order
- record first-visible completion per layer where feasible
- record repeated-run drift inputs
- keep logs machine-readable

In Python audit tooling:
- consume the new markers
- surface hotspot subplans in JSON/HTML outputs
- surface repeated-run drift and memory/instance footprint summaries where data exists
- keep surfacing source-to-manifest mistransformation indicators so performance work cannot silently hide upstream fidelity loss

- [ ] **Step 4: Re-run the Python tests**

Run:

```bash
python3 -m unittest scripts.tests.test_scene_fidelity_audit scripts.tests.test_subplan_harness_artifacts -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/run_studio_harness.sh scripts/scene_fidelity_audit.py scripts/tests/test_scene_fidelity_audit.py scripts/tests/test_subplan_harness_artifacts.py roblox/src/ServerScriptService/ImportService/SceneAudit.lua roblox/src/ServerScriptService/ImportService/RunAustin.lua
git commit -m "feat: add subplan profiling artifacts"
```

### Task 9: Add fine subplans for measured pathological chunks only

**Files:**
- Modify: `rust/crates/arbx_roblox_export/src/subplans.rs`
- Modify: `rust/crates/arbx_roblox_export/tests/subplans.rs`
- Modify: `scripts/manifest_quality_audit.py`
- Modify: `scripts/tests/test_manifest_quality_audit.py`
- Modify: `scripts/run_studio_harness.sh`
- Modify: `roblox/src/ServerScriptService/ImportService/init.lua`
- Modify: `roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua`
- Modify: `roblox/src/ServerScriptService/ImportService/StreamingService.lua`
- Create: `roblox/src/ServerScriptService/Tests/FineSubplanExecution.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/FineSubplanPermutation.spec.lua`
- Test: `rust/crates/arbx_roblox_export/tests/subplans.rs`
- Test: `scripts/tests/test_manifest_quality_audit.py`
- Test: `roblox/src/ServerScriptService/Tests/FineSubplanExecution.spec.lua`
- Test: `roblox/src/ServerScriptService/Tests/FineSubplanPermutation.spec.lua`

- [ ] **Step 1: Write the failing fine-subplan tests**

Add tests asserting:
- fine subplans appear only when fixed thresholds are crossed
- emitted fine-subplan `bounds` are stable and reproducible for the same canonical chunk
- boundary-spanning features are assigned whole by centroid/midpoint ownership
- no duplicated features across sibling subplans
- fine subplans are executable by the importer/runtime scheduler, not just emitted in metadata
- partition-version invalidation is enforced when fine subplan shape changes
- legal fine-subplan permutation inside a layer yields equivalent final content
- edit preview and runtime can both execute allowlisted fine subplans without missing content

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_roblox_export subplans -- --nocapture
python3 -m unittest scripts.tests.test_manifest_quality_audit -v
```

Run: Studio test harness focused on `FineSubplanExecution.spec.lua` and `FineSubplanPermutation.spec.lua`

Expected: FAIL because only coarse subplans exist.

- [ ] **Step 3: Implement fine subplans for one or two measured hot layers**

In `subplans.rs`:
- add deterministic fine subplans for `buildings` and/or `roads` only
- use centroid/midpoint whole-feature ownership
- keep quadrants as the first spatial partition shape

In importer/runtime code:
- extend subplan execution from coarse-only to fine subplans for the same allowlisted hot chunk/layer class
- keep DAG enforcement and retry semantics intact

In audit tooling:
- verify source/manifest counts remain unchanged
- verify source/manifest identity and topology retention remain unchanged
- expose any seam or duplication regression clearly

- [ ] **Step 4: Re-run the tests**

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p arbx_roblox_export subplans -- --nocapture
python3 -m unittest scripts.tests.test_manifest_quality_audit -v
```

Run: Studio test harness focused on `FineSubplanExecution.spec.lua` and `FineSubplanPermutation.spec.lua`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add rust/crates/arbx_roblox_export/src/subplans.rs rust/crates/arbx_roblox_export/tests/subplans.rs scripts/manifest_quality_audit.py scripts/tests/test_manifest_quality_audit.py scripts/run_studio_harness.sh
git commit -m "feat: add deterministic fine subplans for hot chunks"
```

### Task 10: Resilience, mixed-mode, and full verification

**Files:**
- Modify: docs as needed based on actual implementation changes
- Create: `roblox/src/ServerScriptService/Tests/SubplanMixedMode.spec.lua`
- Create: `roblox/src/ServerScriptService/Tests/SubplanCrashResume.spec.lua`
- Modify: `scripts/tests/test_scene_fidelity_audit.py`
- Modify: `scripts/tests/test_generated_austin_assets.py`

- [ ] **Step 1: Write the missing resilience tests**

Add tests for:
- mixed-mode whole-chunk plus subplan rollout
- crash/resume across partial subplan completion
- partition-version invalidation and cache non-reuse across changes
- legal permutation checks within a layer order band

- [ ] **Step 2: Run the focused resilience tests to verify they fail**

Run:

```bash
python3 -m unittest scripts.tests.test_scene_fidelity_audit scripts.tests.test_generated_austin_assets -v
```

Run: Studio test harness focused on `SubplanMixedMode.spec.lua` and `SubplanCrashResume.spec.lua`  
Expected: FAIL because these resilience paths are not covered yet.

- [ ] **Step 3: Implement the missing resilience behavior**

Add the necessary harness/importer/cache behavior so:
- whole-chunk and subplan modes can coexist safely during rollout
- interrupted subplan runs can resume without clearing sibling-owned content
- cache invalidation respects manifest hash and partition version

- [ ] **Step 4: Re-run the resilience tests**

Run the same Python and Studio commands  
Expected: PASS.

- [ ] **Step 5: Regenerate Austin artifacts**

Run:

```bash
bash scripts/export_austin_to_lua.sh
python3 scripts/verify_generated_austin_assets.py
```

Expected: PASS with subplan metadata present in runtime and preview indexes.

- [ ] **Step 6: Run Rust verification**

Run:

```bash
cargo test --manifest-path rust/Cargo.toml --workspace
```

Expected: PASS.

- [ ] **Step 7: Run Python verification**

Run:

```bash
python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
```

Expected: PASS.

- [ ] **Step 8: Run Studio verification**

Run:

```bash
bash scripts/run_studio_harness.sh --takeover --hard-restart
```

Expected:
- edit tests pass
- preview completes
- play import completes
- subplan hotspot/profiling artifacts are generated
- no fidelity regression in scene/manifest audits

- [ ] **Step 9: Review generated artifacts**

Check:
- subplan ordering is captured
- pathological chunk stall is reduced or split into cheaper legal work packets
- final scene counts still match post-load expectations

- [ ] **Step 10: Commit**

```bash
git add docs
git commit -m "docs: finalize deterministic subplan streaming rollout"
```
