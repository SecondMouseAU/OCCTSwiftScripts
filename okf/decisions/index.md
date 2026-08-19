# Decisions

Recorded engineering decisions and their rationale. Add an entry here when a choice needs its
reasoning preserved beyond the commit message, so the next person does not re-litigate it.

Decisions to date are captured in `CLAUDE.md` and the git log; this directory holds the ones
that need standalone rationale.

* [Single-source verb inventory](single-source-verb-inventory.md): `Registry.all` is the only
  verb list; `occtkit --verbs` feeds the Makefile and the docs point at the reference page.
* [SwiftPM path dependency identity](swiftpm-path-dependency-identity.md): a path dep's
  identity is the directory basename, so generated manifests derive declaration and identity from
  one value.
* [Wire sweep factories are not symmetric](wire-sweep-factories-are-not-symmetric.md): `extrude`
  faces a wire for you, `revolve` and `sweep` do not. Assert `solidCount >= 1`.
* [errexit is suppressed in `||` context](errexit-is-suppressed-in-or-context.md): a function
  called as `f || status=1` must `return 1` explicitly or its checks are decorative.
* [Revolve seams cannot be chamfered](revolve-seams-cannot-be-chamfered.md): the all-edge
  `chamfered(distance:)` always fails on a full revolve; select edges explicitly.
* [Concave edge classifier can select wrong edges](concave-edge-classifier-can-select-wrong-edges.md):
  `concaveEdges()` returned two unrelated edges instead of an L-bracket's one true reentrant
  edge; verify a classifier's output geometrically before trusting it.
* [OCCTSwift 2.0.0 floor bump blocked on cohort releases](occtswift-2.0.0-floor-bump-blocked-on-cohort-releases.md):
  `Package.swift` floors OCCTSwift at 2.0.0 and this repo's own code is fixed, but
  OCCTSwiftIO's latest release still caps `occtswift` below 2.0.0 transitively, so a fresh
  clone cannot resolve until the cohort ships. The PR is not blocked; the release is.
  Resolved 2026-08-10.
* [OCCTSwift 3.0.0 floor bump blocked on cohort releases, then on a stale Package.resolved](occtswift-3.0.0-floor-bump-blocked-on-cohort-releases.md):
  same shape of cohort blocker as 2.0.0, plus a second-order trap once the cohort caught up — a
  pre-2.0.0-era `Package.resolved` let SwiftPM's resolver keep a manifest-compatible but
  source-broken `occtswiftais` pin. Released as v1.6.2, `main` fixed green in a follow-up PR.
