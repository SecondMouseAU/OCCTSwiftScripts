// Recipe 03 — Pipe flange
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — a raised-face pipe flange with a bolt circle.
// Notes:   The flange is a surface of revolution. The half-section is drawn in the XY
//          plane as (radius, axial) pairs with radius ≥ bore (so it never crosses the
//          axis) and revolved a full turn about the Y axis. The bolt circle is cut with
//          Shape.circularPatternCut (OCCTSwift v1.3.1, #169), which patterns a single hole
//          tool around the axis and subtracts the whole compound in one call. A small
//          all-edge chamfer breaks sharp corners; it degrades gracefully if it fails.
//
// Run:  swift run occtkit run recipes/03-pipe-flange/main.swift --format brep

import OCCTSwift
import ScriptHarness

// ── Parameters ──────────────────────────────────────────────────────────────
let boreRadius: Double      = 25   // through-bore radius (mm)
let outerRadius: Double     = 75   // flange outer radius (mm)
let thickness: Double       = 15   // flange disk thickness (mm)
let raisedRadius: Double    = 50   // raised-face outer radius (mm)
let raisedHeight: Double    = 2    // raised-face height above the disk (mm)
let boltCircleRadius: Double = 60   // bolt-circle radius (mm)
let boltCount: Int          = 8    // number of bolt holes
let boltRadius: Double      = 7    // bolt-hole radius (mm)

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Pipe flange",
    source: "OCCTSwiftScripts recipe 03",
    tags: ["flange", "revolve", "bolt-circle", "pattern"]
))
let C = ScriptContext.Colors.self

// ── Half-section in XY: x = radius from axis, y = axial position ───────────────
let section = Wire.polygon([
    SIMD2(boreRadius, 0),                          // back face @ bore
    SIMD2(outerRadius, 0),                         // back face → OD
    SIMD2(outerRadius, thickness),                 // OD → front of disk
    SIMD2(raisedRadius, thickness),                // disk front → raised-face OD
    SIMD2(raisedRadius, thickness + raisedHeight), // step up to raised face
    SIMD2(boreRadius, thickness + raisedHeight),   // raised face → bore
])!

// ── Revolve a full turn about the Y axis (the bore axis) ──────────────────────
var flange = Shape.revolve(profile: section, axisOrigin: .zero,
                           axisDirection: SIMD3(0, 1, 0), angle: 2 * .pi)!

// ── Bolt circle: one axial hole tool, patterned + subtracted around the Y axis ─
let depth = thickness + raisedHeight + 2
let holeTool = Shape.cylinder(at: SIMD3(boltCircleRadius, -1.0, 0),
                              direction: SIMD3(0, 1, 0),
                              radius: boltRadius, height: depth)!
flange = flange.circularPatternCut(tool: holeTool, axisPoint: .zero,
                                   axisDirection: SIMD3(0, 1, 0),
                                   count: boltCount, angle: 2 * .pi)!

// ── Break all sharp edges (optional; falls back if the chamfer fails) ─────────
flange = flange.chamfered(distance: 1.0) ?? flange

try ctx.add(flange, color: C.brass, name: "Pipe flange")

print("Flange volume: \(flange.volume ?? 0) mm³, \(boltCount)× Ø\(boltRadius * 2) bolt holes")
try ctx.emit(description: "Raised-face flange — Ø\(boreRadius * 2) bore, \(boltCount)-bolt circle")
