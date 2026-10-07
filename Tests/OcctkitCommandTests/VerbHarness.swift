// VerbHarness.swift
// OcctkitCommandTests
//
// Shared plumbing for driving a `Subcommand` in-process: stdout capture, JSON decoding, temp
// directories, and the BREP fixtures the verb suites share.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing
import simd

@testable import occtkit

enum VerbHarness {
    /// Collects the chunks `GraphIO.emitJSON` delivers to its sink.
    ///
    /// `@unchecked Sendable`: every access goes through `lock`.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk)
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    /// Runs `block` and returns the JSON the verb emitted.
    ///
    /// Bound through `GraphIO.jsonSink`, a task-local, rather than by redirecting fd 1. The test
    /// runner prints its progress lines to that descriptor from other threads, and an earlier
    /// version of this helper that redirected it intermittently captured those lines inside a
    /// verb's JSON (seen in CI as "Garbage at end"). A task-local is private to the calling test,
    /// so concurrent suites cannot see each other and nothing needs a lock.
    static func captureStdout(_ block: () throws -> Int32) throws -> String {
        let collector = Collector()
        _ = try GraphIO.$jsonSink.withValue({ collector.append($0) }, operation: { try block() })
        return collector.text
    }

    /// Runs `verb` with `args`, requires exit code 0, and returns stdout.
    @discardableResult
    static func run(_ verb: any Subcommand.Type, _ args: [String]) throws -> String {
        var exit: Int32 = -1
        let stdout = try captureStdout {
            exit = try verb.run(args: args)
            return exit
        }
        #expect(exit == 0, "\(verb.name) exited \(exit)")
        return stdout
    }

    /// Runs `verb` and decodes its stdout as one JSON object.
    static func runJSON(_ verb: any Subcommand.Type, _ args: [String]) throws -> [String: Any] {
        let stdout = try run(verb, args)
        let object = try JSONSerialization.jsonObject(with: Data(stdout.utf8))
        return try #require(object as? [String: Any], "\(verb.name) did not emit a JSON object")
    }

    /// A fresh directory under the temp dir, removed by the caller's `defer`.
    static func makeTempDir(_ label: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("occtkit-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `shape` as `<name>.brep` inside `dir` and returns its path.
    static func writeBREP(_ shape: Shape, named name: String, in dir: URL) throws -> String {
        let url = dir.appendingPathComponent("\(name).brep")
        try Exporter.writeBREP(shape: shape, to: url)
        return url.path
    }

    // MARK: Fixtures

    /// A box with its corner at the origin.
    static func box(_ width: Double = 10, _ height: Double = 10, _ depth: Double = 10) throws
        -> Shape
    {
        try #require(Shape.box(width: width, height: height, depth: depth))
    }

    /// A 10mm box split through z=4 and recompounded so the cut face is shared by both halves
    /// (11 distinct faces over 12 occurrences).
    static func splitBoxCompound() throws -> Shape {
        let halves = try #require(
            try box().split(atPlane: SIMD3(0, 0, 4), normal: SIMD3(0, 0, 1)))
        return try #require(Shape.compound(halves))
    }

    /// Reads a number out of a decoded JSON dictionary along a key path.
    static func number(_ json: [String: Any], _ path: String...) throws -> Double {
        var node: Any = json
        for key in path {
            let dict = try #require(node as? [String: Any], "no object at \(key) in \(path)")
            node = try #require(dict[key], "missing key \(key) in \(path)")
        }
        return try #require((node as? NSNumber)?.doubleValue, "\(path) is not a number")
    }
}

extension VerbHarness {
    /// Writes `object` as a JSON file named `name` inside `dir` and returns its path.
    ///
    /// Built with `JSONSerialization` so paths are escaped correctly, which hand-assembled
    /// strings are not.
    static func writeJSON(_ object: Any, named name: String, in dir: URL) throws -> String {
        let url = dir.appendingPathComponent(name)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
        return url.path
    }

    /// Runs `verb`, which must throw an error whose description contains `fragment`.
    ///
    /// A bare "throws something" passes for any failure, including an unrelated one such as a
    /// missing file, so a regression that swaps the intended error for another goes unseen.
    static func expectFailure(
        _ verb: any Subcommand.Type, _ args: [String], containing fragment: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try captureStdout { try verb.run(args: args) }
            Issue.record("\(verb.name) was expected to throw", sourceLocation: sourceLocation)
        } catch {
            #expect(
                "\(error)".contains(fragment), "\(verb.name) threw \(error)",
                sourceLocation: sourceLocation)
        }
    }

    /// Runs `verb` without requiring a zero exit code and returns `(exit, stdout)`.
    static func runAllowingFailure(_ verb: any Subcommand.Type, _ args: [String]) throws -> (
        exit: Int32, stdout: String
    ) {
        var exit: Int32 = -1
        let stdout = try captureStdout {
            exit = try verb.run(args: args)
            return exit
        }
        return (exit, stdout)
    }
}
