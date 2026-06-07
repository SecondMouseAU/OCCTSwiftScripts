// Recipe 05 — Strut lattice cube
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — a 3D-printable cubic strut lattice.
// Notes:   The lattice is a grid of round struts running in all three axes. Each axis uses
//          one full-length strut cylinder, replicated across the other two axes with
//          Shape.linearPattern, then all three groups are fused. Full-length rods (rather
//          than per-cell segments) avoid duplicate overlapping struts at cell boundaries.
//
// Run:  swift run occtkit run recipes/05-lattice-cube/main.swift --format brep

import OCCTSwift
import ScriptHarness

// ── Parameters ──────────────────────────────────────────────────────────────
let cell: Double    = 10   // unit cell size (mm)
let cells: Int      = 3    // cells per axis → (cells+1) strut lines per direction
let strutR: Double  = 1.2  // strut radius (mm)

let span = cell * Double(cells)        // overall lattice edge length
let lines = cells + 1                  // strut lines per direction

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Strut lattice cube",
    source: "OCCTSwiftScripts recipe 05",
    tags: ["lattice", "linear-pattern", "boolean", "3d-print"]
))
let C = ScriptContext.Colors.self

// Build one full-length rod along `axis`, then tile it across the other two axes.
func rodGrid(axis: SIMD3<Double>, tileA: SIMD3<Double>, tileB: SIMD3<Double>) -> Shape {
    let rod = Shape.cylinder(at: .zero, direction: axis, radius: strutR, height: span)!
    let row = rod.linearPattern(direction: tileA, spacing: cell, count: lines)!
    return row.linearPattern(direction: tileB, spacing: cell, count: lines)!
}

let xRods = rodGrid(axis: SIMD3(1, 0, 0), tileA: SIMD3(0, 1, 0), tileB: SIMD3(0, 0, 1))
let yRods = rodGrid(axis: SIMD3(0, 1, 0), tileA: SIMD3(1, 0, 0), tileB: SIMD3(0, 0, 1))
let zRods = rodGrid(axis: SIMD3(0, 0, 1), tileA: SIMD3(1, 0, 0), tileB: SIMD3(0, 1, 0))

// Fuse the three rod groups into one solid lattice.
let lattice = xRods.union(yRods)!.union(zRods)!
try ctx.add(lattice, color: C.copper, name: "Strut lattice")

print("\(cells)³ cells, edge \(span) mm, lattice volume: \(lattice.volume ?? 0) mm³")
try ctx.emit(description: "Cubic strut lattice — \(cells)³ cells, Ø\(strutR * 2) struts")
