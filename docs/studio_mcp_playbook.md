# Studio MCP Playbook

This file is written for Kodex or any external coding agent using Roblox Studio MCP.

## Goal

Use Studio MCP as an **iteration surface**, not as the main world generator.

## Recommended loop

1. Keep source-of-truth files in this repository.
2. Sync Roblox sources into Studio.
3. Use MCP to inspect the current place tree.
4. Trigger sample imports or tests.
5. Read logs and profiler output.
6. Make code changes in the filesystem.
7. Repeat.

## First commands Kodex should perform

- inspect `Workspace.GeneratedWorld`
- inspect `ServerScriptService.ImportService`
- require the sample manifest
- import the sample manifest
- run the smoke tests
- report created folders, instance counts, and any warnings

## Hard rules for MCP-driven changes

- avoid one-off manual edits that are not reflected in source files
- do not add runtime HTTP fetches
- do not bypass schema validation
- do not hide generated content outside `Workspace.GeneratedWorld`

## Suggested Kodex prompt

```text
Use Studio MCP to inspect the current place tree, import the sample manifest through
ServerScriptService.ImportService, run the smoke test entry point, and summarize:
1) which folders and instances were created,
2) total imported chunk count,
3) warnings or TODOs surfaced by the importer,
4) the next highest-leverage performance improvement.
```

## Playtest loop

Once chunk lifecycle exists, use MCP to:

- start a playtest
- move/load test chunks
- read console output
- stop playtest
- fix errors in the repo
- repeat

## What MCP should not own

- schema design
- upstream geodata retrieval
- irreversible architecture decisions without ADR updates
