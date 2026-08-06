// BOSL2 `bevel_gear()` Example 1: a 36-tooth zerol bevel gear with a 5mm bore.
//
// One of three scripts behind `docs/guides/bosl2-bevel-gears.md`, which shows this next to
// the OpenSCAD original. The reference OpenSCAD source is `example1.scad` in this folder.
//
// Run:
//   swift run occtkit run docs/guides/bosl2-bevel-gears/example1.swift \
//       --format brep --output /tmp/bosl2-ex1

// ═══════════════════════════ BEGIN SHARED GEAR CORE ═══════════════════════════
// Everything between the BEGIN and END markers is byte-identical in example1.swift,
// example2.swift and example3.swift. `Scripts/gear-core-check.sh` compares the three
// copies and fails when any of them drifts.
//
// Why three copies rather than one library: `occtkit run` compiles exactly one
// `Sources/Script/main.swift` whose only dependency is the `ScriptHarness` product, so an
// example cannot `import` a shared gear module without changing occtkit's `Run.swift`.
// That is also the convention `recipes/README.md` already states ("self-contained, no
// shared utilities, no cross-recipe imports"). The check script is what stops three copies
// quietly diverging.
//
// ── Attribution ──────────────────────────────────────────────────────────────────────
// The parameterisation and the math are ported from BOSL2's `gears.scad`: `bevel_gear()`
// (function at gears.scad:2486-2650, module at 2653-2705), `_gear_tooth_profile()`
// (3366-3541), `bevel_pitch_angle()` (4142) and `pitch_radius()` (3928).
//
//   BOSL2 is BSD-2-Clause, Copyright 2017-2019 Revar Desmera.
//   https://github.com/BelfrySCAD/BOSL2
//
// The construction is NOT ported. BOSL2 assembles a VNF vertex/face array and emits a
// `polyhedron`; this builds a real B-Rep solid out of OCCTSwift primitives (a revolved
// blank, one lofted tooth-space cutter, `circularPatternCut`). See
// `docs/guides/bosl2-bevel-gears.md` and OCCTSwiftScripts#84 for why, and for the list of
// places where the two genuinely differ.

import OCCTSwift
import ScriptHarness
import Foundation
import simd
#if canImport(Darwin)
import Darwin
#endif

// Unbuffered stdout: a failing boolean can trap inside OCCT before Swift's stdio buffer
// flushes, which would swallow every measurement printed before the crash.
setvbuf(stdout, nil, _IONBF, 0)

// ── Gear constants. All three BOSL2 examples use circ_pitch = 5 and every other default. ──
let circPitch: Double         = 5                    // BOSL2 circ_pitch=5
let gearModule: Double        = circPitch / .pi      // module_value(circ_pitch), gears.scad:3803
let pressureAngleDeg: Double  = 20                   // BOSL2 default
let radialClearance: Double   = gearModule * 0.25    // BOSL2 default clearance = mod/4
let flankSamples: Int         = 14                   // involute samples per flank

let alpha = pressureAngleDeg * .pi / 180
func inv(_ a: Double) -> Double { tan(a) - a }

/// `pitch_radius(circ_pitch, teeth)`, gears.scad:3928. circ_pitch * teeth / PI / 2.
func pitchRadius(teeth: Double) -> Double { circPitch * teeth / .pi / 2 }

/// `bevel_pitch_angle(teeth, mate_teeth, drive_angle)`, gears.scad:4142.
func bevelPitchAngle(teeth: Double, mateTeeth: Double, shaftAngle: Double) -> Double {
    atan(sin(shaftAngle) / (mateTeeth / teeth + cos(shaftAngle)))
}

/// The scalar gear geometry: everything gears.scad computes in its `let(...)` preamble
/// before it starts filling vertex arrays.
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
        pr = pitchRadius(teeth: z)
        baseR = pr * cos(alpha)                     // _base_radius, gears.scad:4105
        addR = pr + gearModule                      // outer_radius, _adendum = mod
        rootR = pr - 1.25 * gearModule              // _root_radius_basic, _dedendum = mod + clearance
        pitchAngle = bevelPitchAngle(teeth: z, mateTeeth: mateTeeth, shaftAngle: shaftAngle)
        oconeRad = pr / sin(pitchAngle)             // opp_ang_to_hyp(pr, pitch_angle)
        faceWidth = min(oconeRad / 3, 10 * gearModule)
        iconeRad = oconeRad - faceWidth
        pitchoff = (pr - rootR) * sin(pitchAngle)
    }
}

// ── The lengthwise tooth trace: a Gleason face-mill cutter arc, gears.scad:2528-2537. ──
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
// Two parameters, three tooth forms, in BOSL2's own resolution order:
//   spiral > 0, cutter_radius defaulted or explicit  -> spiral
//   spiral = 0, cutter_radius defaulted or explicit  -> ZEROL (still a curved lengthwise
//                                                       trace; the spiral angle is zero only
//                                                       at the arc midpoint)
//   cutter_radius = 0                                -> straight (BOSL2 fakes it with
//                                                       cutter_radius = face_width*100 and
//                                                       forces slices = 1)
// Example 1 passes spiral=0 with cutter_radius defaulted, so it is ZEROL, not straight.
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
    case .straight:         cutterRadius = g.faceWidth * 100
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
    return CutterArc(cutterRadius: cutterRadius,
                     sang: radcpang - (.pi - angC1),
                     eang: radcpang - (.pi - angC2),
                     radcp: radcp)
}

/// `slices = cutter_radius==0 ? 1 : slices`, gears.scad:2517. Tested against the ORIGINAL
/// input spec, before the `cutter_radius==0 -> face_width*100` substitution.
func resolveSlices(_ slices: Int, cutterRadiusSpec: CutterRadiusSpec) -> Int {
    if case .straight = cutterRadiusSpec { return 1 }
    return slices
}

/// Station `(u, ang)` at arc fraction `v` in [0,1], gears.scad:2548-2550.
func cutterStation(_ cutter: CutterArc, v: Double) -> (u: Double, ang: Double) {
    let theta = cutter.sang + (cutter.eang - cutter.sang) * v
    let p = cutter.radcp + SIMD2(cutter.cutterRadius * cos(theta), cutter.cutterRadius * sin(theta))
    let dist = (p.x * p.x + p.y * p.y).squareRoot()
    return (dist, atan2(p.y, p.x) - .pi / 2)
}

/// The per-slice transform stack, gears.scad:2554-2562:
///   xflip() * zrot(360*tooth/teeth)
///     * up((1-u)*pr/tan(pitch_angle)) * up(pitchoff) * zrot(ang/sin(pitch_angle))
///     * back(u*pr) * xrot(pitch_angle) * scale(u)
/// `local` is a point of the planar tooth (or tooth-space) profile, already recentred on the
/// pitch radius. `ang` only ever varies along the cone distance, so every call that must stay
/// axisymmetric passes `ang: 0`.
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

    return SIMD3(-x1, y1, z0)   // BOSL2's xflip() at the head of the stack
}

/// A point on the involute of the base circle, at involute parameter `t`.
func flankPoint(t: Double, rot: Double, mirror: Bool, baseR: Double) -> SIMD2<Double> {
    let x = baseR * (cos(t) + t * sin(t))
    let y = (mirror ? -1 : 1) * baseR * (sin(t) - t * cos(t))
    return SIMD2(x * cos(rot) - y * sin(rot), x * sin(rot) + y * cos(rot))
}

func radialPoint(angle: Double, radius: Double) -> SIMD2<Double> {
    SIMD2(radius * cos(angle), radius * sin(angle))
}

/// A point on the meridian half-plane at cone station `u` and nominal (flat-profile) radius
/// `R`, as (radius-from-axis, z). This is the same function that places the blank's own
/// profile vertices, so anything derived from it is consistent with the built solid.
func meridianRZ(u: Double, R: Double, g: GearGeometry) -> SIMD2<Double> {
    let p = slicePoint(local: SIMD2(0, R - g.pr), u: u, ang: 0, g: g, toothAngle: 0)
    return SIMD2(p.y, p.z)
}

/// The planar tooth-SPACE profile (BOSL2 builds the tooth; this builds the gap that gets cut
/// out of a blank, which is what Route C needs). Standard involute flanks from the base
/// circle, closed across the root and extended past the tip so the cutter clears the blank.
/// `offset` is the space half-angle at the base circle, pi/(2z) - inv(alpha).
///
/// `rootExtRadius` is the ROOT RADIUS itself, not root minus clearance. The blank carries no
/// root-cone surface of its own (its outer surface is the addendum cone), so whatever radius
/// the cutter bottoms out at IS the finished valley floor. Bottoming out a further
/// `clearance` below the root, which the #109/#110 spikes did to guarantee a clean cut, digs
/// every valley mod/4 deeper than BOSL2's and cost 1.05% of the gear's volume when measured
/// against the reference mesh.
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

/// The un-toothed blank: an axisymmetric solid of revolution bounded by the root cone, the
/// addendum cone and the two cone-distance end planes. `Shape.revolve(profile:)` returns a
/// shell, so the meridian is faced first and the FACE is revolved, which returns a solid.
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

/// One tooth-space cutter: the gap profile sampled at `slices+1` stations along the cutter
/// arc and lofted. A single-gap loft has roughly one period of out-of-plane variation, so
/// `ThruSectionsBuilder(isSolid: true)` caps it correctly; lofting all N gaps in one closed
/// section does not (OCCTSwiftScripts#108).
func buildCutterTool(_ g: GearGeometry, cutter: CutterArc, slices: Int, toothAngle: Double = 0) -> Shape? {
    let gapFlankOffset = .pi / (2 * Double(g.teeth)) - inv(alpha)
    let tTip = ((g.addR / g.baseR) * (g.addR / g.baseR) - 1).squareRoot()
    let rootExtRadius = g.rootR                    // the finished valley floor, see gapLocalProfile
    let tipExtRadius = g.addR + radialClearance    // over-travel past the addendum cone, cuts nothing extra

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

/// BOSL2's `ctr_thickness` (gears.scad:2565-2567): the axial thickness of the body at the
/// tooth profile's first point, which sits on the root radius. BOSL2 reads it off two vnf
/// vertices; this evaluates the same two meridian points directly.
func ctrThickness(_ g: GearGeometry) -> Double {
    let uInner = g.iconeRad / g.oconeRad
    return meridianRZ(u: uInner, R: g.rootR, g: g).y - meridianRZ(u: 1, R: g.rootR, g: g).y
}

/// BOSL2's defaulted `backing` (gears.scad:2587-2588): with none of backing / thickness /
/// bottom given, the gear gets exactly enough backing to reach face_width/2 of centre
/// thickness, and none at all if it is already thicker than that.
func defaultBacking(_ g: GearGeometry) -> Double {
    let ctr = ctrThickness(g)
    return ctr > g.faceWidth / 2 ? 0 : -ctr + g.faceWidth / 2
}

struct BackingResult {
    let shape: Shape
    let analyticVolume: Double
    let outerRadius: Double
    let farRadius: Double
}

/// The backing disc welded onto the back (wide) face, gears.scad:2603-2613. `cone_backing`
/// true continues the gear's conical taper; false attaches a plain cylinder.
/// BOSL2 builds a 2N-gon prism through the root points; this revolves the meridian, so the
/// OCCT version is the exact solid of revolution the polygon approximates.
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
            fatalError("backing=\(backing): the conical taper crosses the axis (r0=\(r0), r1=\(r1)); reduce backing")
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
    guard let face = Shape.face(from: wire) else { fatalError("backing meridian face failed") }
    guard let solid = face.revolved(axisOrigin: .zero, axisDirection: SIMD3(0, 0, 1)) else {
        fatalError("backing revolve failed")
    }

    let analyticVolume = coneBacking
        ? (Double.pi * backing / 3) * (r0 * r0 + r0 * r1 + r1 * r1)
        : Double.pi * r0 * r0 * backing
    return BackingResult(shape: solid, analyticVolume: analyticVolume, outerRadius: r0, farRadius: r1)
}

/// The shaft bore tool: a through cylinder on the gear axis, over-long at both ends so the
/// subtraction never leaves a sliver. BOSL2 cuts a 12-sided prism here
/// (`$fn=max(12, segs(shaft_diam/2))`, gears.scad:2701); this cuts a true cylinder.
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

// ── Reference frames: the replacement for BOSL2's named_anchor system (gears.scad:2643-2645,
// OCCTSwiftScripts#88). Three plain heights along the gear's own build axis. ──
struct GearReferenceFrames {
    let pitchbase: Double
    let flattop: Double
    let apex: Double
}

func referenceFrames(_ g: GearGeometry) -> GearReferenceFrames {
    let pitchbase = g.pitchoff
    // pitchoff and the meridian machinery that places the blank's own vertices are the same
    // z0 formula evaluated at R=pr, u=1. If they ever disagree, slicePoint has been edited.
    let pitchbaseFromMeridian = meridianRZ(u: 1, R: g.pr, g: g).y
    precondition(abs(pitchbase - pitchbaseFromMeridian) < 1e-9,
                 "pitchbase disagreement: pitchoff=\(pitchbase) vs meridian=\(pitchbaseFromMeridian)")

    let uInner = g.iconeRad / g.oconeRad
    let flattop = meridianRZ(u: uInner, R: g.rootR, g: g).y

    // hyp_ang_to_opp(hyp, ang) = hyp * sin(ang), with ang = 90 - pitch_angle.
    let apexCone = g.pitchAngle < .pi / 2 ? g.oconeRad : g.iconeRad
    return GearReferenceFrames(pitchbase: pitchbase, flattop: flattop,
                               apex: pitchbase + apexCone * cos(g.pitchAngle))
}

// ── Placement: BOSL2's anchor / spin / orient, as explicit transforms. BOSL2 applies them in
// the order anchor -> spin -> orient (attachments.scad `reorient`), and so must callers. ──

/// BOSL2's default `anchor="pitchbase"`: put the base of the pitch cone in the XY plane.
func anchoredAtPitchbase(_ shape: Shape, _ f: GearReferenceFrames) -> Shape {
    guard let s = shape.translated(by: SIMD3(0, 0, -f.pitchbase)) else {
        fatalError("anchoredAtPitchbase: translate failed (pitchbase=\(f.pitchbase))")
    }
    return s
}

/// BOSL2's `anchor="apex"`: put the pitch cone's apex at the origin.
func anchoredAtApex(_ shape: Shape, _ f: GearReferenceFrames) -> Shape {
    guard let s = shape.translated(by: SIMD3(0, 0, -f.apex)) else {
        fatalError("anchoredAtApex: translate failed (apex=\(f.apex))")
    }
    return s
}

/// BOSL2's `spin=`: rotate about the gear's own +Z, after the anchor and before orient.
func spun(_ shape: Shape, degrees: Double) -> Shape {
    guard degrees != 0 else { return shape }
    guard let s = shape.rotated(axis: SIMD3(0, 0, 1), angle: degrees * .pi / 180) else {
        fatalError("spun: rotate failed (degrees=\(degrees))")
    }
    return s
}

/// BOSL2's `orient=FWD`: rotate the gear's +Z axis onto -Y, which is xrot(90).
func orientedFWD(_ shape: Shape) -> Shape {
    guard let s = shape.rotated(axis: SIMD3(1, 0, 0), angle: .pi / 2) else {
        fatalError("orientedFWD: rotate failed")
    }
    return s
}

/// BOSL2's `move()` / `back()` / `down()`.
func movedBy(_ shape: Shape, _ v: SIMD3<Double>) -> Shape {
    guard let s = shape.translated(by: v) else { fatalError("movedBy: translate failed (v=\(v))") }
    return s
}

// ── Diagnostics. `solidCount` is the field that matters: three spikes in this epic reported
// isValid == true while emitting solidCount == 0, and heal()/fixSolid() reach isValid by
// demoting Solid to Shell (OCCTSwift#702), so neither is called anywhere here. ──
struct HealthSnapshot {
    let isValid: Bool
    let shapeType: ShapeType
    let solidCount: Int
    let faceCount: Int
    let volume: Double

    init(_ shape: Shape) {
        isValid = shape.isValid
        shapeType = shape.shapeType
        solidCount = shape.subShapeCount(ofType: .solid)
        faceCount = shape.subShapeCount(ofType: .face)
        volume = shape.volume ?? Double.nan
    }

    func describe(_ label: String) {
        print("  [\(label)] isValid=\(isValid) shapeType=\(shapeType) solidCount=\(solidCount) faceCount=\(faceCount) volume=\(volume)")
    }
}

struct GearParams {
    var teeth: Int
    var mateTeeth: Double
    var shaftAngle: Double = .pi / 2
    var spiralDeg: Double = 35                     // gears.scad default
    var cutterRadiusSpec: CutterRadiusSpec = .defaulted
    var slices: Int = 5                            // gears.scad:2498's CODE default, not the docs' 1
    var rightHanded: Bool = false
    var backing: Double? = nil                     // nil -> defaultBacking(g)
    var coneBacking: Bool = true
    var shaftDiam: Double = 0
}

struct BuiltGear {
    let label: String
    let params: GearParams
    let g: GearGeometry
    let frames: GearReferenceFrames
    let cutter: CutterArc
    let usedSlices: Int
    let appliedBacking: Double
    /// Volume of ONE tooth space, measured as (blank - cut gear) / teeth. The natural unit
    /// for "how badly did two meshed gears collide": a half-pitch phase error puts a whole
    /// tooth into a whole gap, so it costs a sizeable fraction of this.
    let toothSpaceVolume: Double
    let rawGearHealth: HealthSnapshot             // straight out of circularPatternCut, no repair
    let finalHealth: HealthSnapshot
    let shape: Shape
}

/// Route C: revolve a blank, loft one tooth-space cutter, `circularPatternCut` it N times,
/// then bore / back / mirror. Every stage asserts `subShapeCount(ofType: .solid) >= 1` on the
/// RAW result. No heal(), no fixSolid(), and no `??` on a fallible geometry call.
func buildGear(_ p: GearParams, label: String) -> BuiltGear {
    let g = GearGeometry(teeth: p.teeth, mateTeeth: p.mateTeeth, shaftAngle: p.shaftAngle)
    let cutter = buildCutterArc(g: g, spiralRad: p.spiralDeg * .pi / 180, cutterRadiusSpec: p.cutterRadiusSpec)
    let slices = resolveSlices(p.slices, cutterRadiusSpec: p.cutterRadiusSpec)
    let backing = p.backing ?? defaultBacking(g)

    print("[\(label)] teeth=\(p.teeth) mate_teeth=\(p.mateTeeth) pitch_angle=\(g.pitchAngle * 180 / .pi)deg " +
          "pr=\(g.pr) face_width=\(g.faceWidth) spiral=\(p.spiralDeg)deg cutter_radius=\(cutter.cutterRadius) slices=\(slices)")
    print("  ctr_thickness=\(ctrThickness(g)) backing=\(backing) (default would be \(defaultBacking(g))) cone_backing=\(p.coneBacking)")

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
        fatalError("\(label): tooth-space cutter is not a solid (solidCount=\(cutterHealth.solidCount))")
    }

    guard let gear = blank.circularPatternCut(tool: cutterShape, axisPoint: .zero,
                                              axisDirection: SIMD3(0, 0, 1), count: p.teeth) else {
        fatalError("\(label): circularPatternCut returned nil")
    }
    let rawGearHealth = HealthSnapshot(gear)
    guard rawGearHealth.solidCount >= 1, rawGearHealth.isValid else {
        fatalError("\(label): pattern-cut gear is not a valid solid without repair " +
                   "(solidCount=\(rawGearHealth.solidCount), isValid=\(rawGearHealth.isValid)); reported as a failure, not routed around with heal()")
    }
    rawGearHealth.describe("teeth cut, RAW")

    // Volume bookkeeping: blank minus N disjoint cutters. The gaps do not overlap, so the
    // prediction is exact up to the parts of each cutter that stick out beyond the blank.
    let predicted = blankHealth.volume - Double(p.teeth) * cutterHealth.volume
    print("  volume: blank=\(blankHealth.volume) - \(p.teeth)*cutter=\(Double(p.teeth) * cutterHealth.volume) " +
          "=> lower bound \(predicted); actual=\(rawGearHealth.volume)")
    guard rawGearHealth.volume > predicted, rawGearHealth.volume < blankHealth.volume else {
        fatalError("\(label): cut volume \(rawGearHealth.volume) outside (\(predicted), \(blankHealth.volume)); the pattern cut did not do what it should")
    }

    var shape = gear

    if backing > 0 {
        let preVol = shape.volume ?? Double.nan
        let br = buildBacking(g, backing: backing, coneBacking: p.coneBacking)
        guard let unioned = shape.union(br.shape), let postVol = unioned.volume, postVol > preVol else {
            fatalError("\(label): backing union failed or did not add volume")
        }
        let delta = postVol - preVol
        let pct = abs(delta - br.analyticVolume) / br.analyticVolume * 100
        print("  backing: predicted=\(br.analyticVolume) (cone_backing=\(p.coneBacking), r0=\(br.outerRadius), r1=\(br.farRadius), depth=\(backing)) actual=\(delta) diff=\(pct)%")
        guard pct < 0.5 else {
            fatalError("\(label): backing volume off by \(pct)% from the analytic frustum/cylinder")
        }
        shape = unioned
        let h = HealthSnapshot(shape)
        guard h.solidCount >= 1 else { fatalError("\(label): backing union produced solidCount=\(h.solidCount)") }
    }

    if p.shaftDiam > 0 {
        let preVol = shape.volume ?? Double.nan
        let radius = p.shaftDiam / 2
        let boreTool = buildBoreCylinder(shape, radius: radius)
        guard let bored = shape.subtracting(boreTool), let postVol = bored.volume, postVol < preVol else {
            fatalError("\(label): bore subtraction failed or did not remove volume")
        }
        // Analytic check against pi*r^2*h over the axial span the material actually occupies
        // on the axis: root plane at u=1 up to the flat top, plus any backing below it.
        let axisSpan = ctrThickness(g) + backing
        let predictedBore = Double.pi * radius * radius * axisSpan
        let delta = preVol - postVol
        let pct = abs(delta - predictedBore) / predictedBore * 100
        print("  bore: predicted=\(predictedBore) (pi*r^2*h, r=\(radius), axis span=\(axisSpan)) actual=\(delta) diff=\(pct)%")
        guard pct < 0.5 else {
            fatalError("\(label): bore volume off by \(pct)% from pi*r^2*h")
        }
        shape = bored
        let h = HealthSnapshot(shape)
        guard h.solidCount >= 1 else { fatalError("\(label): bore subtraction produced solidCount=\(h.solidCount)") }
    }

    // Handedness. gears.scad:2640 is `lvnf = right_handed ? vnf1 : xflip(p=vnf1)`, and
    // `slicePoint` above already carries BOSL2's own `xflip()` from the per-slice transform
    // stack, which is the RIGHT-handed form. BOSL2 reaches its LEFT-handed default by
    // mirroring that a second time, so the extra mirror belongs on right_handed == false.
    if !p.rightHanded {
        guard let mirrored = shape.mirrored(planeNormal: SIMD3(1, 0, 0)) else {
            fatalError("\(label): handedness mirror failed")
        }
        shape = mirrored
    }

    let finalHealth = HealthSnapshot(shape)
    guard finalHealth.solidCount >= 1, finalHealth.isValid else {
        fatalError("\(label): final shape is not a valid solid (solidCount=\(finalHealth.solidCount), isValid=\(finalHealth.isValid))")
    }
    finalHealth.describe("final")
    let b = shape.bounds
    print("  bounds: min=(\(b.min.x), \(b.min.y), \(b.min.z)) max=(\(b.max.x), \(b.max.y), \(b.max.z))")

    return BuiltGear(label: label, params: p, g: g, frames: referenceFrames(g), cutter: cutter,
                     usedSlices: slices, appliedBacking: backing,
                     toothSpaceVolume: (blankHealth.volume - rawGearHealth.volume) / Double(p.teeth),
                     rawGearHealth: rawGearHealth, finalHealth: finalHealth, shape: shape)
}

/// The lengthwise tooth trace, reported as the spiral angle at each end and at the midpoint of
/// the cutter arc. Straight teeth give three angles that are all ~0; zerol gives 0 at the
/// midpoint with equal and OPPOSITE angles at the ends; a spiral gives three angles of the
/// same sign. Callers assert on this, so a trace that silently collapsed to a straight line
/// would fail rather than quietly ship.
func traceAngles(_ cutter: CutterArc) -> (start: Double, mid: Double, end: Double) {
    (cutterStation(cutter, v: 0).ang * 180 / .pi,
     cutterStation(cutter, v: 0.5).ang * 180 / .pi,
     cutterStation(cutter, v: 1).ang * 180 / .pi)
}
// ════════════════════════════ END SHARED GEAR CORE ════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════════════
// Example 1: bevel gear with zerol teeth.
//
// BOSL2 gears.scad:2400-2404, verbatim:
//
//     bevel_gear(
//         circ_pitch=5, teeth=36, mate_teeth=36,
//         shaft_diam=5, spiral=0
//     );
//
// Everything not named takes a BOSL2 default: slices=5, cutter_radius undefined,
// right_handed=false, backing defaulted, cone_backing=true, anchor="pitchbase",
// spin=0, orient=UP.
// ══════════════════════════════════════════════════════════════════════════════════════

// `exportSTEP: true` is spelled out so `occtkit run --format brep` can rewrite it to
// false; the rewriter only recognises that literal (Run.swift:216-217).
let ctx = ScriptContext(exportSTEP: true, metadata: ManifestMetadata(
    name: "BOSL2 bevel_gear() Example 1: zerol teeth",
    source: "OCCTSwiftScripts docs/guides/bosl2-bevel-gears/example1.swift",
    tags: ["bosl2", "gear", "bevel", "zerol", "docs"]
))
let C = ScriptContext.Colors.self

let gear = buildGear(
    GearParams(teeth: 36, mateTeeth: 36, spiralDeg: 0, cutterRadiusSpec: .defaulted,
               slices: 5, shaftDiam: 5),
    label: "Example 1: bevel_gear(circ_pitch=5, teeth=36, mate_teeth=36, shaft_diam=5, spiral=0)")

// ── Check 1: the teeth are ZEROL, not straight. ────────────────────────────────────────
// `spiral=0` with a defaulted cutter_radius resolves to face_width*2/cos(0), a real arc, so
// the lengthwise trace stays curved and only the spiral angle at mid-face is zero. The
// signature of that is a trace whose angular offset is zero at the arc midpoint and turns
// back the SAME way at both ends. A straight cutter (cutter_radius=0 -> face_width*100)
// would put all three angles within a rounding error of zero, so this check fails if the
// tooth form silently degrades to straight.
let t1Angles = traceAngles(gear.cutter)
print("check 1, zerol trace: angular offset at cone distance ends and midpoint = " +
      "\(t1Angles.start)deg, \(t1Angles.mid)deg, \(t1Angles.end)deg")
guard abs(t1Angles.mid) < 0.05,
      t1Angles.start * t1Angles.end > 0,
      min(abs(t1Angles.start), abs(t1Angles.end)) > 0.5 else {
    fatalError("Example 1: the tooth trace is not zerol (mid=\(t1Angles.mid), ends=\(t1Angles.start)/\(t1Angles.end))")
}
print("  PASS: zero spiral angle at mid-face, curved and same-signed at both ends")

// ── Check 2: BOSL2's defaulted backing really is zero for this gear. ───────────────────
// gears.scad:2587-2588 gives a gear just enough backing to reach face_width/2 of centre
// thickness. This gear is already thicker than that, so BOSL2 adds none, and neither do we.
// The check fails if ctr_thickness or face_width drifts far enough to flip the branch.
print("check 2, BOSL2 default backing: ctr_thickness=\(ctrThickness(gear.g)) " +
      "face_width/2=\(gear.g.faceWidth / 2) => backing=\(defaultBacking(gear.g))")
guard defaultBacking(gear.g) == 0, gear.appliedBacking == 0 else {
    fatalError("Example 1: expected BOSL2's defaulted backing to be 0, got \(defaultBacking(gear.g))")
}
print("  PASS: no backing, matching BOSL2")

// ── Check 3: apex height above the pitch base equals the MATE's pitch radius. ──────────
// A closed form that does not come from this file's own apex formula (OCCTSwiftScripts#88),
// so a sign or factor error in `referenceFrames` cannot pass it by accident. For a miter
// pair (36 and 36) the two are the same number, which makes this the weakest instance of
// the identity in the three examples; Example 3 exercises it with 14 against 28.
let apexAbove = gear.frames.apex - gear.frames.pitchbase
let matePR = pitchRadius(teeth: gear.params.mateTeeth)
print("check 3, apex height: apex-pitchbase=\(apexAbove) vs pitch_radius(mate_teeth)=\(matePR) " +
      "diff=\(abs(apexAbove - matePR))")
guard abs(apexAbove - matePR) < 1e-9 else {
    fatalError("Example 1: apex height \(apexAbove) does not match pitch_radius(mate)=\(matePR)")
}
print("  PASS")

// ── Place it the way BOSL2 does: anchor="pitchbase", the module's default. ─────────────
let placed = anchoredAtPitchbase(gear.shape, gear.frames)
let placedHealth = HealthSnapshot(placed)
guard placedHealth.solidCount >= 1 else {
    fatalError("Example 1: placed gear is not a solid (solidCount=\(placedHealth.solidCount))")
}
let pb = placed.bounds
print("placed at anchor=\"pitchbase\": bounds z=[\(pb.min.z), \(pb.max.z)] volume=\(placedHealth.volume)")

try ctx.add(placed, color: C.steel, name: "bevel_gear 36t zerol, shaft_diam=5")
try ctx.emit(description: "BOSL2 bevel_gear() Example 1: 36-tooth zerol bevel gear with a 5mm bore")

print("=== Example 1 done ===")
