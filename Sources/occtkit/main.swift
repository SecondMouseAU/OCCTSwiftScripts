// occtkit: multi-call dispatcher for the OCCTSwift script suite.
//
// Dispatch order:
//   1. argv[0] basename matches a subcommand → use it (busybox-style symlinks).
//   2. argv[1] matches a subcommand → use it, pass remaining args.
//   3. otherwise: print help.
//
// `--serve` (anywhere in args) switches the resolved subcommand into a stdin
// JSONL request loop. Each line is `{"args": [...]}`; the response is a JSON
// envelope on stdout:
//
//   {"ok": true|false, "exit": <int>, "stdout": "<captured>",
//    "stderr": "<captured>", "error": "<msg>"?}
//
// `error` is present only when ok=false. Exactly one envelope object is
// emitted per stdin request line, including for malformed requests, build
// failures, and `Run` invocations whose inner subprocess wrote to inherited
// stdout/stderr (those streams are captured into the envelope, not leaked
// to occtkit's own stdout). EOF on stdin → exit 0.

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(WASILibc)
    import WASILibc
#endif

@MainActor
func printHelp() {
    var msg =
        "occtkit: OCCTSwift script suite\n\nUSAGE:\n  occtkit <subcommand> [args...]\n  occtkit <subcommand> --serve   (read JSONL requests on stdin)\n\nSUBCOMMANDS:\n"
    for cmd in Registry.all {
        msg += "  \(cmd.name.padding(toLength: 20, withPad: " ", startingAt: 0))\(cmd.summary)\n"
    }
    print(msg, terminator: "")
}

func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

@MainActor
func dispatch(_ cmd: any Subcommand.Type, args: [String]) -> Int32 {
    if args.contains("--serve") {
        #if os(WASI)
            // Output capture redirects FDs 1 and 2 with dup2, which WASI does not have.
            writeError("Error: --serve is not supported on WASI; use one-shot invocations")
            return 2
        #else
            return runServe(cmd: cmd)
        #endif
    }
    do {
        return try cmd.run(args: args)
    } catch {
        writeError("Error: \(error.localizedDescription)")
        return 1
    }
}

// MARK: - Entry

let argv = CommandLine.arguments
let exe = (argv.first as NSString?)?.lastPathComponent ?? "occtkit"

if let direct = Registry.find(exe) {
    exit(dispatch(direct, args: Array(argv.dropFirst())))
}

let rest = Array(argv.dropFirst())

// `--verbs` prints one registered verb name per line. This is the single source
// of truth the Makefile reads to create and remove the busybox-style symlinks,
// so the install list cannot drift from `Registry.all`.
if rest.first == "--verbs" {
    print(Registry.verbNames.joined(separator: "\n"))
    exit(0)
}

guard let first = rest.first, !first.hasPrefix("-") else {
    printHelp()
    exit(rest.first == "--help" || rest.first == "-h" ? 0 : (rest.isEmpty ? 0 : 1))
}

guard let cmd = Registry.find(first) else {
    writeError("Unknown subcommand: \(first)")
    printHelp()
    exit(1)
}

exit(dispatch(cmd, args: Array(rest.dropFirst())))
