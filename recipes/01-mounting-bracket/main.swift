// Recipe 01: Mounting bracket
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body: an L-bracket with a filleted inside corner and four
//          through-holes (two per leg).
// Notes:   The reentrant corner at (thickness, thickness) extrudes to exactly one
//          concave edge, a straight line parallel to the extrusion axis. That is the
//          edge this recipe fillets. It is NOT the edge `Shape.concaveEdges()` finds:
//          on this shape that call returns two different edges instead, the top-cap
//          boundary segments at z = width where each wall meets the end face, each
//          running the leg length rather than the extrusion width (OCCTSwiftScripts
//          #105). Those two are bounded by the 5 mm leg thickness and a fillet there
//          fails above roughly that radius, which is why `filletRadius = 8` used to
//          silently no-op behind a `?? prism` fallback. The true inside-corner edge has
//          no such limit (its bound is legLength − thickness, 45 mm here), so this
//          recipe selects it explicitly with `Shape.edges(where:)`: a line parallel to
//          the extrusion axis positioned at (thickness, thickness), the same
//          geometric-selection approach recipe 03 uses for the pipe flange (#103).
//          Fillet before drilling so the selector only ever sees the corner edge, not a
//          drilled hole's rim. Holes are drilled through the leg thickness with a small
//          overshoot so the cut faces stay clean.
//
// Run:  swift run occtkit run recipes/01-mounting-bracket/main.swift --format brep

import OCCTSwift
import ScriptHarness

// ── Parameters ──────────────────────────────────────────────────────────────
let legLength: Double  = 50    // length of each leg, measured from the heel (mm)
let thickness: Double  = 5     // material thickness of each leg (mm)
let width: Double      = 40    // bracket width (extrusion depth, mm)
let filletRadius: Double = 8   // inside-corner radius (mm); fits comfortably under the
                                // legLength − thickness = 45 mm geometric limit (see below)
let holeRadius: Double  = 3.5  // mounting-hole radius (mm)

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Mounting bracket",
    source: "OCCTSwiftScripts recipe 01",
    tags: ["bracket", "L-bracket", "fillet", "holes"]
))
let C = ScriptContext.Colors.self

// ── L-shaped cross-section (XY plane), reentrant corner at (thickness, thickness)
let lProfile = Wire.polygon([
    SIMD2(0, 0), SIMD2(legLength, 0), SIMD2(legLength, thickness),
    SIMD2(thickness, thickness),          // ← inside corner
    SIMD2(thickness, legLength), SIMD2(0, legLength),
])!

// ── Extrude to a solid prism, then round the concave (inside-corner) edge ─────
let prism = Shape.extrude(profile: lProfile, direction: SIMD3(0, 0, 1), length: width)!

// The inside corner is the one straight edge parallel to the extrusion axis (Z) that
// sits at (thickness, thickness): select it geometrically rather than trusting
// concaveEdges(), which picks the wrong edges on this shape (see the header note).
// That classifier defect is OCCTSwift 1.x only: it is fixed in the 2.0.0 line
// (verified on v2.0.0-kernel.1, upstream OCCTSwift#695). This geometric selection is
// therefore a 1.x workaround, and this recipe could return to concaveEdges() once the
// package moves to 2.0.0. Re-run the check in the OKF entry before doing so.
let insideCornerEdges = prism.edges { edge in
    guard edge.isLine else { return false }
    let b = edge.bounds
    let runsFullWidth = abs((b.max.z - b.min.z) - width) < 1e-6
        && abs(b.max.x - b.min.x) < 1e-6 && abs(b.max.y - b.min.y) < 1e-6
    guard runsFullWidth else { return false }
    return abs(b.min.x - thickness) < 1e-6 && abs(b.min.y - thickness) < 1e-6
}
// Guard the selector separately from the fillet. `filleted(edges: [], radius:)` does
// return nil today (checked on both 1.17.0 and 2.0.0-kernel.1), so the force-unwrap
// below would catch an empty match, but only as an anonymous nil-unwrap crash. This
// names the actual fault, and avoids depending on undocumented nil-on-empty behaviour
// if a parameter change or an upstream tweak ever silently breaks the predicate.
precondition(!insideCornerEdges.isEmpty, "inside-corner edge selector matched nothing")
var bracket = prism.filleted(edges: insideCornerEdges, radius: filletRadius)!

// ── Four through-holes: two in the base leg (drill along Y), two in the upright
//    leg (drill along X). Start just outside the entry face and over-run the exit.
let base1 = SIMD3(legLength * 0.55, -1.0, width * 0.30)
let base2 = SIMD3(legLength * 0.55, -1.0, width * 0.70)
let up1   = SIMD3(-1.0, legLength * 0.55, width * 0.30)
let up2   = SIMD3(-1.0, legLength * 0.55, width * 0.70)

bracket = bracket.drilled(at: base1, direction: SIMD3(0, 1, 0), radius: holeRadius, depth: thickness + 2)!
bracket = bracket.drilled(at: base2, direction: SIMD3(0, 1, 0), radius: holeRadius, depth: thickness + 2)!
bracket = bracket.drilled(at: up1,   direction: SIMD3(1, 0, 0), radius: holeRadius, depth: thickness + 2)!
bracket = bracket.drilled(at: up2,   direction: SIMD3(1, 0, 0), radius: holeRadius, depth: thickness + 2)!

try ctx.add(bracket, color: C.steel, name: "Mounting bracket")

print("Bracket volume: \(bracket.volume ?? 0) mm³")
try ctx.emit(description: "L-bracket, \(legLength)mm legs, \(width)mm wide, 4× Ø\(holeRadius * 2) holes")
