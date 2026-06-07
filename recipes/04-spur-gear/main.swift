// Recipe 04 — Involute spur gear
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — a parametric involute spur gear with a central bore.
// Notes:   Standard full-depth involute teeth. The full tooth outline is generated as a
//          single closed polygon by sampling the involute flanks (mirrored per tooth) and
//          connecting them with root points, then extruded to the face width and bored.
//          OCCTSwift has no native involute primitive, so the curve is sampled here from
//          the textbook parametric involute of the base circle.
//
// Run:  swift run occtkit run recipes/04-spur-gear/main.swift --format brep

import OCCTSwift
import ScriptHarness
import Foundation

// ── Parameters ──────────────────────────────────────────────────────────────
let module: Double           = 2   // mm of pitch diameter per tooth
let teeth: Int               = 18  // number of teeth
let pressureAngleDeg: Double  = 20  // pressure angle (degrees)
let faceWidth: Double        = 12  // extrusion depth (mm)
let boreRadius: Double       = 6   // central bore radius (mm)
let flankSamples: Int        = 8   // points sampled along each involute flank

// ── Derived gear geometry ─────────────────────────────────────────────────────
let alpha  = pressureAngleDeg * .pi / 180
let z      = Double(teeth)
let pitchR = module * z / 2          // pitch radius
let baseR  = pitchR * cos(alpha)     // base circle (involute starts here)
let addR   = pitchR + module         // addendum (tip)
let rootR  = pitchR - 1.25 * module  // dedendum (root)

func inv(_ a: Double) -> Double { tan(a) - a }   // involute function inv(α) = tan α − α

// Parametric involute of the base circle at roll angle t, rotated by `rot`:
//   involute(t) = baseR·(cos t + t·sin t, sin t − t·cos t)
// `mirror` flips it about the x-axis (for the opposite flank) before rotating.
func flankPoint(_ t: Double, rot: Double, mirror: Bool) -> SIMD2<Double> {
    let x = baseR * (cos(t) + t * sin(t))
    let y = (mirror ? -1 : 1) * baseR * (sin(t) - t * cos(t))
    return SIMD2(x * cos(rot) - y * sin(rot), x * sin(rot) + y * cos(rot))
}

// Roll angle at which the involute reaches the tip: radius(t) = baseR·√(1+t²)
let tTip = ((addR / baseR) * (addR / baseR) - 1).squareRoot()
// Base-circle angular offset of a flank from the tooth centre: half the tooth angle
// at the pitch circle plus the involute roll out to the pitch circle.
let flankOffset = .pi / (2 * z) + inv(alpha)

func rootPoint(_ angle: Double) -> SIMD2<Double> { SIMD2(rootR * cos(angle), rootR * sin(angle)) }

// ── Build the full gear outline as one CCW closed polygon ──────────────────────
var pts: [SIMD2<Double>] = []
for i in 0..<teeth {
    let centre   = Double(i) * 2 * .pi / z
    let rightRot = centre - flankOffset   // right flank base sits at the lower angle
    let leftRot  = centre + flankOffset   // left flank base sits at the higher angle

    pts.append(rootPoint(rightRot))                                   // root, right side
    for s in 0...flankSamples {                                       // up the right flank
        pts.append(flankPoint(tTip * Double(s) / Double(flankSamples), rot: rightRot, mirror: false))
    }
    for s in stride(from: flankSamples, through: 0, by: -1) {         // down the left flank
        pts.append(flankPoint(tTip * Double(s) / Double(flankSamples), rot: leftRot, mirror: true))
    }
    pts.append(rootPoint(leftRot))                                    // root, left side
}

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Involute spur gear",
    source: "OCCTSwiftScripts recipe 04",
    tags: ["gear", "involute", "extrude"]
))
let C = ScriptContext.Colors.self

guard let outline = Wire.polygon(pts, closed: true) else { fatalError("gear outline wire failed") }
var gear = Shape.extrude(profile: outline, direction: SIMD3(0, 0, 1), length: faceWidth)!

// central bore
let bore = Shape.cylinder(at: SIMD3(0, 0, -1), direction: SIMD3(0, 0, 1),
                          radius: boreRadius, height: faceWidth + 2)!
gear = gear.subtracting(bore)!

try ctx.add(gear, color: C.steel, name: "Spur gear")

print("Pitch Ø\(pitchR * 2), \(teeth) teeth, gear volume: \(gear.volume ?? 0) mm³")
try ctx.emit(description: "Involute spur gear — module \(module), \(teeth) teeth")
