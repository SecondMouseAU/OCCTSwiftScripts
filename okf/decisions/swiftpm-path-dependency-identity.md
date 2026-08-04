---
type: decision
title: SwiftPM derives a path dependency's identity from the directory basename
description: Generated manifests must compute the dependency declaration and the package identity from one value, because a path dependency's identity comes from the checkout directory name and never from the name in its manifest.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/98
tags: [decision, swiftpm, packaging, occtkit, run]
timestamp: 2026-08-04
---

# Decision

When generating a SwiftPM manifest that declares a **path** dependency, compute the
`.package(path:)` declaration and the `package:` identity the target refers to from a **single
value**, never as two parallel derivations and never by hardcoding the identity.

`Sources/occtkit/Commands/Run.swift` does this via a `ScriptsDep` value carrying both.
`Scripts/run-identity-check.sh` (CI: the `verbs` workflow) guards it.

# The gotcha

**SwiftPM derives a path dependency's identity from the checkout directory's basename, not from
the `name:` field in that package's manifest.** A package whose manifest says
`name: "OCCTSwiftScripts"` has identity `bevel-gear` when checked out into a directory called
`bevel-gear`.

A URL dependency behaves differently: its identity comes from the last path component of the URL
minus any `.git`, so it is stable regardless of where anything is checked out. Only path
dependencies are exposed to this.

# Why it matters here

`occtkit run` writes a throwaway workspace whose target depends on `ScriptHarness`. It emitted a
path dependency but hardcoded the consuming side as `package: "OCCTSwiftScripts"`, so the two
agreed only when the checkout happened to carry that name. Everywhere else:

```
error: 'workspace': unknown package 'OCCTSwiftScripts' in dependencies of target 'Script';
valid packages are: 'bevel-gear'
```

That covered forks, second checkouts, git worktrees, and any `OCCTKIT_SCRIPTS_PATH` pointing at a
differently-named directory, which is the documented override. It surfaced while running the
bevel gear spike (#85) in a worktree deliberately placed outside the sibling-checkout layout.

# Consequences

Absolutize and standardize the path once, then take both the declaration and the identity from
it. Absolutizing matters because the generated manifest lives in the cache directory rather than
the caller's working directory, so a relative override would otherwise resolve against the wrong
root. Do **not** resolve symlinks: SwiftPM uses the path as declared, so an aliased path must
keep the alias's own basename for the two sides to agree.

CI cannot catch this by itself, because a CI checkout is always named after the repo. The guard
points the override at a renamed symlink instead.

# Related

The same shape of failure as [single-source-verb-inventory](single-source-verb-inventory.md): two
copies of one fact, kept in step by hand, drifting the moment something was renamed.
