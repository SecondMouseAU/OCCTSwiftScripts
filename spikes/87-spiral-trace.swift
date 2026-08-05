// Spike 87: spiral tooth trace + backing / handedness / bore, on Route A
//
// Part of the BOSL2 bevel gear port epic (#84). Builds on spikes/85-bevel-route-a.swift
// (Route A: ThruSectionsBuilder loft, decided winner per #86's comment thread) and answers
// #87: add the lengthwise tooth trace (straight / zerol / spiral), plus backing, right_handed
// mirroring, and shaft_diam bore, since those are what the three deliverable examples in #89
// need.
//
// Math ported from BOSL2's gears.scad `bevel_gear()` (lines 2486-2650), specifically the
// cutter-arc spiral trace at gears.scad:2528-2537, the backing formula at gears.scad:2602-2613
// (reimplemented as a revolved profile per this spike's task, not a literal vertex-arithmetic
// port), and the right_handed mirror at gears.scad:2640. BOSL2 is BSD-2-Clause, Copyright
// 2017-2019 Revar Desmera: https://github.com/BelfrySCAD/BOSL2/blob/master/gears.scad
//
// GearGeometry, toothLocalProfile, and the base per-slice transform are carried forward
// UNCHANGED from spike 85 (not rewritten): mate_teeth == teeth is still assumed (a symmetric
// miter pair, pitch angle fixed at 45 degrees). Generalizing to mate_teeth != teeth (needed
// for #89's Examples 2 and 3, which pair unequal tooth counts) is explicitly out of scope for
// #87's own acceptance criteria and is not attempted here; it would change GearGeometry's
// pitch_angle formula, not anything this spike touches. Recorded as a known gap for whoever
// picks up #89.
//
// The spiral trace (this spike's actual job): a circle of radius `cutterRadius`, offset from
// the mid-cone radius by the `spiral` angle, crosses the outer and inner cone radii; the arc
// between those crossings is the lengthwise tooth trace, modelling a Gleason face-mill cutter.
// Each slice station samples a point on that arc via law-of-cosines (buildCutterArc below);
// `ang`, the point's angular position, feeds a `zrot(ang/sin(pitchAngle))` step inserted into
// slicePoint's transform stack; spike 85 hard-coded this at 0 as its documented simplification.
// Two parameters give three tooth forms: spiral>0 & cutterRadius>0 = spiral; spiral=0 &
// cutterRadius>0 = zerol (still curved, zero spiral angle at the midpoint); cutterRadius=0 =
// straight, which BOSL2 fakes with cutterRadius = faceWidth*100 and forces slices=1
// (gears.scad:2391 docs say slices defaults to 1; the code at gears.scad:2498 defaults to 5.
// Mirrored here: slices defaults to 5, is caller-settable, and gets force-overridden to 1 only
// when cutterRadiusSpec is .straight, matching the CODE not the docs).
//
// Backing, handedness, and bore all follow the three constraints learned since #85/#86 were
// written (see okf/decisions/): backing revolves a FACE, not a wire, since revolving a wire
// returns a shell and booleans against a shell silently under-cut (wire-sweep-factories-are-not-
// symmetric.md); every Shape-returning call that can fail uses guard/fatalError, no `??`
// fallback (four recipes shipped wrong output behind one this week); no edge classifier is used
// anywhere in this file (concave-edge-classifier-can-select-wrong-edges.md), backing/bore/mirror
// are all built from explicit geometry, not edge selection.
//
// CORRECTION to #85/#86: Route A's gear body is a hollow toothed RING, not "the whole gear
// body" reaching the axis. That claim was inferred from Route A's volume being larger than
// Route B's rim-only blank, never checked directly. `render-preview` on this spike's own output
// shows an unambiguous washer/ring shape with an open centre (see the #87 issue comment), and
// `Shape.classify(point:)` at the axis reports "inside" while the render shows empty space there
// -- itself evidence the shape's topology is not a well-formed 2-manifold in the way isValid/
// classify/volume all separately assume. The two loft end-cap wires are NON-PLANAR (z varies
// with the profile's radial coordinate; see slicePoint below), and whatever surface
// ThruSectionsBuilder fits to close each of them does not extend down to the axis the way a flat
// 2D face-from-wire would. Free-edge count is reliably 0 (a genuinely closed 2-manifold), so this
// is not a missing-cap/open-tube defect either; the honest description is an internally
// inconsistent but formally-closed shape, and it is the most likely root cause of the boolean
// finding below.
//
// FINDING (this spike): Route A's loft body is not a safe boolean operand, at any tooth count
// or flank-sample density tried. `heal()` reports isValid==true with the correct volume and a
// clean analyze() (matches spike 85), but it silently downgrades shapeType from Solid to Shell
// (subShapeCount(ofType: .solid) == 0). Every topology-repair path tried to get a genuine Solid
// back out of that Shell (fixSolid(), solidFromShellFixed(), Shape.solidFromShell(), upgraded(),
// unified(), sewn(tolerance:) at 5 tolerances from 1e-6 to 0.5, and coarser flank sampling down
// to 1 sample/flank at 8 teeth) either keeps it a Shell, or relabels it Solid while isValid stays
// false and analyze() reports hasInvalidTopology==true. Unioning or subtracting against ANY of
// these candidates either returns nil outright, or "succeeds" while silently dropping the other
// operand's volume or splitting the result into the wrong solid count. A plain circular 2-section
// loft (no teeth) was run as a control through the identical pipeline: isValid==true immediately
// (no heal needed), and union/subtract both work exactly as expected. So this is specific to the
// gear's own B-Rep (the many-reflex-vertex zigzag ring wire), not a generic ThruSectionsBuilder or
// heal() defect. Consequence: `backing` (union) and `shaftDiam` bore (subtract) are NOT reliably
// achievable against this loft body via any combination of OCCTSwift 1.17.0 healing/repair calls
// tried here. Both are implemented and independently verified correct in isolation (buildBacking's
// analytic volume formula, applyBoreOrNil's pi*r^2*h prediction, both checked against the plain
// control loft where booleans work) but fail when composed with the actual gear body. Reported as
// a loud, explicit skip (backingApplied/boreApplied flags), not a silent fallback: see
// buildBevelGear below. Full diagnostic trail is in the #87 issue comment.
//
// Handedness note: BOSL2's own right_handed parameter is a double negative in its source
// (`lvnf = right_handed? vnf1 : xflip(p=vnf1)`, where vnf1 itself is already built from a
// per-vertex `xflip()` in the main transform stack) and its sign cannot be checked against a
// rendered OpenSCAD image from inside this spike's tooling. What IS verified here: rightHanded
// = true mirrors the gear across the plane containing the gear axis (the same X=0 plane spike
// 85's own per-vertex xflip already uses), rightHanded = false is the untouched baseline (so
// the existing regression volume is undisturbed), and a mirrored gear has the same volume as
// its source. Matching BOSL2's literal internal sign bit-for-bit is not claimed.
//
// Run:  swift run occtkit run spikes/87-spiral-trace.swift
//       (confirmed working directly in this worktree; spike 85's header note about occtkit run
//       needing a Sources/Script/main.swift copy no longer reproduces here.)

import OCCTSwift
import ScriptHarness
import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Unbuffered stdout: a bad loft can trap deep inside OCCT before Swift's stdio buffer
// flushes, which would otherwise silently swallow every measurement line printed before
// the crash.
setvbuf(stdout, nil, _IONBF, 0)

// ── Fixed gear parameters (unchanged from spike 85; only teeth/spiral/slices/etc vary
//    per test case below) ──────────────────────────────────────────────────────────────
let module: Double            = 2     // mm of pitch diameter per tooth
let pressureAngleDeg: Double  = 20
let flankSamples: Int         = 14    // points sampled along each involute flank

let alpha = pressureAngleDeg * .pi / 180
func inv(_ a: Double) -> Double { tan(a) - a }   // involute function inv(a) = tan a - a

// Per-gear cone/tooth radii. Identical to spike 85's GearGeometry: profile_shift = 0,
// helical = 0, mate_teeth == teeth (pitch angle fixed at 45 degrees). See file header.
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

// Single tooth profile in LOCAL (transverse, radial) coordinates. Unchanged from spike 85.
func toothLocalProfile(_ g: GearGeometry) -> [SIMD2<Double>] {
    let tTip = ((g.addR / g.baseR) * (g.addR / g.baseR) - 1).squareRoot()
    let flankOffset = .pi / (2 * Double(g.teeth)) + inv(alpha)

    func flankPoint(_ t: Double, rot: Double, mirror: Bool) -> SIMD2<Double> {
        let x = g.baseR * (cos(t) + t * sin(t))
        let y = (mirror ? -1 : 1) * g.baseR * (sin(t) - t * cos(t))
        return SIMD2(x * cos(rot) - y * sin(rot), x * sin(rot) + y * cos(rot))
    }
    func rootPoint(_ angle: Double) -> SIMD2<Double> { SIMD2(g.rootR * cos(angle), g.rootR * sin(angle)) }

    let rightRot = -flankOffset
    let leftRot  =  flankOffset

    var absPts: [SIMD2<Double>] = []
    absPts.append(rootPoint(rightRot))
    for s in 0...flankSamples {
        absPts.append(flankPoint(tTip * Double(s) / Double(flankSamples), rot: rightRot, mirror: false))
    }
    for s in stride(from: flankSamples, through: 0, by: -1) {
        absPts.append(flankPoint(tTip * Double(s) / Double(flankSamples), rot: leftRot, mirror: true))
    }
    absPts.append(rootPoint(leftRot))

    return absPts.map { p in SIMD2(-p.y, p.x - g.pr) }
}

// ── The spiral trace: port of gears.scad:2528-2537 ─────────────────────────────────────
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
// law_of_cosines(a,b,c) (trigonometry.scad:48-53, C omitted) returns the angle opposite side
// c: acos(constrain((a*a+b*b-c*c)/(2*a*b), -1, 1)). v_theta (vectors.scad:239-241) is atan2.
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

// slices = cutter_radius==0 ? 1 : slices (gears.scad:2498). Checked against the ORIGINAL
// input spec, before the cutterRadius==0 -> faceWidth*100 substitution.
func resolveSlices(_ slices: Int, cutterRadiusSpec: CutterRadiusSpec) -> Int {
    if case .straight = cutterRadiusSpec { return 1 }
    return slices
}

// Per-slice transform stack, gears.scad:2546-2564: scale(u) -> xrot(pitchAngle) ->
// back(u*pr) -> zrot(ang/sin(pitchAngle)) -> up(pitchoff + (1-u)*pr/tan(pitchAngle)),
// then per-tooth zrot(tooth) and a final xflip(). Spike 85 fixed ang at 0 (straight radial
// trace); this spike restores the zrot step using the arc-sampled `ang`.
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

// Station (u, ang) at arc-fraction v in [0,1]: p = radcp + polar_to_xy(cutterRadius,
// lerp(sang,eang,v)); ang = v_theta(p) - 90 degrees (here: - pi/2); u = norm(p) / oconeRad.
func cutterStation(_ cutter: CutterArc, v: Double) -> (u: Double, ang: Double) {
    let theta = cutter.sang + (cutter.eang - cutter.sang) * v
    let p = cutter.radcp + SIMD2(cutter.cutterRadius * cos(theta), cutter.cutterRadius * sin(theta))
    let dist = (p.x * p.x + p.y * p.y).squareRoot()
    return (dist, atan2(p.y, p.x) - .pi / 2)
}

func buildSectionWires(_ g: GearGeometry, cutter: CutterArc, slices: Int) -> [Wire] {
    let localProfile = toothLocalProfile(g)
    var wires: [Wire] = []
    for vi in 0...slices {
        let v = slices == 0 ? 0.0 : Double(vi) / Double(slices)
        let (dist, ang) = cutterStation(cutter, v: v)
        let u = dist / g.oconeRad

        var ringPts: [SIMD3<Double>] = []
        ringPts.reserveCapacity(g.teeth * localProfile.count)
        for tooth in 0..<g.teeth {
            let toothAngle = 2 * .pi * Double(tooth) / Double(g.teeth)
            for p in localProfile {
                ringPts.append(slicePoint(local: p, u: u, ang: ang, g: g, toothAngle: toothAngle))
            }
        }
        guard let wire = Wire.polygon3D(ringPts, closed: true) else {
            fatalError("teeth=\(g.teeth): section wire \(vi) failed (\(ringPts.count) points)")
        }
        wires.append(wire)
    }
    return wires
}

// The outer (wide, v=0) end's first root vertex in absolute 3D. Used to size the backing
// footprint from the SAME math the loft itself used (no separate analytic re-derivation that
// could silently drift from what was actually built).
func outerEndRootPoint(_ g: GearGeometry, cutter: CutterArc) -> SIMD3<Double> {
    let (dist, ang) = cutterStation(cutter, v: 0)
    let u = dist / g.oconeRad
    let localProfile = toothLocalProfile(g)
    return slicePoint(local: localProfile[0], u: u, ang: ang, g: g, toothAngle: 0)
}

// ── Backing: a revolved profile unioned onto the gear's wide (outer-cone) end ──────────────
//
// Per gears.scad:2602-2613's cone_backing formula: factor = tan(pitchAngle-90)*backing; the
// backing's far radius shrinks by |factor| as it extends `backing` further from the teeth
// (continuing the pitch cone's own taper past the wide end, not flaring outward). Cylindrical
// backing (cone_backing=false) holds the wide end's own radius constant instead. Reimplemented
// here as a revolved trapezoid/rectangle FACE (not wire — revolving a wire gives a shell, see
// okf/decisions/wire-sweep-factories-are-not-symmetric.md), rather than BOSL2's manual
// vertex/face-index arithmetic, per this spike's own task description.
struct BackingResult {
    let shape: Shape
    let analyticVolume: Double
    let outerRadius: Double
    let farRadius: Double
    let backing: Double
}

func buildBacking(_ g: GearGeometry, cutter: CutterArc, backing: Double, coneBacking: Bool) -> BackingResult {
    let outerPoint = outerEndRootPoint(g, cutter: cutter)
    let r0 = (outerPoint.x * outerPoint.x + outerPoint.y * outerPoint.y).squareRoot()
    let z0 = outerPoint.z
    let z1 = z0 - backing   // extends away from the teeth; apex end sits at higher z (spike 85)

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
        SIMD3(0, 0, z0), SIMD3(r0, 0, z0), SIMD3(r1, 0, z1), SIMD3(0, 0, z1),
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
        ? (Double.pi * backing / 3) * (r0 * r0 + r0 * r1 + r1 * r1)   // conical frustum
        : Double.pi * r0 * r0 * backing                                // cylinder
    return BackingResult(shape: solid, analyticVolume: analyticVolume, outerRadius: r0, farRadius: r1, backing: backing)
}

// ── Bore: subtracting(cylinder), matching recipes/04-spur-gear/main.swift:80-82 ────────────
//
// Returns nil (rather than fatalError) specifically when the SUBTRACT itself fails — the known,
// diagnosed Route A boolean-safety defect described where this is called (see file header).
// Building the cylinder tool is unrelated to that defect and still fails loudly.
func applyBoreOrNil(_ shape: Shape, shaftDiam: Double) -> Shape? {
    let b = shape.bounds
    let r = shaftDiam / 2
    let extra = 2.0
    let height = (b.max.z - b.min.z) + 2 * extra
    guard let bore = Shape.cylinder(at: SIMD3(0, 0, b.min.z - extra), direction: SIMD3(0, 0, 1),
                                    radius: r, height: height) else {
        fatalError("shaft bore cylinder failed (r=\(r), height=\(height))")
    }
    return shape.subtracting(bore)
}

// ── Handedness: mirror across the plane containing the gear axis. See file header note. ───
func applyHandedness(_ shape: Shape, rightHanded: Bool) -> Shape {
    guard rightHanded else { return shape }
    guard let mirrored = shape.mirrored(planeNormal: SIMD3(1, 0, 0)) else {
        fatalError("handedness mirror failed")
    }
    return mirrored
}

// ── One gear build, end to end ──────────────────────────────────────────────────────────────
struct GearParams {
    var teeth: Int
    var spiralDeg: Double = 35
    var cutterRadiusSpec: CutterRadiusSpec = .defaulted
    var slices: Int = 5
    var rightHanded: Bool = false
    var backing: Double? = nil
    var coneBacking: Bool = true
    var shaftDiam: Double = 0
}

struct BuildReport {
    let label: String
    let params: GearParams
    let g: GearGeometry
    let usedSlices: Int
    let cutterRadius: Double
    let loftSeconds: Double
    let healSeconds: Double
    let backingSeconds: Double
    let boreSeconds: Double
    let totalSeconds: Double
    let rawIsValid: Bool
    let healed: Bool
    let healedShapeType: ShapeType
    let finalIsValid: Bool
    let finalShapeType: ShapeType
    let solidCount: Int
    let volume: Double
    let faceCount: Int
    let backingAttempted: Bool
    let backingApplied: Bool
    let backingAnalyticVolume: Double?
    let backingActualDelta: Double?
    let boreAttempted: Bool
    let boreApplied: Bool
    let boreAnalyticVolume: Double?
    let boreActualDelta: Double?
    let shape: Shape
}

func buildBevelGear(_ p: GearParams, label: String) -> BuildReport {
    let t0 = Date()
    let g = GearGeometry(teeth: p.teeth)
    let spiralRad = p.spiralDeg * .pi / 180
    let cutter = buildCutterArc(g: g, spiralRad: spiralRad, cutterRadiusSpec: p.cutterRadiusSpec)
    let slices = resolveSlices(p.slices, cutterRadiusSpec: p.cutterRadiusSpec)

    let wires = buildSectionWires(g, cutter: cutter, slices: slices)

    let loft = ThruSectionsBuilder(isSolid: true, isRuled: false)
    loft.checkCompatibility(true)
    for wire in wires {
        guard let wireShape = Shape.fromWire(wire) else { fatalError("\(label): Shape.fromWire failed") }
        loft.addWire(wireShape)
    }
    guard loft.build(), let rawShape = loft.shape else {
        fatalError("\(label): loft build failed")
    }
    let t1 = Date()

    let rawValid = rawShape.isValid
    var shape = rawShape
    var healed = false
    if !rawValid {
        guard let healedShape = rawShape.healed() else { fatalError("\(label): heal() returned nil") }
        guard healedShape.isValid else { fatalError("\(label): heal() did not fix validity") }
        shape = healedShape
        healed = true
    }
    let healedShapeType = shape.shapeType
    let t2 = Date()

    // Backing (union) and bore (subtract) are known, DIAGNOSED failure points on this specific
    // loft body: see the file header / issue #87 comment for the full investigation. heal()
    // returns isValid==true with a correct volume and a clean analyze(), but downgrades
    // shapeType from Solid to Shell (subShapeCount(ofType: .solid) == 0), and every
    // topology-repair pipeline tried (fixSolid/solidFromShellFixed/solidFromShell/upgraded/
    // unified/sewn at 5 tolerances, and coarser flank sampling down to 1 sample/flank at 8
    // teeth) either fails the same way or gets shapeType back to Solid while silently mangling
    // the boolean's OTHER operand. Reported here as a loud, explicit skip rather than a fatal
    // crash, so the rest of the sweep (which does not depend on booleans) still completes and
    // reports. This is NOT a silent `??` fallback: backingApplied/boreApplied say plainly
    // whether the feature landed, and the shape is left exactly as it was if it did not.
    var backingAttempted = false
    var backingApplied = false
    var backingAnalytic: Double? = nil
    var backingDelta: Double? = nil
    if let backing = p.backing {
        backingAttempted = true
        let preVol = shape.volume ?? Double.nan
        let br = buildBacking(g, cutter: cutter, backing: backing, coneBacking: p.coneBacking)
        backingAnalytic = br.analyticVolume
        let unioned = shape.union(br.shape)
        // Same double-check as the bore path: a non-nil union that does not actually GAIN
        // volume is the same silent-drop defect wearing a different face, not success.
        if let unioned, let postVol = unioned.volume, postVol > preVol {
            shape = unioned
            backingApplied = true
            backingDelta = postVol - preVol
        } else {
            let reason = unioned == nil ? "union returned nil"
                : (unioned!.volume == nil ? "result volume uncomputable" : "result volume did not increase")
            print("  FAILED: \(label) backing union failed (\(reason)) (known Route A boolean-safety defect, see file header). Shape left unbacked.")
        }
    }
    let t3 = Date()

    shape = applyHandedness(shape, rightHanded: p.rightHanded)
    let t4 = Date()

    var boreAttempted = false
    var boreApplied = false
    var boreAnalytic: Double? = nil
    var boreDelta: Double? = nil
    if p.shaftDiam > 0 {
        boreAttempted = true
        let preVol = shape.volume ?? Double.nan
        let b = shape.bounds
        let r = p.shaftDiam / 2
        boreAnalytic = Double.pi * r * r * (b.max.z - b.min.z)
        let bored = applyBoreOrNil(shape, shaftDiam: p.shaftDiam)
        // A non-nil result is not enough: the known defect also shows up as subtracting()
        // returning a Compound with an uncomputable (nil) volume, or a volume that did not
        // actually go DOWN, i.e. the cylinder trimmed a surface instead of carving the solid.
        // Both are treated as bore failure, loudly, not silently accepted as success.
        if let bored, let postVol = bored.volume, postVol < preVol {
            shape = bored
            boreApplied = true
            boreDelta = preVol - postVol
        } else {
            let reason = bored == nil ? "subtract returned nil"
                : (bored!.volume == nil ? "result volume uncomputable" : "result volume did not decrease")
            print("  FAILED: \(label) bore subtract failed (\(reason)) (known Route A boolean-safety defect, see file header). Shape left unbored.")
        }
    }
    let t5 = Date()

    let finalValid = shape.isValid
    let finalShapeType = shape.shapeType
    let solidCount = shape.subShapeCount(ofType: .solid)
    let volume = shape.volume ?? Double.nan
    if shape.volume == nil {
        print("  WARNING: \(label) final volume is nil/uncomputable")
    }
    let faceCount = shape.subShapeCount(ofType: .face)

    return BuildReport(
        label: label, params: p, g: g, usedSlices: slices, cutterRadius: cutter.cutterRadius,
        loftSeconds: t1.timeIntervalSince(t0), healSeconds: t2.timeIntervalSince(t1),
        backingSeconds: t3.timeIntervalSince(t2), boreSeconds: t5.timeIntervalSince(t4),
        totalSeconds: t5.timeIntervalSince(t0),
        rawIsValid: rawValid, healed: healed, healedShapeType: healedShapeType,
        finalIsValid: finalValid, finalShapeType: finalShapeType, solidCount: solidCount,
        volume: volume, faceCount: faceCount,
        backingAttempted: backingAttempted, backingApplied: backingApplied,
        backingAnalyticVolume: backingAnalytic, backingActualDelta: backingDelta,
        boreAttempted: boreAttempted, boreApplied: boreApplied,
        boreAnalyticVolume: boreAnalytic, boreActualDelta: boreDelta,
        shape: shape
    )
}

func printReport(_ r: BuildReport) {
    let backingDesc: String = r.params.backing.map { "\($0)" } ?? "nil"
    print("[\(r.label)] teeth=\(r.params.teeth) spiralDeg=\(r.params.spiralDeg) cutterRadius=\(r.cutterRadius)")
    print("  slices(used)=\(r.usedSlices) rightHanded=\(r.params.rightHanded) backing=\(backingDesc) coneBacking=\(r.params.coneBacking) shaftDiam=\(r.params.shaftDiam)")
    let loftMs = r.loftSeconds * 1000
    let healMs = r.healSeconds * 1000
    let backingMs = r.backingSeconds * 1000
    let boreMs = r.boreSeconds * 1000
    let totalMs = r.totalSeconds * 1000
    print("  timing: loft=\(loftMs)ms heal=\(healMs)ms backing=\(backingMs)ms bore=\(boreMs)ms total=\(totalMs)ms")
    print("  rawIsValid=\(r.rawIsValid) healed=\(r.healed) healedShapeType=\(r.healedShapeType)")
    print("  finalIsValid=\(r.finalIsValid) finalShapeType=\(r.finalShapeType) solidCount=\(r.solidCount)")
    let facesPerTooth = Double(r.faceCount) / Double(r.params.teeth)
    print("  volume=\(r.volume) faceCount=\(r.faceCount) facesPerTooth=\(facesPerTooth)")
    if r.backingAttempted {
        print("  backing: attempted=true applied=\(r.backingApplied)")
    }
    if let a = r.backingAnalyticVolume, let d = r.backingActualDelta {
        let diff = abs(d - a)
        let pct = diff / a * 100
        print("  backing check: analytic=\(a) actual-delta=\(d) diff=\(diff) pct=\(pct)")
    }
    if r.boreAttempted {
        print("  bore: attempted=true applied=\(r.boreApplied)")
    }
    if let a = r.boreAnalyticVolume, let d = r.boreActualDelta {
        let diff = abs(d - a)
        let pct = diff / a * 100
        print("  bore check: analytic=\(a) actual-delta=\(d) diff=\(diff) pct=\(pct)")
    }
}

// ── Run the measurement sweep ───────────────────────────────────────────────────────────────
let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Spike 87: bevel gear spiral trace",
    source: "OCCTSwiftScripts spike/87-spiral-trace",
    tags: ["spike", "gear", "bevel", "spiral", "backing", "handedness", "bore"]
))
let C = ScriptContext.Colors.self

func addAndReport(_ r: BuildReport, color: [Float]) {
    printReport(r)
    do {
        try ctx.add(r.shape, color: color, name: r.label)
    } catch {
        print("  ctx.add failed for \(r.label): \(error)")
    }
}

print("=== 1. Tooth form regression / comparison (teeth=36, module=2, PA=20, flankSamples=14) ===")

// Straight: cutterRadiusSpec=.straight forces slices->1 and cutterRadius=faceWidth*100
// regardless of `slices` passed in. This is the direct successor of spike 85's own
// simplification (literal ang=0, straight radial trace); the regression baseline (22814.71
// mm3 at 36 teeth) is checked against THIS configuration.
let straight36 = buildBevelGear(
    GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .straight, slices: 5),
    label: "straight-36t"
)
addAndReport(straight36, color: C.steel)
print("  >>> regression check: expected 22814.71 mm3, got \(straight36.volume) mm3, diff=\(abs(straight36.volume - 22814.71))")

// Zerol: spiral=0 with a DEFAULTED (non-degenerate) cutter radius. Curved trace, symmetric,
// zero spiral angle at the midpoint. This is BOSL2 Example 1's tooth form.
let zerol36 = buildBevelGear(
    GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5),
    label: "zerol-36t"
)
addAndReport(zerol36, color: C.brass)

print("=== 2. Spiral tooth form at slices=12 (the deliverable examples' setting) ===")
let spiral16 = buildBevelGear(
    GearParams(teeth: 16, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12),
    label: "spiral-16t-s12"
)
addAndReport(spiral16, color: C.copper)

let spiral28 = buildBevelGear(
    GearParams(teeth: 28, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12),
    label: "spiral-28t-s12"
)
addAndReport(spiral28, color: C.copper)

let spiral36 = buildBevelGear(
    GearParams(teeth: 36, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12),
    label: "spiral-36t-s12"
)
addAndReport(spiral36, color: C.copper)

print("=== 3. Handedness: rightHanded=true must mirror with identical volume ===")
let spiral36RH = buildBevelGear(
    GearParams(teeth: 36, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12, rightHanded: true),
    label: "spiral-36t-s12-RH"
)
addAndReport(spiral36RH, color: C.yellow)
let handednessVolDiff = abs(spiral36.volume - spiral36RH.volume)
print("  >>> handedness check: base volume=\(spiral36.volume) mirrored volume=\(spiral36RH.volume) diff=\(handednessVolDiff)")

print("=== 4. Backing: conical vs cylindrical, on the zerol base (faster to iterate) ===")
let backingConical = buildBevelGear(
    GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5, backing: 5, coneBacking: true),
    label: "zerol-36t-backing-conical"
)
addAndReport(backingConical, color: C.orange)

let backingCylindrical = buildBevelGear(
    GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5, backing: 5, coneBacking: false),
    label: "zerol-36t-backing-cylindrical"
)
addAndReport(backingCylindrical, color: C.orange)

print("=== 5. Bore: shaft_diam cut, verified against pi*r^2*h ===")
let boreTest = buildBevelGear(
    GearParams(teeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted, slices: 5, shaftDiam: 5),
    label: "zerol-36t-bore"
)
addAndReport(boreTest, color: C.gray)

print("=== 6. Integration: spiral + backing + bore + right_handed together, one gear ===")
let integrationGear = buildBevelGear(
    GearParams(teeth: 28, spiralDeg: 35, cutterRadiusSpec: .defaulted, slices: 12,
               rightHanded: true, backing: 4, coneBacking: true, shaftDiam: 6),
    label: "spiral-28t-integration"
)
addAndReport(integrationGear, color: C.yellow)

do {
    try ctx.emit(description: "Spike 87: bevel gear spiral trace + backing/handedness/bore")
} catch {
    print("ctx.emit failed: \(error)")
}

print("=== Done. Bodies written in add() order: straight36, zerol36, spiral16, spiral28, spiral36, spiral36RH, backingConical, backingCylindrical, boreTest, integrationGear ===")
