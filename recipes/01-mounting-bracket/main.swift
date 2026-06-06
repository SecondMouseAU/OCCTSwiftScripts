// Recipe 01 — Mounting bracket
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — an L-bracket with a filleted inside corner and four
//          through-holes (two per leg).
// Notes:   The inside corner is rounded by filleting the solid's concave edge, found
//          geometrically with Shape.concaveEdges() (OCCTSwift v1.3.1, #171) rather than
//          by a fragile edge index. Fillet before drilling so concaveEdges() returns only
//          the reentrant corner. Holes are drilled through the leg thickness with a small
//          overshoot so the cut faces stay clean.
//
// Run:  swift run occtkit run recipes/01-mounting-bracket/main.swift --format brep

import OCCTSwift
import ScriptHarness

// ── Parameters ──────────────────────────────────────────────────────────────
let legLength: Double  = 50    // length of each leg, measured from the heel (mm)
let thickness: Double  = 5     // material thickness of each leg (mm)
let width: Double      = 40    // bracket width (extrusion depth, mm)
let filletRadius: Double = 8   // inside-corner radius (mm)
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
var bracket = prism.filleted(edges: prism.concaveEdges(), radius: filletRadius) ?? prism

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
try ctx.emit(description: "L-bracket — \(legLength)mm legs, \(width)mm wide, 4× Ø\(holeRadius * 2) holes")
