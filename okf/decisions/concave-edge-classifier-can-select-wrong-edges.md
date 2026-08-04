---
type: decision
title: Shape.concaveEdges() can return the wrong edges entirely, not just a threshold quirk
description: On an extruded L-profile, concaveEdges() returns two top-cap boundary edges bounded by the leg thickness, not the one true reentrant edge that runs the extrusion length. Select fillet/chamfer edges geometrically instead of trusting the classifier.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/105
tags: [decision, occtswift, fillet, topology, recipes, edge-selection]
timestamp: 2026-08-05
---

# Decision

Do not trust `Shape.concaveEdges()` / `Shape.convexEdges()` to find the edge you mean to
fillet or chamfer, even when you can name the one edge you expect geometrically. Verify by
inspecting the returned edges' actual positions, and prefer `Shape.edges(where:)` with an
explicit geometric predicate once you know what you are looking for.

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
    guard edge.isLine else { return false }
    let b = edge.bounds
    let runsFullWidth = abs((b.max.z - b.min.z) - width) < 1e-6
        && abs(b.max.x - b.min.x) < 1e-6 && abs(b.max.y - b.min.y) < 1e-6
    guard runsFullWidth else { return false }
    return abs(b.min.x - thickness) < 1e-6 && abs(b.min.y - thickness) < 1e-6
}
```

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
