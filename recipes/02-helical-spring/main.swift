// Recipe 02: Helical compression spring
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body: a constant-pitch round-wire compression spring.
// Notes:   The coil centre-line is a helix (Wire.helix); the wire cross-section is a
//          circle placed at the helix start and oriented along the start tangent, then
//          swept along the path with Shape.pipeShell(..., solid: true) (OCCTSwiftScripts
//          #100). Shape.sweep wraps BRepOffsetAPI_MakePipe, which never caps the ends of
//          the swept tube and so returns a shell even for a closed circular profile;
//          Shape.pipeShell wraps BRepOffsetAPI_MakePipeShell, which has an explicit
//          `solid:` flag that caps the ends into a genuine solid. This is the documented
//          canonical spring recipe (OCCTSwift cookbook, Helices & Springs). The section
//          MUST sit on the spine start and face along the tangent or the pipe fails.
//          `mode: .correctedFrenet` keeps the round section true along the coil (plain
//          .frenet also builds a valid solid but lets the section twist slightly).
//          Ground/closed ends are out of scope here; this is an open-coil spring.
//
// FIXED BUG (was misdiagnosed as an OCCTSwift 2.0.0 kernel regression, filed as
// https://github.com/SecondMouseAU/OCCTSwift/issues/830, then root-caused and closed
// not-a-bug there): this recipe used to compute the wire's start point/tangent
// ANALYTICALLY, assuming Wire.helix's default clockwise: false winds the same way a
// naive right-handed r(θ)=(R cosθ, R sinθ, pitch·θ/2π) formula does. It doesn't —
// clockwise: false reverses the build axis, so the real start is (-meanRadius, ~0, 0),
// descending, not (meanRadius, 0, 0) ascending. `mode: .frenet` re-derives its own
// trihedron from the spine and was insensitive to this; `mode: .correctedFrenet`'s
// twist-angle law is referenced to the profile's own input frame and was not, so the
// wrong placement corrupted its solid (~14% volume error) once an OCCTSwift fix
// (#598) made .correctedFrenet actually run corrected Frenet instead of silently
// falling back to plain Frenet. See the OCCTSwift cookbook's own "Helices & Springs"
// page (which hit and fixed the identical mistake, #721) for the full writeup. Fixed
// here the same way: measure the spine's own start point and tangent (Edge.curve3D,
// Curve3D.d1(at:)) rather than computing them. Verified: this recipe's volume is now
// 8575.186 mm³, matching a hand calculation (cross-section area x coil path length,
// placement-invariant) and the maintainer's own independent reproduction. This recipe
// has no reference output.brep for now: the OLD one (built from the wrong placement)
// agreed on volume post-fix (as expected, since volume doesn't depend on where along
// the coil the profile starts) but NOT on bounding box (0.53mm drift, since the coil's
// exact start point genuinely moved) — reusing it would have been wrong, not just
// stale. Regenerate a real reference (`occtkit run ... --format brep`) and drop it in
// as output.brep once someone has a local build handy; recipe-check.sh already runs
// every other check (manifest/body/volume>0/solidCount) without one.
//
// Run:  swift run occtkit run recipes/02-helical-spring/main.swift --format brep

import OCCTSwift
import ScriptHarness

// ── Parameters ──────────────────────────────────────────────────────────────
let wireDia: Double     = 4     // round-wire diameter (mm)
let outsideDia: Double  = 40    // coil outside diameter (mm)
let pitch: Double       = 12    // axial distance between adjacent coils (mm)
let activeCoils: Double = 6     // number of active turns

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Helical compression spring",
    source: "OCCTSwiftScripts recipe 02",
    tags: ["spring", "helix", "sweep", "coil"]
))
let C = ScriptContext.Colors.self

// ── Coil centre-line: a helix about Z ──────────────────────────────────────
let meanRadius = (outsideDia - wireDia) / 2
let path = Wire.helix(radius: meanRadius, pitch: pitch, turns: activeCoils)!

// ── Wire cross-section: a circle at the helix's OWN start point, oriented along
//    its OWN measured tangent there — never computed analytically (see header).
let firstEdge = path.edges().first!
let curve = firstEdge.curve3D!
let (origin, rawTangent) = curve.d1(at: curve.domain.lowerBound)
let tLen = (rawTangent.x * rawTangent.x + rawTangent.y * rawTangent.y + rawTangent.z * rawTangent.z).squareRoot()
let tangent = SIMD3<Double>(rawTangent.x / tLen, rawTangent.y / tLen, rawTangent.z / tLen)
let section = Wire.circle(origin: origin, normal: tangent, radius: wireDia / 2)!

let spring = Shape.pipeShell(spine: path, profile: section, mode: .correctedFrenet, solid: true)!
try ctx.add(spring, color: C.steel, name: "Compression spring")

print("Free length ≈ \(pitch * activeCoils) mm, spring volume: \(spring.volume ?? 0) mm³")
try ctx.emit(description: "Compression spring, Ø\(wireDia) wire, Ø\(outsideDia) OD, \(activeCoils) coils")
