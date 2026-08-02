# ADR 0002: Lazy Recursive Archive Indexing

## Status

Accepted.

## Context

Manga libraries frequently contain single-child wrapper folders, nested
archives, and very large volumes. Fully extracting or eagerly walking every
archive at import time would make scanning slow and storage usage unbounded.

## Decision

Only the unambiguous single-child wrapper is collapsed automatically. Nested
archives are indexed lazily with explicit limits: recursion depth 4, 20,000
entries, 512 MB per entry, and 2 GB estimated total size. Extracted pages and
indexes live in the evictable derived cache.

## Consequences

First open may pay a one-time indexing cost. Archive limits can reject
pathological inputs without destabilizing the app.
