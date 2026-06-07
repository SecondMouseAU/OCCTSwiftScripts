// Recipe 07 — Sheet-metal U-channel
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — a folded sheet-metal channel: a base with two walls bent up.
// Notes:   Uses OCCTSwift's SheetMetal.Builder. Each face is a Flange defined by its plane
//          (origin + uAxis + thickness normal + vAxis) and a 2D profile; a Bend joins the
//          base to each wall with an inside radius, and the builder rounds the bend regions
//          into one solid. The two walls run the FULL width of the base and sit on opposite
//          edges — the builder folds chains / opposite flanges, but not flanges that share a
//          corner (a four-wall tray fails the corner fillet), so a U-channel is the robust,
//          canonical sheet-metal part here.
//
// Run:  swift run occtkit run recipes/07-sheet-metal-channel/main.swift --format brep

import OCCTSwift
import ScriptHarness

// ── Parameters ──────────────────────────────────────────────────────────────
let width: Double      = 80   // base size in X — also the wall width (mm)
let depth: Double      = 50   // base size in Y, between the two walls (mm)
let wallHeight: Double = 25   // wall height (mm)
let thickness: Double  = 1.5  // sheet thickness (mm)
let bendRadius: Double = 2.0  // inside bend radius (mm)

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "Sheet-metal U-channel",
    source: "OCCTSwiftScripts recipe 07",
    tags: ["sheet-metal", "flange", "bend", "channel", "fold"]
))
let C = ScriptContext.Colors.self

// Base in the XY plane; thickness extrudes +Z.
let base = SheetMetal.Flange(
    id: "base",
    profile: [SIMD2(0, 0), SIMD2(width, 0), SIMD2(width, depth), SIMD2(0, depth)],
    origin: SIMD3(0, 0, 0), normal: SIMD3(0, 0, 1),
    uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0))

// Two full-width walls on the y=0 and y=depth edges. Each sits on its base edge (origin),
// runs along it in +X (uAxis), rises +Z (vAxis — given explicitly because the default
// cross(normal, uAxis) would point one wall downward), and extrudes thickness outward.
let front = SheetMetal.Flange(
    id: "front",
    profile: [SIMD2(0, 0), SIMD2(width, 0), SIMD2(width, wallHeight), SIMD2(0, wallHeight)],
    origin: SIMD3(0, 0, 0), normal: SIMD3(0, -1, 0),
    uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 0, 1))
let back = SheetMetal.Flange(
    id: "back",
    profile: [SIMD2(0, 0), SIMD2(width, 0), SIMD2(width, wallHeight), SIMD2(0, wallHeight)],
    origin: SIMD3(0, depth, 0), normal: SIMD3(0, 1, 0),
    uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 0, 1))

let bends = [
    SheetMetal.Bend(from: "base", to: "front", radius: bendRadius),
    SheetMetal.Bend(from: "base", to: "back", radius: bendRadius),
]

do {
    let channel = try SheetMetal.Builder(thickness: thickness)
        .build(flanges: [base, front, back], bends: bends)
    try ctx.add(channel, color: C.steel, name: "Sheet-metal U-channel")
    print("Channel \(width)×\(depth)×\(wallHeight), volume: \(channel.volume ?? 0) mm³")
    try ctx.emit(description: "Sheet-metal U-channel — \(width)×\(depth), \(wallHeight) walls")
} catch {
    fatalError("SheetMetal build failed: \(error)")
}
