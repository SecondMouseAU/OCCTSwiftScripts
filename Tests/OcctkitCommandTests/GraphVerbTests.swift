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

    // MARK: graph-compact / graph-dedup

    /// A solid with an inner cavity: one solid bounded by two shells.
    private func hollowBox() throws -> Shape {
        try #require(try VerbHarness.box().subtracting(try VerbHarness.box(4, 4, 4)))
    }

    /// Runs `verb` on `shape` and returns the BREP it wrote plus its JSON report.
    private func rebuild(
        _ verb: any Subcommand.Type, _ shape: Shape, label: String
    ) throws -> (shape: Shape, report: [String: Any]) {
        let dir = try VerbHarness.makeTempDir(label)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(shape, named: "in", in: dir)
        let output = dir.appendingPathComponent("out.brep").path
        let report = try VerbHarness.runJSON(verb, [input, output])
        return (try GraphIO.loadBREP(at: output), report)
    }

    /// The rebuilt shape must be the same body.
    ///
    /// Same volume, same solid and face counts: a bare shell or a lone sub-shape would keep a
    /// plausible volume but lose a count.
    private func expectSameBody(_ rebuilt: Shape, as original: Shape) throws {
        let want = try #require(original.volume)
        #expect(abs(try #require(rebuilt.volume) - want) < 1e-6 * max(1, want))
        #expect(
            rebuilt.subShapeCount(ofType: .solid) == original.subShapeCount(ofType: .solid))
        #expect(rebuilt.faces().count == original.faces().count)
    }

    @Test("graph-compact rebuilds a cube")
    func compactCube() throws {
        let cube = try VerbHarness.box()
        let result = try rebuild(GraphCompactCommand.self, cube, label: "compact")
        try expectSameBody(result.shape, as: cube)
        #expect(result.report["nodesBefore"] != nil)
    }

    @Test(
        "graph-compact keeps both solids and the shared face of a compound, and reports the real counts"
    )
    func compactCompound() throws {
        let compound = try VerbHarness.splitBoxCompound()
        let result = try rebuild(GraphCompactCommand.self, compound, label: "compact")
        try expectSameBody(result.shape, as: compound)
        #expect(result.shape.subShapeCount(ofType: .solid) == 2)

        // The report must match an independent run of the same graph operation, so a verb
        // that rebuilt the shape but reported made-up numbers fails.
        let graph = try GraphIO.buildGraph(from: compound)
        let before = graph.stats.totalNodes
        let compacted = graph.compact()
        #expect(try VerbHarness.number(result.report, "nodesBefore") == Double(before))
        #expect(try VerbHarness.number(result.report, "nodesAfter") == Double(compacted.nodesAfter))
        #expect(
            try VerbHarness.number(result.report, "removed", "faces")
                == Double(compacted.removedFaces))
    }

    @Test("graph-compact keeps a hollow solid's cavity")
    func compactHollow() throws {
        let hollow = try hollowBox()
        try expectSameBody(
            try rebuild(GraphCompactCommand.self, hollow, label: "compact").shape, as: hollow)
    }

    @Test("graph-dedup rebuilds a cube")
    func dedupCube() throws {
        let cube = try VerbHarness.box()
        let result = try rebuild(GraphDedupCommand.self, cube, label: "dedup")
        try expectSameBody(result.shape, as: cube)
        #expect(result.report["output"] != nil)
    }

    @Test(
        "graph-dedup keeps both solids and the shared face of a compound, and reports the real counts"
    )
    func dedupCompound() throws {
        let compound = try VerbHarness.splitBoxCompound()
        let result = try rebuild(GraphDedupCommand.self, compound, label: "dedup")
        try expectSameBody(result.shape, as: compound)
        #expect(result.shape.subShapeCount(ofType: .solid) == 2)

        let expected = try GraphIO.buildGraph(from: compound).deduplicate()
        #expect(
            try VerbHarness.number(result.report, "canonicalSurfaces")
                == Double(expected.canonicalSurfaces))
        #expect(
            try VerbHarness.number(result.report, "canonicalCurves")
                == Double(expected.canonicalCurves))
    }

    @Test("graph-dedup keeps a hollow solid's cavity")
    func dedupHollow() throws {
        let hollow = try hollowBox()
        try expectSameBody(
            try rebuild(GraphDedupCommand.self, hollow, label: "dedup").shape, as: hollow)
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
