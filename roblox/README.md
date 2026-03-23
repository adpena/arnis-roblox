# Roblox Project

This directory contains the Studio/runtime half of the scaffold.

## Files

- `default.project.json` — main Vertigo Sync project for the place using Rojo-style conventions
- `plugin.project.json` — optional plugin model project
- `src/` — runtime/shared/source files
- `plugin/` — plugin source

## Intended usage

- use `python3 ../scripts/bootstrap_arnis_studio.py --open --serve` from the repo root as the supported way to create/open a fresh Arnis place from `default.project.json`
- use `vsync serve --project default.project.json` when you want live sync against that bootstrapped place
- use the plugin project if you want toolbar buttons for sample import and tests
- use Studio MCP to exercise the importer and tests
