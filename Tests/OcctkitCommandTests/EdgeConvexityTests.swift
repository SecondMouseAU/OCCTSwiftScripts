// EdgeConvexityTests.swift
// OcctkitCommandTests
//
// Per-edge convexity and dihedral angle in the graph exports (OCCTSwiftScripts#55). Fixtures have
// physically determined answers: a cube edge is convex at pi/2, an inside corner of an L-shaped
// prism is concave at 3 pi/2, coplanar faces are smooth at pi, and an edge not between two faces
// has no convexity.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing

@testable import occtkit

@Suite("per-edge convexity (#55)")
struct EdgeConvexityTests {

    /// Two boxes unioned into an L-shaped prism: exactly one inside (concave) corner edge.
    private func lPrism() throws -> Shape {
        let base = try VerbHarness.box(20, 10, 10)
        let upright = try #require(
            try VerbHarness.box(10, 10, 20).translated(by: SIMD3(-5, 0, 5)))
        return try #require(base.union(upright))
    }

    private func openBox() throws -> Shape {
        let faces = try VerbHarness.box().subShapes(ofType: .face)
        return try #require(Shape.shellFromFaces(Array(faces.prefix(5))))
    }

    private func classify(_ shape: Shape) throws -> [Int: EdgeClassification] {
        EdgeClassifier.classify(shape: shape, graph: try GraphIO.buildGraph(from: shape))
    }

    // MARK: classifier

    @Test("every edge of a cube is convex at a right angle")
    func cube() throws {
        let classes = try classify(try VerbHarness.box())
        #expect(classes.count == 12)
        for (_, c) in classes {
            #expect(c.convexity == "convex")
            #expect(abs(try #require(c.dihedralAngle) - .pi / 2) < 1e-6)
        }
    }

    @Test("an L-shaped prism has exactly one concave edge, at three quarters of a turn")
    func lShapedPrism() throws {
        let shape = try lPrism()
        let graph = try GraphIO.buildGraph(from: shape)
        let classes = EdgeClassifier.classify(shape: shape, graph: graph)
        let concave = classes.filter { $0.value.convexity == "concave" }
        #expect(concave.count == 1)
        #expect(abs(try #require(concave.values.first?.dihedralAngle) - 3 * .pi / 2) < 1e-6)

        // The classification must land on the right graph edge, not just the right count. The
        // inside corner of this L runs along y at x = 0, z = 5 (the base's top face meets the
        // upright's side face).
        let index = try #require(concave.keys.first)
        let edge = try #require(graph.shape(nodeKind: .edge, nodeIndex: index))
        let centre = try #require(edge.center)
        #expect(abs(centre.x) < 1e-3 && abs(centre.y) < 1e-3 && abs(centre.z - 5) < 1e-3)
        #expect(abs(try #require(edge.size).y - 10) < 1e-3)

        // Coplanar faces left by the union are smooth at pi; the rest are convex at pi/2.
        for c in classes.values where c.convexity == "smooth" {
            #expect(abs(try #require(c.dihedralAngle) - .pi) < 1e-6)
        }
        for c in classes.values where c.convexity == "convex" {
            #expect(abs(try #require(c.dihedralAngle) - .pi / 2) < 1e-6)
        }
    }

    @Test("boundary edges of an open shell are unknown, not the kernel's 'tangent'")
    func openShellBoundaryEdges() throws {
        let shape = try openBox()
        let graph = try GraphIO.buildGraph(from: shape)
        let classes = EdgeClassifier.classify(shape: shape, graph: graph)
        let boundary = (0..<graph.edgeCount).filter { graph.faceCount(of: $0) == 1 }
        #expect(boundary.count == 4)
        for i in boundary {
            #expect(classes[i] == .unknown, "edge \(i) has one face, so no convexity")
        }
        // The eight edges between two faces are still classified.
        #expect(classes.values.filter { $0.convexity == "convex" }.count == 8)
    }

    @Test("edges shared by more than two faces of a compound are unknown")
    func nonManifoldEdgesAreUnknown() throws {
        let shape = try VerbHarness.splitBoxCompound()
        let graph = try GraphIO.buildGraph(from: shape)
        let classes = EdgeClassifier.classify(shape: shape, graph: graph)
        let crowded = (0..<graph.edgeCount).filter { graph.faceCount(of: $0) != 2 }
        #expect(!crowded.isEmpty, "the split compound must contain such edges")
        for i in crowded { #expect(classes[i] == .unknown) }
    }

    // MARK: exports

    @Test("the JSON export carries convexity and dihedralAngle per edge when given the shape")
    func jsonExportWithShape() throws {
        let dir = try VerbHarness.makeTempDir("edgeconv")
        defer { try? FileManager.default.removeItem(at: dir) }
        let shape = try lPrism()
        let graph = try GraphIO.buildGraph(from: shape)
        let url = dir.appendingPathComponent("g.json")

        try BREPGraphJSONExporter.export(graph, to: url, shape: shape)

        let doc = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let meta = try #require(doc["meta"] as? [String: Any])
        #expect(meta["schemaVersion"] as? String == "1.1.0")
        let edges = try #require((doc["nodes"] as? [String: Any])?["edges"] as? [[String: Any]])
        #expect(edges.count == graph.edgeCount)
        let concave = edges.filter { $0["convexity"] as? String == "concave" }
        #expect(concave.count == 1)
        #expect(
            abs(try VerbHarness.number(try #require(concave.first), "dihedralAngle") - 3 * .pi / 2)
                < 1e-6)
    }

    @Test("without the shape the JSON export omits the new keys")
    func jsonExportWithoutShape() throws {
        let dir = try VerbHarness.makeTempDir("edgeconv")
        defer { try? FileManager.default.removeItem(at: dir) }
        let graph = try GraphIO.buildGraph(from: try VerbHarness.box())
        let url = dir.appendingPathComponent("g.json")

        try BREPGraphJSONExporter.export(graph, to: url)

        let doc = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let edges = try #require((doc["nodes"] as? [String: Any])?["edges"] as? [[String: Any]])
        #expect(edges.allSatisfy { $0["convexity"] == nil && $0["dihedralAngle"] == nil })
    }

    @Test("graph-ml emits convexity and dihedralAngle on every edge")
    func graphMLEdges() throws {
        let dir = try VerbHarness.makeTempDir("edgeconv")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try VerbHarness.writeBREP(try lPrism(), named: "l", in: dir)

        let json = try VerbHarness.runJSON(
            GraphMLCommand.self, [path, "--uv-samples", "2", "--edge-samples", "2"])

        let edges = try #require(json["edges"] as? [[String: Any]])
        #expect(edges.count == 28)
        #expect(edges.filter { $0["convexity"] as? String == "concave" }.count == 1)
        #expect(edges.allSatisfy { $0["convexity"] is String })
        // Face-pair convexity (gAAG) from the earlier #55 work still agrees that a concave edge exists.
        let adjacency = try #require(json["faceAdjacency"] as? [[String: Any]])
        #expect(adjacency.contains { $0["convexity"] as? String == "concave" })
    }
}
