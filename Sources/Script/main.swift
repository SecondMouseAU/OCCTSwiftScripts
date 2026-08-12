// Pipeline reconstruction of McMaster 91502A278 M16x70 socket head cap screw
// Drawing type: 3rd_angle, 10 segments traced from real engineering drawing

import Foundation
import OCCTSwift
import ScriptHarness

let ctx = ScriptContext()

guard
    let cSeg1 = Curve2D.segment(
        from: SIMD2(2514.49492791066, 491.771863365059),
        to: SIMD2(2558.01083874765, 468.085981700795)),
    let wSeg1 = Wire.fromCurve2D(cSeg1)
else { fatalError("seg1") }
guard
    let cSeg2 = Curve2D.segment(
        from: SIMD2(2564.92118899864, 447.19099442846),
        to: SIMD2(2558.01083874765, 468.085981700795)),
    let wSeg2 = Wire.fromCurve2D(cSeg2)
else { fatalError("seg2") }
guard
    let cSeg3 = Curve2D.segment(
        from: SIMD2(2558.01083874765, 468.085981700795),
        to: SIMD2(2547.87339896333, 484.788551081164)),
    let wSeg3 = Wire.fromCurve2D(cSeg3)
else { fatalError("seg3") }
guard
    let cSeg4 = Curve2D.segment(
        from: SIMD2(2547.87339896333, 484.788551081164),
        to: SIMD2(2532.50854415954, 493.903950335487)),
    let wSeg4 = Wire.fromCurve2D(cSeg4)
else { fatalError("seg4") }
guard
    let cSeg5 = Curve2D.segment(
        from: SIMD2(2532.50854415954, 493.903950335487),
        to: SIMD2(2514.49492791066, 491.771863365059)),
    let wSeg5 = Wire.fromCurve2D(cSeg5)
else { fatalError("seg5") }
guard
    let cSeg6 = Curve2D.segment(
        from: SIMD2(2551.03468506118, 474.635448965979),
        to: SIMD2(2514.49492791066, 491.771863365059)),
    let wSeg6 = Wire.fromCurve2D(cSeg6)
else { fatalError("seg6") }
guard
    let cSeg7 = Curve2D.segment(
        from: SIMD2(2514.49492791066, 491.771863365059),
        to: SIMD2(2488.86021009317, 483.641737589616)),
    let wSeg7 = Wire.fromCurve2D(cSeg7)
else { fatalError("seg7") }
guard
    let cSeg8 = Curve2D.segment(
        from: SIMD2(2488.86021009317, 483.641737589616),
        to: SIMD2(2470.14234865582, 461.43763920772)),
    let wSeg8 = Wire.fromCurve2D(cSeg8)
else { fatalError("seg8") }
guard
    let cSeg9 = Curve2D.segment(
        from: SIMD2(2470.14234865582, 461.43763920772), to: SIMD2(2461.97468276258, 437.95263891928)
    ),
    let wSeg9 = Wire.fromCurve2D(cSeg9)
else { fatalError("seg9") }
guard
    let cSeg10 = Curve2D.segment(
        from: SIMD2(2471.88354219207, 412.803751762215),
        to: SIMD2(2461.97468276258, 437.95263891928)),
    let wSeg10 = Wire.fromCurve2D(cSeg10)
else { fatalError("seg10") }

guard
    let profile = Wire.join([
        wSeg1, wSeg2, wSeg3, wSeg4, wSeg5, wSeg6, wSeg7, wSeg8, wSeg9, wSeg10,
    ])
else {
    fatalError("Failed to join profile wire")
}
try ctx.add(profile, color: [0, 0.8, 1], name: "profile")

guard let solid = Shape.extrude(profile: profile, direction: SIMD3(0, 0, 1), length: 10) else {
    fatalError("Failed to extrude")
}
try ctx.add(solid, color: [0.6, 0.6, 0.65], name: "Reconstructed M16x70 (FAIL)")

try ctx.emit(description: "Pipeline reconstruction of McMaster M16x70")
