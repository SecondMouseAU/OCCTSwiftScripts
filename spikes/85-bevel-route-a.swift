// Spike 85: bevel gear math port + Route A (ThruSections loft)
//
// Part of the BOSL2 bevel gear port epic (#84). Answers the question in
// issue #85: does OCCT loft a stack of closed section wires (~1100 points
// each, for a 36 tooth gear) into a valid solid, and how slow is it?
//
// Math ported from BOSL2's gears.scad `bevel_gear()` (lines 2486-2650) and
// its cone radii helpers (bevel_pitch_angle, pitch_radius, outer_radius,
// _root_radius_basic, _base_radius, circular_pitch/module_value). BOSL2 is
// BSD-2-Clause, Copyright 2017-2019 Revar Desmera:
// https://github.com/BelfrySCAD/BOSL2/blob/master/gears.scad
//
// Scope, per #85 and the epic's out-of-scope list (#84): straight/zerol
// teeth only (spiral = 0), no backing, no bore, single gear, mate_teeth ==
// teeth (a symmetric miter pair, pitch angle 45 degrees). The lengthwise
// tooth trace is simplified to a straight radial line from the inner cone
// radius to the outer cone radius; BOSL2's Gleason cutter-arc simulation
// (the `cutter_radius` / `spiral` trig block, gears.scad:2528-2537) is
// deferred to spike 3 (#87), which owns the spiral trace. No undercut
// simulation, jaggy-stripping, self-intersection clipping, attachment
// system, or profile shift: the 2D involute flank reuses the existing
// planar math from recipes/04-spur-gear/main.swift:38-48 rather than
// porting BOSL2's full `_gear_tooth_profile()`.
//
// Construction (Route A): for each of `slices+1` axial stations, build one
// CLOSED wire containing all `teeth` tooth profiles around the full circle,
// then loft the stack with ThruSectionsBuilder. Every section is closed
// (mixing closed and open profiles is a known OCCT SIGSEGV in
// BRepFill_CompatibleWires per the OCCTSwift docs).
//
// Finding recorded during this spike: the raw loft (isSolid: true, isRuled:
// false) consistently reports `isValid == false` with zero errors localized
// by `detailedCheckStatuses`, is not self-intersecting, and heals for free
// (same volume, same face count) via a single `heal()` pass. `isRuled: true`
// was also tried and rejected: it produced double the face count and an
// uncomputable volume even after healing, so every measurement below uses
// the smooth (isRuled: false) loft plus a heal step.
//
// Run:  copy this file's content over Sources/Script/main.swift, then
// `swift run Script`. `swift run occtkit run <file>` (the normally
// recommended way to run a script) does not work from this worktree:
// Sources/occtkit/Commands/Run.swift hardcodes the workspace dependency's
// package identity as "OCCTSwiftScripts" (Run.swift:129), but SwiftPM
// derives a local path dependency's identity from the directory's basename,
// which here is "bevel-gear", not "OCCTSwiftScripts". Pre-existing gap in
// occtkit's script runner, unrelated to this spike; left unfixed to stay in
// scope.

import OCCTSwift
import ScriptHarness
import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Unbuffered stdout: a bad loft can trap deep inside OCCT before Swift's
// stdio buffer flushes, which would otherwise silently swallow every
// measurement line printed before the crash.
setvbuf(stdout, nil, _IONBF, 0)

// ── Fixed gear parameters (shared across every teeth count measured) ──────
let module: Double            = 2     // mm of pitch diameter per tooth
let pressureAngleDeg: Double  = 20
let slices: Int               = 5     // BOSL2 default; slices+1 loft stations
let flankSamples: Int         = 14    // points sampled along each involute flank
let teethCounts: [Int]        = [16, 28, 36]

let alpha = pressureAngleDeg * .pi / 180
func inv(_ a: Double) -> Double { tan(a) - a }   // involute function inv(a) = tan a - a

// Per-gear cone/tooth radii, straight port of BOSL2's bevel_gear() prelude
// (gears.scad:2513-2526) with profile_shift = 0, helical = 0, mate_teeth ==
// teeth (so bevel_pitch_angle reduces to 45 degrees for every gear tested).
struct GearGeometry {
    let teeth: Int
    let pitchAngle: Double   // radians
    let pr: Double           // pitch_radius()
    let baseR: Double        // _base_radius()
    let addR: Double         // outer_radius()
    let rootR: Double        // _root_radius_basic()
    let oconeRad: Double     // outer cone distance
    let faceWidth: Double
    let iconeRad: Double     // inner cone distance = oconeRad - faceWidth
    let pitchoff: Double     // (pr - rootR) * sin(pitchAngle), gears.scad:2521

    init(teeth: Int) {
        self.teeth = teeth
        let z = Double(teeth)
        pr = module * z / 2
        baseR = pr * cos(alpha)
        addR = pr + module
        rootR = pr - 1.25 * module
        // bevel_pitch_angle(teeth, mate_teeth, shaft_angle=90)
        //   = atan(sin(90) / (mate_teeth/teeth + cos(90))) = atan(teeth/mate_teeth)
        // mate_teeth == teeth here, so this is always 45 degrees.
        pitchAngle = .pi / 4
        oconeRad = pr / sin(pitchAngle)               // opp_ang_to_hyp(pr, pitchAngle)
        faceWidth = min(oconeRad / 3, 10 * module)     // default_face_width, gears.scad:2524
        iconeRad = oconeRad - faceWidth
        pitchoff = (pr - rootR) * sin(pitchAngle)
    }
}

// Single tooth profile in LOCAL (transverse, radial) coordinates: radial = 0
// at the pitch radius, positive = outward toward the addendum. This mirrors
// BOSL2's `_gear_tooth_profile(center=true)` output, but is built from
// recipe 04's absolute-polar involute (flankPoint/rootPoint) at tooth-centre
// angle 0 instead of porting _gear_tooth_profile itself. Recipe 04's
// pre-rotation frame has radius along local +X; rotating 90 degrees
// ((x, y) -> (-y, x)) swaps that onto local +Y to match the "radial" axis
// the per-slice cone transform below expects, then the pitch radius is
// subtracted to centre the profile the way `fwd(prad)` does in BOSL2.
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

// Per-slice transform stack, gears.scad:2546-2564, applied in the order
// scale(u) -> xrot(pitch_angle) -> back(u*pr) -> zrot(ang/sin(pitch_angle))
// -> up(pitchoff + (1-u)*pr/tan(pitch_angle)), then per-tooth zrot(360*
// tooth/teeth) and a final xflip(). `ang` (the cutter-arc lengthwise skew)
// is fixed at 0 here: see the file header on the straight-trace
// simplification.
func slicePoint(local: SIMD2<Double>, u: Double, g: GearGeometry, toothAngle: Double) -> SIMD3<Double> {
    let transverse = u * local.x
    let radial = u * local.y

    let x0 = transverse
    let y0 = radial * cos(g.pitchAngle) + u * g.pr
    let z0 = radial * sin(g.pitchAngle) + g.pitchoff + (1 - u) * g.pr / tan(g.pitchAngle)

    let x1 = x0 * cos(toothAngle) - y0 * sin(toothAngle)
    let y1 = x0 * sin(toothAngle) + y0 * cos(toothAngle)

    return SIMD3(-x1, y1, z0)   // xflip: negate x
}

func buildSectionWires(_ g: GearGeometry) -> [Wire] {
    let localProfile = toothLocalProfile(g)
    var wires: [Wire] = []
    for vi in 0...slices {
        let v = Double(vi) / Double(slices)
        // v=0 -> outer cone (large end, u=1, full scale); v=1 -> inner cone
        // (near apex, smaller scale). Matches BOSL2's verts1[0] = outer end.
        let dist = g.oconeRad + v * (g.iconeRad - g.oconeRad)
        let u = dist / g.oconeRad

        var ringPts: [SIMD3<Double>] = []
        ringPts.reserveCapacity(g.teeth * localProfile.count)
        for tooth in 0..<g.teeth {
            let toothAngle = 2 * .pi * Double(tooth) / Double(g.teeth)
            for p in localProfile {
                ringPts.append(slicePoint(local: p, u: u, g: g, toothAngle: toothAngle))
            }
        }
        guard let wire = Wire.polygon3D(ringPts, closed: true) else {
            fatalError("teeth=\(g.teeth): section wire \(vi) failed (\(ringPts.count) points)")
        }
        wires.append(wire)
    }
    return wires
}

struct BuildResult {
    let teeth: Int
    let g: GearGeometry
    let pointsPerSection: Int
    let wireBuildSeconds: Double
    let loftSeconds: Double
    let healSeconds: Double
    let built: Bool
    let rawIsValid: Bool
    let healed: Bool          // true if heal() was needed and it fixed validity
    let shape: Shape?         // the shape to measure/keep: healed if healing was needed and worked, else raw
}

func buildBevelGear(teeth: Int) -> BuildResult {
    let g = GearGeometry(teeth: teeth)
    let pointsPerSection = g.teeth * (2 * flankSamples + 4)

    let t0 = Date()
    let wires = buildSectionWires(g)
    let t1 = Date()

    let loft = ThruSectionsBuilder(isSolid: true, isRuled: false)
    loft.checkCompatibility(true)
    for wire in wires {
        guard let wireShape = Shape.fromWire(wire) else {
            fatalError("teeth=\(teeth): Shape.fromWire failed")
        }
        loft.addWire(wireShape)
    }
    let ok = loft.build()
    let t2 = Date()

    guard ok, let rawShape = loft.shape else {
        return BuildResult(teeth: teeth, g: g, pointsPerSection: pointsPerSection,
                            wireBuildSeconds: t1.timeIntervalSince(t0),
                            loftSeconds: t2.timeIntervalSince(t1),
                            healSeconds: 0, built: false, rawIsValid: false,
                            healed: false, shape: nil)
    }

    let rawValid = rawShape.isValid
    var finalShape = rawShape
    var healedFlag = false
    var healSeconds = 0.0
    if !rawValid {
        let h0 = Date()
        if let healedShape = rawShape.healed(), healedShape.isValid {
            finalShape = healedShape
            healedFlag = true
        }
        healSeconds = Date().timeIntervalSince(h0)
    }

    return BuildResult(
        teeth: teeth, g: g, pointsPerSection: pointsPerSection,
        wireBuildSeconds: t1.timeIntervalSince(t0),
        loftSeconds: t2.timeIntervalSince(t1),
        healSeconds: healSeconds,
        built: true,
        rawIsValid: rawValid,
        healed: healedFlag,
        shape: finalShape
    )
}

// ── Run the measurement sweep ───────────────────────────────────────────────
let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Spike 85: bevel gear Route A",
    source: "OCCTSwiftScripts spike/85-bevel-math",
    tags: ["spike", "gear", "bevel", "loft", "thru-sections"]
))
let C = ScriptContext.Colors.self

print("teeth,pitchAngleDeg,pr,oconeRad,faceWidth,pointsPerSection,wireBuildMs,loftMs,healMs,built,rawIsValid,healed,finalIsValid,volume,faceCount,bboxMin,bboxMax")

for teeth in teethCounts {
    let r = buildBevelGear(teeth: teeth)
    guard r.built, let shape = r.shape else {
        print("\(teeth),45,\(r.g.pr),\(r.g.oconeRad),\(r.g.faceWidth),\(r.pointsPerSection),\(r.wireBuildSeconds * 1000),\(r.loftSeconds * 1000),\(r.healSeconds * 1000),false,,,,,,,")
        continue
    }
    let finalValid = shape.isValid
    let volume = shape.volume ?? -1
    let faceCount = shape.faces().count
    let b = shape.bounds
    print("\(teeth),45,\(r.g.pr),\(r.g.oconeRad),\(r.g.faceWidth),\(r.pointsPerSection),\(r.wireBuildSeconds * 1000),\(r.loftSeconds * 1000),\(r.healSeconds * 1000),true,\(r.rawIsValid),\(r.healed),\(finalValid),\(volume),\(faceCount),\(b.min),\(b.max)")

    do {
        try ctx.add(shape, color: C.steel, name: "Bevel gear \(teeth)t")
    } catch {
        print("teeth=\(teeth): ctx.add failed: \(error)")
    }
}

do {
    try ctx.emit(description: "Spike 85: bevel gear Route A (ThruSections loft), teeth=\(teethCounts)")
} catch {
    print("ctx.emit failed: \(error)")
}
