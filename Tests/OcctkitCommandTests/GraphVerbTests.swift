// GraphVerbTests.swift
// OcctkitCommandTests
//
// Coverage for the BRepGraph-backed verbs: `graph-validate`, `graph-query`, `graph-compact`,
// `graph-dedup`, and `feature-recognize` (which reads the AAG built over the same graph).
// `graph-select` and `graph-ml` are covered by `AAGFaceIndexTests`.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing

@testable import occtkit

@Suite("occtkit graph verbs", .serialized)
struct GraphVerbTests {

    /// A cube with its top face removed: five faces sewn into an open shell with 4 free edges.
    private func openBox() throws -> Shape {
        let faces = try VerbHarness.box().subShapes(ofType: .face)
        return try #require(Shape.shellFromFaces(Array(faces.prefix(5))))
    }

    // MARK: graph-validate

    @Test("graph-validate accepts a cube with no errors and no free edges")
    func validCube() throws {
        let dir = try VerbHarness.makeTempDir("validate")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try VerbHarness.writeBREP(try VerbHarness.box(), named: "cube", in: dir)

        let json = try VerbHarness.runJSON(GraphValidateCommand.self, [path])

        #expect(json["isValid"] as? Bool == true)
        #expect(try VerbHarness.number(json, "errorCount") == 0)
        #expect(try VerbHarness.number(json, "healthRecord", "freeEdgeCount") == 0)
        let record = try #require(json["healthRecord"] as? [String: Any])
        #expect(record["shapeType"] as? String == "solid")
    }

    @Test("graph-validate reports the 4 free edges of a cube missing a face")
    func openShellHasFreeEdges() throws {
        let dir = try VerbHarness.makeTempDir("validate")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try VerbHarness.writeBREP(try openBox(), named: "open", in: dir)

        let json = try VerbHarness.runJSON(GraphValidateCommand.self, [path])

        #expect(try VerbHarness.number(json, "healthRecord", "freeEdgeCount") == 4)
        let record = try #require(json["healthRecord"] as? [String: Any])
        #expect(record["shapeType"] as? String == "shell")
    }

    @Test("graph-validate fails on a missing file")
    func validateMissingFile() {
        #expect(throws: (any Error).self) {
            try VerbHarness.run(GraphValidateCommand.self, ["/nonexistent/none.brep"])
        }
    }

    // MARK: graph-query

    @Test("graph-query summarises an exported cube graph: 1 solid, 6 faces, 12 edges, 8 vertices")
    func queryCubeGraph() throws {
        let dir = try VerbHarness.makeTempDir("query")
        defer { try? FileManager.default.removeItem(at: dir) }
        let graph = try GraphIO.buildGraph(from: try VerbHarness.box())
        let sqlite = dir.appendingPathComponent("cube.sqlite")
        try BREPGraphSQLiteExporter.export(graph, to: sqlite)

        let json = try VerbHarness.runJSON(GraphQueryCommand.self, [sqlite.path])

        #expect(try VerbHarness.number(json, "summary", "solids") == 1)
        #expect(try VerbHarness.number(json, "summary", "faces") == 6)
        #expect(try VerbHarness.number(json, "summary", "edges") == 12)
        #expect(try VerbHarness.number(json, "summary", "vertices") == 8)
        #expect(try VerbHarness.number(json, "counts", "freeEdges") == 0)
    }

    @Test("graph-query rejects a path that does not exist")
    func queryMissingFile() {
        #expect(throws: (any Error).self) {
            try VerbHarness.run(GraphQueryCommand.self, ["/nonexistent/none.sqlite"])
        }
    }

    // MARK: graph-compact / graph-dedup (broken, #128)

    @Test(
        "graph-compact writes a rebuilt shape",
        .bug("https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/128"))
    func compactRebuildsShape() throws {
        let dir = try VerbHarness.makeTempDir("compact")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(try VerbHarness.box(), named: "in", in: dir)
        let output = dir.appendingPathComponent("out.brep").path

        // #128: BRepGraph.rootNodes is empty, so the verb throws on every input. When the bug is
        // fixed this block stops throwing, withKnownIssue fails, and the marker must come off.
        withKnownIssue("graph-compact fails on every input (#128)") {
            try VerbHarness.run(GraphCompactCommand.self, [input, output])
            let rebuilt = try GraphIO.loadBREP(at: output)
            #expect(abs(try #require(rebuilt.volume) - 1000) < 1e-3)
        }
    }

    @Test(
        "graph-dedup writes a rebuilt shape",
        .bug("https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/128"))
    func dedupRebuildsShape() throws {
        let dir = try VerbHarness.makeTempDir("dedup")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(try VerbHarness.box(), named: "in", in: dir)
        let output = dir.appendingPathComponent("out.brep").path

        withKnownIssue("graph-dedup fails on every input (#128)") {
            try VerbHarness.run(GraphDedupCommand.self, [input, output])
            let rebuilt = try GraphIO.loadBREP(at: output)
            #expect(abs(try #require(rebuilt.volume) - 1000) < 1e-3)
        }
    }

    // MARK: feature-recognize

    private func recognise(_ shape: Shape) throws -> [String: Any] {
        let dir = try VerbHarness.makeTempDir("recognize")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try VerbHarness.writeBREP(shape, named: "part", in: dir)
        return try VerbHarness.runJSON(FeatureRecognizeCommand.self, [path])
    }

    @Test("feature-recognize finds no features on a plain cube")
    func plainCubeHasNoFeatures() throws {
        let json = try recognise(try VerbHarness.box())
        #expect((json["holes"] as? [Any])?.isEmpty == true)
        #expect((json["pockets"] as? [Any])?.isEmpty == true)
        #expect((json["features"] as? [Any])?.isEmpty == true)
    }

    @Test("feature-recognize finds a through hole with its radius and depth")
    func throughHole() throws {
        let plate = try VerbHarness.box(40, 40, 10)
        let pin = try #require(Shape.cylinder(radius: 4, height: 20))
        let centred = try #require(pin.translated(by: SIMD3(0, 0, -10)))
        let drilled = try #require(plate.subtracting(centred))

        let json = try recognise(drilled)

        let holes = try #require(json["holes"] as? [[String: Any]])
        #expect(holes.count == 1)
        #expect(abs(try VerbHarness.number(holes[0], "radius") - 4) < 1e-3)
        #expect(abs(try VerbHarness.number(holes[0], "depth") - 10) < 1e-2)
        let features = try #require(json["features"] as? [[String: Any]])
        #expect(features.contains { $0["kind"] as? String == "hole" })
    }
}
