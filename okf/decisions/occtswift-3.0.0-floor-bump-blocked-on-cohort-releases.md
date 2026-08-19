---
type: decision
title: OCCTSwift floor bumped to 3.0.0; the graph was blocked on the cohort, then on a stale Package.resolved
description: Package.swift floors OCCTSwift at 3.0.0 (#118/#119, released as v1.6.2). Initially blocked on the rest of the cohort shipping 3.0.0-compatible releases; once they did, main's CI stayed red because the checked-in Package.resolved was stale enough (pre-2.0.0-bump) that SwiftPM's resolver kept a manifest-compatible-but-source-broken occtswiftais@1.3.1 pin instead of picking up 1.3.2. Fixed in #120 by regenerating Package.resolved from a sibling-free /tmp copy.
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

# Update 2026-08-19: the cohort caught up, and "leave it untouched" bit back

Same day, a few hours later: `OCCTSwiftTools` v1.6.4, `OCCTSwiftMesh` v1.7.5, `OCCTSwiftIO` v1.7.8
and `OCCTSwiftAIS` v1.3.2 all shipped OCCTSwift-3.0.0-compatible releases (AIS's included the 3
call-site fixes above). #119 merged and OCCTSwiftScripts v1.6.2 released — but `main`'s `tests`/
`verbs` CI immediately went red again, with the *exact same* `.bounds`-unwrap compile errors this
decision already fixed, now reported inside `.build/checkouts/OCCTSwiftAIS`.

**Root cause: the "leave `Package.resolved` untouched" call above was right while the cohort was
blocked, and wrong the moment it wasn't.** The checked-in `Package.resolved` was stale from well
before even the 2.0.0 bump (`occtswift` pinned at `1.17.0`, `occtswiftais` at `1.3.1`). SwiftPM's
resolver treats an existing `Package.resolved` as a starting point and keeps a pinned version if it
still satisfies every *manifest-declared* constraint — and `occtswiftais@1.3.1` satisfies
`OCCTSwiftTools`'s bare `>= 1.6.1` requirement on paper, even though its actual source doesn't
compile against `OCCTSwift` 3.0.0. Manifest ranges can't see real source compatibility, so the
resolver kept the broken `1.3.1` pin even after `1.3.2` (with the real fix) was already published.
A race made this worse but wasn't the root cause: the CI run that produced #119's own green checks
resolved *before* AIS's fix commit landed, so a plain re-run hit the identical error and looked
like the race was the whole story — it wasn't. A second re-run, well after AIS v1.3.2's publish
timestamp, failed identically.

**Fix**: regenerated `Package.resolved` for real — not via this repo's own `swift build` (every
cohort package has a local sibling checkout here, so `occtDep` substitutes path dependencies that
don't produce meaningful remote pins) but from an isolated `/tmp` copy of the repo with no sibling
directories nearby, forcing genuine remote resolution identical to what CI does. `swift package
resolve` + `swift build --product occtkit` both clean there, resolving `occtswiftais` to `1.3.2`
(not `1.3.1`) and everything else to its current latest. Shipped as
[#120](https://github.com/SecondMouseAU/OCCTSwiftScripts/pull/120), `main` green again afterward.

**The generalizable lesson**: "leave `Package.resolved` untouched, it'll refresh naturally" is
only true the *next* time someone runs `swift package resolve` fresh with no existing lockfile
conflict to resolve around — CI always has an existing lockfile, so it never gets that fresh start
on its own. Once a blocked cohort actually catches up, refreshing `Package.resolved` deliberately
(via a real, sibling-free resolution) is a required follow-up step, not an optional cleanup. A
stale-but-manifest-compatible pin is invisible until something downstream actually fails to
compile against it.
