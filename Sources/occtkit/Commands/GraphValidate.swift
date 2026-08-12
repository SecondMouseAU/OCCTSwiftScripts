// GraphValidate: validate a BREP's topology graph and emit structured health.
//
// Existing fields (isValid / errorCount / warningCount) are preserved for
// backward compatibility. Per the OCCTMCP-driver introspection batch
// (OCCTSwiftScripts#18), the response also carries a normalized
// `healthRecord` populated from Shape.analyze(), small-edge / free-edge /
// self-intersection counts, plus the shape's top-level type. `nakedVertexCount`
// isn't exposed by OCCTSwift today; emitted as 0 with a docstring note.
//
// `selfIntersecting` (OCCTSwift#763, v2.0.0): the old `selfIntersectionCount`
// field this was derived from (`> 0`) was always 0, never computed, so this
// field silently reported "false" for every shape ever passed through here,
// self-intersecting or not. There is no salvageable value to migrate from,
// so `selfIntersecting` is now `Bool?`, backed by the real
// `isSelfIntersecting(timeout:)` check via `Shape.analyze(selfIntersectionTimeout:)`,
// and defaults to `nil` ("not checked") rather than a fabricated `false`. Pass
// `--self-intersection-timeout <seconds>` to opt in; the check is orders of
// magnitude more expensive than the rest of this scan on pathological input
// (measured ~3000x upstream), hence opt-in rather than default-on.
//
// Usage: graph-validate <shape.brep> [--self-intersection-timeout d]

import Foundation
import OCCTSwift
import ScriptHarness

enum GraphValidateCommand: Subcommand {
    static let name = "graph-validate"
    static let summary =
        "Validate a BREP shape's topology graph and surface a structured health record"
    static let usage = "Usage: graph-validate <shape.brep> [--self-intersection-timeout d]"

    struct Response: Encodable {
        let isValid: Bool
        let errorCount: Int
        let warningCount: Int
        let healthRecord: HealthRecord

        struct HealthRecord: Encodable {
            let isValid: Bool
            let shapeType: String
            let freeEdgeCount: Int
            // OCCTSwift v0.156 doesn't expose a naked-vertex count; reported as 0.
            let nakedVertexCount: Int
            let smallEdgeCount: Int
            let smallFaceCount: Int
            // nil = not checked (pass --self-intersection-timeout to opt in); see OCCTSwift#763.
            let selfIntersecting: Bool?
            let errors: [String]
        }
    }

    static func run(args: [String]) throws -> Int32 {
        let path = try GraphIO.argument(at: 0, in: args, usage: usage)
        let selfIntersectionTimeout = try parseSelfIntersectionTimeout(args: args)
        let shape = try GraphIO.loadBREP(at: path)
        let graph = try GraphIO.buildGraph(from: shape)
        let validation = graph.validate()
        let analysis = shape.analyze(selfIntersectionTimeout: selfIntersectionTimeout)

        let record = Response.HealthRecord(
            isValid: shape.isValid,
            shapeType: shape.shapeType.toLowercaseString(),
            freeEdgeCount: analysis?.freeEdgeCount ?? 0,
            nakedVertexCount: 0,
            smallEdgeCount: analysis?.smallEdgeCount ?? 0,
            smallFaceCount: analysis?.smallFaceCount ?? 0,
            selfIntersecting: analysis?.hasSelfIntersection,
            errors: []
        )

        try GraphIO.emitJSON(
            Response(
                isValid: validation.isValid,
                errorCount: validation.errorCount,
                warningCount: validation.warningCount,
                healthRecord: record
            ))
        return 0
    }

    private static func parseSelfIntersectionTimeout(args: [String]) throws -> Double? {
        guard let i = args.firstIndex(of: "--self-intersection-timeout") else { return nil }
        guard i + 1 < args.count, let d = Double(args[i + 1]) else {
            throw ScriptError.message("--self-intersection-timeout expects a number (seconds)")
        }
        return d
    }
}

// `ShapeType.toLowercaseString()` is defined in LoadBrep.swift.
