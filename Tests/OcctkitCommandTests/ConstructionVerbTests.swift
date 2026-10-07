// ConstructionVerbTests.swift
// OcctkitCommandTests
//
// End-to-end coverage for the construction verbs: `transform`, `boolean`, `pattern`. Each test
// drives the verb in-process, then reads the written BREP back and checks geometry, so an
// output file that is empty, untransformed, or the wrong shape fails here.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing
import simd

@testable import occtkit

@Suite("occtkit construction verbs", .serialized)
struct ConstructionVerbTests {

    private func bounds(_ path: String) throws -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        try #require(GraphIO.loadBREP(at: path).bounds)
    }

    private func volume(_ path: String) throws -> Double {
        try #require(GraphIO.loadBREP(at: path).volume)
    }

    private func expectClose(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, tolerance: Double = 1e-3,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(simd_length(a - b) < tolerance, "\(a) != \(b)", sourceLocation: sourceLocation)
    }

    // MARK: transform

    @Test("transform --translate moves the bounding box by the offset and keeps the volume")
    func translateMovesBounds() throws {
        let dir = try VerbHarness.makeTempDir("transform")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(try VerbHarness.box(), named: "in", in: dir)
        let output = dir.appendingPathComponent("out.brep").path

        try VerbHarness.run(
            TransformCommand.self, [input, "--translate", "1,2,3", "--output", output])

        let before = try bounds(input)
        let after = try bounds(output)
        expectClose(after.min - before.min, SIMD3(1, 2, 3))
        expectClose(after.max - before.max, SIMD3(1, 2, 3))
        #expect(abs(try volume(output) - 1000) < 1e-3)
    }

    @Test("transform --scale multiplies the volume by the cube of the factor")
    func uniformScaleCubesVolume() throws {
        let dir = try VerbHarness.makeTempDir("transform")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(try VerbHarness.box(), named: "in", in: dir)
        let output = dir.appendingPathComponent("out.brep").path

        try VerbHarness.run(TransformCommand.self, [input, "--scale", "2", "--output", output])

        #expect(abs(try volume(output) - 8000) < 1e-2)
    }

    @Test("transform --rotate-axis-angle by 90 degrees about z swaps the x and y extents")
    func rotationSwapsExtents() throws {
        let dir = try VerbHarness.makeTempDir("transform")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Non-cubic on purpose: a cube would look identical after any quarter turn.
        let input = try VerbHarness.writeBREP(
            try VerbHarness.box(10, 20, 30), named: "in", in: dir)
        let output = dir.appendingPathComponent("out.brep").path

        try VerbHarness.run(
            TransformCommand.self,
            [input, "--rotate-axis-angle", "0,0,1,\(Double.pi / 2)", "--output", output])

        let b = try bounds(output)
        expectClose(b.max - b.min, SIMD3(20, 10, 30), tolerance: 1e-2)
    }

    @Test("transform rejects a non-uniform scale and writes nothing")
    func nonUniformScaleIsRejected() throws {
        let dir = try VerbHarness.makeTempDir("transform")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(try VerbHarness.box(), named: "in", in: dir)
        let output = dir.appendingPathComponent("out.brep").path

        #expect(throws: (any Error).self) {
            try VerbHarness.run(
                TransformCommand.self, [input, "--scale", "1,2,3", "--output", output])
        }
        #expect(!FileManager.default.fileExists(atPath: output))
    }

    // MARK: boolean

    private func booleanVolume(_ op: String) throws -> Double {
        let dir = try VerbHarness.makeTempDir("boolean")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try VerbHarness.writeBREP(try VerbHarness.box(), named: "a", in: dir)
        // A 2mm-wide overlap slab: union 1800, subtract 800, intersect 200. All three differ, so an
        // op wired to the wrong boolean cannot pass (a half overlap gives subtract == intersect).
        let shifted = try #require(try VerbHarness.box().translated(by: SIMD3(8, 0, 0)))
        let b = try VerbHarness.writeBREP(shifted, named: "b", in: dir)
        let output = dir.appendingPathComponent("out.brep").path

        let json = try VerbHarness.runJSON(
            BooleanCommand.self, ["--op", op, "--a", a, "--b", b, "--output", output])
        let reported = try VerbHarness.number(json, "volume")
        #expect(abs(reported - (try volume(output))) < 1e-3, "reported volume matches the BREP")
        return reported
    }

    @Test("boolean union of boxes overlapping by 2mm is 1800")
    func unionVolume() throws {
        #expect(abs(try booleanVolume("union") - 1800) < 1e-2)
    }

    @Test("boolean subtract removes the overlap, leaving 800")
    func subtractVolume() throws {
        #expect(abs(try booleanVolume("subtract") - 800) < 1e-2)
    }

    @Test("boolean intersect keeps only the overlap, 200")
    func intersectVolume() throws {
        #expect(abs(try booleanVolume("intersect") - 200) < 1e-2)
    }

    @Test("boolean rejects an unknown op")
    func unknownOpThrows() throws {
        let dir = try VerbHarness.makeTempDir("boolean")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try VerbHarness.writeBREP(try VerbHarness.box(), named: "a", in: dir)

        #expect(throws: (any Error).self) {
            try VerbHarness.run(
                BooleanCommand.self,
                [
                    "--op", "weld", "--a", a, "--b", a, "--output",
                    dir.appendingPathComponent("o.brep").path,
                ])
        }
    }

    // MARK: pattern

    @Test("pattern linear writes one BREP per instance, spaced by the requested distance")
    func linearPatternSpacing() throws {
        let dir = try VerbHarness.makeTempDir("pattern")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(try VerbHarness.box(), named: "in", in: dir)
        let outDir = dir.appendingPathComponent("out")

        let json = try VerbHarness.runJSON(
            PatternCommand.self,
            [
                input, "--kind", "linear", "--direction", "1,0,0", "--spacing", "20", "--count",
                "3",
                "--output-dir", outDir.path,
            ])

        #expect(try VerbHarness.number(json, "totalCount") == 3)
        let paths = try #require(json["outputPaths"] as? [String])
        #expect(paths.count == 3)
        let centres = try paths.map { try #require(GraphIO.loadBREP(at: $0).center) }
        for path in paths { #expect(abs(try volume(path) - 1000) < 1e-3) }
        let xs = centres.map(\.x).sorted()
        #expect(abs((xs[1] - xs[0]) - 20) < 1e-3 && abs((xs[2] - xs[1]) - 20) < 1e-3)
    }

    @Test("pattern mirror across the yz plane reflects x about the origin")
    func mirrorReflectsAcrossPlane() throws {
        let dir = try VerbHarness.makeTempDir("pattern")
        defer { try? FileManager.default.removeItem(at: dir) }
        let shifted = try #require(try VerbHarness.box().translated(by: SIMD3(10, 0, 0)))
        let input = try VerbHarness.writeBREP(shifted, named: "in", in: dir)
        let outDir = dir.appendingPathComponent("out")

        let json = try VerbHarness.runJSON(
            PatternCommand.self,
            [input, "--kind", "mirror", "--plane", "yz", "--output-dir", outDir.path])

        let paths = try #require(json["outputPaths"] as? [String])
        let mirrored = try #require(paths.first)
        let centre = try #require(GraphIO.loadBREP(at: mirrored).center)
        expectClose(centre, SIMD3(-10, 0, 0), tolerance: 1e-2)
    }

    @Test("pattern circular produces the requested number of instances")
    func circularInstanceCount() throws {
        let dir = try VerbHarness.makeTempDir("pattern")
        defer { try? FileManager.default.removeItem(at: dir) }
        let shifted = try #require(try VerbHarness.box().translated(by: SIMD3(30, 0, 0)))
        let input = try VerbHarness.writeBREP(shifted, named: "in", in: dir)
        let outDir = dir.appendingPathComponent("out")

        let json = try VerbHarness.runJSON(
            PatternCommand.self,
            [
                input, "--kind", "circular", "--axis-origin", "0,0,0", "--axis-direction", "0,0,1",
                "--total-count", "4", "--output-dir", outDir.path,
            ])

        #expect(try VerbHarness.number(json, "totalCount") == 4)
        let paths = try #require(json["outputPaths"] as? [String])
        #expect(paths.count == 4)
        // Four instances of a part 30mm out should all sit 30mm from the axis.
        for path in paths {
            let c = try #require(GraphIO.loadBREP(at: path).center)
            #expect(abs(hypot(c.x, c.y) - 30) < 1e-2)
        }
    }

    @Test("pattern rejects a zero count with the count guard's own message")
    func zeroCountThrows() throws {
        let dir = try VerbHarness.makeTempDir("pattern")
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try VerbHarness.writeBREP(try VerbHarness.box(), named: "in", in: dir)

        // Asserting the message matters: with the guard gone the kernel call still fails, so a
        // bare "throws" cannot tell the guard from the failure behind it.
        do {
            try VerbHarness.run(
                PatternCommand.self,
                [
                    input, "--kind", "linear", "--direction", "1,0,0", "--spacing", "5", "--count",
                    "0",
                    "--output-dir", dir.path,
                ])
            Issue.record("expected pattern --count 0 to throw")
        } catch {
            #expect("\(error)".contains("--count must be >= 1"), "got \(error)")
        }
    }
}
