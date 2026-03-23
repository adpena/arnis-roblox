# VertigoSync Boundary

## Decision

`vertigo-sync` should be treated as an adjacent repository, not as a core subsystem inside `arnis-roblox`.

## Why

The world pipeline has three different concerns:

1. Offline data compilation and manifest generation
2. Roblox import/runtime behavior in edit and play mode
3. Studio sync/plugin ergonomics

The first two define product correctness. The third only affects iteration speed.

When those concerns get blurred together, plugin failures look like world-generation failures and runtime regressions get masked by editor transport issues. That is exactly the failure mode we have been hitting.

This boundary is not a rejection of VertigoSync. It remains a high-value development tool for this project, and when the bug is in source syncing, plugin packaging, or Studio transport, we should fix it there instead of papering over it in the importer/runtime path.

## Contract

`arnis-roblox` owns:

- schema and manifest contracts
- Rust export logic
- Roblox importer/builders
- edit-mode and play-mode runtime behavior
- harnesses and regression tests proving runtime correctness

`vertigo-sync` owns:

- Studio sync transport
- plugin packaging and installation
- source/module syncing ergonomics
- edit-time automation glue
- edit-preview integration paths that are specific to synced source workflows

## Rules

1. World import/export correctness must not depend on plugin-only APIs.
2. Play-mode success must be reproducible from a built place and manifest data, even if VertigoSync is absent.
3. Edit-mode helpers may accelerate iteration, but they are optional integration paths.
4. If a bug can be reproduced from a built place without VertigoSync, fix it here.
5. If a bug is specific to source syncing, plugin packaging, or Studio transport, fix it in the adjacent `vertigo-sync` repo.
6. Supporting VertigoSync is part of the development workflow, but it must remain an optional integration path rather than the sole proof of world correctness.

## Practical implication

This repo should keep only the minimum integration surface needed to work with VertigoSync:

- project config compatibility
- harness hooks
- documentation for local adjacent-repo setup

It should not treat VertigoSync as part of the importer architecture.
