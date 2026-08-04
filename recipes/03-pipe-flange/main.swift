// Recipe 03: Pipe flange
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body: a raised-face pipe flange with a bolt circle.
// Notes:   The flange is a surface of revolution. The half-section is drawn in the XY
//          plane as (radius, axial) pairs with radius ≥ bore (so it never crosses the
//          axis), faced, and the face revolved a full turn about the Y axis.
//          Shape.revolve(profile: wire, ...) revolves the curve itself and returns a
//          shell (BRepPrimAPI_MakeRevol on a wire), not a solid; facing the wire first
//          with Shape.face(from:) and revolving the face closes the ends into a solid
//          (OCCTSwiftScripts #100). The bolt circle is cut with Shape.circularPatternCut
//          (OCCTSwift v1.3.1, #169), which patterns a single hole tool around the axis
//          and subtracts the whole compound in one call. A chamfer breaks the OD and
//          the raised-face rim; it targets those edges specifically because
//          Shape.chamfered(distance:), which chamfers every edge, cannot handle this
//          shape at all (OCCTSwiftScripts #103): every seam edge produced by the
//          revolve (the closing edge of each periodic cylindrical face: the bore, the
//          OD, the raised-face wall, and all eight bolt holes) fails to chamfer in
//          isolation at any distance from 1 mm down to 0.001 mm, because
//          BRepFilletAPI_MakeChamfer cannot resolve a blend on the seam of a periodic
//          surface, where both "adjacent" faces are really the same face. Excluding the
//          seams and chamfering only the OD and the raised-face rim's outer edge with
//          Shape.chamferedWithFullHistory(distance:edges:) avoids every seam.
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

// ── Face the half-section, then revolve the face a full turn about the Y axis
//    (the bore axis). Revolving the wire directly would only sweep out the curve
//    and return a shell; revolving the face closes the ends into a solid.
let sectionFace = Shape.face(from: section)!
var flange = sectionFace.revolved(axisOrigin: .zero, axisDirection: SIMD3(0, 1, 0))!

// ── Bolt circle: one axial hole tool, patterned + subtracted around the Y axis ─
let depth = thickness + raisedHeight + 2
let holeTool = Shape.cylinder(at: SIMD3(boltCircleRadius, -1.0, 0),
                              direction: SIMD3(0, 1, 0),
                              radius: boltRadius, height: depth)!
flange = flange.circularPatternCut(tool: holeTool, axisPoint: .zero,
                                   axisDirection: SIMD3(0, 1, 0),
                                   count: boltCount, angle: 2 * .pi)!

// ── Break the exposed sharp edges: the OD (front + back) and the raised face's
//    outer rim. The step's base, where the disk-front annulus meets the raised-face
//    wall, is a reentrant corner, not a sharp edge, so it is excluded: chamfering it
//    would add material rather than break a corner, and doing that alongside the rim
//    exhausts the 2mm-tall wall and fails outright. Select by geometry, not raw edge
//    index, so the recipe still finds the right edges if the parameters change
//    (same reasoning as recipe 01's concaveEdges() selection).
func nearAxisRadius(_ edge: borrowing Edge) -> Double? {
    guard edge.isCircle, let bounds = edge.parameterBounds,
          let p = edge.point(at: (bounds.first + bounds.last) / 2) else { return nil }
    return (p.x * p.x + p.z * p.z).squareRoot()
}
let chamferTargets = flange.edges(where: { edge in
    guard let r = nearAxisRadius(edge) else { return false }
    if abs(r - outerRadius) < 1e-3 { return true }                                          // OD, front + back
    if abs(r - raisedRadius) < 1e-3 && edge.bounds.min.y > thickness + 1e-3 { return true }  // raised-face rim
    return false
})
flange = flange.chamferedWithFullHistory(distance: 1.0, edges: chamferTargets.map(\.index))!.result

try ctx.add(flange, color: C.brass, name: "Pipe flange")

print("Flange volume: \(flange.volume ?? 0) mm³, \(boltCount)× Ø\(boltRadius * 2) bolt holes")
try ctx.emit(description: "Raised-face flange, Ø\(boreRadius * 2) bore, \(boltCount)-bolt circle")
