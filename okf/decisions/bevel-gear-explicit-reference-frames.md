---
type: decision
title: Bevel gear placement uses explicit reference-frame heights, not BOSL2 anchors
description: pitchbase/flattop/apex ported from BOSL2's named_anchor system as plain Double heights exposed alongside the Shape and in the manifest; callers position with ordinary translated/rotated instead of an anchor string.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/88
tags: [decision, occtswift, gears, bevel, placement, anchors]
timestamp: 2026-08-06
---

# Decision

BOSL2's `bevel_gear()` positions a gear via `anchor="pitchbase"|"flattop"|"apex"`, one string
argument that selects among three named points BOSL2's `attachable()`/`named_anchor()`
infrastructure computes internally and hides. OCCTSwift has no equivalent attachment system
(noted as explicitly out of scope in [#84](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/84)).
The replacement is not a ported anchor system: it is three plain `Double` heights, computed
alongside the `Shape` and returned to the caller, who positions with ordinary
`Shape.translated(by:)` / `.rotated(axis:angle:)`.

```swift
struct GearReferenceFrames { let pitchbase: Double; let flattop: Double; let apex: Double }
func referenceFrames(_ g: GearGeometry) -> GearReferenceFrames
```

A second helper, `meshPair(reference:mate:shaftAngle:tiltAxis:matePhaseDeg:)`, is the direct
replacement for BOSL2's `anchor="apex"` idiom for a meshed pair: given two gears' reference
frames and a shaft angle, it returns the `GearMeshStep` (translation + optional phase rotation
+ tilt rotation) for each member that places both pitch-cone apexes at a common point with axes
separated by the shaft angle.

# Why plain heights, not a ported anchor system

A ported `anchor` string would need to reproduce BOSL2's `attachable()`/`reorient()` machinery
(thousands of lines, already ruled out of scope in #84) just to resolve one of three fixed
points. Exposing the three heights directly is strictly less code, is fully transparent (a
caller can read `frames.apex` and see the number), and composes with OCCTSwift's own
transform vocabulary instead of introducing a parallel one.

# What "reference frame" means here, precisely

Heights are along the gear's own build axis (+Z), in the SAME coordinate frame the shape was
actually built in:

- **pitchbase**: the pitch line's height at the back (wide, cone-distance = ocone_rad) edge.
  Equals `pitchoff` exactly (verified as a regression check against the meridian machinery that
  places the blank's own vertices).
- **flattop**: the flat annulus at the front (narrow, near-apex) edge, the same point
  `buildFullBlank`'s `innerRoot` computes for the axial front face.
- **apex**: `pitchbase + oconeRad * cos(pitchAngle)` (or `iconeRad * cos(pitchAngle)` for
  `pitchAngle >= 90`, per BOSL2's own ternary; unexercised in this repo's matrix, which stays
  under 90 degrees). This reduces from BOSL2's `hyp_ang_to_opp(ocone_rad, 90-pitch_angle)`.

This deviates from BOSL2's literal formula in one respect: BOSL2 folds `ctr_thickness` (a
vertex-array bookkeeping artifact, not an independently derivable quantity) and `backing` into
all three anchors, because it recenters the whole body (teeth + backing) around their combined
midpoint before exposing anchors. This repo does not recenter, so `backing` does not shift
these heights: meshing is a property of the teeth's pitch cone, not of how thick an optional
mounting boss is. The deviation is invisible to the one quantity that actually gets checked,
apex height above pitchbase, since BOSL2's own `ctr_thickness`/`backing` terms appear
identically in its pitchbase and apex formulas and cancel exactly in the subtraction.

# The ground-truth check, and why it is checked this way

At a 90 degree shaft angle, a gear's apex height above its pitchbase equals its **mate's**
pitch radius, exactly:

| gear | pr | pitch angle | apex height | mate pr |
|---|---|---|---|---|
| z=36, mate=36 | 36.0 | 45.00 deg | 36.000 | 36.0 |
| z=16, mate=28 | 16.0 | 29.74 deg | 28.000 | 28.0 |
| z=28, mate=16 | 28.0 | 60.26 deg | 16.000 | 16.0 |
| z=14, mate=28 | 14.0 | 26.57 deg | 28.000 | 28.0 |
| z=28, mate=14 | 28.0 | 63.43 deg | 14.000 | 14.0 |

This is checked against the literal numbers above, not re-derived from this repo's own code,
because comparing a helper's output only to itself (or to a second computation sharing the same
formula) cannot fail on a shared sign or factor error. `spikes/88-placement.swift` asserts all
five rows to 1e-9.

The `meshPair` helper's own "do the two positioned apexes land at the same world point" check is
weaker than it looks: `meshPair` translates both gears by the negative of their own computed
apex height, so agreement is true by construction regardless of whether that height is correct.
It is included (per #88's acceptance criteria) because it does exercise real, independently
useful code, the translate/phase-rotate/tilt-rotate composition and rotation axes, but the table
above is the check that can actually fail on a wrong formula. Away from 90 degrees this repo has
no independently-sourced ground-truth number, only a structural necessary condition (the two
pitch angles must sum to the shaft angle) and the same weaker world-space check; this is recorded
as a real limitation, not papered over.

# Rotational phase for tooth interleaving

Meshing two gears by position alone is not sufficient; BOSL2's own Example 2
(`bevel_gear(..., spin=180/t2)`) applies a rotational phase to the mating member so the teeth
interleave rather than collide. `meshPair`'s `matePhaseDeg` parameter threads this through in
BOSL2's own `anchor -> spin -> orient` order (spin about the gear's own, still axis-aligned, Z
axis, applied BEFORE the shaft-angle tilt); the caller supplies the value, since the correct
phase depends on the two tooth cutters' flank/handedness convention, not on geometry this helper
can derive from the shaft angle alone.

# Consequences

`ScriptHarness.BodyDescriptor` gained an optional `referenceFrames: [String: Double]?` field
(and `ScriptContext.add(_:Shape...)` a matching parameter), surfaced into `manifest.json` for
`render-preview` and other downstream consumers. Deliberately generic (a named-height dictionary,
not a gear-specific type): this is a manifest-schema concept, usable by any future part family
that wants to expose named axis heights, while the strongly-typed `GearReferenceFrames` struct
stays in gear-domain code.
