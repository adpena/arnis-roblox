# Roblox Project

This directory contains the Studio/runtime half of the scaffold.

## Files

- `default.project.json` — main Rojo project for the place
- `plugin.project.json` — optional plugin model project
- `src/` — runtime/shared/source files
- `plugin/` — plugin source

## Intended usage

- use Rojo to sync `default.project.json` into Studio
- use the plugin project if you want toolbar buttons for sample import and tests
- use Studio MCP to exercise the importer and tests
