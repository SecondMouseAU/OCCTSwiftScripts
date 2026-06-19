// MeasureDeviation — directed + symmetric surface deviation (one-sided /
// symmetric Hausdorff) between two BREPs.
//
// Where measure-distance returns the *minimum* gap (≈0 for an overlapping
// reconstruction-vs-source pair, hence useless as a fidelity figure), this
// samples one shape's tessellated surface and projects each sample onto the
// other shape's triangles to report the *worst* / RMS / mean deviation in each
// direction. The metric a mesh→analytic reconstruction check needs
// (OCCTMCP #41): fromToTo (over-extension), toToFrom (under-coverage).
//
// Mesh-based: both inputs are typically meshes (an STL source vs a STEP
// reconstruction), and meshing once + a KD-tree is far cheaper than N per-point
// BRep extrema. The per-sample distance is exact point-to-triangle, so the only
// approximation is the tessellation — tightened by a finer --deflection.
//
// Two input modes:
//   1. Flag form:
//      occtkit measure-deviation <a.brep> <b.brep>
//          [--deflection D] [--max-samples N]
//   2. JSON form:
//      { "a": "...", "b": "...", "deflection": D, "maxSamples": N }

import Foundation
import OCCTSwift
import ScriptHarness
import simd

enum MeasureDeviationCommand: Subcommand {
    static let name = "measure-deviation"
    static let summary = "Directed + symmetric surface deviation (Hausdorff) between two BREPs"
    static let usage = """
        Usage:
          measure-deviation <a.brep> <b.brep> [--deflection D] [--max-samples N]
          measure-deviation <request.json>     (JSON request from file)
          measure-deviation                    (JSON request from stdin)

        --deflection   mesh linear deflection (model units). Default: 0.5% of
                       the a-shape bbox diagonal. Smaller = finer = tighter bound.
        --max-samples  max source surface samples per direction. Default 20000.
        """

    private struct Request {
        var a: String
        var b: String
        var deflection: Double?
        var maxSamples: Int
    }

    private struct JSONRequest: Decodable {
        let a: String
        let b: String
        let deflection: Double?
        let maxSamples: Int?
    }

    struct DirectionStat: Encodable {
        let max: Double
        let rms: Double
        let mean: Double
        let worstPoint: [Double]
        let samples: Int
    }

    struct Response: Encodable {
        let deflection: Double
        let fromToTo: DirectionStat
        let toToFrom: DirectionStat
        let symmetricHausdorff: Double
    }

    static func run(args: [String]) throws -> Int32 {
        let req = try parseRequest(args: args)
        let aShape = try GraphIO.loadBREP(at: req.a)
        let bShape = try GraphIO.loadBREP(at: req.b)

        let defl = req.deflection ?? defaultDeflection(for: aShape)
        guard defl > 0 else { throw ScriptError.message("deflection must be positive") }

        guard let aTris = TriMesh(shape: aShape, deflection: defl) else {
            throw ScriptError.message("Failed to tessellate '\(req.a)' for deviation")
        }
        guard let bTris = TriMesh(shape: bShape, deflection: defl) else {
            throw ScriptError.message("Failed to tessellate '\(req.b)' for deviation")
        }
        guard let fwd = directedDeviation(source: aTris, target: bTris, maxSamples: req.maxSamples),
              let rev = directedDeviation(source: bTris, target: aTris, maxSamples: req.maxSamples) else {
            throw ScriptError.message("Deviation computation failed (empty tessellation)")
        }

        try GraphIO.emitJSON(Response(
            deflection: defl,
            fromToTo: fwd,
            toToFrom: rev,
            symmetricHausdorff: Swift.max(fwd.max, rev.max)
        ))
        return 0
    }

    // ── tessellation snapshot ───────────────────────────────────────────

    struct TriMesh {
        let vertices: [SIMD3<Double>]
        let triangles: [(UInt32, UInt32, UInt32)]
        let kd: KDTree
        let incident: [[Int]]

        init?(shape: Shape, deflection: Double) {
            var params = MeshParameters.default
            params.deflection = deflection
            params.internalVertices = true
            params.inParallel = true
            params.allowQualityDecrease = true   // honour the requested deflection (#211)
            guard let mesh = shape.mesh(parameters: params) else { return nil }

            let verts = mesh.vertices.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }
            let idx = mesh.indices
            guard !verts.isEmpty, idx.count >= 3, let kd = KDTree(points: verts) else { return nil }

            var tris: [(UInt32, UInt32, UInt32)] = []
            tris.reserveCapacity(idx.count / 3)
            var adj = [[Int]](repeating: [], count: verts.count)
            var t = 0
            while t + 2 < idx.count {
                let a = idx[t], b = idx[t + 1], c = idx[t + 2]
                let ti = tris.count
                tris.append((a, b, c))
                adj[Int(a)].append(ti); adj[Int(b)].append(ti); adj[Int(c)].append(ti)
                t += 3
            }
            self.vertices = verts; self.triangles = tris; self.kd = kd; self.incident = adj
        }
    }

    // ── directed deviation ──────────────────────────────────────────────

    static func directedDeviation(source: TriMesh, target: TriMesh, maxSamples: Int) -> DirectionStat? {
        let n = source.vertices.count
        guard n > 0 else { return nil }
        let stride = maxSamples > 0 ? Swift.max(1, (n + maxSamples - 1) / maxSamples) : 1
        let k = 6

        var maxD = 0.0, sumSq = 0.0, sum = 0.0, count = 0
        var worst = SIMD3<Double>(0, 0, 0)
        var stamp = [Int](repeating: -1, count: target.triangles.count)

        var i = 0
        while i < n {
            let p = source.vertices[i]
            var best = Double.greatestFiniteMagnitude
            let neighbours = target.kd.kNearest(to: p, k: k)
            if neighbours.isEmpty {
                if let nv = target.kd.nearest(to: p) { best = nv.distance }
            } else {
                for (vi, _) in neighbours {
                    for ti in target.incident[vi] where stamp[ti] != i {
                        stamp[ti] = i
                        let (a, b, c) = target.triangles[ti]
                        let d = pointTriangleDistance(p, target.vertices[Int(a)],
                                                      target.vertices[Int(b)], target.vertices[Int(c)])
                        if d < best { best = d }
                    }
                }
                if best == .greatestFiniteMagnitude, let nv = target.kd.nearest(to: p) { best = nv.distance }
            }
            if best != .greatestFiniteMagnitude {
                if best > maxD { maxD = best; worst = p }
                sumSq += best * best; sum += best; count += 1
            }
            i += stride
        }
        guard count > 0 else { return nil }
        return DirectionStat(
            max: maxD,
            rms: (sumSq / Double(count)).squareRoot(),
            mean: sum / Double(count),
            worstPoint: [worst.x, worst.y, worst.z],
            samples: count
        )
    }

    // ── geometry helpers ────────────────────────────────────────────────

    static func defaultDeflection(for shape: Shape) -> Double {
        let b = shape.bounds
        let diag = simd_length(b.max - b.min)
        return Swift.max(diag * 0.005, 1e-6)
    }

    /// Closest-point-on-triangle distance, Ericson "Real-Time Collision
    /// Detection" §5.1.5.
    static func pointTriangleDistance(_ p: SIMD3<Double>, _ a: SIMD3<Double>,
                                      _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return simd_length(ap) }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return simd_length(bp) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { let v = d1 / (d1 - d3); return simd_length(p - (a + v * ab)) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return simd_length(cp) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { let w = d2 / (d2 - d6); return simd_length(p - (a + w * ac)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6)); return simd_length(p - (b + w * (c - b)))
        }
        let denom = 1.0 / (va + vb + vc)
        return simd_length(p - (a + ab * (vb * denom) + ac * (vc * denom)))
    }

    // ── request parsing ─────────────────────────────────────────────────

    private static func parseRequest(args: [String]) throws -> Request {
        if args.count == 1, args[0].hasSuffix(".json") {
            return try decodeJSON(data: try readFile(args[0]))
        }
        if args.isEmpty {
            return try decodeJSON(data: FileHandle.standardInput.readDataToEndOfFile())
        }
        guard args.count >= 2, !args[0].hasPrefix("-"), !args[1].hasPrefix("-") else {
            throw ScriptError.message("Expected: <a.brep> <b.brep> [flags]")
        }
        var deflection: Double?
        var maxSamples = 20_000
        var i = 2
        while i < args.count {
            switch args[i] {
            case "--deflection":
                i += 1
                guard i < args.count, let d = Double(args[i]) else {
                    throw ScriptError.message("--deflection expects a number")
                }
                deflection = d
            case "--max-samples":
                i += 1
                guard i < args.count, let n = Int(args[i]) else {
                    throw ScriptError.message("--max-samples expects an integer")
                }
                maxSamples = n
            default:
                throw ScriptError.message("Unknown flag: \(args[i])")
            }
            i += 1
        }
        return Request(a: args[0], b: args[1], deflection: deflection, maxSamples: maxSamples)
    }

    private static func readFile(_ path: String) throws -> Data {
        guard let bytes = FileManager.default.contents(atPath: path) else {
            throw ScriptError.message("Failed to read request at \(path)")
        }
        return bytes
    }

    private static func decodeJSON(data: Data) throws -> Request {
        let raw: JSONRequest
        do {
            raw = try JSONDecoder().decode(JSONRequest.self, from: data)
        } catch {
            throw ScriptError.message("Invalid JSON: \(error.localizedDescription)")
        }
        return Request(a: raw.a, b: raw.b, deflection: raw.deflection,
                       maxSamples: raw.maxSamples ?? 20_000)
    }
}
