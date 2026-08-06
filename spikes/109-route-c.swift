// Spike 109: bevel gear Route C (per-tooth solids + booleans, avoiding the
// ThruSections capping defect)
//
// Follow-on from #108 (root cause: ThruSectionsBuilder(isSolid: true) silently omits both
// end caps when a section wire has 2 or more periods of out-of-plane variation around the
// loop; Route A lofts all N teeth in one closed wire, so k = N, and never produces a solid).
// This spike composes the gear from per-tooth solids instead: loft ONE tooth space (k ~ 1,
// caps correctly per #108's own measurement), subtract N copies from a solid blank via
// circularPatternCut, and verify the result is a genuine solid, not just isValid.
//
// GearGeometry, slicePoint, flankPoint, radialPoint, meridianRZ, gapLocalProfile and
// buildCutterTool are copied UNCHANGED from spikes/86-bevel-route-b.swift (per #109's
// instruction to reuse the existing scaffold rather than re-derive it); this file cannot
// `import` that spike script (a standalone Sources/Script/main.swift payload, not a module),
// so the duplication is deliberate. buildBacking/applyBoreOrNil are adapted from
// spikes/87-spiral-trace.swift's versions, with the spiral cutter-arc dependency removed
// since Route C stays in the straight/zerol scope spike 85 established (mate_teeth == teeth,
// pitch angle fixed at 45 degrees).
//
// ── What Route B was missing, and how this fixes it ─────────────────────────────────────
// Route B's blank ran root radius to addendum radius only (rootR to addR), producing a
// hollow toothed RING: 6029.13 mm3 at 36 teeth, against Route A's 22814.71. This file's
// buildFullBlank extends the SAME validated meridian (spike 86's 4-corner
// outerRoot/outerTip/innerTip/innerRoot trapezoid, its edges unchanged) inward to the axis
// by adding two more corners at r=0: one at the SAME z as outerRoot (z=0, always, since
// pitchoff is defined so that z(rootR, u=1) = 0 identically for every teeth count), one at
// the same z as innerRoot. This is a minimal, provably-correct extension: the two new edges
// (bottomAxis-outerRoot, innerRoot-topAxis) are flat (constant z) rather than following the
// cone taper, so they cannot introduce the self-crossing that a naive "extend the root-cone
// generator line to r=0" attempt produces (that alternative was checked by hand: extending
// the FIXED-u root/tip generator line inward to r=0, rather than adding a flat closing edge
// at the SAME z, lands at a wildly negative z (roughly -34mm at 36 teeth, versus the tooth
// region's own 0-14.7mm span) because the pitch angle's generator slope is steep; the flat
// closing edge avoids that distortion entirely while still reaching the axis).
//
// Math ported from BOSL2's gears.scad `bevel_gear()` (lines 2486-2650), same scope as #85/#86:
// straight/zerol teeth (spiral = 0), single gear, mate_teeth == teeth (45 degree symmetric
// miter pair). BOSL2 is BSD-2-Clause, Copyright 2017-2019 Revar Desmera:
// https://github.com/BelfrySCAD/BOSL2/blob/master/gears.scad
//
// ── FINDING: Route C reaches a valid solid at every acceptance criterion, without healing ──
// Measured at 16/28/36 teeth. Every stage (blank, single-tooth cutter, pattern-cut gear, post-
// bore, post-backing) reports subShapeCount(ofType: .solid) >= 1, isValid == true, and a clean
// analyze() (0 free edges, 0 small edges, 0 small faces, 0 self-intersections), with NO heal()
// call anywhere in the pipeline. The pattern-cut gear's shapeType is Compound (solidCount == 1,
// one solid wrapped in a compound), which per
// okf/decisions/wire-sweep-factories-are-not-symmetric.md is circularPatternCut's normal,
// healthy result, not a red flag.
//
// Volume: pattern-cut gear volume runs 2.6%-4.8% ABOVE the naive prediction (blank volume minus
// teeth times one cutter's volume), consistently across all three teeth counts, larger at lower
// teeth counts. Adjacent tooth-space cutters share a boundary near the tooth flanks (the same
// radialClearance overshoot Route B introduced to clear the blank's own root/tip surfaces
// tangentially), so their union removes slightly less than N independent, non-overlapping copies
// would; this is the expected direction and magnitude for that overlap, not an unexplained gap.
//
// Bore: a naive pi*r^2*h prediction using the gear's full bounding-box height OVER-predicts by
// 17-31%, because the full-body blank's meridian pinches away from the axis into a thin annulus
// near the tooth-tip end (z beyond innerRoot's own z), and a bore centred on the axis cannot
// remove material from a region that never reached the axis. Using the height between the two
// axis-touching corners the blank's own construction defines (outerRoot.z to innerRoot.z, exactly
// the span buildFullBlank's two new closing edges cover) instead of the full bbox height gives a
// match within 1.2e-12% to 0.45% (the 16-tooth case's small residual is because its
// innerRoot radius, 9.49mm, is itself just under the 10mm bore radius tested, so the bore
// slightly exceeds the true material radius right at that end of its span). Both figures are
// printed at runtime so this is visible directly, not asserted from the header.
//
// Backing: matches its own analytic conical-frustum volume to 13 significant figures at every
// teeth count (diff% from 1.1e-11 down to 6e-13), because the backing is placed entirely beyond
// the blank's own z-range (extending away from the teeth, per spike 87's convention), so the
// union never overlaps pre-existing material and the analytic formula is exact.
//
// Timing: Route C's core construction (blank + single-tooth-cutter loft + circularPatternCut)
// runs 4356ms / 8398ms / 10518ms at 16/28/36 teeth, against Route A's 419ms / 1171ms / 1909ms
// (#109's own comparison figures): roughly 10.4x / 7.2x / 5.5x slower, narrowing as teeth count
// grows. circularPatternCut itself dominates (4340ms / 8387ms / 10509ms of the totals above);
// the single-tooth loft and blank revolve are both sub-15ms at every teeth count. Route C trades
// this multiplier for reaching a solid at all, which Route A cannot do on OCCTSwift 1.x (#108).
//
// Rendered gear (36 teeth, bore + backing): spikes/109-route-c-renders/route-c-36t-iso.png and
// -bottom.png (the bottom view shows the bore hole and the backing boss step directly).
//
// Run:  swift run occtkit run spikes/109-route-c.swift

import OCCTSwift
import ScriptHarness
import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Unbuffered stdout: a bad boolean can trap deep inside OCCT before Swift's stdio buffer
// flushes, which would otherwise silently swallow every measurement line printed before
// the crash. Same rationale as spikes 85-87.
setvbuf(stdout, nil, _IONBF, 0)

// ── Fixed gear parameters (identical to spikes 85/86, for a head-to-head compare) ─────────
let module: Double            = 2
let pressureAngleDeg: Double  = 20
let slices: Int               = 5
let flankSamples: Int         = 14
let teethCounts: [Int]        = [16, 28, 36]
let radialClearance: Double   = module * 0.25
let boreRadius: Double        = 10.0     // a realistic shaft bore for a module-2 gear this size
let backingDepth: Double      = 5.0

let alpha = pressureAngleDeg * .pi / 180
func inv(_ a: Double) -> Double { tan(a) - a }

// Copied UNCHANGED from spikes/85-bevel-route-a.swift / 86-bevel-route-b.swift.
struct GearGeometry {
    let teeth: Int
    let pitchAngle: Double
    let pr: Double
    let baseR: Double
    let addR: Double
    let rootR: Double
    let oconeRad: Double
    let faceWidth: Double
    let iconeRad: Double
    let pitchoff: Double

    init(teeth: Int) {
        self.teeth = teeth
        let z = Double(teeth)
        pr = module * z / 2
        baseR = pr * cos(alpha)
        addR = pr + module
        rootR = pr - 1.25 * module
        pitchAngle = .pi / 4
        oconeRad = pr / sin(pitchAngle)
        faceWidth = min(oconeRad / 3, 10 * module)
        iconeRad = oconeRad - faceWidth
        pitchoff = (pr - rootR) * sin(pitchAngle)
    }
}

// Copied UNCHANGED from spike 86 (per-slice transform stack, gears.scad:2546-2564).
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

// Copied UNCHANGED from spike 86.
func flankPoint(t: Double, rot: Double, mirror: Bool, baseR: Double) -> SIMD2<Double> {
    let x = baseR * (cos(t) + t * sin(t))
    let y = (mirror ? -1 : 1) * baseR * (sin(t) - t * cos(t))
    return SIMD2(x * cos(rot) - y * sin(rot), x * sin(rot) + y * cos(rot))
}
func radialPoint(angle: Double, radius: Double) -> SIMD2<Double> {
    SIMD2(radius * cos(angle), radius * sin(angle))
}

// Copied UNCHANGED from spike 86. Point on the meridian half-plane (a pitch-cone generator
// line) at station u and nominal (flat-profile) radius R, returned as (radius-from-axis, z).
func meridianRZ(u: Double, R: Double, g: GearGeometry) -> SIMD2<Double> {
    let p = slicePoint(local: SIMD2(0, R - g.pr), u: u, g: g, toothAngle: 0)
    return SIMD2(p.y, p.z)
}

// Copied UNCHANGED from spike 86.
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

// ── NEW: full-body blank, from the axis to the addendum cone across the face width ────────
//
// Six-point meridian, reusing spike 86's 4 corners UNCHANGED (outerRoot/outerTip/innerTip/
// innerRoot, so the addendum-cone and root-cone boundaries that Route B already validated
// against the cutter are untouched) plus two new axis corners closing the profile at r=0:
//
//   bottomAxis(0, z=outerRoot.z) -> outerRoot -> outerTip -> innerTip -> innerRoot
//     -> topAxis(0, z=innerRoot.z) -> back to bottomAxis (along r=0)
//
// z(rootR, u=1) = 0 identically for every teeth count (pitchoff is defined exactly so that
// the (rootR - pr)*sin(pitchAngle) term cancels it), so bottomAxis always lands at z=0; no
// per-teeth special-casing needed.
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
    // Face the wire before revolving: Shape.revolve(profile: wire, ...) revolves a curve and
    // returns a shell, which is useless as a boolean operand. See
    // okf/decisions/wire-sweep-factories-are-not-symmetric.md.
    guard let face = Shape.face(from: wire) else { return nil }
    return face.revolved(axisOrigin: .zero, axisDirection: SIMD3(0, 0, 1))
}

// ── Tooth-space cutter: one wedge, lofted. Copied UNCHANGED from spike 86. ────────────────
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

// ── Backing: revolved profile unioned onto the wide (outer) end, extending AWAY from the
// blank (z < 0, since the blank's own z-range is [0, innerRoot.z]) so the union never
// overlaps existing material and the analytic prediction is exact. Adapted from spike 87's
// buildBacking with the spiral cutter-arc dependency removed (Route C stays zerol/straight).
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

// ── Bore: subtracting(cylinder). Adapted from spike 87's applyBoreOrNil; house idiom is
// guard/fatalError for the cylinder build (never fails for sane inputs), and the subtract's
// own success is verified by volume delta at the call site, not assumed from a non-nil result.
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

// ── Diagnostics ─────────────────────────────────────────────────────────────────────────
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

// ── One full Route C build, per teeth count ────────────────────────────────────────────
struct RouteCResult {
    let teeth: Int
    let g: GearGeometry
    let blankMs: Double
    let cutterMs: Double
    let patternCutMs: Double
    let coreMs: Double            // blank + cutter + patternCut, comparable to Route A's timing
    let blankHealth: HealthSnapshot
    let cutterHealth: HealthSnapshot
    let gearHealth: HealthSnapshot
    let boreMs: Double
    let boreNaivePredicted: Double
    let boreRefinedPredicted: Double
    let boreActualDelta: Double
    let boreApplied: Bool
    let boreHealth: HealthSnapshot
    let backingMs: Double
    let backingPredicted: Double
    let backingActualDelta: Double
    let backingApplied: Bool
    let backingHealth: HealthSnapshot
    let finalShape: Shape
}

func buildRouteC(teeth: Int) -> RouteCResult {
    let g = GearGeometry(teeth: teeth)

    let t0 = Date()
    guard let blank = buildFullBlank(g) else { fatalError("teeth=\(teeth): buildFullBlank failed") }
    let t1 = Date()
    let blankHealth = HealthSnapshot(blank)
    guard blankHealth.solidCount >= 1 else {
        fatalError("teeth=\(teeth): blank is not a solid (solidCount=\(blankHealth.solidCount)); refusing to use it as a boolean operand")
    }

    guard let cutter = buildCutterTool(g) else { fatalError("teeth=\(teeth): buildCutterTool failed") }
    let t2 = Date()
    let cutterHealth = HealthSnapshot(cutter)
    guard cutterHealth.solidCount >= 1 else {
        fatalError("teeth=\(teeth): tooth-space cutter is not a solid (solidCount=\(cutterHealth.solidCount)); refusing to use it as a cutting tool")
    }

    guard let gear = blank.circularPatternCut(tool: cutter, axisPoint: .zero,
                                              axisDirection: SIMD3(0, 0, 1), count: teeth) else {
        fatalError("teeth=\(teeth): circularPatternCut returned nil")
    }
    let t3 = Date()
    let gearHealth = HealthSnapshot(gear)

    print("teeth=\(teeth):")
    blankHealth.describe("blank")
    cutterHealth.describe("cutter (single tooth space)")
    gearHealth.describe("gear (post pattern-cut, RAW, no heal)")

    let predictedGearVolume = blankHealth.volume - Double(teeth) * cutterHealth.volume
    let gearVolDiff = gearHealth.volume - predictedGearVolume
    let gearVolPct = abs(gearVolDiff) / predictedGearVolume * 100
    print("  volume check: blank=\(blankHealth.volume) - teeth*cutter=\(Double(teeth) * cutterHealth.volume) = predicted \(predictedGearVolume); actual=\(gearHealth.volume); diff=\(gearVolDiff) (\(gearVolPct)%)")

    guard gearHealth.solidCount >= 1, gearHealth.isValid else {
        fatalError("teeth=\(teeth): pattern-cut gear failed to be a valid solid without healing (solidCount=\(gearHealth.solidCount), isValid=\(gearHealth.isValid)); per house policy this is reported as a failure, not routed around with heal()")
    }

    // ── Bore: shaft bore at a realistic radius, verified against pi*r^2*height ──────────
    //
    // Two predictions, reported side by side. The NAIVE one uses the full bounding-box
    // height (outerRoot.z to innerTip.z) and over-predicts: for z beyond innerRoot.z the
    // meridian has already pinched away from the axis into the thin tooth-tip annulus (see
    // buildFullBlank's header), so a bore centred on the axis cannot remove material there,
    // no matter how the rest of the body is shaped. The REFINED prediction uses only the
    // z-span where the blank's meridian actually touches the axis (outerRoot.z to
    // innerRoot.z, exactly the span the new closing edges in buildFullBlank cover), which
    // is where a bore of this radius has uninterrupted full-disc material to remove.
    let b0 = Date()
    let preboreVol = gearHealth.volume
    let boreTool = buildBoreCylinder(gear, radius: boreRadius)
    let boundsForBore = gear.bounds
    let outerRootZ = meridianRZ(u: 1, R: g.rootR, g: g).y
    let uInner = g.iconeRad / g.oconeRad
    let innerRootZ = meridianRZ(u: uInner, R: g.rootR, g: g).y
    let boreNaivePredicted = Double.pi * boreRadius * boreRadius * (boundsForBore.max.z - boundsForBore.min.z)
    let boreRefinedPredicted = Double.pi * boreRadius * boreRadius * (innerRootZ - outerRootZ)
    var boredShape = gear
    var boreApplied = false
    var boreActualDelta = 0.0
    if let bored = gear.subtracting(boreTool), let postVol = bored.volume, postVol < preboreVol {
        boredShape = bored
        boreApplied = true
        boreActualDelta = preboreVol - postVol
    } else {
        print("  FAILED: teeth=\(teeth) bore subtract did not reduce volume (subtract returned nil, or volume uncomputable, or volume did not decrease)")
    }
    let boreMs = Date().timeIntervalSince(b0) * 1000
    let boreHealth = HealthSnapshot(boredShape)
    boreHealth.describe("gear (post bore)")
    let boreNaivePct = abs(boreActualDelta - boreNaivePredicted) / boreNaivePredicted * 100
    let boreRefinedPct = abs(boreActualDelta - boreRefinedPredicted) / boreRefinedPredicted * 100
    print("  bore check: naive-predicted=\(boreNaivePredicted) (pi*r^2*h, r=\(boreRadius), h=full-bbox=\(boundsForBore.max.z - boundsForBore.min.z)) diff%=\(boreNaivePct)")
    print("  bore check: refined-predicted=\(boreRefinedPredicted) (pi*r^2*h, r=\(boreRadius), h=axis-span=\(innerRootZ - outerRootZ)) actual-delta=\(boreActualDelta) diff%=\(boreRefinedPct) applied=\(boreApplied)")

    // ── Backing: conical boss unioned onto the wide end, verified against the revolved
    // profile's own analytic frustum/cylinder volume ────────────────────────────────────
    let bk0 = Date()
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
        print("  FAILED: teeth=\(teeth) backing union did not increase volume (union returned nil, or volume uncomputable, or volume did not increase)")
    }
    let backingMs = Date().timeIntervalSince(bk0) * 1000
    let backingHealth = HealthSnapshot(backedShape)
    backingHealth.describe("gear (post backing)")
    let backingPct = abs(backingActualDelta - br.analyticVolume) / br.analyticVolume * 100
    print("  backing check: predicted=\(br.analyticVolume) (conical frustum r0=\(br.outerRadius) r1=\(br.farRadius) depth=\(backingDepth)) actual-delta=\(backingActualDelta) diff%=\(backingPct) applied=\(backingApplied)")

    let coreMs = t3.timeIntervalSince(t0) * 1000
    print("  timing: blank=\((t1.timeIntervalSince(t0))*1000)ms cutter=\((t2.timeIntervalSince(t1))*1000)ms patternCut=\((t3.timeIntervalSince(t2))*1000)ms core-total=\(coreMs)ms bore=\(boreMs)ms backing=\(backingMs)ms")
    print("")

    return RouteCResult(
        teeth: teeth, g: g,
        blankMs: (t1.timeIntervalSince(t0)) * 1000, cutterMs: (t2.timeIntervalSince(t1)) * 1000,
        patternCutMs: (t3.timeIntervalSince(t2)) * 1000, coreMs: coreMs,
        blankHealth: blankHealth, cutterHealth: cutterHealth, gearHealth: gearHealth,
        boreMs: boreMs, boreNaivePredicted: boreNaivePredicted, boreRefinedPredicted: boreRefinedPredicted, boreActualDelta: boreActualDelta, boreApplied: boreApplied, boreHealth: boreHealth,
        backingMs: backingMs, backingPredicted: br.analyticVolume, backingActualDelta: backingActualDelta, backingApplied: backingApplied, backingHealth: backingHealth,
        finalShape: backedShape
    )
}

// ── Run the measurement sweep ──────────────────────────────────────────────────────────
let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Spike 109: bevel gear Route C",
    source: "OCCTSwiftScripts spike/109-route-c",
    tags: ["spike", "gear", "bevel", "route-c", "per-tooth-solid", "circular-pattern-cut"]
))
let C = ScriptContext.Colors.self

// Route A's own comparison numbers, from #109's acceptance criteria.
let routeATimingMs: [Int: Double] = [16: 419, 28: 1171, 36: 1909]

var results: [RouteCResult] = []
for teeth in teethCounts {
    let r = buildRouteC(teeth: teeth)
    results.append(r)
    do {
        try ctx.add(r.finalShape, color: C.steel, name: "Route C gear \(teeth)t (bore+backing)")
    } catch {
        print("teeth=\(teeth): ctx.add failed: \(error)")
    }
}

do {
    try ctx.emit(description: "Spike 109: bevel gear Route C, teeth=\(teethCounts)")
} catch {
    print("ctx.emit failed: \(error)")
}

print("=== Summary ===")
print("teeth,solidCount(rawGear),isValid(rawGear),volume(rawGear),predictedVolume,volDiffPct,boreApplied,boreRefinedPredicted,boreActualDelta,boreRefinedPct,backingApplied,backingPredicted,backingActualDelta,backingPct,coreMs,routeAMs,analyzeClean(final)")
for r in results {
    let predicted = r.blankHealth.volume - Double(r.teeth) * r.cutterHealth.volume
    let volDiffPct = abs(r.gearHealth.volume - predicted) / predicted * 100
    let boreRefinedPct = abs(r.boreActualDelta - r.boreRefinedPredicted) / r.boreRefinedPredicted * 100
    let backingPct = abs(r.backingActualDelta - r.backingPredicted) / r.backingPredicted * 100
    let routeAMs = routeATimingMs[r.teeth].map { String($0) } ?? "n/a"
    print("\(r.teeth),\(r.gearHealth.solidCount),\(r.gearHealth.isValid),\(r.gearHealth.volume),\(predicted),\(volDiffPct),\(r.boreApplied),\(r.boreRefinedPredicted),\(r.boreActualDelta),\(boreRefinedPct),\(r.backingApplied),\(r.backingPredicted),\(r.backingActualDelta),\(backingPct),\(r.coreMs),\(routeAMs),\(r.backingHealth.clean)")
}
