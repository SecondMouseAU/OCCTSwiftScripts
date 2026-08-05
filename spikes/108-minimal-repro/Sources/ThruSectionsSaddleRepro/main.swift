// Minimal standalone repro for OCCTSwiftScripts#108 (downstream investigation
// of OCCTSwift#702): ThruSectionsBuilder(isSolid: true) silently fails to
// build end-cap faces when a section wire is a genuinely non-planar closed
// curve, i.e. one with two or more periods of out-of-plane variation around
// the loop. No teeth, no gear math: this is a bare geometric trigger.
//
// Background: OCCTSwiftScripts#108 investigated whether a bevel gear's
// ThruSections loft (36 toothed sections stacked along a cone) could ever
// reach a valid SOLID on OCCTSwift 1.17.0. The raw loft reports isValid ==
// false with zero detailedCheckStatuses; healed()/fixSolid() only reach
// isValid == true by silently demoting the shape from Solid to Shell
// (subShapeCount(ofType: .solid) drops to 0), which is OCCTSwift#702. This
// repro isolates the actual trigger, bisected away from every property of
// the real gear (tooth shape, tooth count, point density, cone taper, flank
// proximity all turned out to be irrelevant):
//
//   "outer"/"inner" ring profile: r constant, z = amp * cos(k * theta).
//
//   k = 0: flat, planar.                                    -> caps, valid solid.
//   k = 1: non-zero z-spread, but this is SECRETLY PLANAR    -> caps, valid solid.
//          (z = amp*cos(theta) at fixed r is exactly the
//          intersection of the cylinder r=const with a
//          TILTED PLANE -- a "tilted circle", not a saddle).
//   k >= 2: genuinely non-planar (no single plane fits it).  -> FAILS.
//
// At k >= 2 the loft still reports build() == true and shape != nil (no
// error surfaces at all), but:
//   - raw.isValid is false, with checkResult.errorCount == 0 and
//     detailedCheckStatuses == [] (BRepCheck flags the shape invalid
//     overall without localizing why to any sub-shape).
//   - The face count is EXACTLY the wall-face count (one face per polyline
//     segment/column), never wall+2. A working (k <= 1) loft's face count
//     is always wall+2, and the two extra faces are large (disc-sized) in a
//     top-N-by-area sort; at k >= 2 no such large face exists at all: the
//     end caps were never built.
//   - healed() and fixSolid() both "fix" validity only by relabeling the
//     TopoDS type from Solid to Shell -- legal, since an open Shell doesn't
//     need to be closed to pass BRepCheck_Analyzer, whereas a Solid does.
//     Nothing is repaired; the same face set comes back unchanged.
//   - Shape.solidFromShells([healed]) (an untried rebuild path, distinct
//     from solidFromShellFixed()/solidFromShell()/upgraded()/unified()/
//     sewn(), all previously tried against the real gear and all failing
//     the same way) re-wraps the shell as shapeType == .solid again, but
//     isValid stays false: it cannot conjure the missing caps either.
//   - Shape.fill(boundaries:) (BRepFill_Filling, a general N-sided patch
//     algorithm) can attempt an explicit cap, but is far slower than the
//     rest of this repro on a few-hundred-point boundary and its own
//     success is no longer guaranteed either -- see the parent issue
//     comment for measurements against this exact repro.
//
// Run: swift run ThruSectionsSaddleRepro

import OCCTSwift
import Foundation
#if canImport(Darwin)
import Darwin
#endif

setvbuf(stdout, nil, _IONBF, 0)

func ring(r: Double, k: Int, amp: Double, zOffset: Double, n: Int) -> Wire {
    var pts: [SIMD3<Double>] = []
    for i in 0..<n {
        let a = 2 * .pi * Double(i) / Double(n)
        let z = amp * cos(Double(k) * a) + zOffset
        pts.append(SIMD3(r * cos(a), r * sin(a), z))
    }
    guard let w = Wire.polygon3D(pts, closed: true) else { fatalError("ring(k:\(k)) wire build failed") }
    return w
}

func loft(_ wires: [Wire]) -> Shape {
    let builder = ThruSectionsBuilder(isSolid: true, isRuled: false)
    builder.checkCompatibility(true)
    for w in wires {
        guard let s = Shape.fromWire(w) else { fatalError("Shape.fromWire failed") }
        builder.addWire(s)
    }
    guard builder.build(), let shape = builder.shape else { fatalError("loft build failed") }
    return shape
}

func report(_ label: String, _ shape: Shape) {
    let cr = shape.checkResult
    let volStr: String = shape.volume.map { "\($0)" } ?? "nil"
    let areas = shape.faces().map { $0.area() }.sorted(by: >)
    print("\(label):")
    print("  type=\(shape.shapeType) solids=\(shape.subShapeCount(ofType: .solid)) faces=\(shape.subShapeCount(ofType: .face)) valid=\(cr.isValid) errCount=\(cr.errorCount) vol=\(volStr)")
    print("  detailedCheckStatuses=\(shape.detailedCheckStatuses)")
    print("  top3FaceAreas=\(areas.prefix(3)) (a cap face would stand out here; none does once k >= 2)")
}

for k in [0, 1, 2, 6] {
    print("=== k=\(k) ===")
    let outer = ring(r: 20, k: k, amp: 5, zOffset: 0, n: 180)
    let inner = ring(r: 15, k: k, amp: 5, zOffset: -10, n: 180)
    let raw = loft([outer, inner])
    report("  raw", raw)
    guard let healed = raw.healed() else { fatalError("healed() returned nil") }
    report("  healed", healed)
    if let rebuilt = Shape.solidFromShells([healed]) {
        report("  solidFromShells([healed])", rebuilt)
    } else {
        print("  solidFromShells([healed]): nil")
    }
    print("")
}
