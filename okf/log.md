# Knowledge Log

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
