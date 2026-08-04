---
type: decision
title: The verb inventory is single-sourced from Registry.all
description: occtkit --verbs is the only authoritative verb list; the Makefile reads it rather than keeping a second copy, and docs point at the reference page instead of re-listing.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/82
tags: [decision, duplication, cli, occtkit, build]
timestamp: 2026-08-04
---

# Decision

`Registry.all` in `Sources/occtkit/Subcommand.swift` is the single source of truth for which
verbs exist. `occtkit --verbs` prints that list, and the `Makefile` calls it to create and
remove the busybox-style symlinks. Do not add a second hand-maintained verb list anywhere.

Documentation may group verbs by domain for orientation, but the authoritative per-verb
reference is `docs/reference/occtkit-verbs.md`, and any count or list elsewhere is a
convenience copy that must be checked against `occtkit --verbs` when verbs change.

# Why

The list was duplicated across ten places, and **five of the ten had gone stale**:

| Location | Said | |
|---|---|---|
| `README.md`, `okf/index.md`, `okf/components/index.md` | 26 | stale |
| `CLAUDE.md` (enumerated list, no numeral) | 27 | stale |
| `Makefile` VERBS (enumerated list, no numeral) | 28 | stale |
| `docs/guides/architecture.md`, `docs/guides/getting-started.md`, `docs/guides/cookbook/occtkit-cli.md`, `docs/reference/README.md`, `context7.json` | 29 | correct |

`Registry.all` had 29. `docs/reference/occtkit-verbs.md` documented all 29 without stating a
count, which is why it became the canonical per-verb reference.

The drift was not cosmetic. The Makefile's copy was missing `graph-select`, so `make install`
silently never created that symlink and the verb was unreachable under its installed name.

`Registry.verbNames` already existed, carrying the comment "for the install Makefile", and was
dead code that nothing called. The mechanism to prevent this had been written and never wired
up, which is the failure mode [search-before-building](../policies/search-before-building.md)
exists to catch.

# Consequences

`uninstall` no longer replays a verb list either. It removes every symlink in `BINDIR` that
points at the `occtkit` binary, so it still works when the build tree is gone and it cleans up
verbs that have since been removed from `Registry.all`.

Adding a verb remains two edits (a file in `Sources/occtkit/Commands/` and an entry in
`Registry.all`) and now correctly requires no build-system change.
