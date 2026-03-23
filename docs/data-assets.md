# Data Assets Policy

This repo contains source fixtures that are required to reproduce the offline Austin pipeline and
runtime behavior. It does not treat generated build outputs as canonical source.

## Canonical tracked data

Tracked data is allowed only when it is one of:

- a source fixture required to reproduce exporter/importer behavior
- a deterministic sample manifest or shard used by tests or Studio startup
- a small generated example under `specs/generated/` that documents schema shape

Current intentional heavy tracked fixtures include:

- `rust/data/austin_overpass.json`
- `rust/data/N30W098.hgt`
- `rust/data/terrarium/`
- `roblox/src/ServerStorage/SampleData/AustinManifestIndex.lua`
- `roblox/src/ServerStorage/SampleData/AustinManifestChunks/`
- `roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua`
- `roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/`

## Never commit

These are generated or local-only and must stay out of Git:

- `rust/out/`
- `roblox/out/`
- `out/`
- `exports/`
- `tmp/`
- monolithic local Austin manifests such as `roblox/src/ServerStorage/SampleData/AustinManifest.lua`
- local env files, keys, logs, and scratch assets

## Large file rules

- Files over `50 MB` require explicit justification.
- Files over `100 MB` are blocked by GitHub and must not enter history.
- If a file is reproducible from scripts, prefer the script and source fixture over the generated blob.

## Publishing gate

Before push:

```bash
python3 scripts/repo_audit.py --strict
python3 scripts/run_all_checks.py
```

If the audit reports tracked ignored files, remove them from the index:

```bash
git rm --cached -r out roblox/out tmp
```
