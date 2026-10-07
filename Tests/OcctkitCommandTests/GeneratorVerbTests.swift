// GeneratorVerbTests.swift
// OcctkitCommandTests
//
// Coverage for the JSON-spec generator verbs: `reconstruct`, `compose-sheet-metal`,
// `drawing-export`. Specs are built with `JSONSerialization` and the produced files are read back.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing

@testable import occtkit

@Suite("occtkit generator verbs", .serialized)
struct GeneratorVerbTests {

    // MARK: reconstruct

    /// A 10 x 10 x 5 block with a 4mm through-bore.
    ///
    /// Extrude is the control path: it yields a real solid.
    private func blockFeatures(extra: [[String: Any]] = []) -> [[String: Any]] {
        [
            [
                "kind": "extrude", "id": "block",
                "profile_points_2d": [[0, 0], [10, 0], [10, 10], [0, 10]],
                "plane_origin": [0, 0, 0], "plane_normal": [0, 0, 1], "length": 5,
            ],
            [
                "kind": "hole", "id": "bore",
                "axis_point": [5, 5, 10], "axis_direction": [0, 0, -1], "diameter": 4, "depth": 20,
            ],
        ] + extra
    }

    @Test("reconstruct builds a block with a drilled bore of the analytic volume")
    func reconstructBlockWithBore() throws {
        let dir = try VerbHarness.makeTempDir("reconstruct")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try VerbHarness.writeJSON(
            ["outputDir": dir.path, "outputName": "block", "features": blockFeatures()],
            named: "spec.json", in: dir)

        let json = try VerbHarness.runJSON(ReconstructCommand.self, [spec])

        #expect(json["fulfilled"] as? [String] == ["block", "bore"])
        #expect((json["skipped"] as? [Any])?.isEmpty == true)
        let shape = try GraphIO.loadBREP(at: try #require(json["shape"] as? String))
        #expect(shape.subShapeCount(ofType: .solid) == 1)
        let expected = 10 * 10 * 5 - Double.pi * 2 * 2 * 5
        #expect(abs(try #require(shape.volume) - expected) < 1e-2)
    }

    @Test(
        "reconstruct revolve yields a solid",
        .bug("https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/129"))
    func reconstructRevolveIsSolid() throws {
        let dir = try VerbHarness.makeTempDir("reconstruct")
        defer { try? FileManager.default.removeItem(at: dir) }
        let revolve: [String: Any] = [
            "kind": "revolve", "id": "body",
            "profile_points_2d": [[0, 0], [12, 0], [12, 60], [0, 60]],
            "axis_origin": [0, 0, 0], "axis_direction": [0, 0, 1], "angle_deg": 360,
        ]
        let spec = try VerbHarness.writeJSON(
            ["outputDir": dir.path, "outputName": "shaft", "features": [revolve]],
            named: "spec.json", in: dir)

        let json = try VerbHarness.runJSON(ReconstructCommand.self, [spec])
        let shape = try GraphIO.loadBREP(at: try #require(json["shape"] as? String))

        // #129: the revolve comes back as a bare Shell. A shell still reports a plausible volume,
        // so the solid count is the assertion that matters (#100).
        withKnownIssue("revolve returns a Shell with no solid (#129)") {
            #expect(shape.subShapeCount(ofType: .solid) == 1)
        }
    }

    @Test("reconstruct reports an unknown feature kind as skipped and still builds the rest")
    func reconstructSkipsUnknownKind() throws {
        let dir = try VerbHarness.makeTempDir("reconstruct")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try VerbHarness.writeJSON(
            [
                "outputDir": dir.path, "outputName": "block",
                "features": blockFeatures(extra: [["kind": "widget", "id": "mystery"]]),
            ], named: "spec.json", in: dir)

        let json = try VerbHarness.runJSON(ReconstructCommand.self, [spec])

        #expect(json["fulfilled"] as? [String] == ["block", "bore"])
        let skipped = try #require(json["skipped"] as? [[String: Any]])
        #expect(skipped.count == 1)
        #expect(skipped.first?["id"] as? String == "mystery")
    }

    @Test("reconstruct exits 2 and writes no shape when nothing can be built")
    func reconstructNothingBuilt() throws {
        let dir = try VerbHarness.makeTempDir("reconstruct")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try VerbHarness.writeJSON(
            [
                "outputDir": dir.path, "outputName": "none",
                "features": [["kind": "widget", "id": "mystery"]],
            ], named: "spec.json", in: dir)

        let result = try VerbHarness.runAllowingFailure(ReconstructCommand.self, [spec])

        #expect(result.exit == 2)
        #expect(
            !FileManager.default.fileExists(atPath: dir.appendingPathComponent("none.brep").path))
    }

    @Test("reconstruct rejects malformed JSON")
    func reconstructBadJSON() throws {
        let dir = try VerbHarness.makeTempDir("reconstruct")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("bad.json")
        try Data("{ not json".utf8).write(to: path)

        #expect(throws: (any Error).self) {
            try VerbHarness.run(ReconstructCommand.self, [path.path])
        }
    }

    // MARK: compose-sheet-metal

    private func flatPlate(outputDir: URL, thickness: Double = 1.5) -> [String: Any] {
        [
            "outputDir": outputDir.path, "outputName": "plate", "thickness": thickness,
            "flanges": [
                [
                    "id": "base", "profile": [[0, 0], [80, 0], [80, 50], [0, 50]],
                    "origin": [0, 0, 0], "uAxis": [1, 0, 0], "normal": [0, 0, 1],
                ]
            ],
        ]
    }

    @Test("compose-sheet-metal extrudes a flat flange to profile area times thickness")
    func sheetMetalPlateVolume() throws {
        let dir = try VerbHarness.makeTempDir("sheetmetal")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try VerbHarness.writeJSON(flatPlate(outputDir: dir), named: "spec.json", in: dir)

        let json = try VerbHarness.runJSON(ComposeSheetMetalCommand.self, [spec])

        #expect(try VerbHarness.number(json, "flanges") == 1)
        #expect(try VerbHarness.number(json, "bends") == 0)
        let shape = try GraphIO.loadBREP(at: try #require(json["shape"] as? String))
        #expect(abs(try #require(shape.volume) - 80 * 50 * 1.5) < 1e-2)
    }

    @Test("compose-sheet-metal thickness scales the volume")
    func sheetMetalThickness() throws {
        let dir = try VerbHarness.makeTempDir("sheetmetal")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try VerbHarness.writeJSON(
            flatPlate(outputDir: dir, thickness: 3), named: "spec.json", in: dir)

        let json = try VerbHarness.runJSON(ComposeSheetMetalCommand.self, [spec])

        let shape = try GraphIO.loadBREP(at: try #require(json["shape"] as? String))
        #expect(abs(try #require(shape.volume) - 80 * 50 * 3) < 1e-2)
    }

    @Test("compose-sheet-metal rejects a flange whose origin is not 3 numbers")
    func sheetMetalBadOrigin() throws {
        let dir = try VerbHarness.makeTempDir("sheetmetal")
        defer { try? FileManager.default.removeItem(at: dir) }
        var request = flatPlate(outputDir: dir)
        var flanges = try #require(request["flanges"] as? [[String: Any]])
        flanges[0]["origin"] = [0, 0]
        request["flanges"] = flanges
        let spec = try VerbHarness.writeJSON(request, named: "spec.json", in: dir)

        #expect(throws: (any Error).self) {
            try VerbHarness.run(ComposeSheetMetalCommand.self, [spec])
        }
    }

    // MARK: drawing-export

    @Test("drawing-export lays three views of a cube onto one DXF sheet")
    func drawingThreeViews() throws {
        let dir = try VerbHarness.makeTempDir("drawing")
        defer { try? FileManager.default.removeItem(at: dir) }
        let brep = try VerbHarness.writeBREP(try VerbHarness.box(), named: "cube", in: dir)
        let out = dir.appendingPathComponent("sheet.dxf").path
        let spec = try VerbHarness.writeJSON(
            [
                "shape": brep, "output": out,
                "sheet": [
                    "size": "a3", "orientation": "landscape", "projection": "third",
                    "scale": "auto",
                ],
                "title": ["title": "Cube"],
                "views": [["name": "front"], ["name": "top"], ["name": "right"]],
            ], named: "spec.json", in: dir)

        let json = try VerbHarness.runJSON(DrawingExportCommand.self, [spec])

        #expect(try VerbHarness.number(json, "viewCount") == 3)
        #expect(json["sheet"] as? String == "A3 landscape")
        let dxf = try String(contentsOfFile: out, encoding: .utf8)
        #expect(dxf.contains("ENTITIES"))
        #expect(dxf.contains("Cube"), "title block text reaches the sheet")
    }

    @Test("drawing-export rejects a spec that is not JSON")
    func drawingBadSpec() throws {
        let dir = try VerbHarness.makeTempDir("drawing")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("bad.json")
        try Data("nope".utf8).write(to: path)

        #expect(throws: (any Error).self) {
            try VerbHarness.run(DrawingExportCommand.self, [path.path])
        }
    }
}
