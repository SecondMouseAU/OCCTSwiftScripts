# Knowledge Log

## 2026-08-05

* **Update**: Fixed two cookbook recipes that emitted shells while documenting themselves as
  solids (#100). `03-pipe-flange` revolved a wire, `02-helical-spring` swept one. The flange's
  shell was also silently under-cutting its bolt circle, removing one third of the correct
  material. Hardened `Scripts/recipe-check.sh` to assert `solidCount`, and fixed a bug there that
  made every check it performed decorative.
* **Creation**: Recorded the wire-sweep-factories-are-not-symmetric decision.
* **Creation**: Recorded the errexit-is-suppressed-in-or-context decision.

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
