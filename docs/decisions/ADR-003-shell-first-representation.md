# ADR-003: Shell-First Representation

## Status
Accepted

## Context

A faithful first port that includes detailed interiors and dense decoration would front-load
performance risk and slow iteration.

## Decision

Prioritize terrain, roads, water, and building shells first. Defer interiors and dense decoration.

## Consequences

- faster importer development
- cleaner benchmarks
- less early rework
- fidelity expands later from a stable base
