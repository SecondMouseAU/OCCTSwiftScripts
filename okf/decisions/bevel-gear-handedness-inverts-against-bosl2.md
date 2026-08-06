---
type: decision
title: right_handed inverts between BOSL2 and this bevel gear port
description: BOSL2 mirrors on right_handed == false because its per-slice transform stack already carries an xflip; a port that reuses that stack must put the extra mirror on the false branch, and only a surface-deviation check can catch getting it backwards.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/89
tags: [decision, occtswift, gears, bevel, handedness, verification]
timestamp: 2026-08-06
---

# The finding

`gears.scad:2640` reads:

```openscad
lvnf = right_handed? vnf1 : xflip(p=vnf1),
```

`vnf1` is built through a per-slice transform stack that already begins with `xflip()`
(gears.scad:2562), so `vnf1` is the RIGHT-handed form and BOSL2 reaches its left-handed default by
mirroring a second time. Any port that reuses that transform stack, as this one does in
`slicePoint`, inherits the single `xflip` and must therefore apply its extra mirror when
`right_handed == false`:

```swift
if !p.rightHanded {
    guard let mirrored = shape.mirrored(planeNormal: SIMD3(1, 0, 0)) else { ... }
    shape = mirrored
}
```

Reading the ternary at face value and mirroring on `true` produces gears of the wrong hand
throughout, which is what the #87 spike lineage did.

# Why this needs a specific kind of check

A mirrored gear has **exactly** the same volume, exactly the same bounding box, the same face and
edge counts, and the same `isValid`. Every cheap check passes. A visual comparison catches it only
if the reader knows which way the spiral should run.

What does catch it is a surface-deviation measurement against the reference geometry:
`docs/guides/bosl2-bevel-gears/compare.py` measures the distance from every vertex of one mesh to
the nearest point on the other mesh's surface, after scanning out the one legitimate degree of
freedom (which tooth sits at angle zero). Measured on #89's Example 2:

| | mean deviation to BOSL2 |
|---|---|
| as built | 0.032 mm (16t), 0.051 mm (28t) |
| both bodies mirrored in X | 0.370 mm, 0.367 mm |

and the rotation scan is flat for the mirrored pair (0.351 to 0.395 mm across a whole tooth
pitch), because no rotation about the axis can undo a mirror. That is the negative control: the
check was shown to fail before it was believed.

# Related

The tooth PHASE also differs by convention: this port centres a tooth space where BOSL2 centres a
tooth, so a single gear compared as built is half a tooth pitch out of phase (measured at 0.504,
0.507, 0.497, 0.507 and 0.494 of a pitch across the five gears on the page). It cancels in a
meshed pair, since both members carry the same offset, which is why BOSL2's own `spin=180/t2`
idiom still interleaves the teeth here.
