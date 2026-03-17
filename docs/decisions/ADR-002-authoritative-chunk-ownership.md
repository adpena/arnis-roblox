# ADR-002: Authoritative Chunk Ownership

## Status
Accepted

## Context

Without clear ownership, repeated imports create duplication and unload becomes ambiguous.

## Decision

Every imported object must belong to exactly one authoritative chunk folder.

## Consequences

- idempotent import becomes realistic
- unload/reload becomes straightforward
- cross-chunk geometry needs an explicit split or owner rule
