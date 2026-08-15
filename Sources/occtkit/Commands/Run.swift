// Run subcommand, execute an arbitrary user .swift file as an OCCTSwift script.
//
// Maintains a cached SPM workspace under ~/.occtswift-scripts/runner-cache,
// copies the user's source in, builds and runs.
//
// Workspace ScriptHarness dependency resolution order:
//   1. $OCCTKIT_SCRIPTS_PATH (path-based dep), explicit override
//   2. Auto-detect package root from argv[0] (path-based dep), works when
//      running via `swift run occtkit ...` from a built tree
//   3. Remote `from: "1.0.0"` against SecondMouseAU/OCCTSwiftScripts
//
// The checkout directory may be named anything. For the two path-based branches
// SwiftPM derives the dependency's identity from the directory basename rather
// than from the `name:` in its manifest, so the generated manifest computes both
// the declaration and the identity from one value (see `pathDep`). Hardcoding
// that identity previously broke `occtkit run` in forks, second checkouts, git
// worktrees, and any OCCTKIT_SCRIPTS_PATH pointing somewhere named differently
// (OCCTSwiftScripts#98).
//
// Usage:
//   occtkit run <script.swift> [--format brep,step,graph-json,graph-sqlite] [--output <dir>]

import Foundation
import ScriptHarness

enum RunCommand: Subcommand {
    static let name = "run"
    static let summary = "Run a user .swift file via a cached SPM workspace"
    static let usage = """
        Usage: occtkit run <script.swift> [options]
        Options:
          --format <list>   brep, step, graph-json, graph-sqlite (default: brep,step)
          --output, -o <d>  Copy output dir to <d> after run
        """

    private struct Config {
        let scriptPath: String
        let formats: Set<String>
        let outputDir: String?
        static let defaultFormats: Set<String> = ["brep", "step"]
        static let allFormats: Set<String> = ["brep", "step", "graph-json", "graph-sqlite"]
    }

    static func run(args: [String]) throws -> Int32 {
        let config = try parse(args: args)
        try ensureWorkspace()
        try prepareScript(config)
        try buildAndRun()
        try copyOutput(config)
        return 0
    }

    // MARK: - Argument parsing

    private static func parse(args: [String]) throws -> Config {
        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            throw ScriptError.message(usage)
        }
        var scriptPath: String?
        var formats = Config.defaultFormats
        var outputDir: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--format":
                i += 1
                guard i < args.count else { throw ScriptError.message("--format requires a value") }
                formats = Set(
                    args[i].split(separator: ",").map {
                        String($0).trimmingCharacters(in: .whitespaces)
                    })
                let invalid = formats.subtracting(Config.allFormats)
                if !invalid.isEmpty {
                    throw ScriptError.message(
                        "Unknown format(s): \(invalid.sorted().joined(separator: ", "))")
                }
            case "--output", "-o":
                i += 1
                guard i < args.count else { throw ScriptError.message("--output requires a path") }
                outputDir = args[i]
            default:
                if args[i].hasPrefix("-") {
                    throw ScriptError.message("Unknown option: \(args[i])")
                }
                if scriptPath != nil {
                    throw ScriptError.message("Multiple script files specified")
                }
                scriptPath = args[i]
            }
            i += 1
        }
        guard let path = scriptPath else { throw ScriptError.message("No script file specified") }
        guard FileManager.default.fileExists(atPath: path) else {
            throw ScriptError.message("Script not found: \(path)")
        }
        return Config(scriptPath: path, formats: formats, outputDir: outputDir)
    }

    // MARK: - Workspace

    private static let cacheDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".occtswift-scripts/runner-cache")
    private static let workspaceDir: URL = cacheDir.appendingPathComponent("workspace")

    /// The generated workspace manifest needs two things that must agree: the
    /// dependency declaration, and the package identity the target refers to.
    ///
    /// SwiftPM derives a **path** dependency's identity from the checkout
    /// directory's basename, not from the `name:` in its manifest. Hardcoding the
    /// identity as "OCCTSwiftScripts" therefore broke `occtkit run` in every
    /// checkout not literally named that: forks, second checkouts, and git
    /// worktrees, plus any `OCCTKIT_SCRIPTS_PATH` pointing somewhere named
    /// differently. Returning both together is what keeps them in step (#98).
    private struct ScriptsDep {
        /// The `.package(...)` line to interpolate into `dependencies:`.
        let declaration: String
        /// The identity to pass as `package:` in the target's product dependency.
        let identity: String
    }

    private static func pathDep(_ path: String) -> ScriptsDep {
        // Absolutized and standardized once, so the declaration and the identity
        // are provably the same value rather than two parallel derivations.
        //
        // Absolutizing matters because the generated manifest lives in the cache
        // directory, not the caller's CWD: a relative OCCTKIT_SCRIPTS_PATH passes
        // the `fileExists` probe against occtkit's CWD but would then resolve
        // against the workspace directory, pointing at nothing.
        //
        // `standardizedFileURL` collapses `.` and `..` (`/a/b/..` has a
        // `lastPathComponent` of ".." raw, "a" standardized). It does not resolve
        // symlinks, which is deliberate: SwiftPM derives the identity from the
        // path as declared, so a symlinked OCCTKIT_SCRIPTS_PATH must keep the
        // symlink's own basename for the two to agree.
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return ScriptsDep(
            declaration: ".package(path: \"\(escapedForManifest(url.path))\")",
            identity: url.lastPathComponent
        )
    }

    /// Escape a string for embedding in a generated Swift string literal.
    ///
    /// Both `"` and `\` are legal in APFS path components, so every value that
    /// reaches the generated manifest goes through this. Escaping happens at each
    /// interpolation site rather than inside `ScriptsDep`, so `identity` keeps
    /// comparing equal to the real directory basename. A half-applied escape is
    /// worse than none, because it reads as handled.
    private static func escapedForManifest(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func resolveScriptsDep() -> ScriptsDep {
        if let p = ProcessInfo.processInfo.environment["OCCTKIT_SCRIPTS_PATH"],
            FileManager.default.fileExists(atPath: p + "/Package.swift")
        {
            return pathDep(p)
        }
        // argv[0] is typically <pkg>/.build/<cfg>/occtkit when run via `swift run`
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidate = exe.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("Package.swift").path)
        {
            return pathDep(candidate.path)
        }
        // A URL dependency's identity is the last path component of the URL minus
        // any .git suffix, so this one is "OCCTSwiftScripts" regardless of where
        // the consumer checked anything out.
        return ScriptsDep(
            declaration:
                ".package(url: \"https://github.com/SecondMouseAU/OCCTSwiftScripts.git\", from: \"1.0.0\")",
            identity: "OCCTSwiftScripts"
        )
    }

    private static func ensureWorkspace() throws {
        let fm = FileManager.default
        let packageSwift = workspaceDir.appendingPathComponent("Package.swift")
        let sourcesDir = workspaceDir.appendingPathComponent("Sources/Script")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let scriptsDep = resolveScriptsDep()
        let packageContent = """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "OCCTSwiftUserScript",
                platforms: [.macOS(.v15)],
                dependencies: [
                    \(scriptsDep.declaration),
                ],
                targets: [
                    .executableTarget(
                        name: "Script",
                        dependencies: [
                            .product(name: "ScriptHarness", package: "\(escapedForManifest(scriptsDep.identity))"),
                        ],
                        path: "Sources/Script",
                        swiftSettings: [.swiftLanguageMode(.v6)]
                    ),
                ]
            )
            """
        try packageContent.write(to: packageSwift, atomically: true, encoding: .utf8)
    }

    private static func prepareScript(_ config: Config) throws {
        let scriptURL = URL(fileURLWithPath: config.scriptPath)
        var source = try String(contentsOf: scriptURL, encoding: .utf8)

        let wantsGraphJSON = config.formats.contains("graph-json")
        let wantsGraphSQLite = config.formats.contains("graph-sqlite")
        if wantsGraphJSON || wantsGraphSQLite {
            let graphCall = "try ctx.addGraphsForAllShapes(sqlite: \(wantsGraphSQLite))"
            if let emitRange = source.range(of: "try ctx.emit(") {
                source.insert(contentsOf: "\n\(graphCall)\n", at: emitRange.lowerBound)
            }
        }
        if !config.formats.contains("step") {
            source = source.replacingOccurrences(
                of: "ScriptContext()", with: "ScriptContext(exportSTEP: false)")
            source = source.replacingOccurrences(
                of: "ScriptContext(exportSTEP: true", with: "ScriptContext(exportSTEP: false")
        }

        let destURL =
            workspaceDir
            .appendingPathComponent("Sources/Script")
            .appendingPathComponent("main.swift")
        try source.write(to: destURL, atomically: true, encoding: .utf8)
    }

    private static func buildAndRun() throws {
        let buildProcess = Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        buildProcess.arguments = ["build", "--package-path", workspaceDir.path]
        buildProcess.currentDirectoryURL = workspaceDir
        let (buildStatus, buildStderr) = try runCapturingStderr(buildProcess)
        if buildStatus != 0 {
            // Lossy, not `String(data:encoding:)`: a garbled byte or two from a crashed
            // linker or a non-UTF-8 path shouldn't discard an otherwise-readable diagnostic
            // dump, which large builds are now far more likely to actually reach (#116).
            let errorOutput = String(decoding: buildStderr, as: UTF8.self)
            throw ScriptError.message("Build failed:\n\(errorOutput)")
        }

        let runProcess = Process()
        runProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        runProcess.arguments = [
            "run", "--skip-build", "--package-path", workspaceDir.path, "Script",
        ]
        runProcess.currentDirectoryURL = workspaceDir
        try runProcess.run()
        runProcess.waitUntilExit()
        if runProcess.terminationStatus != 0 {
            throw ScriptError.message("Script exited with code \(runProcess.terminationStatus)")
        }
    }

    /// Runs `process` with its stderr captured to a temp file, returning its termination
    /// status alongside everything it wrote.
    static func runCapturingStderr(_ process: Process) throws -> (status: Int32, stderr: Data) {
        // Not `private`, unlike this file's other helpers: `RunBuildPipeDrainTests.swift`
        // exercises it directly via `@testable import occtkit` against a cheap synthetic
        // subprocess rather than a real `swift build`. Still module-internal, not public API.
        //
        // Owns `process.standardError` end to end, rather than taking a caller-wired pipe
        // or handle, so a caller can't wire it to something else and have this silently
        // capture nothing. Not asserted: `Process.standardError` is never nil by default
        // (Foundation lazily wraps inherited stdio in a private `_NSStdIOFileHandle`), so
        // "did the caller already customize this" isn't distinguishable from "untouched"
        // without depending on that private type.
        //
        // Doesn't reuse `main.swift`'s `captureOutput`: that redirects the current
        // process's own stdout+stderr together and only surfaces them after its closure
        // returns, which would buffer `swift build`'s live progress on stdout until the
        // whole build finished instead of letting it stream to the terminal as it happens.
        // This captures only `process`'s stderr, on `process` itself, leaving its stdout
        // to flow through live.
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpURL = tmpDir.appendingPathComponent("occtkit-run-stderr-\(UUID().uuidString)")

        // Best-effort sweep of any stderr temp file a prior run couldn't clean up itself
        // (SIGKILL, e.g. a CI timeout, skips the `defer` below entirely): bounds the leak
        // to at most one orphaned file per kill rather than letting them accumulate.
        if let stale = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil)
        {
            for url in stale where url.lastPathComponent.hasPrefix("occtkit-run-stderr-") {
                try? FileManager.default.removeItem(at: url)
            }
        }

        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let handle = try FileHandle(forWritingTo: tmpURL)
        // Closes `handle` on every exit path, including `process.run()` throwing before
        // the child ever starts, rather than only after a successful run.
        defer { try? handle.close() }
        process.standardError = handle

        // A temp file has no fixed capacity to block the child's write() on, unlike an OS
        // pipe (~64KB on macOS): waitUntilExit() called on a pipe-backed stderr before
        // anything drained it deadlocked both sides on a large enough write, which is what
        // happened before this (#116; same class of bug fixed on the OCCTParts side in
        // SecondMouseAU/OCCTParts#23). Blocks the calling thread for the run's duration:
        // fine for today's synchronous callers; a future async caller should hop off its
        // own cooperative-pool thread before calling in, rather than this function
        // guessing at one. Waits for `process` itself, not any grandchild it spawns and
        // doesn't reap before exiting; fine for `swift build`/`swift run`, which wait out
        // their own subprocesses before they themselves exit.
        try process.run()
        process.waitUntilExit()

        let stderrData: Data
        do {
            stderrData = try Data(contentsOf: tmpURL)
        } catch {
            // A build failure with a blank diagnostic dump is exactly the silent loss
            // #116 was about; say so explicitly rather than returning empty Data
            // indistinguishable from "the build wrote nothing."
            stderrData = Data(
                "(failed to read captured stderr: \(error.localizedDescription))".utf8)
        }
        return (process.terminationStatus, stderrData)
    }

    private static func copyOutput(_ config: Config) throws {
        guard let outputDir = config.outputDir else { return }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let iCloud = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/OCCTSwiftScripts/output")
        let local = home.appendingPathComponent(".occtswift-scripts/output")
        let sourceDir = fm.fileExists(atPath: iCloud.path) ? iCloud : local
        guard fm.fileExists(atPath: sourceDir.path) else { return }

        let destURL = URL(fileURLWithPath: outputDir)
        try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
        for file in try fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil) {
            let dest = destURL.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: file, to: dest)
        }
        print("Output copied to \(outputDir)")
    }
}
