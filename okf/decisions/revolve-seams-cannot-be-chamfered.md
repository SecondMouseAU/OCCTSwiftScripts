---
type: decision
title: A full revolve cannot be chamfered or filleted with the all-edge convenience call
description: Every periodic face a full revolve creates contributes a seam edge, and BRepFilletAPI cannot blend a seam because both adjacent faces are the same face. Select edges explicitly instead.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/103
tags: [decision, occtswift, chamfer, fillet, revolve, topology]
timestamp: 2026-08-05
---

# Decision

Do not call `Shape.chamfered(distance:)` or the equivalent all-edge fillet on the result of a
full 360 degree revolve. It will return nil. Select the edges you actually want and use
`Shape.chamferedWithFullHistory(distance:edges:)` or `filleted(edges:radius:)`.

# Why

A full revolve produces **periodic** faces, and every periodic face carries a **seam edge** where
the surface closes on itself. `BRepFilletAPI_MakeChamfer` cannot blend a seam: a chamfer or fillet
is defined between two adjacent faces, and at a seam both "adjacent" faces are the same face.

The all-edge convenience call bundles every edge into a single operation, so one unblendable seam
fails the entire call. It returns nil rather than skipping the edge.

Measured on the pipe flange in
[#103](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/103): 11 of 33 edges were seams,
one per periodic face (bore, OD, raised-face wall, and each of the eight bolt holes). Isolating
every edge and chamfering it alone showed each circular edge succeeds by itself, while all 11
seams fail alone at every distance tried, from 1 mm down to 0.001 mm. It is structural, not a
size problem.

# How to select instead

Prefer a predicate that states the real geometric condition. For circles concentric with the
revolve axis, `centerOfCurvature(at:)` pins the centre to the axis and `1 / curvature(at:)` gives
the true radius:

```swift
func axisCircleRadius(_ edge: Edge) -> Double? {
    guard edge.isCircle, let b = edge.parameterBounds else { return nil }
    let mid = (b.first + b.last) / 2
    guard let c = edge.centerOfCurvature(at: mid),
          let k = edge.curvature(at: mid), k > 1e-9,
          abs(c.x) < 1e-6, abs(c.z) < 1e-6 else { return nil }   // axis is Y here
    return 1 / k
}
```

Sampling a single point and taking its distance from the axis answers the weaker question "does
some point on this edge lie at radius R", which is not the same test.

**Caveat on using `isCircle` to exclude seams.** The seam edges of a revolve are the profile edges
themselves. With a polygonal half-section they are lines, so `isCircle` happens to exclude them.
Put an arc or a fillet in the profile and the seam becomes circular, and that exclusion silently
stops working. `Edge.isSeam(on:)` is the direct test when a profile is not purely polygonal.

# Related

Reentrant edges are a second trap in the same area: chamfering one **adds** material rather than
breaking a corner. On the flange, chamfering the raised-face step base alone increased volume by
about 158 mm3. Note also that `convexEdges()` and `concaveEdges()` classified that shape in a way
that disagreed with what chamfering the edges actually did, so geometric selection was preferred
over the classifier there.
