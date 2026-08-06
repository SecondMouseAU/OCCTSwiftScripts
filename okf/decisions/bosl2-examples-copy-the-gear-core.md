---
type: decision
title: The BOSL2 bevel gear examples copy the gear core rather than sharing it
description: occtkit run compiles one file with one dependency, so the three docs examples each carry an identical 617-line construction core; Scripts/gear-core-check.sh asserts the copies stay identical, and promoting the core to a library product is left as a recommendation.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/89
tags: [decision, occtswift, gears, bevel, docs, duplication, ci]
timestamp: 2026-08-06
---

# Decision

`docs/guides/bosl2-bevel-gears/example1.swift`, `example2.swift` and `example3.swift` each carry
a byte-identical 617-line block of gear construction code, delimited by `BEGIN SHARED GEAR CORE`
and `END SHARED GEAR CORE` marker comments. `Scripts/gear-core-check.sh` asserts the three copies
hash identically and runs in CI (`.github/workflows/docs-consistency.yml`, alongside
`policy-check.sh`).

# Why the duplication is forced

`occtkit run` generates a cached SPM workspace with exactly one `Sources/Script/main.swift` whose
only dependency is the `ScriptHarness` product (`Sources/occtkit/Commands/Run.swift`). A script
cannot `import` a shared gear module without changing `Run.swift`. The acceptance criterion for
[#89](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/89) is that each example actually
runs under `occtkit run`, so each example has to be self-contained. That is also the convention
`recipes/README.md` already states: self-contained, no shared utilities, no cross-recipe imports.

# Why the core was not promoted to a library product

A new library product is a permanent public-API commitment for a SemVer-stable package. It is the
"where does this live" question [#88](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/88)
explicitly left open, and shipping a docs page is not the right moment to answer it. The
recommendation, with the 617-line duplication as the evidence, is recorded on #89 instead.

# What the check does, and what would make it fail

Three copies of 617 lines drift. #82 had just finished removing 217 lines of exactly this kind of
duplication, so shipping three more copies without a guard would have been a regression in
everything but name.

`Scripts/gear-core-check.sh` extracts the marked block from each `example*.swift`, and fails if:

1. any file has other than exactly one BEGIN and one END marker, in that order;
2. any extracted block is shorter than 300 lines, which is what stops the degenerate case where
   the block has been gutted in ALL copies from passing trivially as "all equal";
3. any two extracted blocks differ, in which case it prints the diff.

Both failure modes were exercised before the check was committed: changing `flankSamples` from 14
to 15 in one copy fails with the diff, and reducing the block to its two marker lines in all three
copies fails on the length guard.

# Consequences

Editing the gear core means editing all three files. The intended workflow is to edit one and copy
the block into the other two, then run `Scripts/gear-core-check.sh` before committing.
