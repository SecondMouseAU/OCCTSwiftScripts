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

The list had been duplicated across ten places (the Makefile, `CLAUDE.md`, `README.md`,
`okf/index.md`, `okf/components/index.md`, three `docs/guides/` pages,
`docs/reference/README.md`, and `context7.json`) and had drifted to four different answers:
26, 27, 28 and 29.

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
