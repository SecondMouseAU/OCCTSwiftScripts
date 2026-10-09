// EdgeClassification.swift
// ScriptHarness
//
// Per-edge convexity and dihedral angle for a shape's BRepGraph edges, for the graph exports
// (OCCTSwiftScripts#55). Convexity is the strongest per-edge feature in B-rep feature-recognition
// GNNs and the usual machining-feature discriminator.

import Foundation
import OCCTSwift

/// Convexity and interior dihedral angle of one graph edge.
public struct EdgeClassification: Codable, Sendable, Equatable {
    /// `"convex"`, `"concave"`, `"smooth"` (tangent faces), or `"unknown"`.
    ///
    /// Same vocabulary as the `faceAdjacency` convexity `graph-ml` already emits. `"unknown"` means
    /// the edge does not sit between exactly two faces, so a convexity is not defined: a boundary
    /// edge of an open shell, a non-manifold edge, or an edge the kernel did not classify.
    public let convexity: String

    /// Interior angle between the two faces in radians, or `nil` when `convexity` is `"unknown"`.
    ///
    /// Below pi for convex, equal to pi for smooth, above pi for concave (a cube edge is pi/2, an
    /// inside corner is 3 pi/2).
    public let dihedralAngle: Double?

    public static let unknown = EdgeClassification(convexity: "unknown", dihedralAngle: nil)
}

public enum EdgeClassifier {

    /// Classify every edge of `graph`, which must have been built from `shape`.
    ///
    /// Returns one entry per graph edge index, `.unknown` where no convexity is defined. The kernel
    /// labels a boundary edge "tangent", which would be wrong to repeat, so only edges with exactly
    /// two faces in the graph are classified.
    public static func classify(shape: Shape, graph: BRepGraph) -> [Int: EdgeClassification] {
        var result = [Int: EdgeClassification](
            uniqueKeysWithValues: (0..<graph.edgeCount).map { ($0, .unknown) })
        guard let classified = shape.edgeConcavities() else { return result }

        for (edge, concavity) in classified {
            // Identity lookup, not an index assumption: graph edge order is the graph's own.
            guard let edgeShape = Shape.fromEdge(edge),
                let node = graph.findNode(for: edgeShape), node.kind == .edge,
                graph.faceCount(of: node.index) == 2
            else { continue }

            var angle: Double?
            if let faces = edge.adjacentFaces(in: shape), faces.count == 2 {
                angle = edge.dihedralAngle(between: faces[0], and: faces[1])
            }
            result[node.index] = EdgeClassification(
                convexity: label(concavity), dihedralAngle: angle)
        }
        return result
    }

    private static func label(_ concavity: Shape.EdgeConcavity) -> String {
        switch concavity {
        case .convex: return "convex"
        case .concave: return "concave"
        case .tangent: return "smooth"
        }
    }
}
