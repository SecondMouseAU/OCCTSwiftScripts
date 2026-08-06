// Spike 110: Route C at unequal mate_teeth, de-risking the blank away from 45 degrees
//
// Follow-on from #109. Route C (spikes/109-route-c.swift) reaches a valid solid, but every
// spike in this chain (#85 through #109) hardcoded `pitchAngle = .pi / 4`, i.e. mate_teeth ==
// teeth, a symmetric 45 degree miter pair. #89's Examples 2 and 3 need unequal pairs (16/28,
// 14/28), so this spike replaces the constant with BOSL2's real formula and asks: does Route
// C's blank, which was designed and validated ONLY at 45 degrees, still reach a valid solid
// away from it, at both extremes?
//
// pitch_angle = atan(sin(shaft_angle) / (mate_teeth/teeth + cos(shaft_angle)))
//   BOSL2 gears.scad:4142 (bevel_pitch_angle), used at gears.scad:2518. BOSL2 is BSD-2-Clause,
//   Copyright 2017-2019 Revar Desmera: https://github.com/BelfrySCAD/BOSL2/blob/master/gears.scad
//
// At shaft_angle = 90 degrees (this spike's default, matching every prior spike's implicit
// assumption) sin(90) = 1 and cos(90) = 0, so the formula reduces to atan(teeth/mate_teeth).
// Spike 85's own header already noted this reduction (line 116) without generalizing it; this
// spike is that generalization.
//
// Every declaration below through `buildBoreCylinder` is copied UNCHANGED in structure from
// spikes/109-route-c.swift (per #110's instruction to extend that file's approach rather than
// rewrite it); this file cannot `import` that spike script (a standalone Sources/Script/main.swift
// payload, not a module), so the duplication is deliberate, as it was for 109 copying from 86.
// The ONLY change to the copied code is `GearGeometry.init` gaining `mateTeeth`/`shaftAngle`
// parameters and computing `pitchAngle` from `bevelPitchAngle(...)` instead of the constant;
// every downstream function still consumes `g.pitchAngle` exactly as before, so slicePoint,
// flankPoint, radialPoint, meridianRZ, gapLocalProfile, buildFullBlank, buildCutterTool,
// buildBacking, buildBoreCylinder and HealthSnapshot are untouched byte-for-byte apart from
// GearGeometry's own call sites.
//
// ── FINDING: no failure boundary found; Route C's blank is sound away from 45 degrees ─────
// Every required build (36/36 regression, 16/28, 28/16, 14/28, 28/14) reaches a valid solid:
// solidCount == 1, isValid == true, analyze() clean (0 free/small edges, 0 small faces, 0
// self-intersections), no heal() anywhere. 36/36 matches #109's own numbers exactly, same
// volume (38232.985571431236) to every printed digit, since bevelPitchAngle(36,36,90) reduces
// to exactly pi/4 in floating point.
//
// The two STEEP unequal gears, the predicted risk case, are the cleanest results in the whole
// run: bore and backing on 28/16 (60.26deg) and 28/14 (63.43deg) match their analytic
// predictions to 1e-11/1e-12 percent, tighter than 36/36's own baseline. The two SHALLOW
// gears (16/28, 14/28) match well but not as tightly on bore (0.99% and 5.62%): both are the
// same already-diagnosed #109 effect, the bore's fixed 10mm radius exceeds the blank's local
// radius over part of its axis-touching span once the meridian is this tapered, not a new
// defect; the sign and mechanism match #109's own 16-tooth caveat, just larger because 14/28's
// taper is more pronounced.
//
// The sweep (Part 3) found no boundary anywhere in the tested range. Blank+cutter (cheap, no
// patternCut) stayed solid, valid, and clean at EVERY 2-degree step from 2 to 88 degrees, for
// 14/16/28/36 teeth (172 points, zero failures); axisSpan (the blank's own axis-touching
// height) shrinks smoothly toward 0 as pitch angle approaches 90 but never crosses zero or
// flips sign, so the pinch the issue worried about never inverts into a self-crossing profile,
// it just gets thinner. The full pipeline (patternCut included, expensive, so tested coarser)
// held at every one of 5/10/15/20/70/75/80/85 degrees too, well outside the 26.57-63.43 degree
// range #89 actually needs. Volume-vs-naive-prediction diff grows toward the steep extreme
// (2.7% at 5deg up to 8.9% at 85deg) but the gear is still solidCount==1, isValid, and clean at
// every point; that drift is a size effect (adjacent-cutter overlap, same mechanism #109 named
// for the 45 degree case), not a validity failure.
//
// Full tables in the #110 issue comment.
//
// Run:  swift run occtkit run spikes/110-unequal-mate-teeth.swift

import OCCTSwift
import ScriptHarness
import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Unbuffered stdout: a bad boolean can trap deep inside OCCT before Swift's stdio buffer
// flushes, which would otherwise silently swallow every measurement line printed before
// the crash. Same rationale as spikes 85-87/109.
setvbuf(stdout, nil, _IONBF, 0)

// ── Fixed gear parameters (identical to spike 109, for a head-to-head compare) ────────────
let module: Double            = 2
let pressureAngleDeg: Double  = 20
let slices: Int               = 5
let flankSamples: Int         = 14
let radialClearance: Double   = module * 0.25
let boreRadius: Double        = 10.0
let backingDepth: Double      = 5.0

let alpha = pressureAngleDeg * .pi / 180
func inv(_ a: Double) -> Double { tan(a) - a }

// ── NEW: BOSL2 bevel_pitch_angle, gears.scad:4142 ──────────────────────────────────────────
func bevelPitchAngle(teeth: Double, mateTeeth: Double, shaftAngle: Double) -> Double {
    atan(sin(shaftAngle) / (mateTeeth / teeth + cos(shaftAngle)))
}

// GearGeometry, slicePoint, flankPoint, radialPoint, meridianRZ, gapLocalProfile copied from
// spikes/109-route-c.swift (itself copied unchanged from spike 86); ONLY GearGeometry.init
// changed, to compute pitchAngle from bevelPitchAngle instead of the .pi/4 constant.
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

// Copied UNCHANGED from spike 86/109 (per-slice transform stack, gears.scad:2546-2564).
func slicePoint(local: SIMD2<Double>, u: Double, g: GearGeometry, toothAngle: Double) -> SIMD3<Double> {
    let transverse = u * local.x
    let radial = u * local.y

    let x0 = transverse
    let y0 = radial * cos(g.pitchAngle) + u * g.pr
    let z0 = radial * sin(g.pitchAngle) + g.pitchoff + (1 - u) * g.pr / tan(g.pitchAngle)

    let x1 = x0 * cos(toothAngle) - y0 * sin(toothAngle)
    let y1 = x0 * sin(toothAngle) + y0 * cos(toothAngle)

    return SIMD3(-x1, y1, z0)
}

// Copied UNCHANGED from spike 86/109.
func flankPoint(t: Double, rot: Double, mirror: Bool, baseR: Double) -> SIMD2<Double> {
    let x = baseR * (cos(t) + t * sin(t))
    let y = (mirror ? -1 : 1) * baseR * (sin(t) - t * cos(t))
    return SIMD2(x * cos(rot) - y * sin(rot), x * sin(rot) + y * cos(rot))
}
func radialPoint(angle: Double, radius: Double) -> SIMD2<Double> {
    SIMD2(radius * cos(angle), radius * sin(angle))
}

// Copied UNCHANGED from spike 86/109. Point on the meridian half-plane (a pitch-cone generator
// line) at station u and nominal (flat-profile) radius R, returned as (radius-from-axis, z).
func meridianRZ(u: Double, R: Double, g: GearGeometry) -> SIMD2<Double> {
    let p = slicePoint(local: SIMD2(0, R - g.pr), u: u, g: g, toothAngle: 0)
    return SIMD2(p.y, p.z)
}

// Copied UNCHANGED from spike 86/109.
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

// ── Full-body blank. Copied UNCHANGED from spike 109 (see that file's header for why the
// two axis-closing edges are flat rather than following the cone-taper generator line, and
// why z(rootR, u=1) = 0 identically for every teeth count). That identity does not depend on
// pitchAngle's value (pitchoff is defined exactly so the (rootR-pr)*sin(pitchAngle) term
// cancels for ANY angle), so it is expected to still hold away from 45 degrees; the sweep
// below checks whether the REST of the profile (innerRoot.z in particular) stays well-behaved.
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

// ── Tooth-space cutter. Copied UNCHANGED from spike 86/109. ───────────────────────────────
func buildCutterTool(_ g: GearGeometry, toothAngle: Double = 0) -> Shape? {
    let gapFlankOffset = .pi / (2 * Double(g.teeth)) - inv(alpha)
    let tTip = ((g.addR / g.baseR) * (g.addR / g.baseR) - 1).squareRoot()
    let rootExtRadius = g.rootR - radialClearance
    let tipExtRadius = g.addR + radialClearance

    let localProfile = gapLocalProfile(offset: gapFlankOffset, tTip: tTip,
                                        rootExtRadius: rootExtRadius, tipExtRadius: tipExtRadius, g: g)

    var wires: [Wire] = []
    for vi in 0...slices {
        let v = Double(vi) / Double(slices)
        let dist = g.oconeRad + v * (g.iconeRad - g.oconeRad)
        let u = dist / g.oconeRad
        let pts = localProfile.map { slicePoint(local: $0, u: u, g: g, toothAngle: toothAngle) }
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

// ── Backing. Copied UNCHANGED from spike 109 (adapted there from spike 87, spiral removed). ──
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

// ── Bore. Copied UNCHANGED from spike 109. ─────────────────────────────────────────────────
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

// ── Diagnostics. Copied UNCHANGED from spike 109. ──────────────────────────────────────────
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
// PART 1: pitch angle table, verified against #110's ground-truth table and the pair invariant
// ══════════════════════════════════════════════════════════════════════════════════════════
struct PitchAnglePair { let teeth: Int; let mate: Int; let expectedDeg: Double }
let pitchAngleTable: [PitchAnglePair] = [
    PitchAnglePair(teeth: 36, mate: 36, expectedDeg: 45.00),
    PitchAnglePair(teeth: 16, mate: 28, expectedDeg: 29.74),
    PitchAnglePair(teeth: 28, mate: 16, expectedDeg: 60.26),
    PitchAnglePair(teeth: 14, mate: 28, expectedDeg: 26.57),
    PitchAnglePair(teeth: 28, mate: 14, expectedDeg: 63.43),
]

print("=== Part 1: pitch angle table ===")
let shaftAngleDefault = Double.pi / 2
for p in pitchAngleTable {
    let angleRad = bevelPitchAngle(teeth: Double(p.teeth), mateTeeth: Double(p.mate), shaftAngle: shaftAngleDefault)
    let angleDeg = angleRad * 180 / .pi
    let diff = abs(angleDeg - p.expectedDeg)
    print("  teeth=\(p.teeth) mate=\(p.mate): computed=\(angleDeg) expected=\(p.expectedDeg) diff=\(diff)")
    guard diff < 0.005 else {
        fatalError("pitch angle mismatch: teeth=\(p.teeth) mate=\(p.mate) computed=\(angleDeg) expected=\(p.expectedDeg)")
    }
}

print("  invariant check (pair angles sum to shaft angle):")
let pairs: [(Int, Int)] = [(16, 28), (14, 28)]
for (t, m) in pairs {
    let a1 = bevelPitchAngle(teeth: Double(t), mateTeeth: Double(m), shaftAngle: shaftAngleDefault) * 180 / .pi
    let a2 = bevelPitchAngle(teeth: Double(m), mateTeeth: Double(t), shaftAngle: shaftAngleDefault) * 180 / .pi
    let sum = a1 + a2
    let shaftDeg = shaftAngleDefault * 180 / .pi
    print("    \(t)/\(m): \(a1) + \(a2) = \(sum) (shaft angle = \(shaftDeg))")
    guard abs(sum - shaftDeg) < 0.005 else {
        fatalError("invariant failed: \(t)/\(m) angles sum to \(sum), expected \(shaftDeg)")
    }
}
print("  PASS: all pitch angles match table to 2dp, both pair invariants hold")
print("")

// ══════════════════════════════════════════════════════════════════════════════════════════
// PART 2: full Route C build (blank, cutter, pattern-cut gear, bore, backing) at each
// required teeth/mate pair, matching #109's own acceptance checks generalized to mateTeeth.
// ══════════════════════════════════════════════════════════════════════════════════════════
struct RouteCResult {
    let teeth: Int
    let mateTeeth: Double
    let g: GearGeometry
    let blankHealth: HealthSnapshot
    let cutterHealth: HealthSnapshot
    let gearHealth: HealthSnapshot
    let predictedGearVolume: Double
    let boreApplied: Bool
    let boreRefinedPredicted: Double
    let boreActualDelta: Double
    let boreHealth: HealthSnapshot
    let backingApplied: Bool
    let backingPredicted: Double
    let backingActualDelta: Double
    let backingHealth: HealthSnapshot
    let coreMs: Double
    let finalShape: Shape
}

func buildRouteC(teeth: Int, mateTeeth: Double, shaftAngle: Double = .pi / 2) -> RouteCResult {
    let g = GearGeometry(teeth: teeth, mateTeeth: mateTeeth, shaftAngle: shaftAngle)
    let pitchDeg = g.pitchAngle * 180 / .pi

    let t0 = Date()
    guard let blank = buildFullBlank(g) else { fatalError("teeth=\(teeth) mate=\(mateTeeth): buildFullBlank failed") }
    let t1 = Date()
    let blankHealth = HealthSnapshot(blank)
    guard blankHealth.solidCount >= 1 else {
        fatalError("teeth=\(teeth) mate=\(mateTeeth) pitch=\(pitchDeg)deg: blank is not a solid (solidCount=\(blankHealth.solidCount)); refusing to use it as a boolean operand")
    }

    guard let cutter = buildCutterTool(g) else { fatalError("teeth=\(teeth) mate=\(mateTeeth): buildCutterTool failed") }
    let t2 = Date()
    let cutterHealth = HealthSnapshot(cutter)
    guard cutterHealth.solidCount >= 1 else {
        fatalError("teeth=\(teeth) mate=\(mateTeeth) pitch=\(pitchDeg)deg: tooth-space cutter is not a solid (solidCount=\(cutterHealth.solidCount)); refusing to use it as a cutting tool")
    }

    guard let gear = blank.circularPatternCut(tool: cutter, axisPoint: .zero,
                                              axisDirection: SIMD3(0, 0, 1), count: teeth) else {
        fatalError("teeth=\(teeth) mate=\(mateTeeth) pitch=\(pitchDeg)deg: circularPatternCut returned nil")
    }
    let t3 = Date()
    let gearHealth = HealthSnapshot(gear)

    print("teeth=\(teeth) mate=\(mateTeeth) pitchAngle=\(pitchDeg)deg:")
    blankHealth.describe("blank")
    cutterHealth.describe("cutter (single tooth space)")
    gearHealth.describe("gear (post pattern-cut, RAW, no heal)")

    let predictedGearVolume = blankHealth.volume - Double(teeth) * cutterHealth.volume
    let gearVolDiff = gearHealth.volume - predictedGearVolume
    let gearVolPct = abs(gearVolDiff) / predictedGearVolume * 100
    print("  volume check: blank=\(blankHealth.volume) - teeth*cutter=\(Double(teeth) * cutterHealth.volume) = predicted \(predictedGearVolume); actual=\(gearHealth.volume); diff=\(gearVolDiff) (\(gearVolPct)%)")

    guard gearHealth.solidCount >= 1, gearHealth.isValid else {
        fatalError("teeth=\(teeth) mate=\(mateTeeth) pitch=\(pitchDeg)deg: pattern-cut gear failed to be a valid solid without healing (solidCount=\(gearHealth.solidCount), isValid=\(gearHealth.isValid)); per house policy this is reported as a failure, not routed around with heal()")
    }

    // ── Bore, same refined-prediction logic as spike 109 (axis-touching z-span, not bbox). ──
    let preboreVol = gearHealth.volume
    let boreTool = buildBoreCylinder(gear, radius: boreRadius)
    let outerRootZ = meridianRZ(u: 1, R: g.rootR, g: g).y
    let uInner = g.iconeRad / g.oconeRad
    let innerRootZ = meridianRZ(u: uInner, R: g.rootR, g: g).y
    let boreRefinedPredicted = Double.pi * boreRadius * boreRadius * abs(innerRootZ - outerRootZ)
    var boredShape = gear
    var boreApplied = false
    var boreActualDelta = 0.0
    if let bored = gear.subtracting(boreTool), let postVol = bored.volume, postVol < preboreVol {
        boredShape = bored
        boreApplied = true
        boreActualDelta = preboreVol - postVol
    } else {
        print("  NOTE: teeth=\(teeth) mate=\(mateTeeth) bore subtract did not reduce volume (subtract returned nil, or volume uncomputable, or volume did not decrease)")
    }
    let boreHealth = HealthSnapshot(boredShape)
    boreHealth.describe("gear (post bore)")
    let boreRefinedPct = boreRefinedPredicted > 0 ? abs(boreActualDelta - boreRefinedPredicted) / boreRefinedPredicted * 100 : Double.nan
    print("  bore check: refined-predicted=\(boreRefinedPredicted) (pi*r^2*h, r=\(boreRadius), h=axis-span=\(abs(innerRootZ - outerRootZ))) actual-delta=\(boreActualDelta) diff%=\(boreRefinedPct) applied=\(boreApplied)")

    // ── Backing, same conical-frustum analytic check as spike 109. ──────────────────────────
    let preBackingVol = boreHealth.volume
    let br = buildBacking(g, backing: backingDepth, coneBacking: true)
    var backedShape = boredShape
    var backingApplied = false
    var backingActualDelta = 0.0
    if let unioned = boredShape.union(br.shape), let postVol = unioned.volume, postVol > preBackingVol {
        backedShape = unioned
        backingApplied = true
        backingActualDelta = postVol - preBackingVol
    } else {
        print("  NOTE: teeth=\(teeth) mate=\(mateTeeth) backing union did not increase volume (union returned nil, or volume uncomputable, or volume did not increase)")
    }
    let backingHealth = HealthSnapshot(backedShape)
    backingHealth.describe("gear (post backing)")
    let backingPct = abs(backingActualDelta - br.analyticVolume) / br.analyticVolume * 100
    print("  backing check: predicted=\(br.analyticVolume) (conical frustum r0=\(br.outerRadius) r1=\(br.farRadius) depth=\(backingDepth)) actual-delta=\(backingActualDelta) diff%=\(backingPct) applied=\(backingApplied)")

    let coreMs = t3.timeIntervalSince(t0) * 1000
    print("  timing: core-total=\(coreMs)ms")
    print("")

    return RouteCResult(
        teeth: teeth, mateTeeth: mateTeeth, g: g,
        blankHealth: blankHealth, cutterHealth: cutterHealth, gearHealth: gearHealth,
        predictedGearVolume: predictedGearVolume,
        boreApplied: boreApplied, boreRefinedPredicted: boreRefinedPredicted, boreActualDelta: boreActualDelta, boreHealth: boreHealth,
        backingApplied: backingApplied, backingPredicted: br.analyticVolume, backingActualDelta: backingActualDelta, backingHealth: backingHealth,
        coreMs: coreMs,
        finalShape: backedShape
    )
}

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Spike 110: bevel gear Route C, unequal mate_teeth",
    source: "OCCTSwiftScripts spike/110-unequal-mate-teeth",
    tags: ["spike", "gear", "bevel", "route-c", "unequal-mate-teeth"]
))
let C = ScriptContext.Colors.self

print("=== Part 2: required builds (36/36 regression + 4 unequal pairs) ===")
// (teeth, mateTeeth): 36/36 first as the regression check, then the two pairs #89 needs.
let requiredBuilds: [(Int, Double)] = [(36, 36), (16, 28), (28, 16), (14, 28), (28, 14)]
var results: [RouteCResult] = []
for (teeth, mate) in requiredBuilds {
    let r = buildRouteC(teeth: teeth, mateTeeth: mate)
    results.append(r)
    do {
        try ctx.add(r.finalShape, color: C.steel, name: "Route C gear \(teeth)t/mate\(Int(mate))t (bore+backing)")
    } catch {
        print("teeth=\(teeth) mate=\(mate): ctx.add failed: \(error)")
    }
}

do {
    try ctx.emit(description: "Spike 110: Route C unequal mate_teeth")
} catch {
    print("ctx.emit failed: \(error)")
}

print("=== Part 2 summary ===")
print("teeth,mateTeeth,pitchAngleDeg,solidCount(rawGear),isValid(rawGear),volume(rawGear),predictedVolume,volDiffPct,boreApplied,boreRefinedPredicted,boreActualDelta,boreRefinedPct,backingApplied,backingPredicted,backingActualDelta,backingPct,coreMs,finalClean")
for r in results {
    let volDiffPct = abs(r.gearHealth.volume - r.predictedGearVolume) / r.predictedGearVolume * 100
    let boreRefinedPct = r.boreRefinedPredicted > 0 ? abs(r.boreActualDelta - r.boreRefinedPredicted) / r.boreRefinedPredicted * 100 : Double.nan
    let backingPct = abs(r.backingActualDelta - r.backingPredicted) / r.backingPredicted * 100
    let pitchDeg = r.g.pitchAngle * 180 / .pi
    print("\(r.teeth),\(r.mateTeeth),\(pitchDeg),\(r.gearHealth.solidCount),\(r.gearHealth.isValid),\(r.gearHealth.volume),\(r.predictedGearVolume),\(volDiffPct),\(r.boreApplied),\(r.boreRefinedPredicted),\(r.boreActualDelta),\(boreRefinedPct),\(r.backingApplied),\(r.backingPredicted),\(r.backingActualDelta),\(backingPct),\(r.coreMs),\(r.backingHealth.clean)")
}
print("")

// ══════════════════════════════════════════════════════════════════════════════════════════
// PART 3: ratio sweep to find the failure boundary, if one exists.
//
// circularPatternCut dominates Route C's cost (#109 measured it at 4.3-10.5s per build); the
// blank revolve and single-tooth cutter loft are both sub-15ms. So the sweep runs in two
// passes: a fine, cheap pass over blank+cutter only (no patternCut) across a wide angle grid,
// to see where the geometry itself goes bad (nil build, self-intersection, non-solid, or the
// innerRoot.z sign flip the issue hypothesizes for the pinch getting worse); then a coarser,
// full-pipeline pass (patternCut included) at teeth counts and angles bracketing anything the
// cheap pass flagged, plus the two extremes of the sweep range.
//
// The sweep holds `teeth` fixed and varies `mateTeeth` (a Double, not required to be an
// integer teeth count, bevel_pitch_angle only uses the ratio) so that the SIZE of the gear
// under construction (module * teeth) stays fixed while pitchAngle scans across (0, 90) via
// pitchAngle = atan(teeth/mateTeeth) at the default 90 degree shaft angle.
struct GeometrySweepPoint {
    let teeth: Int
    let pitchDeg: Double
    let outerRootZ: Double
    let innerRootZ: Double
    let axisSpan: Double          // innerRootZ - outerRootZ; the blank's own axis-touching height
    let blankBuilt: Bool
    let blankSolid: Bool
    let blankClean: Bool
    let cutterBuilt: Bool
    let cutterSolid: Bool
    let cutterClean: Bool
}

func sweepBlankAndCutter(teeth: Int, pitchDeg: Double) -> GeometrySweepPoint {
    let pitchRad = pitchDeg * .pi / 180
    // Derive the mateTeeth that produces this exact pitch angle at shaftAngle=90:
    // pitchAngle = atan(teeth/mateTeeth)  =>  mateTeeth = teeth / tan(pitchAngle).
    let mate = Double(teeth) / tan(pitchRad)
    let g = GearGeometry(teeth: teeth, mateTeeth: mate)

    let uInner = g.iconeRad / g.oconeRad
    let outerRootZ = meridianRZ(u: 1, R: g.rootR, g: g).y
    let innerRootZ = meridianRZ(u: uInner, R: g.rootR, g: g).y

    var blankBuilt = false, blankSolid = false, blankClean = false
    var cutterBuilt = false, cutterSolid = false, cutterClean = false

    if let blank = buildFullBlank(g) {
        blankBuilt = true
        let h = HealthSnapshot(blank)
        blankSolid = h.solidCount >= 1 && h.isValid
        blankClean = h.clean
    }
    if let cutter = buildCutterTool(g) {
        cutterBuilt = true
        let h = HealthSnapshot(cutter)
        cutterSolid = h.solidCount >= 1 && h.isValid
        cutterClean = h.clean
    }

    return GeometrySweepPoint(
        teeth: teeth, pitchDeg: pitchDeg, outerRootZ: outerRootZ, innerRootZ: innerRootZ,
        axisSpan: innerRootZ - outerRootZ,
        blankBuilt: blankBuilt, blankSolid: blankSolid, blankClean: blankClean,
        cutterBuilt: cutterBuilt, cutterSolid: cutterSolid, cutterClean: cutterClean
    )
}

print("=== Part 3a: blank+cutter geometry sweep (cheap, no patternCut) ===")
print("teeth,pitchDeg,outerRootZ,innerRootZ,axisSpan,blankBuilt,blankSolid,blankClean,cutterBuilt,cutterSolid,cutterClean")
let sweepTeethCounts = [14, 16, 28, 36]
var sweepPoints: [GeometrySweepPoint] = []
for teeth in sweepTeethCounts {
    var angle = 2.0
    while angle <= 88.0 {
        let p = sweepBlankAndCutter(teeth: teeth, pitchDeg: angle)
        sweepPoints.append(p)
        print("\(p.teeth),\(p.pitchDeg),\(p.outerRootZ),\(p.innerRootZ),\(p.axisSpan),\(p.blankBuilt),\(p.blankSolid),\(p.blankClean),\(p.cutterBuilt),\(p.cutterSolid),\(p.cutterClean)")
        angle += 2.0
    }
}
print("")

let firstBadByTeeth = Dictionary(grouping: sweepPoints, by: { $0.teeth }).mapValues { pts -> (low: Double?, high: Double?) in
    let sorted = pts.sorted { $0.pitchDeg < $1.pitchDeg }
    let bad = sorted.filter { !($0.blankBuilt && $0.blankSolid && $0.cutterBuilt && $0.cutterSolid) }
    return (bad.filter { $0.pitchDeg < 45 }.map(\.pitchDeg).max(), bad.filter { $0.pitchDeg > 45 }.map(\.pitchDeg).min())
}
print("=== Part 3a summary: bad angle boundaries (blank+cutter only) per teeth count ===")
for teeth in sweepTeethCounts {
    let bounds = firstBadByTeeth[teeth] ?? (nil, nil)
    print("  teeth=\(teeth): shallow-side worst bad angle <=45deg: \(bounds.low.map { String($0) } ?? "none found"); steep-side worst bad angle >=45deg: \(bounds.high.map { String($0) } ?? "none found")")
}
print("")

// ── Part 3b: full-pipeline sweep (patternCut included) at teeth=28, coarser grid, plus the
// extremes of the range Part 3a swept. teeth=28 chosen since it appears on both the shallow
// (16/28, 14/28) and steep (28/16, 28/14) side of the required pairs.
struct FullSweepPoint {
    let teeth: Int
    let pitchDeg: Double
    let mateTeeth: Double
    let gearBuilt: Bool
    let gearSolid: Bool
    let gearValid: Bool
    let gearClean: Bool
    let volume: Double
    let predictedVolume: Double
    let volDiffPct: Double
    let coreMs: Double
}

func sweepFullPipeline(teeth: Int, pitchDeg: Double) -> FullSweepPoint {
    let pitchRad = pitchDeg * .pi / 180
    let mate = Double(teeth) / tan(pitchRad)
    let g = GearGeometry(teeth: teeth, mateTeeth: mate)

    let t0 = Date()
    guard let blank = buildFullBlank(g) else {
        return FullSweepPoint(teeth: teeth, pitchDeg: pitchDeg, mateTeeth: mate, gearBuilt: false, gearSolid: false, gearValid: false, gearClean: false, volume: .nan, predictedVolume: .nan, volDiffPct: .nan, coreMs: 0)
    }
    let blankHealth = HealthSnapshot(blank)
    guard blankHealth.solidCount >= 1 else {
        return FullSweepPoint(teeth: teeth, pitchDeg: pitchDeg, mateTeeth: mate, gearBuilt: false, gearSolid: false, gearValid: false, gearClean: false, volume: .nan, predictedVolume: .nan, volDiffPct: .nan, coreMs: 0)
    }
    guard let cutter = buildCutterTool(g) else {
        return FullSweepPoint(teeth: teeth, pitchDeg: pitchDeg, mateTeeth: mate, gearBuilt: false, gearSolid: false, gearValid: false, gearClean: false, volume: .nan, predictedVolume: .nan, volDiffPct: .nan, coreMs: 0)
    }
    let cutterHealth = HealthSnapshot(cutter)
    guard cutterHealth.solidCount >= 1 else {
        return FullSweepPoint(teeth: teeth, pitchDeg: pitchDeg, mateTeeth: mate, gearBuilt: false, gearSolid: false, gearValid: false, gearClean: false, volume: .nan, predictedVolume: .nan, volDiffPct: .nan, coreMs: 0)
    }
    guard let gear = blank.circularPatternCut(tool: cutter, axisPoint: .zero, axisDirection: SIMD3(0, 0, 1), count: teeth) else {
        return FullSweepPoint(teeth: teeth, pitchDeg: pitchDeg, mateTeeth: mate, gearBuilt: false, gearSolid: false, gearValid: false, gearClean: false, volume: .nan, predictedVolume: .nan, volDiffPct: .nan, coreMs: 0)
    }
    let coreMs = Date().timeIntervalSince(t0) * 1000
    let gearHealth = HealthSnapshot(gear)
    let predicted = blankHealth.volume - Double(teeth) * cutterHealth.volume
    let volDiffPct = abs(gearHealth.volume - predicted) / predicted * 100
    return FullSweepPoint(
        teeth: teeth, pitchDeg: pitchDeg, mateTeeth: mate,
        gearBuilt: true, gearSolid: gearHealth.solidCount >= 1, gearValid: gearHealth.isValid, gearClean: gearHealth.clean,
        volume: gearHealth.volume, predictedVolume: predicted, volDiffPct: volDiffPct, coreMs: coreMs
    )
}

print("=== Part 3b: full-pipeline sweep (patternCut included), teeth=28, extremes beyond Part 2's required pairs ===")
print("teeth,pitchDeg,mateTeeth,gearBuilt,gearSolid,gearValid,gearClean,volume,predictedVolume,volDiffPct,coreMs")
// Part 2 already covers 26.57-63.43deg (the required pairs) at full resolution; this pass
// pushes further out toward both extremes, since circularPatternCut is the expensive step
// (#109 measured 4.3-55s per call depending on system load) and re-testing the already-covered
// middle would not add information toward finding a boundary outside it.
let fullSweepAngles: [Double] = [5, 10, 15, 20, 70, 75, 80, 85]
var fullSweepPoints: [FullSweepPoint] = []
for angle in fullSweepAngles {
    let p = sweepFullPipeline(teeth: 28, pitchDeg: angle)
    fullSweepPoints.append(p)
    print("\(p.teeth),\(p.pitchDeg),\(p.mateTeeth),\(p.gearBuilt),\(p.gearSolid),\(p.gearValid),\(p.gearClean),\(p.volume),\(p.predictedVolume),\(p.volDiffPct),\(p.coreMs)")
}
print("")

print("=== Part 3b summary: full-pipeline failures ===")
let fullFailures = fullSweepPoints.filter { !($0.gearBuilt && $0.gearSolid && $0.gearValid) }
if fullFailures.isEmpty {
    print("  none: full pipeline (blank+cutter+patternCut) succeeded at every swept angle (\(fullSweepAngles))")
} else {
    for f in fullFailures {
        print("  FAIL at pitch=\(f.pitchDeg)deg (mateTeeth=\(f.mateTeeth)): built=\(f.gearBuilt) solid=\(f.gearSolid) valid=\(f.gearValid)")
    }
}
print("")
print("=== Done ===")
