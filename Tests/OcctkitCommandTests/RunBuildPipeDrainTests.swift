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
// This exercises the extracted `runDrainingStderr(_:pipe:)` helper directly against a
// cheap synthetic subprocess (`yes | head`) rather than a real `swift build` invocation,
// which would need to resolve and compile the whole OCCTSwift dependency graph just to
// reach the code path under test. `yes | head -c` reproduces the one property that matters
// here, a child writing well past the pipe buffer before exiting, in milliseconds.

import Foundation
import Testing

@testable import occtkit

@Suite("occtkit run: build pipe draining (#116)")
struct RunBuildPipeDrainTests {

    /// Boxes a `Result` across the background thread that races `runDrainingStderr`
    /// against the timeout below. `@unchecked Sendable`: `wait(timeout:)` returning
    /// `.success` happens-after the thread's `done.signal()`, which happens-after its
    /// write to `value`, so the read on the waiting side is never concurrent with it.
    private final class ResultBox: @unchecked Sendable {
        var value: Result<(status: Int32, stderr: Data), Error>?
    }

    @Test("draining stderr before waitUntilExit doesn't deadlock past the pipe buffer")
    func doesNotDeadlockOnLargeOutput() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 300KB comfortably clears macOS's ~64KB pipe buffer several times over. Piped
        // through `head -c` so the child both writes a bounded, known amount and exits on
        // its own; `exit 7` after gives the test a termination status to assert on that
        // can't be confused with a coincidental 0/1.
        process.arguments = ["-c", "yes X | head -c 300000 1>&2; exit 7"]
        let pipe = Pipe()
        process.standardError = pipe

        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.value = Result { try RunCommand.runDrainingStderr(process, pipe: pipe) }
            done.signal()
        }

        // Before #116's fix this hangs forever: `waitUntilExit()` ran before anything
        // drained the pipe, so the child blocked on its own write() with nothing reading
        // it. 10s comfortably covers the fixed path (which finishes in well under a
        // second) while still failing this test, rather than hanging CI, if that ordering
        // regresses.
        guard done.wait(timeout: .now() + 10) == .success else {
            Issue.record("runDrainingStderr hung past the OS pipe buffer (#116 regression)")
            return
        }

        switch box.value {
        case .success(let result):
            #expect(result.status == 7)
            #expect(result.stderr.count == 300_000)
        case .failure(let error):
            Issue.record("runDrainingStderr threw: \(error)")
        case nil:
            Issue.record("runDrainingStderr produced no result")
        }
    }
}
