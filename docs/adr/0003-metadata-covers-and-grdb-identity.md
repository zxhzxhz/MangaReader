# ADR 0003: Metadata Covers and GRDB Identity

## Status

Accepted.

## Context

Custom covers must not rewrite user archives or folders, and reading progress
and passwords must survive moves and renames, including moves made in the Files
app outside MangaReader.

## Decision

Covers are stored as app metadata in Application Support and referenced from
GRDB. Library records use a stable UUID plus a source fingerprint; the
filesystem path is a current position, not the identity. Path changes made
inside the app update records directly; external changes are reconciled by
fingerprint, and duplicate copies are never merged.

## Consequences

Source files stay byte-for-byte untouched. Metadata recovery is best-effort for
externally moved files but deterministic when changes happen inside the app.
