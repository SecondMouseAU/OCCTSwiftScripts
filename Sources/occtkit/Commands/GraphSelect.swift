// GraphSelect — direct B-rep graph adjacency / selection queries.
//
// Closes OCCTSwiftScripts#54. Lets a consumer answer a *local* topology
// question — "what is adjacent to face[N]?", "faces of edge[M]?", "edges of
// vertex[K]?", "all boundary edges", "the convex/concave face adjacencies" —
// without exporting and re-parsing the whole graph (graph-ml). This is the
// selection / "pointer" primitive behind DSL-style selectors and the
// face-adjacency-graph + GNN selection used in the generative-CAD literature
// (UV-Net, Pointer-CAD, AAGNet).
//
// Index spaces: face queries run over the Attributed Adjacency Graph (AAG),
// whose face indices follow `shape.faces()` order — the same `face[N]` scheme
// `query-topology` emits. Edge/vertex queries run over the BRepGraph
// (`edge[M]` / `vertex[K]`). Convexity is a property of the dihedral between two
// faces, so it is reported on face *adjacencies* (AAG edges), not on a lone edge.
//
// Usage:
//   graph-select <shape.brep> --query face-neighbors --face N
//   graph-select <shape.brep> --query edge-faces     --edge M
//   graph-select <shape.brep> --query vertex-edges   --vertex K
//   graph-select <shape.brep> --query face-adjacency
//   graph-select <shape.brep> --query edges-class    --class boundary|non-manifold|seam|degenerate

import Foundation
import OCCTSwift
import ScriptHarness

extension EdgeConvexity {
    /// Stable lowercase label for JSON output.
    var label: String {
        switch self {
        case .concave: return "concave"
        case .smooth:  return "smooth"
        case .convex:  return "convex"
        }
    }
}

enum GraphSelectCommand: Subcommand {
    static let name = "graph-select"
    static let summary = "Query B-rep graph adjacency / selection (face neighbours, edge faces, vertex edges, convexity)"
    static let usage = """
        Usage:
          graph-select <shape.brep> --query <type> [ids]

        Queries:
          --query face-neighbors --face N    faces adjacent to face N (+ convexity, shared-edge count)
          --query edge-faces     --edge M    faces / vertices / flags of edge M
          --query vertex-edges   --vertex K  edges incident to vertex K
          --query face-adjacency             full attributed face-adjacency graph (gAAG)
          --query edges-class    --class K   edge indices matching: boundary | non-manifold | seam | degenerate

        Face indices follow shape.faces() order (the `face[N]` scheme query-topology emits);
        edge/vertex indices are BRepGraph indices (`edge[M]` / `vertex[K]`).
        """

    // MARK: responses

    struct NeighbourOut: Encodable { let face: Int; let convexity: String; let sharedEdgeCount: Int }
    struct FaceNeighboursResponse: Encodable {
        let query = "face-neighbors"
        let face: Int
        let isPlanar: Bool
        let isVertical: Bool
        let isHorizontal: Bool
        let normal: [Double]?
        let neighbors: [NeighbourOut]
    }
    struct EdgeFacesResponse: Encodable {
        let query = "edge-faces"
        let edge: Int
        let faces: [Int]
        let startVertex: Int?
        let endVertex: Int?
        let boundary: Bool
        let manifold: Bool
    }
    struct VertexEdgesResponse: Encodable {
        let query = "vertex-edges"
        let vertex: Int
        let edges: [Int]
    }
    struct FaceAdj: Encodable { let face1: Int; let face2: Int; let convexity: String; let sharedEdgeCount: Int }
    struct FaceAdjacencyResponse: Encodable {
        let query = "face-adjacency"
        let faceCount: Int
        let adjacencies: [FaceAdj]
    }
    struct EdgesClassResponse: Encodable {
        let query = "edges-class"
        let `class`: String
        let edges: [Int]
    }

    // MARK: run

    static func run(args: [String]) throws -> Int32 {
        guard let path = args.first(where: { !$0.hasPrefix("--") }) else {
            throw ScriptError.message(usage)
        }
        let queryType = value("--query", in: args) ?? "face-adjacency"
        let shape = try GraphIO.loadBREP(at: path)

        switch queryType {
        case "face-neighbors":
            let aag = AAG(shape: shape)
            let face = try intValue("--face", in: args)
            guard face >= 0 && face < aag.nodes.count else {
                throw ScriptError.message("face \(face) out of range (0..<\(aag.nodes.count))")
            }
            let node = aag.nodes[face]
            let neighbors = aag.neighbors(of: face).sorted().map { nb -> NeighbourOut in
                let e = aag.edge(between: face, and: nb)
                return NeighbourOut(face: nb,
                                    convexity: (e?.convexity ?? .smooth).label,
                                    sharedEdgeCount: e?.sharedEdgeCount ?? 0)
            }
            try GraphIO.emitJSON(FaceNeighboursResponse(
                face: face,
                isPlanar: node.isPlanar,
                isVertical: node.isVertical,
                isHorizontal: node.isHorizontal,
                normal: node.normal.map { [$0.x, $0.y, $0.z] },
                neighbors: neighbors))

        case "edge-faces":
            let g = try GraphIO.buildGraph(from: shape)
            let edge = try intValue("--edge", in: args)
            guard edge >= 0 && edge < g.edgeCount else {
                throw ScriptError.message("edge \(edge) out of range (0..<\(g.edgeCount))")
            }
            try GraphIO.emitJSON(EdgeFacesResponse(
                edge: edge,
                faces: g.faces(of: edge),
                startVertex: g.edgeStartVertex(edge),
                endVertex: g.edgeEndVertex(edge),
                boundary: g.isBoundaryEdge(edge),
                manifold: g.isManifoldEdge(edge)))

        case "vertex-edges":
            let g = try GraphIO.buildGraph(from: shape)
            let vertex = try intValue("--vertex", in: args)
            guard vertex >= 0 && vertex < g.vertexCount else {
                throw ScriptError.message("vertex \(vertex) out of range (0..<\(g.vertexCount))")
            }
            try GraphIO.emitJSON(VertexEdgesResponse(vertex: vertex, edges: g.edges(of: vertex)))

        case "face-adjacency":
            let aag = AAG(shape: shape)
            let adjacencies = aag.edges.map {
                FaceAdj(face1: $0.face1Index, face2: $0.face2Index,
                        convexity: $0.convexity.label, sharedEdgeCount: $0.sharedEdgeCount)
            }
            try GraphIO.emitJSON(FaceAdjacencyResponse(faceCount: aag.nodes.count, adjacencies: adjacencies))

        case "edges-class":
            let g = try GraphIO.buildGraph(from: shape)
            let kind = value("--class", in: args) ?? "boundary"
            let matches: [Int] = (0..<g.edgeCount).filter { i in
                switch kind {
                case "boundary":     return g.isBoundaryEdge(i)
                case "non-manifold": return !g.isManifoldEdge(i)
                case "seam":         return g.edgeCoEdges(i).contains { g.coedgeSeamPair($0) != nil }
                case "degenerate":   return g.isEdgeDegenerated(i)
                default:             return false
                }
            }
            guard ["boundary", "non-manifold", "seam", "degenerate"].contains(kind) else {
                throw ScriptError.message("--class must be boundary | non-manifold | seam | degenerate")
            }
            try GraphIO.emitJSON(EdgesClassResponse(class: kind, edges: matches))

        default:
            throw ScriptError.message("Unknown --query '\(queryType)'.\n\(usage)")
        }
        return 0
    }

    // MARK: arg helpers

    private static func value(_ name: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private static func intValue(_ name: String, in args: [String]) throws -> Int {
        guard let raw = value(name, in: args), let n = Int(raw) else {
            throw ScriptError.message("\(name) <Int> is required for this query")
        }
        return n
    }
}
