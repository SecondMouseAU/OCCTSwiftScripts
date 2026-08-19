---
type: decision
title: OCCTSwift floor bumped to 3.0.0 in source, but the graph cannot resolve until the cohort releases
description: Package.swift now floors OCCTSwift at 3.0.0 and this repo's own code is fixed against both breaks, but OCCTSwiftTools/Mesh's latest releases still cap occtswift below 3.0.0, OCCTSwiftIO gates via Tools, and OCCTSwiftAIS has 3 of its own unfixed .bounds call sites. Neither a fresh clone/CI run nor an as-is local sibling build can resolve until the cohort ships.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/118
tags: [decision, occtswift, dependency-resolution, release-sequencing, semver]
timestamp: 2026-08-19
---

# Decision

`Package.swift`'s `OCCTSwift` dependency is `from: "3.0.0"` as of OCCTSwiftScripts#118. This
repo's own source is fixed against both v3.0.0 breaks (see `CLAUDE.md`'s dependency entry): the
`Selector.SubShapeType.compsolid` -> `.compSolid` rename needed no change here (already spelled
correctly), and every `.bounds` call site that became `Optional` (`Shape`/`Wire`/`Edge`/`Face`)
now unwraps, throwing a named `ScriptError` in the five `occtkit` verbs that read a bounding box
off a loaded BREP, and returning `false` from the two recipe edge-selector predicates that filter
on one.

**This is a smaller version of the same blocker as the 2.0.0 bump**
([prior decision](occtswift-2.0.0-floor-bump-blocked-on-cohort-releases.md)), but this time it
also blocks the *local sibling* build, not just remote/CI resolution:

* OCCTSwiftTools (latest: v1.6.3) and OCCTSwiftMesh (latest: v1.7.4) both still declare
  `occtDep("OCCTSwift", from: "2.0.0")`, which SwiftPM's `from:` resolves as `.upToNextMajor`,
  i.e. `>=2.0.0, <3.0.0` — excluding 3.0.0.
* OCCTSwiftIO has no direct `OCCTSwift` dependency but gates transitively through Tools.
* OCCTSwiftAIS (latest: v1.3.1) depends on `OCCTSwiftTools >= 1.6.1` and additionally has 3 of its
  own `.bounds` call sites that do not yet unwrap: `Dimension.swift:238` (`resolveBody`),
  `Dimension.swift:249` (`resolveFace`), `AreaSelection.swift:109` (body-mode hit testing).
* OCCTSwiftScripts depends on all four locally as real sibling checkouts (`../OCCTSwiftTools` etc.
  all exist under `/Users/elb/Projects/`), so `occtDep`'s local-path-override trick applies
  uniformly across the whole graph, not just to `OCCTSwift` itself. Since path dependencies
  bypass semver ranges entirely, Tools/Mesh/IO's version caps do not block a local build by
  themselves — but AIS's own unfixed `.bounds` sites are a real compile error in the local graph,
  confirmed directly: `swift build` in this repo fails inside
  `OCCTSwiftAIS/Sources/OCCTSwiftAIS/AreaSelection.swift:109` and `Dimension.swift:238,249` with
  "value of optional type ... must be unwrapped".

Verified past that point by patching those 3 AIS call sites *locally only* (not committed; AIS's
own repin is out of scope for this repo and reportedly already in progress elsewhere), then running
`swift build`, `swift build --build-tests`, `swift test` (12/12 passing, including the new
`Tests/OcctkitCommandTests/OptionalBoundsTests.swift` regression suite that constructs a
genuinely void shape via the intersection of two disjoint boxes and asserts the new throw paths
fire instead of fabricating a zero-size box), and `Scripts/recipe-check.sh` against a release
build (all 7 recipes match their reference `output.brep`, `Δvol 0.00e+00`). The AIS patch was
reverted immediately after verification, leaving that repo untouched.

Note for anyone resuming this: `swift test` (unlike `swift build --build-tests`) sometimes pulls
OCCTSwiftAIS's own `Tests/` target into the build plan too, which has 2 more unrelated `.bounds`
sites of its own (`RemapTests.swift`) plus an unrelated pre-existing `SubShape` inference error.
This looked nondeterministic across otherwise-identical runs (plausibly incremental-plan-cache
dependent) and is unrelated to this repo's own correctness; `swift test --skip-build` after a
successful `swift build --build-tests` sidesteps it without touching AIS's test files.

# What this means for sequencing

Same conclusion as the 2.0.0 precedent: the **PR** for this repo's own fix is not blocked (review
and merge do not require a resolvable graph from either remote or an unpatched local sibling set).
The **release** (a git tag consumers resolve against) and, this time, **CI on the PR itself** are
both blocked until OCCTSwiftTools and OCCTSwiftMesh ship their own OCCTSwift-3.0.0-compatible
releases and OCCTSwiftAIS ships both its repin and its 3 call-site fixes. `.github/workflows/*.yml`
in this repo use a plain `actions/checkout@v4` with no sibling checkouts, so CI resolves purely
from remote and will fail red on this PR until then, unlike a local sibling build (which fails for
the different, AIS-specific reason above).

`Package.resolved` is left untouched by the OCCTSwiftScripts#118 change, same reasoning as #111:
regenerating it now would either commit path-relative local-machine state or fail outright against
remote. It refreshes naturally once `swift package resolve`/`swift build` runs after the cohort
catches up.
