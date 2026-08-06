---
type: decision
title: A tooth-space cutter's inner radius IS the finished root surface
description: The Route C bevel gear blank has no root cone of its own, so extending the tooth-space cutter below the root radius for cutting clearance digs every valley that much deeper; on a 36-tooth gear the habitual mod/4 of over-travel cost 1.05% of the volume.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/89
tags: [decision, occtswift, gears, bevel, booleans, verification]
timestamp: 2026-08-06
---

# The finding

Route C builds a bevel gear by revolving a blank and subtracting one tooth-space cutter N times.
The blank's meridian runs axis, root point, tip point, tip point, root point, axis, so its outer
surface is the **addendum** cone and its ends are the two cone-distance planes. There is no root
cone anywhere in the blank. Whatever radius the cutter bottoms out at therefore becomes the
finished valley floor.

The #109 / #110 / #87 spikes set `rootExtRadius = rootR - radialClearance`, on the usual instinct
that a cutting tool should over-travel past the surface it is clearing. Here that has no surface
to clear: it simply cuts every valley `mod/4` deeper than nominal.

# The measurement

Against the BOSL2 reference mesh for the 36-tooth gear of
[#89](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/89) Example 1:

| `rootExtRadius` | volume | delta vs BOSL2 |
|---|---|---|
| `rootR - clearance` | 19069.53 mm3 | -1.563% |
| `rootR` | 19272.12 mm3 | -0.517% |

The remaining 0.5% is accounted for elsewhere (BOSL2's root fillet, its straight tangent root land
sitting about 0.048 mm below the root circle, and its 12-sided bore).

# The robustness concern, and how it turned out

Bottoming out exactly at the root radius puts the cutter's inner corner on the blank's back-face
outer edge circle, which is the kind of coincident geometry that makes OCCT booleans fragile.
Tested rather than assumed: all five gears across the three examples still reach
`solidCount == 1` and `isValid == true` straight out of `circularPatternCut`, with no `heal()`.

Over-travel past the ADDENDUM cone (`tipExtRadius = addR + clearance`) is a different matter and
is kept: there the blank does have a surface to clear, and the extra travel removes nothing extra.

# The general rule

Before adding cutting clearance to a boolean tool, check whether the operand actually has a
surface at that boundary. If it does not, the clearance is not clearance, it is a change to the
part.
