# ADR 0001: Unsigned IPA from GitHub Actions

## Status

Accepted.

## Context

The project must produce an installable-package artifact without an Apple ID or
signing certificates. Apple's normal device distribution path requires
signing, so a completely unsigned build cannot be directly installed on a
stock iPad.

## Decision

GitHub Actions builds the app with `CODE_SIGNING_ALLOWED=NO`, packages
`Payload/MangaReader.app` into an unsigned `.ipa`, and attaches it to `v*`
releases. The README clearly documents re-signing and sideload options.

## Consequences

The artifact is not directly installable without a user-side signing step. CI
stays secret-free and reproducible.
