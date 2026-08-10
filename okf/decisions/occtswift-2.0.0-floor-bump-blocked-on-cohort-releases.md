---
type: decision
title: OCCTSwift floor bumped to 2.0.0 in source, but the graph cannot resolve from remote until the cohort releases
description: Package.swift now floors OCCTSwift at 2.0.0 and this repo's own code is fixed against every relevant break, but OCCTSwiftIO's latest release (v1.7.6) still requires occtswift 1.17.0..<2.0.0 transitively, and OCCTSwiftTools/AIS/Mesh's own latest releases are on the same floor. A fresh clone cannot resolve until at least OCCTSwiftIO ships a 2.0.0-compatible release.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/111
tags: [decision, occtswift, dependency-resolution, release-sequencing, semver]
timestamp: 2026-08-10
---

# Decision

`Package.swift`'s `OCCTSwift` dependency is `from: "2.0.0"` as of OCCTSwiftScripts#111. This
repo's own source is fixed against every relevant v2.0.0 break (see `CLAUDE.md`'s dependency
entry for the two that needed a code change: OCCTSwift#763 and #642). `swift build`/`swift test`
are clean **locally**, via the local-sibling-checkout trick (`occtDep` in `Package.swift`
prefers a `../<name>` path dependency when present) — every sibling repo's own, not-yet-released
local checkout has already moved its floor to 2.0.0 too, so the local graph resolves.

**A fresh clone / CI run cannot resolve the same graph from remote yet.** Verified directly, not
inferred: copying this repo to a location with no local `OCCTSwift` sibling and running
`swift package resolve` fails with

```
error: Dependencies could not be resolved because root depends on 'occtswift' 2.0.0..<3.0.0 and
root depends on 'occtswiftio' 1.7.5..<2.0.0.
'occtswiftio' >= 1.7.5 practically depends on 'occtswift' 1.12.9..<2.0.0 because 'occtswiftio'
1.7.5 depends on 'occtswift' 1.12.9..<2.0.0 and 'occtswiftio' 1.7.6 depends on 'occtswift'
1.17.0..<2.0.0.
```

OCCTSwiftIO's latest GitHub release (v1.7.6) declares its own `occtswift` dependency as
`from: "1.17.0"`, which SwiftPM's `from:` resolves as `>=1.17.0, <2.0.0` — an implicit upper
bound that now excludes 2.0.0. OCCTSwiftTools (v1.6.2), OCCTSwiftAIS (v1.3.1), and OCCTSwiftMesh
(v1.7.2) are all on the same "repin to 1.17.0" era release as their latest published tag, so the
same mechanism almost certainly blocks each of them too, transitively, even once OCCTSwiftIO's
own floor moves.

# What this means for sequencing

This is the same situation OCCTSwiftScripts#111's own issue text anticipated ("sequence the
release after OCCTSwiftTools's 2.0.0 release lands"), just confirmed to be wider than Tools
alone: **the whole cohort** needs a 2.0.0-compatible release before this repo's own PR can be
tagged as a release, not merged as a PR. The PR itself is not blocked — review and merge do not
require a resolvable remote graph, only a resolvable local one (which the sibling-checkout trick
already provides for every contributor working the way this ecosystem's `Package.swift` files
expect). Only the **release** (a git tag consumers resolve against) is blocked, and only until at
least OCCTSwiftIO ships first.

`Package.resolved` is intentionally left untouched by the OCCTSwiftScripts#111 PR (matching the
precedent set by `d5d31e8`, a prior pure floor-bump commit that also touched only `Package.swift`):
regenerating it from the local sibling graph would commit path-relative local-machine state, and
regenerating it from remote is not possible yet for the reason above. It will refresh naturally
the first time `swift package resolve`/`swift build` runs after the cohort catches up.
