// VerbHarness.swift
// OcctkitCommandTests
//
// Shared plumbing for driving a `Subcommand` in-process: stdout capture, JSON decoding, temp
// directories, and the BREP fixtures the verb suites share.

import Foundation
import OCCTSwift
import ScriptHarness
import simd
import Testing

@testable import occtkit

enum VerbHarness {
    /// Process-wide lock: `captureStdout` redirects the real fd 1, and Swift Testing runs suites
    /// in parallel, so two captures at once would clobber each other's redirect target.
    private static let captureLock = NSLock()

    /// Accumulates bytes read off a pipe on a background thread. `@unchecked Sendable`: the
    /// compiler cannot see it, but `captureStdout` only reads `data` after polling
    /// `thread.isFinished` to `true`, which happens-after the thread's last write to it.
    private final class PipeReader: @unchecked Sendable {
        var data = Data()
    }

    /// Runs `block` with fd 1 redirected into a pipe drained on a background thread (reading
    /// only after `block` returns can deadlock once the ~64KB pipe buffer fills) and returns
    /// what was written to stdout.
    static func captureStdout(_ block: () throws -> Int32) throws -> String {
        captureLock.lock()
        defer { captureLock.unlock() }

        let pipe = Pipe()
        let savedStdout = dup(FileHandle.standardOutput.fileDescriptor)
        dup2(pipe.fileHandleForWriting.fileDescriptor, FileHandle.standardOutput.fileDescriptor)

        let reader = PipeReader()
        let readHandle = pipe.fileHandleForReading
        let thread = Thread { reader.data = readHandle.readDataToEndOfFile() }
        thread.start()

        let outcome: Result<Int32, Error>
        do { outcome = .success(try block()) } catch { outcome = .failure(error) }

        pipe.fileHandleForWriting.closeFile()
        dup2(savedStdout, FileHandle.standardOutput.fileDescriptor)
        close(savedStdout)
        while !thread.isFinished { usleep(1_000) }

        if case .failure(let error) = outcome { throw error }
        return String(data: reader.data, encoding: .utf8) ?? ""
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
    static func box(_ width: Double = 10, _ height: Double = 10, _ depth: Double = 10) throws -> Shape {
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
