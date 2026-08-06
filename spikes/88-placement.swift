// Spike 88: bevel gear placement via explicit pitchbase / flattop / apex reference frames,
// replacing BOSL2's anchor system.
//
// Follow-on from spikes/87-spiral-route-c.swift (Route C, unequal mate_teeth, three tooth
// forms). This file extends that lineage: through `buildRouteC` (module constants, GearGeometry,
// the spiral cutter-arc, slicePoint, meridianRZ, buildFullBlank/buildCutterTool/buildBacking/
// buildBoreCylinder, HealthSnapshot, GearParams/RouteCResult/buildRouteC) is copied UNCHANGED,
// per #88's instruction to extend rather than edit 87/109/110. The new material starts at
// "GearReferenceFrames" below.
//
// Math ported from BOSL2's gears.scad `bevel_gear()` named anchors, lines 2640-2643:
//
//   named_anchor("pitchbase", [0,0,pitchoff-ctr_thickness/2+backing/2]),
//   named_anchor("flattop",   [0,0,ctr_thickness/2+backing/2]),
//   named_anchor("apex",      [0,0,hyp_ang_to_opp(pitch_angle<90?ocone_rad:icone_rad,
//                                 90-pitch_angle)+pitchoff-ctr_thickness/2+backing/2])
//
// BOSL2 is BSD-2-Clause, Copyright 2017-2019 Revar Desmera:
// https://github.com/BelfrySCAD/BOSL2/blob/master/gears.scad
//
// ── A deliberate deviation from BOSL2's literal formula, and why it doesn't matter ──────────
// BOSL2's `ctr_thickness` is the Z-difference between two specific vnf vertices (index 0 of the
// tooth profile, at the two end slicing stations), an artifact of its vertex-array bookkeeping,
// not a named, independently-derivable quantity. And BOSL2 folds `backing` into pitchbase/
// flattop/apex because it recenters the WHOLE body (teeth + backing) around their combined
// midpoint (`down(cpz, ...)`) before exposing anchors.
//
// This file does neither. It defines pitchbase/flattop/apex directly from the same meridian
// analytic points already used and verified throughout 87/109/110 (`meridianRZ`, the exact
// function that places the real profile vertices of the blank and the backing):
//   - pitchbase: the pitch line's height at the back (wide, u=1) cone edge. This is `pitchoff`
//     by construction (verified below against `meridianRZ(u:1,R:pr)` as a regression check).
//   - flattop: the flat annulus at the front (narrow, near-apex, u=iconeRad/oconeRad) cone edge,
//     `meridianRZ(u:uInner,R:rootR)`, literally the same point `buildFullBlank`'s `innerRoot`
//     computes for the axial front face of the blank.
//   - apex: pitchbase + the pitch cone's apex height above it, `hyp_ang_to_opp` reduced to
//     `oconeRad * cos(pitchAngle)` (or `iconeRad * cos(pitchAngle)` for pitchAngle >= 90, per
//     BOSL2's own ternary; unexercised here since our matrix stays under 90 degrees).
// No recentering step is introduced, so `backing` does not shift these heights: meshing is a
// property of the TEETH's pitch cone, not of how thick an optional mounting boss is.
//
// This changes the ABSOLUTE numeric value of pitchbase/flattop/apex relative to BOSL2's own
// convention, but the quantity issue #88's ground truth actually checks, apex height ABOVE
// pitchbase, is `apex - pitchbase = ocone_rad*cos(pitch_angle)` in BOTH conventions: BOSL2's own
// `ctr_thickness` and `backing` terms appear identically in its pitchbase and apex formulas and
// cancel exactly in the subtraction. The deviation is invisible to the one check that matters.
//
// ── House policy compliance (okf/policies, okf/decisions) ──────────────────────────────────
// No `heal()` anywhere in this file. No `??` on a geometry operation (the only `??` is
// `p.mateTeeth ?? Double(p.teeth)`, a plain numeric default, copied unchanged from spike 87).
// Every gear built here asserts `subShapeCount(ofType: .solid) >= 1` before use (standing trap
// #1). The meshing helper's world-space apex-agreement check is real code, not a description:
// see the comment at its call site for what it does and does not prove (standing trap in #88's
// own text: a helper that positions both gears by the same computed quantity trivially agrees
// with itself; the pr(mate) closed form is the check that can actually fail).
//
// Run:  swift run occtkit run spikes/88-placement.swift

import OCCTSwift
import ScriptHarness
import Foundation
import simd
#if canImport(Darwin)
import Darwin
#endif

setvbuf(stdout, nil, _IONBF, 0)

// ══════════════════════════════════════════════════════════════════════════════════════════
// Copied UNCHANGED from spikes/87-spiral-route-c.swift, through buildRouteC. See that file for
// full commentary on each piece; only the parts #88 actually needs are reproduced here (the
// spiral cutter-arc machinery, since the deliverable examples in #89 use spiral teeth).
// ══════════════════════════════════════════════════════════════════════════════════════════
let module: Double            = 2
let pressureAngleDeg: Double  = 20
let flankSamples: Int         = 14
let radialClearance: Double   = module * 0.25

let alpha = pressureAngleDeg * .pi / 180
func inv(_ a: Double) -> Double { tan(a) - a }

func bevelPitchAngle(teeth: Double, mateTeeth: Double, shaftAngle: Double) -> Double {
    atan(sin(shaftAngle) / (mateTeeth / teeth + cos(shaftAngle)))
}

struct GearGeometry {
    let teeth: Int
    let mateTeeth: Double
    let shaftAngle: Double
    let pitchAngle: Double
    let pr: Double
    let baseR: Double
    let addR: Double
    let rootR: Double
    let oconeRad: Double
    let faceWidth: Double
    let iconeRad: Double
    let pitchoff: Double

    init(teeth: Int, mateTeeth: Double, shaftAngle: Double = .pi / 2) {
        self.teeth = teeth
        self.mateTeeth = mateTeeth
        self.shaftAngle = shaftAngle
        let z = Double(teeth)
        pr = module * z / 2
        baseR = pr * cos(alpha)
        addR = pr + module
        rootR = pr - 1.25 * module
        pitchAngle = bevelPitchAngle(teeth: z, mateTeeth: mateTeeth, shaftAngle: shaftAngle)
        oconeRad = pr / sin(pitchAngle)
        faceWidth = min(oconeRad / 3, 10 * module)
        iconeRad = oconeRad - faceWidth
        pitchoff = (pr - rootR) * sin(pitchAngle)
    }
}

enum CutterRadiusSpec {
    case defaulted
    case straight
    case explicit(Double)
}

struct CutterArc {
    let cutterRadius: Double
    let sang: Double
    let eang: Double
    let radcp: SIMD2<Double>
}

func buildCutterArc(g: GearGeometry, spiralRad: Double, cutterRadiusSpec: CutterRadiusSpec) -> CutterArc {
    let cutterRadius: Double
    switch cutterRadiusSpec {
    case .defaulted:        cutterRadius = g.faceWidth * 2 / cos(spiralRad)
    case .straight:          cutterRadius = g.faceWidth * 100
    case .explicit(let r):  cutterRadius = r
    }

    let midpr = (g.iconeRad + g.oconeRad) / 2
    let radcp = SIMD2(0, midpr) + SIMD2(cutterRadius * cos(.pi + spiralRad), cutterRadius * sin(.pi + spiralRad))
    let normRadcp = (radcp.x * radcp.x + radcp.y * radcp.y).squareRoot()

    func lawOfCosines(a: Double, b: Double, c: Double) -> Double {
        let cosC = (a * a + b * b - c * c) / (2 * a * b)
        return acos(min(1, max(-1, cosC)))
    }
    let angC1 = lawOfCosines(a: cutterRadius, b: normRadcp, c: g.oconeRad)
    let angC2 = lawOfCosines(a: cutterRadius, b: normRadcp, c: g.iconeRad)
    let radcpang = atan2(radcp.y, radcp.x)
    let sang = radcpang - (.pi - angC1)
    let eang = radcpang - (.pi - angC2)

    return CutterArc(cutterRadius: cutterRadius, sang: sang, eang: eang, radcp: radcp)
}

func resolveSlices(_ slices: Int, cutterRadiusSpec: CutterRadiusSpec) -> Int {
    if case .straight = cutterRadiusSpec { return 1 }
    return slices
}

func cutterStation(_ cutter: CutterArc, v: Double) -> (u: Double, ang: Double) {
    let theta = cutter.sang + (cutter.eang - cutter.sang) * v
    let p = cutter.radcp + SIMD2(cutter.cutterRadius * cos(theta), cutter.cutterRadius * sin(theta))
    let dist = (p.x * p.x + p.y * p.y).squareRoot()
    return (dist, atan2(p.y, p.x) - .pi / 2)
}

func slicePoint(local: SIMD2<Double>, u: Double, ang: Double, g: GearGeometry, toothAngle: Double) -> SIMD3<Double> {
    let transverse = u * local.x
    let radial = u * local.y

    let x0 = transverse
    let yPreZrot = radial * cos(g.pitchAngle) + u * g.pr
    let z0 = radial * sin(g.pitchAngle) + g.pitchoff + (1 - u) * g.pr / tan(g.pitchAngle)

    let theta = ang / sin(g.pitchAngle)
    let x0z = x0 * cos(theta) - yPreZrot * sin(theta)
    let y0z = x0 * sin(theta) + yPreZrot * cos(theta)

    let x1 = x0z * cos(toothAngle) - y0z * sin(toothAngle)
    let y1 = x0z * sin(toothAngle) + y0z * cos(toothAngle)

    return SIMD3(-x1, y1, z0)
}

func flankPoint(t: Double, rot: Double, mirror: Bool, baseR: Double) -> SIMD2<Double> {
    let x = baseR * (cos(t) + t * sin(t))
    let y = (mirror ? -1 : 1) * baseR * (sin(t) - t * cos(t))
    return SIMD2(x * cos(rot) - y * sin(rot), x * sin(rot) + y * cos(rot))
}
func radialPoint(angle: Double, radius: Double) -> SIMD2<Double> {
    SIMD2(radius * cos(angle), radius * sin(angle))
}

func meridianRZ(u: Double, R: Double, g: GearGeometry) -> SIMD2<Double> {
    let p = slicePoint(local: SIMD2(0, R - g.pr), u: u, ang: 0, g: g, toothAngle: 0)
    return SIMD2(p.y, p.z)
}

func gapLocalProfile(offset: Double, tTip: Double, rootExtRadius: Double,
                      tipExtRadius: Double, g: GearGeometry) -> [SIMD2<Double>] {
    let rightRot = -offset
    let leftRot  =  offset

    func tipExtension(rot: Double, mirror: Bool) -> SIMD2<Double> {
        let tip = flankPoint(t: tTip, rot: rot, mirror: mirror, baseR: g.baseR)
        return radialPoint(angle: atan2(tip.y, tip.x), radius: tipExtRadius)
    }

    var absPts: [SIMD2<Double>] = []
    absPts.append(radialPoint(angle: rightRot, radius: rootExtRadius))
    for s in 0...flankSamples {
        absPts.append(flankPoint(t: tTip * Double(s) / Double(flankSamples), rot: rightRot, mirror: true, baseR: g.baseR))
    }
    absPts.append(tipExtension(rot: rightRot, mirror: true))
    absPts.append(tipExtension(rot: leftRot, mirror: false))
    for s in stride(from: flankSamples, through: 0, by: -1) {
        absPts.append(flankPoint(t: tTip * Double(s) / Double(flankSamples), rot: leftRot, mirror: false, baseR: g.baseR))
    }
    absPts.append(radialPoint(angle: leftRot, radius: rootExtRadius))

    return absPts.map { p in SIMD2(-p.y, p.x - g.pr) }
}

func buildFullBlank(_ g: GearGeometry) -> Shape? {
    let uInner = g.iconeRad / g.oconeRad
    let outerRoot = meridianRZ(u: 1, R: g.rootR, g: g)
    let outerTip  = meridianRZ(u: 1, R: g.addR, g: g)
    let innerTip  = meridianRZ(u: uInner, R: g.addR, g: g)
    let innerRoot = meridianRZ(u: uInner, R: g.rootR, g: g)

    let profilePts: [SIMD3<Double>] = [
        SIMD3(0, 0, outerRoot.y),
        SIMD3(0, outerRoot.x, outerRoot.y),
        SIMD3(0, outerTip.x, outerTip.y),
        SIMD3(0, innerTip.x, innerTip.y),
        SIMD3(0, innerRoot.x, innerRoot.y),
        SIMD3(0, 0, innerRoot.y),
    ]
    guard let wire = Wire.polygon3D(profilePts, closed: true) else { return nil }
    guard let face = Shape.face(from: wire) else { return nil }
    return face.revolved(axisOrigin: .zero, axisDirection: SIMD3(0, 0, 1))
}

func buildCutterTool(_ g: GearGeometry, cutter: CutterArc, slices: Int, toothAngle: Double = 0) -> Shape? {
    let gapFlankOffset = .pi / (2 * Double(g.teeth)) - inv(alpha)
    let tTip = ((g.addR / g.baseR) * (g.addR / g.baseR) - 1).squareRoot()
    let rootExtRadius = g.rootR - radialClearance
    let tipExtRadius = g.addR + radialClearance

    let localProfile = gapLocalProfile(offset: gapFlankOffset, tTip: tTip,
                                        rootExtRadius: rootExtRadius, tipExtRadius: tipExtRadius, g: g)

    var wires: [Wire] = []
    for vi in 0...slices {
        let v = slices == 0 ? 0.0 : Double(vi) / Double(slices)
        let (dist, ang) = cutterStation(cutter, v: v)
        let u = dist / g.oconeRad
        let pts = localProfile.map { slicePoint(local: $0, u: u, ang: ang, g: g, toothAngle: toothAngle) }
        guard let wire = Wire.polygon3D(pts, closed: true) else { return nil }
        wires.append(wire)
    }

    let loft = ThruSectionsBuilder(isSolid: true, isRuled: false)
    loft.checkCompatibility(true)
    for wire in wires {
        guard let s = Shape.fromWire(wire) else { return nil }
        loft.addWire(s)
    }
    guard loft.build(), let raw = loft.shape else { return nil }
    return raw
}

struct BackingResult {
    let shape: Shape
    let analyticVolume: Double
    let outerRadius: Double
    let farRadius: Double
}

func buildBacking(_ g: GearGeometry, backing: Double, coneBacking: Bool) -> BackingResult {
    let outerRoot = meridianRZ(u: 1, R: g.rootR, g: g)
    let r0 = outerRoot.x
    let z0 = outerRoot.y
    let z1 = z0 - backing

    let r1: Double
    if coneBacking {
        let factor = tan(g.pitchAngle - .pi / 2) * backing
        r1 = r0 + factor
        guard r1 > 0 else {
            fatalError("backing=\(backing): conical taper crosses the axis (r0=\(r0), r1=\(r1)); reduce backing")
        }
    } else {
        r1 = r0
    }

    let meridian: [SIMD3<Double>] = [
        SIMD3(0, 0, z0), SIMD3(0, r0, z0), SIMD3(0, r1, z1), SIMD3(0, 0, z1),
    ]
    guard let wire = Wire.polygon3D(meridian, closed: true) else {
        fatalError("backing meridian wire failed (r0=\(r0), r1=\(r1), z0=\(z0), z1=\(z1))")
    }
    guard let face = Shape.face(from: wire) else {
        fatalError("backing meridian face failed")
    }
    guard let solid = face.revolved(axisOrigin: .zero, axisDirection: SIMD3(0, 0, 1)) else {
        fatalError("backing revolve failed")
    }

    let analyticVolume = coneBacking
        ? (Double.pi * backing / 3) * (r0 * r0 + r0 * r1 + r1 * r1)
        : Double.pi * r0 * r0 * backing
    return BackingResult(shape: solid, analyticVolume: analyticVolume, outerRadius: r0, farRadius: r1)
}

struct HealthSnapshot {
    let isValid: Bool
    let shapeType: ShapeType
    let solidCount: Int
    let faceCount: Int
    let volume: Double
    let freeEdgeCount: Int
    let smallEdgeCount: Int
    let smallFaceCount: Int
    let selfIntersectionCount: Int

    init(_ shape: Shape) {
        isValid = shape.isValid
        shapeType = shape.shapeType
        solidCount = shape.subShapeCount(ofType: .solid)
        faceCount = shape.subShapeCount(ofType: .face)
        volume = shape.volume ?? Double.nan
        let a = shape.analyze()
        freeEdgeCount = a?.freeEdgeCount ?? -1
        smallEdgeCount = a?.smallEdgeCount ?? -1
        smallFaceCount = a?.smallFaceCount ?? -1
        selfIntersectionCount = a?.selfIntersectionCount ?? -1
    }

    func describe(_ label: String) {
        print("  [\(label)] isValid=\(isValid) shapeType=\(shapeType) solidCount=\(solidCount) faceCount=\(faceCount) volume=\(volume)")
    }
}

struct GearParams {
    var teeth: Int
    var mateTeeth: Double? = nil
    var shaftAngle: Double = .pi / 2
    var spiralDeg: Double = 35
    var cutterRadiusSpec: CutterRadiusSpec = .defaulted
    var slices: Int = 5
    var rightHanded: Bool = false
    var backing: Double? = nil
    var coneBacking: Bool = true
}

struct RouteCResult {
    let label: String
    let params: GearParams
    let g: GearGeometry
    let gearHealth: HealthSnapshot
    let backingApplied: Bool
    let finalHealth: HealthSnapshot
    let finalShape: Shape
}

func buildRouteC(_ p: GearParams, label: String) -> RouteCResult {
    let mateTeeth = p.mateTeeth ?? Double(p.teeth)
    let g = GearGeometry(teeth: p.teeth, mateTeeth: mateTeeth, shaftAngle: p.shaftAngle)
    let spiralRad = p.spiralDeg * .pi / 180
    let cutter = buildCutterArc(g: g, spiralRad: spiralRad, cutterRadiusSpec: p.cutterRadiusSpec)
    let slices = resolveSlices(p.slices, cutterRadiusSpec: p.cutterRadiusSpec)

    guard let blank = buildFullBlank(g) else { fatalError("\(label): buildFullBlank failed") }
    let blankHealth = HealthSnapshot(blank)
    guard blankHealth.solidCount >= 1 else {
        fatalError("\(label): blank is not a solid (solidCount=\(blankHealth.solidCount))")
    }

    guard let cutterShape = buildCutterTool(g, cutter: cutter, slices: slices) else {
        fatalError("\(label): buildCutterTool failed")
    }
    let cutterHealth = HealthSnapshot(cutterShape)
    guard cutterHealth.solidCount >= 1 else {
        fatalError("\(label): tooth-space cutter is not a solid (solidCount=\(cutterHealth.solidCount))")
    }

    guard let gear = blank.circularPatternCut(tool: cutterShape, axisPoint: .zero,
                                              axisDirection: SIMD3(0, 0, 1), count: p.teeth) else {
        fatalError("\(label): circularPatternCut returned nil")
    }
    let gearHealth = HealthSnapshot(gear)
    guard gearHealth.solidCount >= 1, gearHealth.isValid else {
        fatalError("\(label): pattern-cut gear failed to be a valid solid without healing (solidCount=\(gearHealth.solidCount), isValid=\(gearHealth.isValid))")
    }

    print("[\(label)] teeth=\(p.teeth) mateTeeth=\(mateTeeth) pitchAngle=\(g.pitchAngle * 180 / .pi)deg")
    gearHealth.describe("gear (post pattern-cut, RAW, no heal)")

    var shape = gear

    var backingApplied = false
    if let backing = p.backing {
        let preVol = shape.volume ?? Double.nan
        let br = buildBacking(g, backing: backing, coneBacking: p.coneBacking)
        if let unioned = shape.union(br.shape), let postVol = unioned.volume, postVol > preVol {
            shape = unioned
            backingApplied = true
        } else {
            print("  NOTE: \(label) backing union did not increase volume as expected")
        }
    }

    if p.rightHanded {
        guard let mirrored = shape.mirrored(planeNormal: SIMD3(1, 0, 0)) else {
            fatalError("\(label): handedness mirror failed")
        }
        shape = mirrored
    }

    let finalHealth = HealthSnapshot(shape)
    guard finalHealth.solidCount >= 1 else {
        fatalError("\(label): final composed shape is not a solid (solidCount=\(finalHealth.solidCount))")
    }
    finalHealth.describe("final")
    print("")

    return RouteCResult(label: label, params: p, g: g, gearHealth: gearHealth,
                         backingApplied: backingApplied, finalHealth: finalHealth, finalShape: shape)
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// NEW FOR #88: explicit reference frames.
// ══════════════════════════════════════════════════════════════════════════════════════════
struct GearReferenceFrames {
    let pitchbase: Double
    let flattop: Double
    let apex: Double
}

func referenceFrames(_ g: GearGeometry) -> GearReferenceFrames {
    let pitchbase = g.pitchoff
    // Regression check: pitchoff and the meridian machinery that actually places the blank's
    // vertices must agree exactly, since they are the same z0 formula evaluated at R=pr, u=1.
    let pitchbaseFromMeridian = meridianRZ(u: 1, R: g.pr, g: g).y
    precondition(abs(pitchbase - pitchbaseFromMeridian) < 1e-9,
                 "pitchbase disagreement: pitchoff=\(pitchbase) vs meridian=\(pitchbaseFromMeridian)")

    let uInner = g.iconeRad / g.oconeRad
    let flattop = meridianRZ(u: uInner, R: g.rootR, g: g).y

    // hyp_ang_to_opp(hyp, ang) = hyp * sin(ang); ang = 90 - pitchAngle, so sin(ang) = cos(pitchAngle).
    let apexCone = g.pitchAngle < .pi / 2 ? g.oconeRad : g.iconeRad
    let apexAboveBase = apexCone * cos(g.pitchAngle)
    let apex = pitchbase + apexAboveBase

    return GearReferenceFrames(pitchbase: pitchbase, flattop: flattop, apex: apex)
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// NEW FOR #88: the meshing helper. Given two gears' reference frames and a shaft angle, return
// the transform that meshes them, with coincident pitch-cone apexes.
// ══════════════════════════════════════════════════════════════════════════════════════════

/// One gear's placement: translate its apex to the world origin, optionally spin it about its
/// OWN (still axis-aligned) +Z axis for tooth-phase interleaving, then tilt that axis by
/// `tiltAngle` about `tiltAxis`. Order matters: spin BEFORE tilt, matching BOSL2's own
/// anchor -> spin -> orient order for `bevel_gear()` (gears.scad's doc comment for `spin`:
/// "Rotate this many degrees around the Z axis after anchor", applied before `orient`). Spinning
/// after the tilt would rotate about the already-tilted axis, not the gear's manufacturing axis.
struct GearMeshStep {
    let translation: SIMD3<Double>
    let phaseAngle: Double   // radians, about (0,0,1), applied before the tilt
    let tiltAxis: SIMD3<Double>
    let tiltAngle: Double    // radians
}

func meshStep(_ frames: GearReferenceFrames, tiltAxis: SIMD3<Double>, tiltAngle: Double,
              phaseAngle: Double = 0) -> GearMeshStep {
    GearMeshStep(translation: SIMD3(0, 0, -frames.apex), phaseAngle: phaseAngle,
                 tiltAxis: tiltAxis, tiltAngle: tiltAngle)
}

/// Apply a mesh step to a Shape via ordinary `translated`/`rotated` (per #88's brief: "Callers
/// then position with ordinary translated and rotated").
func applyMeshStep(_ shape: Shape, _ step: GearMeshStep) -> Shape {
    guard let translated = shape.translated(by: step.translation) else {
        fatalError("meshStep: translate failed (translation=\(step.translation))")
    }
    var current = translated
    if step.phaseAngle != 0 {
        guard let spun = current.rotated(axis: SIMD3(0, 0, 1), angle: step.phaseAngle) else {
            fatalError("meshStep: phase rotate failed (angle=\(step.phaseAngle))")
        }
        current = spun
    }
    guard step.tiltAngle != 0 else { return current }
    guard let tilted = current.rotated(axis: step.tiltAxis, angle: step.tiltAngle) else {
        fatalError("meshStep: tilt rotate failed (axis=\(step.tiltAxis), angle=\(step.tiltAngle))")
    }
    return tilted
}

/// Apply the SAME mesh step to a point, via OCCTSwift's `TransformFactory3D` (the gce_Make*/
/// gp_Trsf machinery that `Shape.translated`/`.rotated` themselves wrap underneath, per the
/// API map in the occtswift docs). Used to check where a gear's own precomputed apex point
/// lands once the SAME step is applied to it, independent of re-implementing rotation math by
/// hand.
func applyMeshStep(_ point: SIMD3<Double>, _ step: GearMeshStep) -> SIMD3<Double> {
    var p = TransformFactory3D.translation(step.translation).apply(to: point)
    if step.phaseAngle != 0 {
        p = TransformFactory3D.rotation(point: .zero, direction: SIMD3(0, 0, 1), angle: step.phaseAngle).apply(to: p)
    }
    if step.tiltAngle != 0 {
        p = TransformFactory3D.rotation(point: .zero, direction: step.tiltAxis, angle: step.tiltAngle).apply(to: p)
    }
    return p
}

/// Given two gears' reference frames and a shaft angle, return the pair of steps that mesh
/// them: `reference` stays on its own build axis, `mate` tilts by `shaftAngle` about `tiltAxis`
/// so the two axes meet at `shaftAngle` with both pitch-cone apexes coincident at the world
/// origin. `matePhaseDeg` threads BOSL2's `spin = 180/mate_teeth` idiom (gears.scad Example 2)
/// through in the geometrically correct pre-tilt order (see GearMeshStep's doc), but the VALUE
/// is the caller's choice: the right phase depends on which flank convention the two tooth
/// cutters were built with (handedness, starting tooth-gap angle), not a fixed geometric
/// constant this helper can derive on its own. This is what standing trap #4 in #88 asks to be
/// explicit about: the helper handles the MECHANICS and ORDERING of phase, not the value.
func meshPair(reference: GearReferenceFrames, mate: GearReferenceFrames, shaftAngle: Double,
              tiltAxis: SIMD3<Double> = SIMD3(1, 0, 0), matePhaseDeg: Double = 0)
    -> (reference: GearMeshStep, mate: GearMeshStep)
{
    let refStep = meshStep(reference, tiltAxis: tiltAxis, tiltAngle: 0)
    let mateStep = meshStep(mate, tiltAxis: tiltAxis, tiltAngle: shaftAngle,
                             phaseAngle: matePhaseDeg * .pi / 180)
    return (refStep, mateStep)
}

func refFramesDict(_ f: GearReferenceFrames) -> [String: Double] {
    ["pitchbase": f.pitchbase, "flattop": f.flattop, "apex": f.apex]
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// Driver
// ══════════════════════════════════════════════════════════════════════════════════════════
let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Spike 88: bevel gear placement (pitchbase/flattop/apex + meshing helper)",
    source: "OCCTSwiftScripts spike/88-placement",
    tags: ["spike", "gear", "bevel", "placement", "reference-frames", "meshing"]
))
let C = ScriptContext.Colors.self

// ── 1. Ground truth table (issue #88), pure arithmetic, no shapes built. ────────────────────
// "A gear's apex height equals its mate's pitch radius, exactly", at a 90 degree shaft angle.
// This is the STRONG, independent check: it compares against literal numbers given in the
// issue, not against anything this file re-derives, so a shared sign or factor error in
// `referenceFrames` cannot pass it by accident.
print("=== 1. Ground truth table: apex height above pitchbase vs mate's pitch radius (90deg) ===")
struct GroundTruthRow { let teeth: Int; let mate: Int; let expectedPitchDeg: Double; let expectedApex: Double }
let groundTruth: [GroundTruthRow] = [
    GroundTruthRow(teeth: 36, mate: 36, expectedPitchDeg: 45.00, expectedApex: 36.000),
    GroundTruthRow(teeth: 16, mate: 28, expectedPitchDeg: 29.74, expectedApex: 28.000),
    GroundTruthRow(teeth: 28, mate: 16, expectedPitchDeg: 60.26, expectedApex: 16.000),
    GroundTruthRow(teeth: 14, mate: 28, expectedPitchDeg: 26.57, expectedApex: 28.000),
    GroundTruthRow(teeth: 28, mate: 14, expectedPitchDeg: 63.43, expectedApex: 14.000),
]
var groundTruthAllPass = true
for row in groundTruth {
    let g = GearGeometry(teeth: row.teeth, mateTeeth: Double(row.mate), shaftAngle: .pi / 2)
    let frames = referenceFrames(g)
    let pitchDeg = g.pitchAngle * 180 / .pi
    let apexAboveBase = frames.apex - frames.pitchbase
    let matePr = module * Double(row.mate) / 2
    let apexDiff = abs(apexAboveBase - matePr)
    let pitchDiff = abs(pitchDeg - row.expectedPitchDeg)
    let pass = apexDiff < 1e-9 && pitchDiff < 5e-3
    groundTruthAllPass = groundTruthAllPass && pass
    print("  z=\(row.teeth) mate=\(row.mate): pitchAngle=\(pitchDeg)deg (expected \(row.expectedPitchDeg)) " +
          "apexAboveBase=\(apexAboveBase) mate.pr=\(matePr) diff=\(apexDiff) \(pass ? "PASS" : "FAIL")")
}
guard groundTruthAllPass else { fatalError("ground truth table check failed; see FAIL rows above") }
print("  PASS: all 5 rows match the issue's ground truth table exactly")
print("")

// ── 2. Non-right-angle structural check: pitch angles must sum to the shaft angle. ──────────
// This does not carry the same evidentiary weight as the ground-truth table (that closed form
// is only given, and only holds, at 90 degrees: apex1=pr(mate) reduces to cos(pitchAngle1) ==
// sin(pitchAngle2), i.e. pitchAngle1+pitchAngle2==90, which is specific to Sigma=90). Away from
// 90 degrees this file has no independently-sourced ground-truth number to check against, so it
// checks the structural necessary condition instead (both cones' half-angles must sum to the
// full shaft angle for the cones to be tangent along a common pitch line) plus, in section 3
// below, the world-space positioning check the issue asks for. Noted plainly: this is a lighter
// verification than the 90-degree case, not an equally strong one.
print("=== 2. Non-right-angle case: pitch angles sum to shaft angle (65deg, teeth 35/15) ===")
let shaftAngle65 = 65.0 * .pi / 180
let gA65 = GearGeometry(teeth: 35, mateTeeth: 15, shaftAngle: shaftAngle65)
let gB65 = GearGeometry(teeth: 15, mateTeeth: 35, shaftAngle: shaftAngle65)
let pitchSum = gA65.pitchAngle + gB65.pitchAngle
let pitchSumDiff = abs(pitchSum - shaftAngle65)
print("  pitchAngle(35t)=\(gA65.pitchAngle * 180 / .pi)deg pitchAngle(15t)=\(gB65.pitchAngle * 180 / .pi)deg sum=\(pitchSum * 180 / .pi)deg (target 65deg)")
guard pitchSumDiff < 1e-9 else { fatalError("pitch angles do not sum to the shaft angle: diff=\(pitchSumDiff)") }
print("  PASS: pitch angles sum to the shaft angle exactly")
print("")

// ── 3. Build real gears and mesh them: 90 degrees (16t/28t, mirrors #89 Example 2). ─────────
print("=== 3. Meshed pair at 90 degrees: 16t (mate 28) + 28t (mate 16, right_handed, backing) ===")
let gear16 = buildRouteC(GearParams(teeth: 16, mateTeeth: 28, spiralDeg: 35, slices: 12),
                          label: "gear16-mate28-90deg")
let gear28 = buildRouteC(GearParams(teeth: 28, mateTeeth: 16, spiralDeg: 35, slices: 12,
                                     rightHanded: true, backing: 3, coneBacking: true),
                          label: "gear28-mate16-90deg-RH-backed")

let frames16 = referenceFrames(gear16.g)
let frames28 = referenceFrames(gear28.g)
print("  gear16 frames: pitchbase=\(frames16.pitchbase) flattop=\(frames16.flattop) apex=\(frames16.apex)")
print("  gear28 frames: pitchbase=\(frames28.pitchbase) flattop=\(frames28.flattop) apex=\(frames28.apex)")

try ctx.add(gear16.finalShape, color: C.copper, name: "gear16 (raw, mate=28, 90deg)",
            referenceFrames: refFramesDict(frames16))
try ctx.add(gear28.finalShape, color: C.steel, name: "gear28 (raw, mate=16, 90deg, RH, backed)",
            referenceFrames: refFramesDict(frames28))

// BOSL2 Example 2's own idiom: the second-built (mate) member receives spin = 180/mate_teeth.
let matePhase90 = 180.0 / Double(gear28.g.teeth)
let (step16, step28) = meshPair(reference: frames16, mate: frames28, shaftAngle: .pi / 2,
                                 tiltAxis: SIMD3(1, 0, 0), matePhaseDeg: matePhase90)
let positioned16 = applyMeshStep(gear16.finalShape, step16)
let positioned28 = applyMeshStep(gear28.finalShape, step28)
try ctx.add(positioned16, color: C.copper, name: "gear16 (meshed, 90deg)")
try ctx.add(positioned28, color: C.steel, name: "gear28 (meshed, 90deg, phase=\(matePhase90)deg)")

// World-space apex agreement, as #88 explicitly asks for, alongside a note on what it does and
// does not prove. `meshPair` translates BOTH gears by the negative of their OWN computed apex
// height, so "the two positioned apex points coincide" is true by construction of the helper
// REGARDLESS of whether `apex` was computed correctly: translating a shape by -X necessarily
// puts whatever point was at height X at the origin, whether or not X is the true apex height.
// This check therefore exercises the TRANSFORM COMPOSITION (translate -> phase -> tilt, correct
// order, correct axes) rather than the gear geometry itself; section 1's ground-truth comparison
// is what actually falsifies a wrong apex formula. Both are worth having, for different reasons.
let worldApex16 = applyMeshStep(SIMD3(0, 0, frames16.apex), step16)
let worldApex28 = applyMeshStep(SIMD3(0, 0, frames28.apex), step28)
let apexWorldDiff = simd_length(worldApex16 - worldApex28)
print("  world-space apex: gear16->\(worldApex16) gear28->\(worldApex28) diff=\(apexWorldDiff)")
guard apexWorldDiff < 1e-9 else { fatalError("meshPair: positioned apexes disagree in world space by \(apexWorldDiff)") }
print("  PASS (transform-composition check, see comment above for what this does/does not prove)")
print("")

// ── 4. Build real gears and mesh them at a non-right angle (65deg, 35t/15t). ────────────────
print("=== 4. Meshed pair at 65 degrees: 35t (mate 15) + 15t (mate 35, right_handed) ===")
let gear35 = buildRouteC(GearParams(teeth: 35, mateTeeth: 15, shaftAngle: shaftAngle65,
                                     spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5),
                          label: "gear35-mate15-65deg")
let gear15 = buildRouteC(GearParams(teeth: 15, mateTeeth: 35, shaftAngle: shaftAngle65,
                                     spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5,
                                     rightHanded: true),
                          label: "gear15-mate35-65deg-RH")

let frames35 = referenceFrames(gear35.g)
let frames15 = referenceFrames(gear15.g)
print("  gear35 frames: pitchbase=\(frames35.pitchbase) flattop=\(frames35.flattop) apex=\(frames35.apex)")
print("  gear15 frames: pitchbase=\(frames15.pitchbase) flattop=\(frames15.flattop) apex=\(frames15.apex)")

try ctx.add(gear35.finalShape, color: C.brass, name: "gear35 (raw, mate=15, 65deg)",
            referenceFrames: refFramesDict(frames35))
try ctx.add(gear15.finalShape, color: C.gray, name: "gear15 (raw, mate=35, 65deg, RH)",
            referenceFrames: refFramesDict(frames15))

let matePhase65 = 180.0 / Double(gear15.g.teeth)
let (step35, step15) = meshPair(reference: frames35, mate: frames15, shaftAngle: shaftAngle65,
                                 tiltAxis: SIMD3(1, 0, 0), matePhaseDeg: matePhase65)
let positioned35 = applyMeshStep(gear35.finalShape, step35)
let positioned15 = applyMeshStep(gear15.finalShape, step15)
try ctx.add(positioned35, color: C.brass, name: "gear35 (meshed, 65deg)")
try ctx.add(positioned15, color: C.gray, name: "gear15 (meshed, 65deg, phase=\(matePhase65)deg)")

let worldApex35 = applyMeshStep(SIMD3(0, 0, frames35.apex), step35)
let worldApex15 = applyMeshStep(SIMD3(0, 0, frames15.apex), step15)
let apexWorldDiff65 = simd_length(worldApex35 - worldApex15)
print("  world-space apex: gear35->\(worldApex35) gear15->\(worldApex15) diff=\(apexWorldDiff65)")
guard apexWorldDiff65 < 1e-9 else { fatalError("meshPair: positioned apexes disagree in world space by \(apexWorldDiff65)") }
print("  PASS (transform-composition check; structural pitch-angle-sum check in section 2 is the geometry check for this angle)")
print("")

do {
    try ctx.emit(description: "Spike 88: bevel gear placement, pitchbase/flattop/apex reference frames + meshing helper")
} catch {
    print("ctx.emit failed: \(error)")
}

print("=== Done. Bodies written in add() order: gear16(raw), gear28(raw), gear16(meshed), gear28(meshed), gear35(raw), gear15(raw), gear35(meshed), gear15(meshed) ===")
