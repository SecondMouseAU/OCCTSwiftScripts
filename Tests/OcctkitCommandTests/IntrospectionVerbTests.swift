// IntrospectionVerbTests.swift
// OcctkitCommandTests
//
// Coverage for the read-only introspection verbs: `metrics`, `query-topology`,
// `measure-distance`. Fixtures have analytically known answers (a 10mm cube), so a verb that
// reports a plausible but wrong number fails.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing

@testable import occtkit

@Suite("occtkit introspection verbs", .serialized)
struct IntrospectionVerbTests {

    private func cubePath(in dir: URL) throws -> String {
        try VerbHarness.writeBREP(try VerbHarness.box(), named: "cube", in: dir)
    }

    // MARK: metrics

    @Test("metrics reports a 10mm cube's volume, area, bounds and one solid")
    func cubeMetrics() throws {
        let dir = try VerbHarness.makeTempDir("metrics")
        defer { try? FileManager.default.removeItem(at: dir) }

        let json = try VerbHarness.runJSON(MetricsCommand.self, [try cubePath(in: dir)])

        #expect(abs(try VerbHarness.number(json, "volume") - 1000) < 1e-3)
        #expect(abs(try VerbHarness.number(json, "surfaceArea") - 600) < 1e-3)
        #expect(try VerbHarness.number(json, "solidCount") == 1)
        let box = try #require(json["boundingBox"] as? [String: Any])
        let max = try #require(box["max"] as? [Double])
        #expect(max.allSatisfy { abs($0 - 5) < 1e-3 })
    }

    @Test("metrics --metrics volume emits only the requested key")
    func metricsSubset() throws {
        let dir = try VerbHarness.makeTempDir("metrics")
        defer { try? FileManager.default.removeItem(at: dir) }

        let json = try VerbHarness.runJSON(
            MetricsCommand.self, [try cubePath(in: dir), "--metrics", "volume"])

        #expect(json["volume"] != nil)
        #expect(json["surfaceArea"] == nil)
        #expect(json["solidCount"] == nil)
    }

    @Test("metrics solidCount counts every solid in a compound (#100)")
    func solidCountOfCompound() throws {
        let dir = try VerbHarness.makeTempDir("metrics")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try VerbHarness.writeBREP(
            try VerbHarness.splitBoxCompound(), named: "split", in: dir)

        let json = try VerbHarness.runJSON(MetricsCommand.self, [path, "--metrics", "solidCount"])

        #expect(try VerbHarness.number(json, "solidCount") == 2)
    }

    @Test("metrics solidCount counts solids, not shells, on a hollow solid")
    func solidCountOfHollowSolid() throws {
        let dir = try VerbHarness.makeTempDir("metrics")
        defer { try? FileManager.default.removeItem(at: dir) }
        // One solid bounded by two shells (outer skin and inner cavity). A shell count would say 2.
        let hollow = try #require(try VerbHarness.box().subtracting(try VerbHarness.box(4, 4, 4)))
        let path = try VerbHarness.writeBREP(hollow, named: "hollow", in: dir)

        let json = try VerbHarness.runJSON(
            MetricsCommand.self, [path, "--metrics", "solidCount,volume"])

        #expect(try VerbHarness.number(json, "solidCount") == 1)
        #expect(abs(try VerbHarness.number(json, "volume") - 936) < 1e-2)
    }

    @Test("metrics fails on a missing file")
    func metricsMissingFile() {
        #expect(throws: (any Error).self) {
            try VerbHarness.run(MetricsCommand.self, ["/nonexistent/none.brep"])
        }
    }

    // MARK: query-topology

    private func topology(_ entity: String, _ extra: [String] = []) throws -> [String: Any] {
        let dir = try VerbHarness.makeTempDir("topology")
        defer { try? FileManager.default.removeItem(at: dir) }
        return try VerbHarness.runJSON(
            QueryTopologyCommand.self, [try cubePath(in: dir), "--entity", entity] + extra)
    }

    @Test("query-topology counts a cube's 6 faces, 12 edges and 8 vertices")
    func cubeEntityCounts() throws {
        #expect(try VerbHarness.number(try topology("face"), "total") == 6)
        #expect(try VerbHarness.number(try topology("edge"), "total") == 12)
        #expect(try VerbHarness.number(try topology("vertex"), "total") == 8)
    }

    @Test("query-topology --limit truncates the results but reports the full total")
    func limitTruncates() throws {
        let json = try topology("face", ["--limit", "2"])
        #expect((json["results"] as? [Any])?.count == 2)
        #expect(try VerbHarness.number(json, "total") == 6)
        #expect(json["truncated"] as? Bool == true)
    }

    @Test("query-topology normalDirection filter selects exactly the +z face")
    func normalFilter() throws {
        let json = try topology(
            "face", ["--filter", #"{"normalDirection":[0,0,1],"normalTolerance":0.1}"#])
        let results = try #require(json["results"] as? [[String: Any]])
        #expect(results.count == 1)
        let normal = try #require(results.first?["normal"] as? [Double])
        #expect(abs(normal[2] - 1) < 1e-6)
    }

    @Test("query-topology minArea filter above a face's area selects nothing")
    func areaFilterExcludes() throws {
        let json = try topology("face", ["--filter", #"{"minArea":101}"#])
        #expect((json["results"] as? [Any])?.isEmpty == true)
    }

    // MARK: measure-distance

    private func twoCubes(gap: Double, in dir: URL) throws -> (String, String) {
        let a = try VerbHarness.writeBREP(try VerbHarness.box(), named: "a", in: dir)
        let moved = try #require(try VerbHarness.box().translated(by: SIMD3(10 + gap, 0, 0)))
        return (a, try VerbHarness.writeBREP(moved, named: "b", in: dir))
    }

    @Test("measure-distance between cubes 20mm apart reports 20")
    func separatedCubes() throws {
        let dir = try VerbHarness.makeTempDir("distance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, b) = try twoCubes(gap: 20, in: dir)

        let json = try VerbHarness.runJSON(MeasureDistanceCommand.self, [a, b])

        #expect(abs(try VerbHarness.number(json, "minDistance") - 20) < 1e-3)
        // Contacts are opt-in: without --compute-contacts the list must be empty.
        #expect((json["contacts"] as? [Any])?.isEmpty ?? true)
    }

    @Test("measure-distance --compute-contacts lists contact points at that distance")
    func contactsAtMinimum() throws {
        let dir = try VerbHarness.makeTempDir("distance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, b) = try twoCubes(gap: 20, in: dir)

        let json = try VerbHarness.runJSON(
            MeasureDistanceCommand.self, [a, b, "--compute-contacts"])

        let contacts = try #require(json["contacts"] as? [[String: Any]])
        #expect(!contacts.isEmpty)
        for contact in contacts {
            #expect(abs(try VerbHarness.number(contact, "distance") - 20) < 1e-3)
        }
    }

    @Test("measure-distance from a point ref measures from that point to the other shape")
    func pointRef() throws {
        let dir = try VerbHarness.makeTempDir("distance")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, b) = try twoCubes(gap: 20, in: dir)

        // `b` spans x in [25,35]; the point is 13mm short of its -x face.
        let json = try VerbHarness.runJSON(
            MeasureDistanceCommand.self, [a, b, "--from-ref", "point:12,0,0"])

        #expect(abs(try VerbHarness.number(json, "minDistance") - 13) < 1e-3)
    }
}
