// CaptureIsolationTests.swift
// OcctkitCommandTests
//
// Regression test for the intermittent "Garbage at end" failure seen in CI. The verb tests used to
// capture a verb's JSON by redirecting fd 1, and Swift Testing prints its own progress lines to
// fd 1 from other threads. A runner line landing inside the capture (including glued to the
// closing brace, because the old emitJSON wrote the object and its newline separately) broke JSON
// parsing in an unrelated test. The capture now goes through a task-local sink and never touches
// fd 1, so another writer cannot reach it.

import Foundation
import OCCTSwift
import Testing

@testable import occtkit

@Suite("verb output capture")
struct CaptureIsolationTests {

    /// Writes junk to the real stdout until told to stop, shaped like the failure: a runner line
    /// glued to a closing brace, and bare lines with no leading mark.
    private final class Hammer: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        private(set) var thread: Thread?

        func start() {
            let t = Thread { [self] in
                var n = 0
                while !isStopped && n < 2000 {
                    FileHandle.standardOutput.write(Data("}◇ Test hammer \(n) passed\n".utf8))
                    FileHandle.standardOutput.write(
                        Data("  continuation line without a mark\n".utf8))
                    n += 1
                }
            }
            thread = t
            t.start()
        }

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
            while !(thread?.isFinished ?? true) { usleep(500) }
        }
    }

    @Test("a verb's JSON survives another thread writing to stdout the whole time")
    func captureIgnoresOtherStdoutWriters() throws {
        let dir = try VerbHarness.makeTempDir("capture")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try VerbHarness.writeBREP(try VerbHarness.box(), named: "cube", in: dir)

        let hammer = Hammer()
        hammer.start()
        defer { hammer.stop() }

        var bad = 0
        for _ in 0..<300 {
            let json = try? VerbHarness.runJSON(MetricsCommand.self, [path, "--metrics", "volume"])
            if json?["volume"] == nil { bad += 1 }
        }
        #expect(bad == 0, "\(bad) of 300 captures were corrupted by another stdout writer")
    }
}
