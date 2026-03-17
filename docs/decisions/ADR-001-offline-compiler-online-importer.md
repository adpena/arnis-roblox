# ADR-001: Offline Compiler + Online Importer

## Status
Accepted

## Context

Roblox is not the right place to own external geodata acquisition and heavyweight transformation.

## Decision

Use an offline Rust-side compiler/exporter that emits versioned manifests consumed by Roblox.

## Consequences

### Positive
- deterministic inputs for Studio
- easier testing
- better performance control
- cleaner agent workflows

### Negative
- two environments to maintain
- exporter/importer version compatibility matters
