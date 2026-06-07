// Recipe 06 — Twisted fan blade
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — a single tapered, twisted fan/propeller blade on a hub boss.
// Notes:   The blade is a loft through several NACA-symmetric airfoil sections stacked along
//          the span (Z). Each section is scaled (chord taper) and rotated in its own plane
//          (twist) before lofting. Every section is built from the SAME number of points in
//          the same order so the loft correspondence is unambiguous. A hub cylinder at the
//          root is fused on.
//
// Run:  swift run occtkit run recipes/06-fan-blade/main.swift --format brep

import OCCTSwift
import ScriptHarness
import Foundation

// ── Parameters ──────────────────────────────────────────────────────────────
let span: Double       = 60    // blade length along Z (mm)
let rootChord: Double  = 30    // chord at the root (mm)
let taper: Double      = 0.45  // tip chord = rootChord·(1−taper)
let thickness: Double  = 0.12  // airfoil max thickness as a fraction of chord (NACA t)
let twistRootDeg: Double = 32  // section twist at the root (degrees)
let twistTipDeg: Double  = 8   // section twist at the tip (degrees)
let sections: Int      = 6     // number of lofted sections
let stations: Int      = 12    // chordwise sample points per surface

// NACA symmetric half-thickness at chord fraction x∈[0,1], in chord units.
func naca(_ x: Double) -> Double {
    5 * thickness * (0.2969 * x.squareRoot() - 0.1260 * x - 0.3516 * x * x
                     + 0.2843 * x * x * x - 0.1015 * x * x * x * x)
}

// Base airfoil as a closed point loop (upper LE→TE, then lower TE→LE), chord-normalised.
// Cosine spacing clusters points at the leading edge for a clean nose.
let xs = (0..<stations).map { 0.5 * (1 - cos(.pi * Double($0) / Double(stations - 1))) }
var baseAirfoil: [SIMD2<Double>] = []
for x in xs { baseAirfoil.append(SIMD2(x - 0.25, naca(x))) }            // upper, LE→TE
for x in xs.dropFirst().dropLast().reversed() {                          // lower, TE→LE
    baseAirfoil.append(SIMD2(x - 0.25, -naca(x)))
}

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Twisted fan blade",
    source: "OCCTSwiftScripts recipe 06",
    tags: ["fan", "blade", "loft", "airfoil", "twist"]
))
let C = ScriptContext.Colors.self

// ── Build one airfoil wire per spanwise section: scale (taper) + rotate (twist) ─
var profiles: [Wire] = []
for i in 0..<sections {
    let f = Double(i) / Double(sections - 1)
    let z = f * span
    let chord = rootChord * (1 - taper * f)
    let twist = (twistRootDeg + (twistTipDeg - twistRootDeg) * f) * .pi / 180
    let pts3d = baseAirfoil.map { p -> SIMD3<Double> in
        let sx = p.x * chord, sy = p.y * chord
        return SIMD3(sx * cos(twist) - sy * sin(twist),
                     sx * sin(twist) + sy * cos(twist),
                     z)
    }
    guard let w = Wire.polygon3D(pts3d, closed: true) else { fatalError("section \(i) wire failed") }
    profiles.append(w)
}

guard var blade = Shape.loft(profiles: profiles, solid: true) else { fatalError("loft failed") }

// ── Hub boss at the root, fused on ────────────────────────────────────────────
let hubR = rootChord * 0.55
let hub = Shape.cylinder(at: SIMD3(0, 0, -12), direction: SIMD3(0, 0, 1),
                         radius: hubR, height: 14)!
blade = blade.union(hub) ?? blade

try ctx.add(blade, color: C.steel, name: "Fan blade")

print("span \(span) mm, \(sections) sections, blade volume: \(blade.volume ?? 0) mm³")
try ctx.emit(description: "Twisted fan blade — \(sections) airfoil sections, span \(span) mm")
