// Recipe 02 — Helical compression spring
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — a constant-pitch round-wire compression spring.
// Notes:   The coil centre-line is a helix (Wire.helix); the wire cross-section is a
//          circle placed at the helix start and oriented along the start tangent, then
//          swept along the path (Shape.sweep → BRepOffsetAPI_MakePipe). The section
//          MUST sit on the spine start and face along the tangent or the pipe fails.
//          Shape.sweep orientation-normalises its result (OCCTSwift v1.3.1, #170), so the
//          solid has positive volume regardless of section sense. Ground/closed ends are
//          out of scope here — this is an open-coil spring.
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

// ── Coil centre-line: a helix about Z, starting at (meanRadius, 0, 0) ─────────
let meanRadius = (outsideDia - wireDia) / 2
let path = Wire.helix(radius: meanRadius, pitch: pitch, turns: activeCoils)!

// ── Wire cross-section: a circle at the helix start, oriented along the start
//    tangent. Helix r(θ)=(R cosθ, R sinθ, pitch·θ/2π); tangent at θ=0 is (0, R, pitch/2π).
let t = SIMD3<Double>(0, meanRadius, pitch / (2 * .pi))
let tLen = (t.x * t.x + t.y * t.y + t.z * t.z).squareRoot()
let tangent = SIMD3<Double>(t.x / tLen, t.y / tLen, t.z / tLen)
let section = Wire.circle(origin: SIMD3(meanRadius, 0, 0), normal: tangent, radius: wireDia / 2)!

let spring = Shape.sweep(profile: section, along: path)!
try ctx.add(spring, color: C.steel, name: "Compression spring")

print("Free length ≈ \(pitch * activeCoils) mm, spring volume: \(spring.volume ?? 0) mm³")
try ctx.emit(description: "Compression spring — Ø\(wireDia) wire, Ø\(outsideDia) OD, \(activeCoils) coils")
