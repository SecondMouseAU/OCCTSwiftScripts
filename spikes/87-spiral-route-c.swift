// Spike 87 (re-sited): spiral tooth trace grafted onto Route C
//
// Follow-on from the #87 comment thread. The spiral trace built in spikes/87-spiral-trace.swift
// was grafted onto Route A (the all-N-teeth ThruSections loft), and Route A has since been shown
// unable to reach a valid solid on OCCTSwift 1.x at all (#108, OCCTSwift#702). That is why that
// spike's backing and bore criteria failed: the operand was a shell, not because the backing or
// bore code was wrong (it was verified correct in isolation there). This spike re-sites the same
// cutter-arc math onto Route C (spikes/109-route-c.swift, extended for unequal mate_teeth in
// spikes/110-unequal-mate-teeth.swift), where backing and bore are already known to work.
//
// Math ported from BOSL2's gears.scad `bevel_gear()` (lines 2486-2650): the cutter-arc spiral
// trace at gears.scad:2528-2537, `bevel_pitch_angle` at gears.scad:4142, the backing formula at
// gears.scad:2602-2613, and the right_handed mirror at gears.scad:2640. BOSL2 is BSD-2-Clause,
// Copyright 2017-2019 Revar Desmera: https://github.com/BelfrySCAD/BOSL2/blob/master/gears.scad
//
// ── What actually moved, versus spikes/110-unequal-mate-teeth.swift ────────────────────────
// Every declaration through `buildBoreCylinder` is copied UNCHANGED in structure from spike 110
// (per #87's instruction: "extend this lineage... do not edit 109 or 110"; this file cannot
// `import` a standalone spike script, so the duplication is deliberate, as it was for 109
// copying from 86 and 110 copying from 109). The graft is narrow, exactly where the issue said
// it would be:
//
//   1. `slicePoint` gains an `ang` parameter (ported from spikes/87-spiral-trace.swift's own
//      version) that inserts a `zrot(ang/sin(pitchAngle))` step between the base transform and
//      the per-tooth `toothAngle` rotation. `ang` only ever varies along z (the axial direction);
//      it never appears in `z0`, so every call that must stay axisymmetric (the blank's own
//      `meridianRZ`, and `buildBacking` through it) passes `ang: 0` explicitly and is otherwise
//      untouched.
//   2. `buildCutterTool` no longer interpolates `dist` linearly between `oconeRad` and
//      `iconeRad`. It samples `cutterStation(cutter, v:)` instead (ported unchanged from spike
//      87), which returns both the station's `u` AND its `ang`, and threads `ang` into every
//      `slicePoint` call for that station. `buildFullBlank` is untouched: the blank is an
//      axisymmetric solid of revolution and the spiral trace only shapes the per-tooth cutter
//      that gets subtracted from it.
//
// `CutterRadiusSpec` / `CutterArc` / `buildCutterArc` / `resolveSlices` / `cutterStation` are
// copied UNCHANGED from spikes/87-spiral-trace.swift; none of that math depended on Route A.
//
// ── The three tooth forms and the trap the issue named ──────────────────────────────────────
// Two parameters, three forms, matching gears.scad:2528-2530 and BOSL2's own resolution order:
//   spiral > 0, cutterRadius > 0 (defaulted or explicit)  -> spiral
//   spiral = 0, cutterRadius > 0 (defaulted or explicit)  -> zerol (still curved, zero spiral
//                                                             angle at the midpoint)
//   cutterRadius = 0                                       -> straight (BOSL2 fakes it with
//                                                             cutterRadius = faceWidth*100,
//                                                             forces slices = 1)
// #89's Example 1 passes spiral=0 with cutter_radius defaulted, which resolves to
// faceWidth*2/cos(spiral): that is ZEROL, not straight, the trap the issue called out by name.
// This file's test matrix builds a genuine straight case (cutterRadiusSpec = .straight) and a
// genuine zerol case (cutterRadiusSpec = .defaulted, spiralDeg = 0) as two DIFFERENT builds, not
// one relabeled as the other.
//
// Also per the issue: BOSL2's docs say `slices` defaults to 1 (gears.scad:2391) but the CODE
// defaults to 5 (gears.scad:2498, `slices==0 -> 5` under `is_undef`... concretely `slices=5` in
// the parameter list). Mirrored here: `slices` defaults to 5 and is force-overridden to 1 only
// when `cutterRadiusSpec == .straight`, matching the code, not the docs.
//
// ── House policy compliance (okf/policies, okf/decisions) ───────────────────────────────────
// No `heal()` anywhere in this file: Route C reaches a solid without one (#109/#110), and
// healed() silently demotes Solid to Shell (#108, OCCTSwift#702). No edge classifier is used
// (concave-edge-classifier-can-select-wrong-edges.md doesn't apply here, nothing in this file
// fillets or chamfers, but noting the policy was checked). backing/bore/mirror all revolve or
// build a FACE, never a wire (wire-sweep-factories-are-not-symmetric.md). Every Shape-returning
// call that can fail uses guard/fatalError; the only `??` in this file is a plain numeric
// default (`p.mateTeeth ?? Double(p.teeth)`), never on a geometry operation. Every build asserts
// `subShapeCount(ofType: .solid) >= 1` before calling anything a solid, not just `isValid` and a
// positive volume (the trap that let spike 85 ship undetected shells for two spikes running).
//
// Run:  swift run occtkit run spikes/87-spiral-route-c.swift

import OCCTSwift
import ScriptHarness
import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Unbuffered stdout: a bad boolean can trap deep inside OCCT before Swift's stdio buffer
// flushes, which would otherwise silently swallow every measurement line printed before the
// crash. Same rationale as spikes 85-87/109/110.
setvbuf(stdout, nil, _IONBF, 0)

// ── Fixed gear parameters (identical to spike 109/110, for a head-to-head compare) ─────────
let module: Double            = 2
let pressureAngleDeg: Double  = 20
let flankSamples: Int         = 14
let radialClearance: Double   = module * 0.25

let alpha = pressureAngleDeg * .pi / 180
func inv(_ a: Double) -> Double { tan(a) - a }

// ── bevel_pitch_angle, gears.scad:4142. Copied UNCHANGED from spike 110. ───────────────────
func bevelPitchAngle(teeth: Double, mateTeeth: Double, shaftAngle: Double) -> Double {
    atan(sin(shaftAngle) / (mateTeeth / teeth + cos(shaftAngle)))
}

// GearGeometry copied UNCHANGED from spike 110.
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

// ── The spiral trace: port of gears.scad:2528-2537. Copied UNCHANGED from
// spikes/87-spiral-trace.swift; this math never depended on Route A. ───────────────────────
//
//   cutter_radius = is_undef(cutter_radius) ? face_width*2/cos(spiral)
//                 : cutter_radius==0 ? face_width*100 : cutter_radius,
//   midpr  = (icone_rad + ocone_rad) / 2,
//   radcp  = [0, midpr] + polar_to_xy(cutter_radius, 180+spiral),
//   angC1  = law_of_cosines(a=cutter_radius, b=norm(radcp), c=ocone_rad),
//   angC2  = law_of_cosines(a=cutter_radius, b=norm(radcp), c=icone_rad),
//   sang   = v_theta(radcp) - (180-angC1),
//   eang   = v_theta(radcp) - (180-angC2),
//
// law_of_cosines(a,b,c) (trigonometry.scad:48-53) returns the angle opposite side c:
// acos(constrain((a*a+b*b-c*c)/(2*a*b), -1, 1)). v_theta (vectors.scad:239-241) is atan2.
// polar_to_xy (coords.scad:171-178) is [r*cos(theta), r*sin(theta)]. All angles below are
// radians throughout (Swift trig, unlike OpenSCAD, takes radians).
enum CutterRadiusSpec {
    case defaulted            // BOSL2 undef: face_width * 2 / cos(spiral)
    case straight              // BOSL2 0: face_width * 100, forces slices = 1
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

// slices = cutter_radius==0 ? 1 : slices (gears.scad:2498). Checked against the ORIGINAL input
// spec, before the cutterRadius==0 -> faceWidth*100 substitution.
func resolveSlices(_ slices: Int, cutterRadiusSpec: CutterRadiusSpec) -> Int {
    if case .straight = cutterRadiusSpec { return 1 }
    return slices
}

// Station (u, ang) at arc-fraction v in [0,1]: p = radcp + polar_to_xy(cutterRadius,
// lerp(sang,eang,v)); ang = v_theta(p) - 90 degrees (here: - pi/2); u = norm(p) / oconeRad.
func cutterStation(_ cutter: CutterArc, v: Double) -> (u: Double, ang: Double) {
    let theta = cutter.sang + (cutter.eang - cutter.sang) * v
    let p = cutter.radcp + SIMD2(cutter.cutterRadius * cos(theta), cutter.cutterRadius * sin(theta))
    let dist = (p.x * p.x + p.y * p.y).squareRoot()
    return (dist, atan2(p.y, p.x) - .pi / 2)
}

// Per-slice transform stack, gears.scad:2546-2564: scale(u) -> xrot(pitchAngle) -> back(u*pr) ->
// zrot(ang/sin(pitchAngle)) -> up(pitchoff + (1-u)*pr/tan(pitchAngle)), then per-tooth zrot(tooth)
// and a final xflip(). THE GRAFT: `ang` is now a real parameter again (spike 110 had fixed it
// at an implicit 0 by omitting the zrot step entirely, since Route C stayed in straight-only
// scope). Every call site that must stay axisymmetric (the blank's meridian, via meridianRZ)
// passes `ang: 0` explicitly; only buildCutterTool's per-station calls pass a real `ang` from
// cutterStation.
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

    return SIMD3(-x1, y1, z0)   // xflip: negate x
}

// Copied UNCHANGED from spike 110.
func flankPoint(t: Double, rot: Double, mirror: Bool, baseR: Double) -> SIMD2<Double> {
    let x = baseR * (cos(t) + t * sin(t))
    let y = (mirror ? -1 : 1) * baseR * (sin(t) - t * cos(t))
    return SIMD2(x * cos(rot) - y * sin(rot), x * sin(rot) + y * cos(rot))
}
func radialPoint(angle: Double, radius: Double) -> SIMD2<Double> {
    SIMD2(radius * cos(angle), radius * sin(angle))
}

// Point on the meridian half-plane (a pitch-cone generator line) at station u and nominal
// (flat-profile) radius R, returned as (radius-from-axis, z). Passes ang: 0 explicitly: the
// blank is axisymmetric and must never see the spiral trace's angular offset.
func meridianRZ(u: Double, R: Double, g: GearGeometry) -> SIMD2<Double> {
    let p = slicePoint(local: SIMD2(0, R - g.pr), u: u, ang: 0, g: g, toothAngle: 0)
    return SIMD2(p.y, p.z)
}

// Copied UNCHANGED from spike 110.
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

// ── Full-body blank. Copied UNCHANGED from spike 109/110: unaffected by the spiral trace,
// since it is an axisymmetric solid of revolution and the trace only shapes the cutter. ────
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

// ── Tooth-space cutter. THE OTHER HALF OF THE GRAFT: station sampling now comes from the
// cutter arc (cutterStation), not linear interpolation of `dist`, and `ang` threads into every
// slicePoint call for that station. Structure otherwise unchanged from spike 109/110. ───────
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

// ── Backing. Copied UNCHANGED from spike 109/110 (originally adapted there from spike 87,
// spiral removed; now re-adapted back here, still spiral-free since backing is axisymmetric). ──
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

// ── Bore. Copied UNCHANGED from spike 109/110. ─────────────────────────────────────────────
func buildBoreCylinder(_ shape: Shape, radius: Double) -> Shape {
    let b = shape.bounds
    let extra = 2.0
    let height = (b.max.z - b.min.z) + 2 * extra
    guard let bore = Shape.cylinder(at: SIMD3(0, 0, b.min.z - extra), direction: SIMD3(0, 0, 1),
                                    radius: radius, height: height) else {
        fatalError("shaft bore cylinder failed (r=\(radius), height=\(height))")
    }
    return bore
}

// ── Diagnostics. Copied UNCHANGED from spike 109/110. ──────────────────────────────────────
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

    var clean: Bool {
        freeEdgeCount == 0 && smallEdgeCount == 0 && smallFaceCount == 0 && selfIntersectionCount == 0
    }

    func describe(_ label: String) {
        print("  [\(label)] isValid=\(isValid) shapeType=\(shapeType) solidCount=\(solidCount) faceCount=\(faceCount) volume=\(volume)")
        print("  [\(label)] freeEdges=\(freeEdgeCount) smallEdges=\(smallEdgeCount) smallFaces=\(smallFaceCount) selfIntersections=\(selfIntersectionCount) clean=\(clean)")
    }
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// The driver: one gear build, end to end, spiral trace + backing + bore + handedness all
// composed on Route C.
// ══════════════════════════════════════════════════════════════════════════════════════════
struct GearParams {
    var teeth: Int
    var mateTeeth: Double? = nil          // nil -> Double(teeth), the symmetric miter pair
    var shaftAngle: Double = .pi / 2
    var spiralDeg: Double = 35
    var cutterRadiusSpec: CutterRadiusSpec = .defaulted
    var slices: Int = 5                    // gears.scad:2498's CODE default, not the docs' 1
    var rightHanded: Bool = false
    var backing: Double? = nil
    var coneBacking: Bool = true
    var shaftDiam: Double = 0
}

struct RouteCResult {
    let label: String
    let params: GearParams
    let g: GearGeometry
    let cutterRadius: Double
    let usedSlices: Int
    let blankHealth: HealthSnapshot
    let cutterHealth: HealthSnapshot
    let gearHealth: HealthSnapshot          // raw pattern-cut gear, pre bore/backing/handedness
    let predictedGearVolume: Double
    let boreAttempted: Bool
    let boreApplied: Bool
    let boreAnalyticVolume: Double?
    let boreActualDelta: Double?
    let backingAttempted: Bool
    let backingApplied: Bool
    let backingAnalyticVolume: Double?
    let backingActualDelta: Double?
    let coreMs: Double
    let totalMs: Double
    let finalHealth: HealthSnapshot
    let finalShape: Shape
}

func buildRouteC(_ p: GearParams, label: String) -> RouteCResult {
    let mateTeeth = p.mateTeeth ?? Double(p.teeth)
    let g = GearGeometry(teeth: p.teeth, mateTeeth: mateTeeth, shaftAngle: p.shaftAngle)
    let pitchDeg = g.pitchAngle * 180 / .pi
    let spiralRad = p.spiralDeg * .pi / 180
    let cutter = buildCutterArc(g: g, spiralRad: spiralRad, cutterRadiusSpec: p.cutterRadiusSpec)
    let slices = resolveSlices(p.slices, cutterRadiusSpec: p.cutterRadiusSpec)

    let t0 = Date()
    guard let blank = buildFullBlank(g) else { fatalError("\(label): buildFullBlank failed") }
    let blankHealth = HealthSnapshot(blank)
    guard blankHealth.solidCount >= 1 else {
        fatalError("\(label): blank is not a solid (solidCount=\(blankHealth.solidCount)); refusing to use it as a boolean operand")
    }

    guard let cutterShape = buildCutterTool(g, cutter: cutter, slices: slices) else {
        fatalError("\(label): buildCutterTool failed")
    }
    let cutterHealth = HealthSnapshot(cutterShape)
    guard cutterHealth.solidCount >= 1 else {
        fatalError("\(label): tooth-space cutter is not a solid (solidCount=\(cutterHealth.solidCount)); refusing to use it as a cutting tool")
    }

    guard let gear = blank.circularPatternCut(tool: cutterShape, axisPoint: .zero,
                                              axisDirection: SIMD3(0, 0, 1), count: p.teeth) else {
        fatalError("\(label): circularPatternCut returned nil")
    }
    let t1 = Date()
    let gearHealth = HealthSnapshot(gear)
    guard gearHealth.solidCount >= 1, gearHealth.isValid else {
        fatalError("\(label): pattern-cut gear failed to be a valid solid without healing (solidCount=\(gearHealth.solidCount), isValid=\(gearHealth.isValid)); per house policy this is reported as a failure, not routed around with heal()")
    }
    let predictedGearVolume = blankHealth.volume - Double(p.teeth) * cutterHealth.volume

    print("[\(label)] teeth=\(p.teeth) mateTeeth=\(mateTeeth) pitchAngle=\(pitchDeg)deg spiralDeg=\(p.spiralDeg) cutterRadius=\(cutter.cutterRadius) slices(used)=\(slices)")
    blankHealth.describe("blank")
    cutterHealth.describe("cutter (single tooth space)")
    gearHealth.describe("gear (post pattern-cut, RAW, no heal)")
    let gearVolDiffPct = abs(gearHealth.volume - predictedGearVolume) / predictedGearVolume * 100
    print("  volume check: blank=\(blankHealth.volume) - teeth*cutter=\(Double(p.teeth) * cutterHealth.volume) = predicted \(predictedGearVolume); actual=\(gearHealth.volume); diffPct=\(gearVolDiffPct)")

    var shape = gear

    // ── Bore: shaftDiam, verified against pi*r^2*h using the blank's own axis-touching z-span
    // (not the bounding box: the naive full-bbox prediction over-predicts by 21-31%, per #109). ──
    var boreAttempted = false
    var boreApplied = false
    var boreAnalyticVolume: Double? = nil
    var boreActualDelta: Double? = nil
    if p.shaftDiam > 0 {
        boreAttempted = true
        let preVol = shape.volume ?? Double.nan
        let radius = p.shaftDiam / 2
        let outerRootZ = meridianRZ(u: 1, R: g.rootR, g: g).y
        let uInner = g.iconeRad / g.oconeRad
        let innerRootZ = meridianRZ(u: uInner, R: g.rootR, g: g).y
        let axisSpan = abs(innerRootZ - outerRootZ)
        let predicted = Double.pi * radius * radius * axisSpan
        boreAnalyticVolume = predicted
        let boreTool = buildBoreCylinder(shape, radius: radius)
        if let bored = shape.subtracting(boreTool), let postVol = bored.volume, postVol < preVol {
            shape = bored
            boreApplied = true
            let delta = preVol - postVol
            boreActualDelta = delta
            let pct = abs(delta - predicted) / predicted * 100
            print("  bore check: predicted=\(predicted) (pi*r^2*h, r=\(radius), axisSpan=\(axisSpan)) actual-delta=\(delta) diffPct=\(pct)")
        } else {
            print("  NOTE: \(label) bore subtract did not reduce volume as expected (subtract returned nil, or volume uncomputable, or volume did not decrease)")
        }
    }

    // ── Backing: conical or cylindrical, verified against the analytic frustum/cylinder. ────
    var backingAttempted = false
    var backingApplied = false
    var backingAnalyticVolume: Double? = nil
    var backingActualDelta: Double? = nil
    if let backing = p.backing {
        backingAttempted = true
        let preVol = shape.volume ?? Double.nan
        let br = buildBacking(g, backing: backing, coneBacking: p.coneBacking)
        backingAnalyticVolume = br.analyticVolume
        if let unioned = shape.union(br.shape), let postVol = unioned.volume, postVol > preVol {
            shape = unioned
            backingApplied = true
            let delta = postVol - preVol
            backingActualDelta = delta
            let pct = abs(delta - br.analyticVolume) / br.analyticVolume * 100
            print("  backing check: predicted=\(br.analyticVolume) (coneBacking=\(p.coneBacking), r0=\(br.outerRadius), r1=\(br.farRadius), depth=\(backing)) actual-delta=\(delta) diffPct=\(pct)")
        } else {
            print("  NOTE: \(label) backing union did not increase volume as expected (union returned nil, or volume uncomputable, or volume did not increase)")
        }
    }

    // ── Handedness: mirror across the plane containing the gear axis. right_handed=false is
    // the untouched baseline; right_handed=true mirrors the fully-composed (bore+backing
    // included) shape, verified by volume below and by an explicit vertex check at the call
    // site for the dedicated handedness test. ─────────────────────────────────────────────
    if p.rightHanded {
        guard let mirrored = shape.mirrored(planeNormal: SIMD3(1, 0, 0)) else {
            fatalError("\(label): handedness mirror failed")
        }
        shape = mirrored
    }

    let t2 = Date()
    let finalHealth = HealthSnapshot(shape)
    let coreMs = t1.timeIntervalSince(t0) * 1000
    let totalMs = t2.timeIntervalSince(t0) * 1000
    print("  final: isValid=\(finalHealth.isValid) shapeType=\(finalHealth.shapeType) solidCount=\(finalHealth.solidCount) volume=\(finalHealth.volume)")
    print("  timing: core(blank+cutter+patternCut)=\(coreMs)ms total(+bore+backing+handedness)=\(totalMs)ms")
    print("")

    return RouteCResult(
        label: label, params: p, g: g, cutterRadius: cutter.cutterRadius, usedSlices: slices,
        blankHealth: blankHealth, cutterHealth: cutterHealth, gearHealth: gearHealth,
        predictedGearVolume: predictedGearVolume,
        boreAttempted: boreAttempted, boreApplied: boreApplied,
        boreAnalyticVolume: boreAnalyticVolume, boreActualDelta: boreActualDelta,
        backingAttempted: backingAttempted, backingApplied: backingApplied,
        backingAnalyticVolume: backingAnalyticVolume, backingActualDelta: backingActualDelta,
        coreMs: coreMs, totalMs: totalMs,
        finalHealth: finalHealth, finalShape: shape
    )
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// Run the measurement sweep
// ══════════════════════════════════════════════════════════════════════════════════════════
let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Spike 87 (re-sited): spiral trace on Route C",
    source: "OCCTSwiftScripts spike/87-spiral-on-route-c",
    tags: ["spike", "gear", "bevel", "spiral", "route-c", "backing", "handedness", "bore"]
))
let C = ScriptContext.Colors.self

func addResult(_ r: RouteCResult, color: [Float]) {
    do {
        try ctx.add(r.finalShape, color: color, name: r.label)
    } catch {
        print("  ctx.add failed for \(r.label): \(error)")
    }
}

print("=== 1. Tooth form matrix (teeth=36, mate=36, 45deg pair): straight / zerol / spiral ===")

// Straight: cutterRadiusSpec=.straight forces slices->1 and cutterRadius=faceWidth*100
// regardless of the `slices` passed in. This is the regression anchor: the raw pattern-cut
// gear (pre bore/backing) must still match 38232.985571431236, the figure #109 and #110 both
// produced with a spiral-free, purely-linear-interpolated cutter station.
let straight = buildRouteC(GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .straight, slices: 5),
                            label: "straight-36t")
addResult(straight, color: C.steel)
let regressionExpected = 38232.985571431236
let regressionDiff = abs(straight.gearHealth.volume - regressionExpected)
let regressionPct = regressionDiff / regressionExpected * 100
print(">>> regression check: expected \(regressionExpected) mm3, got \(straight.gearHealth.volume) mm3, diff=\(regressionDiff) (\(regressionPct)%)")
print("")

// Zerol: spiral=0 with a DEFAULTED (non-degenerate) cutter radius: faceWidth*2/cos(0) =
// faceWidth*2. Curved trace, symmetric, zero spiral angle at the midpoint. THIS is #89
// Example 1's tooth form, not straight; the trap the issue named by name.
let zerol = buildRouteC(GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5),
                         label: "zerol-36t")
addResult(zerol, color: C.brass)

// Spiral at slices=12, the deliverable examples' setting, at all three required tooth counts.
print("=== 2. Spiral tooth form at slices=12 (16t, 28t, 36t; the deliverable examples' setting) ===")
let spiral16 = buildRouteC(GearParams(teeth: 16, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12),
                            label: "spiral-16t-s12")
addResult(spiral16, color: C.copper)

let spiral28 = buildRouteC(GearParams(teeth: 28, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12),
                            label: "spiral-28t-s12")
addResult(spiral28, color: C.copper)

let spiral36 = buildRouteC(GearParams(teeth: 36, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12),
                            label: "spiral-36t-s12")
addResult(spiral36, color: C.copper)

// Three forms differ from each other in volume: if not, the arc is not actually being applied.
print("=== 2b. Tooth-form divergence check (36t, raw pattern-cut gear, pre bore/backing) ===")
let straightVsZerol = abs(straight.gearHealth.volume - zerol.gearHealth.volume)
let zerolVsSpiral = abs(zerol.gearHealth.volume - spiral36.gearHealth.volume)
let straightVsSpiral = abs(straight.gearHealth.volume - spiral36.gearHealth.volume)
print("  straight=\(straight.gearHealth.volume) zerol=\(zerol.gearHealth.volume) spiral=\(spiral36.gearHealth.volume)")
print("  |straight-zerol|=\(straightVsZerol) |zerol-spiral|=\(zerolVsSpiral) |straight-spiral|=\(straightVsSpiral)")
guard straightVsZerol > 1e-6, zerolVsSpiral > 1e-6, straightVsSpiral > 1e-6 else {
    fatalError("tooth forms did not diverge in volume; the cutter arc is not being applied")
}
print("  PASS: all three forms have distinct volumes (the arc is being applied, not a no-op)")
print("")

// ── 3. Handedness: rightHanded=true must mirror with identical volume AND a vertex-level
// X sign flip (trap #4: volume alone would not rule out right_handed silently doing nothing). ──
print("=== 3. Handedness: rightHanded=true, verified by volume and by a vertex X sign-flip ===")
let spiral36RH = buildRouteC(GearParams(teeth: 36, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12, rightHanded: true),
                              label: "spiral-36t-s12-RH")
addResult(spiral36RH, color: C.yellow)
let handednessVolDiff = abs(spiral36.finalHealth.volume - spiral36RH.finalHealth.volume)
print("  volume: base=\(spiral36.finalHealth.volume) mirrored=\(spiral36RH.finalHealth.volume) diff=\(handednessVolDiff)")
guard handednessVolDiff < 1e-6 else {
    fatalError("handedness mirror changed volume by \(handednessVolDiff); expected exact match")
}

// Pick the vertex with the LARGEST |x| in the base shape, not subShapes(...).first: a bevel
// gear blank's revolve seam sits exactly on the x=0 mirror plane (its profile is defined at
// x=0 in buildFullBlank, before being revolved about Z), so the first-enumerated vertex can
// trivially satisfy "x sign-flipped" (0 == -0) without the check meaning anything, which is
// exactly what an earlier version of this check did. The tooth flanks are off-axis and give a
// genuinely nonzero x to check against. Then find its counterpart in the mirrored shape by
// matching (y, z), since an X-plane mirror leaves y and z untouched, rather than assuming
// subShapes() enumerates both shapes in the same order.
let baseVerts = spiral36.finalShape.subShapes(ofType: .vertex).map { $0.vertexPoint }
let mirroredVerts = spiral36RH.finalShape.subShapes(ofType: .vertex).map { $0.vertexPoint }
print("  vertex counts: base=\(baseVerts.count) mirrored=\(mirroredVerts.count)")
guard baseVerts.count == mirroredVerts.count else {
    fatalError("handedness mirror changed the vertex count (base=\(baseVerts.count), mirrored=\(mirroredVerts.count))")
}
guard let baseV = baseVerts.max(by: { abs($0.x) < abs($1.x) }) else {
    fatalError("could not extract any vertex point from the base shape")
}
guard let matched = mirroredVerts.first(where: { abs($0.y - baseV.y) < 1e-6 && abs($0.z - baseV.z) < 1e-6 }) else {
    fatalError("no vertex in the mirrored shape matches base vertex \(baseV) on (y, z)")
}
print("  vertex (max |x| in base): base=\(baseV) mirrored-match=\(matched)")
let xSignFlipped = abs(baseV.x - (-matched.x)) < 1e-6
let yzUnchanged = abs(baseV.y - matched.y) < 1e-6 && abs(baseV.z - matched.z) < 1e-6
print("  x sign-flip exact: \(xSignFlipped)  y/z unchanged: \(yzUnchanged)")
guard xSignFlipped, yzUnchanged else {
    fatalError("handedness mirror did not produce an exact per-vertex X sign flip")
}
print("  PASS: volume-preserving AND exact vertex-level X sign flip (non-trivial vertex, |x|=\(abs(baseV.x)))")
print("")

// ── 4. Backing: conical AND cylindrical, on the zerol base (faster to iterate). ─────────────
print("=== 4. Backing: conical vs cylindrical ===")
let backingConical = buildRouteC(GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5,
                                             backing: 5, coneBacking: true),
                                  label: "zerol-36t-backing-conical")
addResult(backingConical, color: C.orange)
guard backingConical.backingApplied else { fatalError("conical backing did not apply") }

let backingCylindrical = buildRouteC(GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5,
                                                 backing: 5, coneBacking: false),
                                      label: "zerol-36t-backing-cylindrical")
addResult(backingCylindrical, color: C.orange)
guard backingCylindrical.backingApplied else { fatalError("cylindrical backing did not apply") }
print("  PASS: both backing forms applied (conical delta=\(backingConical.backingActualDelta ?? .nan), cylindrical delta=\(backingCylindrical.backingActualDelta ?? .nan))")
print("")

// ── 5. Bore: shaftDiam, verified against pi*r^2*h with the blank's axis-touching span. ──────
print("=== 5. Bore: shaftDiam cut, verified against pi*r^2*h (axis span, not bounding box) ===")
let boreTest = buildRouteC(GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5, shaftDiam: 10),
                            label: "zerol-36t-bore")
addResult(boreTest, color: C.gray)
guard boreTest.boreApplied else { fatalError("bore did not apply") }
print("  PASS: bore applied (delta=\(boreTest.boreActualDelta ?? .nan) against predicted \(boreTest.boreAnalyticVolume ?? .nan))")
print("")

// ── 6. Integration: spiral + backing + bore + right_handed together, one gear, at slices=12. ──
print("=== 6. Integration: spiral + backing + bore + right_handed together, one gear, slices=12 ===")
let integrationGear = buildRouteC(GearParams(teeth: 28, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12,
                                              rightHanded: true, backing: 4, coneBacking: true, shaftDiam: 6),
                                   label: "spiral-28t-integration")
addResult(integrationGear, color: C.yellow)
guard integrationGear.boreApplied, integrationGear.backingApplied else {
    fatalError("integration build: bore or backing did not apply (bore=\(integrationGear.boreApplied), backing=\(integrationGear.backingApplied))")
}
print("  PASS: spiral + conical backing + bore + right_handed all composed on one gear")
print("")

do {
    try ctx.emit(description: "Spike 87 (re-sited): spiral trace + backing/handedness/bore, on Route C")
} catch {
    print("ctx.emit failed: \(error)")
}

print("=== Done. Bodies written in add() order: straight, zerol, spiral16, spiral28, spiral36, spiral36RH, backingConical, backingCylindrical, boreTest, integrationGear ===")
