// AnalysisVerbTests.swift
// OcctkitCommandTests
//
// Coverage for the engineering-analysis and I/O verbs: `check-thickness`, `analyze-clearance`,
// `heal`, `mesh`, `load-brep`. Fixtures are boxes with analytically known answers.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing

@testable import occtkit

@Suite("occtkit analysis verbs", .serialized)
struct AnalysisVerbTests {

    private func write(_ shape: Shape, _ name: String, in dir: URL) throws -> String {
        try VerbHarness.writeBREP(shape, named: name, in: dir)
    }

    // MARK: check-thickness

    @Test("check-thickness measures a 2mm plate as 2mm and flags it below a 5mm minimum")
    func thinPlateIsFlagged() throws {
        let dir = try VerbHarness.makeTempDir("thickness")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write(try VerbHarness.box(40, 40, 2), "plate", in: dir)

        let json = try VerbHarness.runJSON(
            CheckThicknessCommand.self, [path, "--min-acceptable", "5"])

        #expect(abs(try VerbHarness.number(json, "minThickness") - 2) < 1e-2)
        let thin = try #require(json["thinRegions"] as? [[String: Any]])
        #expect(!thin.isEmpty)
        for region in thin { #expect(try VerbHarness.number(region, "thickness") < 5) }
    }

    @Test("check-thickness reports no thin regions on a 10mm cube against a 5mm minimum")
    func thickCubeIsClean() throws {
        let dir = try VerbHarness.makeTempDir("thickness")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write(try VerbHarness.box(), "cube", in: dir)

        let json = try VerbHarness.runJSON(
            CheckThicknessCommand.self, [path, "--min-acceptable", "5"])

        #expect(abs(try VerbHarness.number(json, "minThickness") - 10) < 1e-2)
        #expect((json["thinRegions"] as? [Any])?.isEmpty == true)
    }

    @Test("check-thickness sampling density changes the sample count")
    func samplingDensityScalesSamples() throws {
        let dir = try VerbHarness.makeTempDir("thickness")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write(try VerbHarness.box(), "cube", in: dir)

        let coarse = try VerbHarness.runJSON(
            CheckThicknessCommand.self, [path, "--sampling-density", "coarse"])
        let fine = try VerbHarness.runJSON(
            CheckThicknessCommand.self, [path, "--sampling-density", "fine"])

        // 6 faces: 4x4 grid is 96 samples, 16x16 is 1536.
        #expect(try VerbHarness.number(coarse, "samples") == 96)
        #expect(try VerbHarness.number(fine, "samples") == 1536)
    }

    // MARK: analyze-clearance

    private func pair(gap: Double, in dir: URL) throws -> (String, String) {
        let a = try write(try VerbHarness.box(), "a", in: dir)
        let moved = try #require(try VerbHarness.box().translated(by: SIMD3(10 + gap, 0, 0)))
        return (a, try write(moved, "b", in: dir))
    }

    private func firstPair(_ json: [String: Any]) throws -> [String: Any] {
        let pairs = try #require(json["pairs"] as? [[String: Any]])
        return try #require(pairs.first)
    }

    @Test("analyze-clearance reports the gap between separated cubes and no interference")
    func separatedCubes() throws {
        let dir = try VerbHarness.makeTempDir("clearance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, b) = try pair(gap: 20, in: dir)

        let result = try firstPair(
            try VerbHarness.runJSON(AnalyzeClearanceCommand.self, [a, b, "--min-clearance", "25"]))

        #expect(abs(try VerbHarness.number(result, "minDistance") - 20) < 1e-3)
        #expect(result["intersects"] as? Bool == false)
        #expect(result["belowMinClearance"] as? Bool == true, "20mm gap is under the 25mm minimum")
        #expect(result["interferenceVolume"] == nil || result["interferenceVolume"] is NSNull)
    }

    @Test("analyze-clearance reports the interference volume of overlapping cubes")
    func overlappingCubes() throws {
        let dir = try VerbHarness.makeTempDir("clearance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, b) = try pair(gap: -2, in: dir)  // 2mm overlap slab, 2 x 10 x 10

        let result = try firstPair(try VerbHarness.runJSON(AnalyzeClearanceCommand.self, [a, b]))

        #expect(result["intersects"] as? Bool == true)
        #expect(abs(try VerbHarness.number(result, "interferenceVolume") - 200) < 1e-2)
    }

    @Test("analyze-clearance --no-contacts drops the contact list")
    func noContacts() throws {
        let dir = try VerbHarness.makeTempDir("clearance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, b) = try pair(gap: 20, in: dir)

        let withContacts = try firstPair(try VerbHarness.runJSON(AnalyzeClearanceCommand.self, [a, b]))
        let without = try firstPair(
            try VerbHarness.runJSON(AnalyzeClearanceCommand.self, [a, b, "--no-contacts"]))

        #expect(!((withContacts["contacts"] as? [Any]) ?? []).isEmpty)
        #expect(((without["contacts"] as? [Any]) ?? []).isEmpty)
    }

    @Test("analyze-clearance --max-contacts caps the contact list")
    func maxContactsCaps() throws {
        let dir = try VerbHarness.makeTempDir("clearance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, b) = try pair(gap: 20, in: dir)  // 4 equal-distance corner contacts

        let all = try firstPair(try VerbHarness.runJSON(AnalyzeClearanceCommand.self, [a, b]))
        let capped = try firstPair(
            try VerbHarness.runJSON(AnalyzeClearanceCommand.self, [a, b, "--max-contacts", "2"]))

        #expect((all["contacts"] as? [Any])?.count == 4)
        #expect((capped["contacts"] as? [Any])?.count == 2)
    }

    // MARK: heal

    @Test("heal reports the free edges of an open shell before healing and writes a BREP")
    func healReportsBeforeState() throws {
        let dir = try VerbHarness.makeTempDir("heal")
        defer { try? FileManager.default.removeItem(at: dir) }
        let faces = try VerbHarness.box().subShapes(ofType: .face)
        let open = try #require(Shape.shellFromFaces(Array(faces.prefix(5))))
        let input = try write(open, "open", in: dir)
        let output = dir.appendingPathComponent("healed.brep").path

        let json = try VerbHarness.runJSON(HealCommand.self, [input, "--output", output])

        #expect(try VerbHarness.number(json, "before", "freeEdgeCount") == 4)
        #expect(FileManager.default.fileExists(atPath: output))
        #expect(try GraphIO.loadBREP(at: output).faces().count >= 5)
    }

    @Test("heal on an already clean cube changes nothing and says so")
    func healCleanCubeIsNoOp() throws {
        let dir = try VerbHarness.makeTempDir("heal")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try write(try VerbHarness.box(), "cube", in: dir)
        let output = dir.appendingPathComponent("healed.brep").path

        let json = try VerbHarness.runJSON(HealCommand.self, [input, "--output", output])

        #expect(try VerbHarness.number(json, "before", "faceCount") == 6)
        #expect(try VerbHarness.number(json, "after", "faceCount") == 6)
        #expect(try VerbHarness.number(json, "after", "freeEdgeCount") == 0)
        let warnings = try #require(json["warnings"] as? [String])
        #expect(warnings.contains { $0.contains("no changes") })
    }

    // MARK: mesh

    @Test("mesh triangulates a cube into 12 triangles and returns the geometry inline")
    func meshCubeInline() throws {
        let dir = try VerbHarness.makeTempDir("mesh")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write(try VerbHarness.box(), "cube", in: dir)

        let json = try VerbHarness.runJSON(MeshCommand.self, [path])

        #expect(try VerbHarness.number(json, "triangleCount") == 12)
        let geometry = try #require(json["geometry"] as? [String: Any])
        #expect((geometry["indices"] as? [Any])?.count == 36)  // 12 triangles x 3
        #expect((geometry["vertices"] as? [Any])?.count == Int(try VerbHarness.number(json, "vertexCount")) * 3)
    }

    @Test("mesh --output writes an STL and drops the inline geometry")
    func meshWritesStl() throws {
        let dir = try VerbHarness.makeTempDir("mesh")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write(try VerbHarness.box(), "cube", in: dir)
        let stl = dir.appendingPathComponent("cube.stl").path

        let json = try VerbHarness.runJSON(MeshCommand.self, [path, "--output", stl])

        #expect(FileManager.default.fileExists(atPath: stl))
        #expect(json["geometry"] is NSNull || json["geometry"] == nil)
        #expect(json["outputPath"] as? String == stl)
    }

    @Test("mesh --no-return-geometry keeps the counts but drops the geometry")
    func meshNoGeometry() throws {
        let dir = try VerbHarness.makeTempDir("mesh")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try write(try VerbHarness.box(), "cube", in: dir)

        let json = try VerbHarness.runJSON(MeshCommand.self, [path, "--no-return-geometry"])

        #expect(try VerbHarness.number(json, "triangleCount") == 12)
        #expect(json["geometry"] is NSNull || json["geometry"] == nil)
    }

    // MARK: load-brep

    @Test("load-brep copies the body into the manifest directory under the requested id")
    func loadBrepWritesManifest() throws {
        let dir = try VerbHarness.makeTempDir("loadbrep")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try write(try VerbHarness.box(), "cube", in: dir)
        let emit = dir.appendingPathComponent("emit")

        let json = try VerbHarness.runJSON(
            LoadBrepCommand.self, [input, "--emit-manifest", emit.path, "--id", "widget"])

        #expect(json["bodyId"] as? String == "widget")
        #expect(try VerbHarness.number(json, "faceCount") == 6)
        #expect(try VerbHarness.number(json, "vertexCount") == 8)
        #expect(FileManager.default.fileExists(atPath: emit.appendingPathComponent("widget.brep").path))
        let manifest = try String(
            contentsOf: emit.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(manifest.contains("widget"))
    }

    @Test("load-brep fails on a missing input and writes no manifest")
    func loadBrepMissingInput() throws {
        let dir = try VerbHarness.makeTempDir("loadbrep")
        defer { try? FileManager.default.removeItem(at: dir) }
        let emit = dir.appendingPathComponent("emit")

        #expect(throws: (any Error).self) {
            try VerbHarness.run(
                LoadBrepCommand.self, ["/nonexistent/none.brep", "--emit-manifest", emit.path])
        }
        #expect(!FileManager.default.fileExists(atPath: emit.appendingPathComponent("manifest.json").path))
    }
}
