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
* [Bevel gear explicit reference frames](bevel-gear-explicit-reference-frames.md): BOSL2's
  `anchor="pitchbase"|"flattop"|"apex"` string is replaced by three plain `Double` heights plus
  a `meshPair` helper; ground truth checked against literal numbers, not re-derived.
* [BOSL2 examples copy the gear core](bosl2-examples-copy-the-gear-core.md): `occtkit run`
  compiles one file with one dependency, so the three docs examples each carry an identical
  617-line core; `Scripts/gear-core-check.sh` is what stops the copies drifting.
* [`right_handed` inverts against BOSL2](bevel-gear-handedness-inverts-against-bosl2.md): BOSL2
  mirrors on the FALSE branch because its transform stack already carries an `xflip`; volume and
  bounding box are blind to getting this backwards, surface deviation is not.
* [A tooth-space cutter's inner radius is the root surface](tooth-space-cutter-defines-the-root-surface.md):
  the Route C blank has no root cone, so cutting-clearance over-travel below the root radius just
  makes every valley deeper; it cost 1.05% of a 36-tooth gear's volume.
