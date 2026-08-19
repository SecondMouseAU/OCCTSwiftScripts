---
type: decision
title: Shape.concaveEdges() can return the wrong edges entirely, not just a threshold quirk
description: On OCCTSwift 1.x, concaveEdges() on an extruded L-profile returns two top-cap boundary edges rather than the one true reentrant edge, and classifies that edge convex. Fixed in the 2.0.0 line. Select fillet/chamfer edges geometrically while on 1.x.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/105
tags: [decision, occtswift, fillet, topology, recipes, edge-selection]
timestamp: 2026-08-05
---

# Decision

On the OCCTSwift 1.x line, do not trust `Shape.concaveEdges()` / `Shape.convexEdges()` to
find the edge you mean to fillet or chamfer, even when you can name the one edge you expect
geometrically. Verify by
inspecting the returned edges' actual positions, and prefer `Shape.edges(where:)` with an
explicit geometric predicate once you know what you are looking for.

# Version scope: 1.x only, fixed in 2.0.0

This is an **OCCTSwift 1.x defect**. It is already fixed in the 2.0.0 line, verified against the
published `v2.0.0-kernel.1` prerelease with the same repro:

```
1.17.0          L-prism concave=2 (expected 1)   insideCorner inConcave=false   MISMATCH
2.0.0-kernel.1  L-prism concave=1 (expected 1)   insideCorner inConcave=true    OK
```

A T-prism with two reentrant edges reports 3 on 1.17.0 and 2 on 2.0.0-kernel.1. A box, having no
reentrant edges, is correct on both.

**No 1.x fix will land**, but not because a backport was infeasible. Upstream built, merged and
measured one (OCCTSwift PR #700, all 4646 tests green on both CI jobs) and then **reverted it**,
for what it costs the release branch rather than for any defect in it: merging main into
`refactor/381-pass1b`, which carries the whole of v2.0.0, conflicted in 8 files across 18 regions,
and those are not all mechanical. Main and the refactor branch made genuinely different, individually
correct decisions on the same lines, because the sub-shape indexing work landed only on the refactor
branch.

The backport is not lost: re-landing means reverting the revert, so if 1.x becomes untenable before
v2.0.0 ships this can be revisited. Tracked at
[OCCTSwift#695](https://github.com/SecondMouseAU/OCCTSwift/issues/695).

**Root cause, worth knowing because it generalises.** An edge or vertex index crossing the bridge
addressed a topology *occurrence* rather than a position in the deduplicated enumeration that
`edges()` / `edgeCount` / `edge(at:)` return. A 20 mm box has 12 distinct edges but 24 edge
occurrences, so the two enumerations diverge from the first repeat onwards on any ordinary solid,
and `edgeConcavities()` zips one against the other. Upstream root-cause issue is OCCTSwift#613; the
fix is #650. Treat any bridge-crossing index with the same suspicion until 2.0.0.

Neither route to the fix is open to this package. It is reachable both from the refactor branch
and from the published `v2.0.0-kernel.1` prerelease tag, but this package is released under a semver
floor of `from: "1.17.0"`, meaning `>=1.17.0 <2.0.0`, so it cannot resolve a 2.x version at all
without a major bump, and a revision pin would propagate an unstable dependency to every downstream
consumer. This repo has carried a revision pin before (OCCTSwiftViewport, before `OffscreenRenderer`
had a release tag) and the note in `CLAUDE.md` records why it was replaced with a version pin.

**So the geometric selection below is permanent for as long as this repo is on the 1.x line.** Do
not wait for a patch release; there will not be one. The workaround becomes removable only at a
2.0.0 migration, at which point `concaveEdges()` is usable for this case again and recipe 01 could
return to it as a legitimate simplification. Re-run the repro above at that point rather than
assuming the migration carried the fix.

# Why

Recipe 01's L-bracket profile has exactly one reentrant vertex, at `(thickness, thickness)`.
Extruded along Z, that vertex produces exactly one concave edge: a line parallel to the
extrusion axis, running its full length.

`prism.concaveEdges()` does not return that edge. It returns two different edges instead,
each length `legLength - thickness` (45 mm on the recipe's own parameters), lying in the
*end cap* plane (`z = width`) rather than running the extrusion axis:

```
edge[7]  (the true reentrant edge)   isLine, len=40 (=width), bounds x:[5,5] y:[5,5] z:[0,40]  -> classified CONVEX
edge[9]  (concaveEdges() result #1)  isLine, len=45,           bounds x:[5,50] y:[5,5] z:[40,40] -> classified CONCAVE
edge[12] (concaveEdges() result #2)  isLine, len=45,           bounds x:[5,5] y:[5,50] z:[40,40] -> classified CONCAVE
```

`edge[7]` is exactly where the reentrant vertex's profile predicts a concave edge should be.
It is classified **convex**. The two edges classified concave are boundary segments of the
top cap, at the far end of the part from where the reentrant corner's own edge runs.

This is not a rounding or threshold problem (`concaveEdges(angle:)`'s default tolerance is
irrelevant here): the classifier is naming structurally different edges than the geometric
feature it is supposed to describe.

## Consequence: the wrong edges have the wrong feasible radius

The two edges `concaveEdges()` returns are bounded by the 5 mm leg thickness (they sit on
the boundary between the end cap and a wall that is only 5 mm across), so filleting them
fails above roughly that radius. The true edge (`edge[7]`) is bounded only by
`legLength - thickness` (45 mm here), since it runs along the full unconstrained length of
each wall. A radius that is completely reasonable for the real feature (8 mm, comfortably
under 45 mm) reads as infeasible when applied to the wrong edges (over the 5 mm limit), and
`prism.filleted(edges:radius:)` returns `nil`. That nil, hidden behind a `?? prism`
fallback, is what recipe 01 shipped for as long as it trusted `concaveEdges()`
([OCCTSwiftScripts#105](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/105)).

## A concave fillet adds material; verify the sign, not just a nonzero delta

Filleting the true reentrant edge **increases** the bracket's volume: it fills part of the
sharp inside corner with a rounded blend. `prism.filleted(edges: [edge7], radius: r).volume`
is `prism.volume + r² · (1 - π/4) · length`, not minus. Filleting the two edges
`concaveEdges()` actually returns *removes* material instead, because those two are
ordinary 90-degree corners from the fillet's point of view (the same
`r² · (1 - π/4) · length` formula, sign flipped): measured 176.42 mm3 removed at r=3 mm
across both wrong edges (2 × 45 mm), against 77.26 mm3 that a single correct fillet at r=3
mm over the 40 mm extrusion length would add. A volume check that only asserts "some
material moved" would have passed on the wrong edges; the sign and the magnitude both have
to match the specific edge you intended.

# How to select instead

Once you know the geometric feature you want (here: a line parallel to the extrusion axis,
positioned at the profile's reentrant vertex), select it directly rather than filtering a
classifier's output:

```swift
let insideCorner = prism.edges { edge in
    guard edge.isLine, let b = edge.bounds else { return false }
    let runsFullWidth = abs((b.max.z - b.min.z) - width) < 1e-6
        && abs(b.max.x - b.min.x) < 1e-6 && abs(b.max.y - b.min.y) < 1e-6
    guard runsFullWidth else { return false }
    return abs(b.min.x - thickness) < 1e-6 && abs(b.min.y - thickness) < 1e-6
}
```

(`edge.bounds` became `Optional` at OCCTSwift 3.0.0, unrelated to this entry's own finding; the
`let b = edge.bounds` unwrap above was added then, see
[OCCTSwift 3.0.0 floor bump](occtswift-3.0.0-floor-bump-blocked-on-cohort-releases.md).)

# Related

[Revolve seams cannot be chamfered](revolve-seams-cannot-be-chamfered.md) already noted, on
the pipe flange (#103/#104), that `convexEdges()` / `concaveEdges()` disagreed with what
chamfering the edges actually did volumetrically. This is the same finding on a second,
unrelated shape, which is why it is worth its own entry rather than a footnote: two
independent recipes have now hit a classifier/reality mismatch on `concaveEdges()` and
`convexEdges()`. Treat both as a hint, to be checked against the shape's actual geometry and
the operation's actual volumetric effect, not as ground truth.

This is also the third instance of a broader pattern tracked across #100, #103, and #105: an
optional-returning geometry operation degrades silently via a `?? fallback`, the emitted
output stays volumetrically plausible, and the docs keep describing the intended behaviour.
A fourth, dormant instance (`recipes/06-fan-blade`'s `blade.union(hub) ?? blade`, which has
never actually failed) was fixed alongside #105 once the audit turned it up. Any new
`Shape`-returning call in a recipe that can return `nil` should fail loudly (force-unwrap or
an explicit `guard ... else { fatalError(...) }`), never degrade through `??`.
