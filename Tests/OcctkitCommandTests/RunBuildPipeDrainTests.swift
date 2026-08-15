// RunBuildPipeDrainTests.swift
// OcctkitCommandTests
//
// Regression coverage for OCCTSwiftScripts#116: `RunCommand.buildAndRun()` called
// `waitUntilExit()` on its build subprocess before anything drained its stderr pipe. A
// child that writes more than the OS pipe buffer (~64KB on macOS) before exiting blocks on
// its own `write()` once that buffer fills, and with nothing reading it, `occtkit run`
// deadlocked forever instead of failing cleanly with the diagnostics it was about to
// report. Real trigger: a genuine compile error with full Swift 6 strict-concurrency
// diagnostics, or verbose SPM build output.
//
// The fix moved capture off pipes entirely onto a temp file (mirroring `main.swift`'s
// `captureOutput`), so the specific pipe/ordering bug this issue describes can't recur by
// construction. What's still worth a permanent regression test is the contract that
// motivated the fix: a subprocess writing well past the old 64KB pipe threshold has its
// stderr captured completely and correctly. 300KB isn't chasing a capacity limit in the
// current temp-file design (a file has none); it's a comfortably-larger-than-any-known-
// buffer size, so this keeps catching a truncation regression regardless of what capture
// mechanism a future change uses, pipe or otherwise.
//
// This exercises the extracted `runCapturingStderr(_:)` helper directly against a cheap
// synthetic subprocess (system `perl`) rather than a real `swift build` invocation, which
// would need to resolve and compile the whole OCCTSwift dependency graph just to reach the
// code path under test. `perl` writes directly to its own stderr with no shell or pipeline
// involved, so there's exactly one process in play: nothing for a `terminate()` in the
// timeout branch below to fail to reach.

import Foundation
import Testing

@testable import occtkit

@Suite("occtkit run: build stderr capture (#116)")
struct RunBuildPipeDrainTests {

    /// Boxes a `Result` across the background thread that races `runCapturingStderr`
    /// against the timeout below.
    private final class ResultBox: @unchecked Sendable {
        // `@unchecked Sendable`: `wait(timeout:)` returning `.success` happens-after the
        // thread's `done.signal()`, which happens-after its write to `value`, so the read
        // on the waiting side is never concurrent with it.
        var value: Result<(status: Int32, stderr: Data), Error>?
    }

    @Test("large stderr output is captured completely, without truncation, corruption, or hanging")
    func capturesLargeOutputCompletely() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // A single process writing directly to its own stderr, no shell/pipe/fork chain:
        // `process` here is the one and only process actually doing the write, so
        // `process.terminate()` below is guaranteed to reach it.
        process.arguments = ["-e", "print STDERR 'X' x 300000; exit 7"]

        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.value = Result { try RunCommand.runCapturingStderr(process) }
            done.signal()
        }

        // This specific bug can no longer hang (capture is temp-file-backed, which has no
        // fixed capacity to block a writer on), but the timeout still guards against any
        // future capture-mechanism regression that reintroduces a bounded-buffer wait, and
        // keeps a stuck subprocess from failing this test by hanging CI instead of by
        // failing loudly. 10s comfortably covers the real path, which finishes in well
        // under a second.
        guard done.wait(timeout: .now() + 10) == .success else {
            if process.isRunning { process.terminate() }
            Issue.record("runCapturingStderr hung capturing large stderr output (#116 regression)")
            return
        }

        switch box.value {
        case .success(let result):
            #expect(result.status == 7)
            #expect(result.stderr.count == 300_000)
        case .failure(let error):
            Issue.record("runCapturingStderr threw: \(error)")
        case nil:
            Issue.record("runCapturingStderr produced no result")
        }
    }
}
