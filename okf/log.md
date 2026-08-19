# Knowledge Log

## 2026-08-19 (fix/stale-package-resolved-post-3.0.0)

* **Update**: Released OCCTSwiftScripts v1.6.2 (#118/#119) once the cohort (`OCCTSwiftTools`
  v1.6.4, `OCCTSwiftMesh` v1.7.5, `OCCTSwiftIO` v1.7.8, `OCCTSwiftAIS` v1.3.2) shipped
  OCCTSwift-3.0.0-compatible releases — but `main`'s `tests`/`verbs` CI stayed red with the exact
  break the release had already fixed. Root cause: `Package.resolved` was stale from before the
  2.0.0 bump (`occtswift` at `1.17.0`, `occtswiftais` at `1.3.1`), and SwiftPM's resolver kept the
  broken `1.3.1` pin because it still satisfied every *manifest-declared* range, even though its
  actual source doesn't compile against 3.0.0. Fixed in #120 by regenerating `Package.resolved`
  from an isolated `/tmp` copy with no local sibling checkouts nearby (forcing genuine remote
  resolution instead of this repo's usual path-dependency substitution), verified clean there via
  `swift package resolve` + `swift build --product occtkit`, then merged. `main`'s `tests`/
  `verbs`/`recipes` all green on the resulting HEAD.
* **Update**: Recorded the lesson in the 3.0.0 decision entry: "leave `Package.resolved`
  untouched while blocked" is correct only until the cohort actually catches up — refreshing it
  deliberately afterward (via a real, sibling-free resolution) is then a required follow-up step,
  not optional cleanup, since CI never gets a fresh-lockfile start on its own.

## 2026-08-19 (chore/118-occtswift-3.0.0)

* **Update**: Bumped the OCCTSwift floor to 3.0.0 (#118), a correctness/consolidation major (OCCT
  itself stays at 8.0.1). Two breaks: `Selector.SubShapeType.compsolid` -> `.compSolid` needed no
  source change (this repo already used the surviving `ShapeType.compSolid` spelling); six
  bounding-box accessors (`Shape.bounds`/`.size`/`.center`, `Wire.bounds`, `Edge.bounds`,
  `Face.bounds`) became `Optional` instead of fabricating `(0,0,0)-(0,0,0)` for a shape with no
  bounding box. Fixed every call site: `QueryTopology.swift`, `LoadBrep.swift`,
  `MeasureDeviation.swift`, `RenderPreview.swift`, and `Metrics.swift` now throw a named
  `ScriptError` on a `nil` bounding box; the two recipe edge-selector predicates
  (`01-mounting-bracket`, `03-pipe-flange`) return `false` on `nil` rather than fabricate a match.
  Added `Tests/OcctkitCommandTests/OptionalBoundsTests.swift`, constructing a genuinely void
  shape (two disjoint boxes' intersection) to regression-test the throw path directly.
  `swift build`/`swift test` (12/12) clean and all 7 recipe smoke tests match their reference
  `output.brep` exactly (`Δvol 0.00e+00`).
* **Creation**: Recorded the occtswift-3.0.0-floor-bump-blocked-on-cohort-releases decision: this
  repo's own bump is complete and verified, but OCCTSwiftTools/Mesh still cap `occtswift` below
  3.0.0 and OCCTSwiftAIS has 3 of its own unfixed `.bounds` sites, so even a local sibling build
  fails past that point (verified by a temporary, reverted local-only patch to AIS) — a stricter
  blocker than the 2.0.0 bump, which only blocked remote/CI resolution.

## 2026-08-10 (chore/bump-occtswift-2.0.0)

* **Update**: Bumped the OCCTSwift floor to 2.0.0 (#111), a correctness major with 17 breaking
  changes. Fixed two real breaks found by auditing every OCCTSwift call site against the full
  break table, not just the issue's own first-pass grep: `ShapeAnalysisResult.selfIntersectionCount`
  removed (#763) forced `Heal.swift`/`GraphValidate.swift` onto the real, opt-in
  `hasSelfIntersection`/`selfIntersecting: Bool?` check; AAG building nodes from face
  occurrences rather than distinct faces (#642) silently broke the `face[N]` alignment
  `FeatureRecognize.swift`, `GraphSelect.swift`, and `GraphML.swift` each document for their own
  AAG-derived output, fixed by resolving through the new `AAGNode.distinctFaceIndex` bridge.
  Added `Tests/OcctkitCommandTests/AAGFaceIndexTests.swift`, a real regression suite against a
  split-box-compound fixture, verified to fail if the fix is reverted.
* **Creation**: Recorded the occtswift-2.0.0-floor-bump-blocked-on-cohort-releases decision:
  this repo's own bump is complete, but a fresh clone cannot resolve the dependency graph from
  remote until OCCTSwiftIO (and likely Tools/AIS/Mesh) ship a 2.0.0-compatible release.

## 2026-08-05 (fix/105-bracket-fillet)

* **Update**: Fixed recipe 01's inside-corner fillet, which had never applied (#105).
  `prism.concaveEdges()` returns the wrong two edges on this shape (top-cap boundary
  segments bounded by the 5 mm leg thickness), not the one true reentrant edge (bounded
  only by `legLength - thickness`, 45 mm). `filletRadius = 8` was infeasible for the wrong
  edges and a `?? prism` fallback hid the resulting `nil`. Now selects the true edge
  geometrically with `Shape.edges(where:)`; the same `filletRadius = 8` now applies,
  adding 549.38 mm3 (matches the analytic `r² · (1 - pi/4) · width` prediction exactly).
  Also fixed `recipes/06-fan-blade`'s `blade.union(hub) ?? blade`, the same pattern found
  dormant during the `??`-fallback audit #105 requested (the union has never actually
  failed; behaviour is unchanged).
* **Creation**: Recorded the concave-edge-classifier-can-select-wrong-edges decision.

## 2026-08-05

* **Update**: Fixed two cookbook recipes that emitted shells while documenting themselves as
  solids (#100). `03-pipe-flange` revolved a wire, `02-helical-spring` swept one. The flange's
  shell was also silently under-cutting its bolt circle: it removed only one third of the
  material it should have, so two thirds of each bolt hole was left unfinished. Hardened `Scripts/recipe-check.sh` to assert `solidCount`, and fixed a bug there that
  made every check it performed decorative.
* **Creation**: Recorded the wire-sweep-factories-are-not-symmetric decision.
* **Creation**: Recorded the errexit-is-suppressed-in-or-context decision.
* **Update**: Fixed recipe 03's chamfer, which had never applied (#103). `chamfered(distance:)`
  bundles all edges into one operation and a full revolve always contributes unblendable seam
  edges, so the call returned nil and a `??` fallback hid it. Now selects the OD and raised-face
  rim explicitly.
* **Creation**: Recorded the revolve-seams-cannot-be-chamfered decision.
* **Update**: Recorded that OCCTSwift#695, the concaveEdges/convexEdges reentrant-edge
  misclassification, will not be backported to 1.x. A backport was built and merged upstream
  (PR #700, tests green) then reverted for what it costs the 2.0.0 release branch. The geometric
  edge selection in recipe 01 is therefore permanent while this repo is on the 1.x line, not a
  stopgap awaiting a patch release.

## 2026-08-04

* **Update**: Deduplication pass for issue #82. Moved `readFile`, `decodeJSON`, `valueAfter`,
  `value`, `parseVec3` and `vec3` into `GraphIO`, removing 44 copied helper definitions across
  `Sources/occtkit/Commands/`. Single-sourced the verb inventory from `Registry.all` via a new
  `occtkit --verbs` flag, fixing a `make install` bug that silently omitted `graph-select`.
  The verb list appeared in ten places and five had gone stale; corrected them.
* **Creation**: Recorded the single-source-verb-inventory decision.
* **Update**: Fixed `occtkit run` failing in any checkout not named `OCCTSwiftScripts`
  (#98). The generated workspace manifest hardcoded the package identity, but SwiftPM derives a
  path dependency's identity from the directory basename. Added `Scripts/run-identity-check.sh`
  and wired it into the `verbs` workflow.
* **Creation**: Recorded the swiftpm-path-dependency-identity decision.
* **Update**: Consolidated the two knowledge bundles into one. `okf/` is now the single
  knowledge store. Migrated the open-source-boundary policy, the OCCTStudio commercial-app
  relationship, and the OKF format reference out of the older `docs/knowledge/` bundle, then
  removed it. Updated the OCCTStudio link to `SecondMouseAU/OCCTStudio` after the org migration.
* **Update**: `CLAUDE.md` now points at `okf/index.md` and lists the mandatory policies inline.
  It previously referenced only `docs/knowledge/`, so the four mandatory policies were not
  reachable from the always-loaded quick reference.

## 2026-07-26

* **Creation**: Recorded the search-before-building policy.

## 2026-07-24

* **Creation**: Recorded the writing-style policy (no em-dashes, banned hedge and sycophancy
  words).

## 2026-06-27

* **Creation**: Recorded the context-first documentation-lookup policy and the docs-current
  policy.

## 2026-06-22

* **Creation**: Added the OKF knowledge catalog (`ecosystem.yml` plus `okf/`).

## 2026-06-18

* **Creation**: Initialised the first knowledge bundle (at `docs/knowledge/`, since superseded
  by `okf/`).
* **Creation**: Recorded the open-source-boundary policy and the relationship to the downstream
  commercial app (OCCTStudio), which consumes the `reconstruct` feature-graph IR.
