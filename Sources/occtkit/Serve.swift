// Serve.swift: `--serve` JSONL request loop and the FD-level output capture it depends on.
//
// Moved out of main.swift unchanged so the whole file can be compiled out on WASI, which has no
// dup2 (see Package.swift and the `--serve` branch of `dispatch`).

#if !os(WASI)
    import Foundation

    #if canImport(Darwin)
        import Darwin
    #elseif canImport(Glibc)
        import Glibc
    #endif

    struct ServeRequest: Decodable {
        let args: [String]
    }

    struct ServeResponse: Encodable {
        let ok: Bool
        let exit: Int32
        let stdout: String
        let stderr: String
        let error: String?
    }

    @MainActor
    func runServe(cmd: any Subcommand.Type) -> Int32 {
        let stdin = FileHandle.standardInput
        var buffer = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                return 0
            }
            buffer.append(chunk)
            while let nlIdx = buffer.firstIndex(of: 0x0A) {
                let lineRange = buffer.startIndex..<nlIdx
                let line = buffer.subdata(in: lineRange)
                buffer.removeSubrange(buffer.startIndex...nlIdx)
                handleServeLine(cmd: cmd, line: line)
            }
        }
    }

    @MainActor
    func handleServeLine(cmd: any Subcommand.Type, line: Data) {
        if line.isEmpty || line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
            return
        }

        let req: ServeRequest
        do {
            req = try JSONDecoder().decode(ServeRequest.self, from: line)
        } catch {
            emitResponse(
                ServeResponse(
                    ok: false, exit: 1, stdout: "", stderr: "",
                    error: "invalid request JSON: \(error.localizedDescription)"
                ))
            return
        }

        let captured = captureOutput { try cmd.run(args: req.args) }
        emitResponse(
            ServeResponse(
                ok: captured.error == nil && captured.exit == 0,
                exit: captured.exit,
                stdout: String(data: captured.stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: captured.stderrData, encoding: .utf8) ?? "",
                error: captured.error
            ))
    }

    func emitResponse(_ response: ServeResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(response) {
            // Write directly to FD 1: the FileHandle.standardOutput cache may
            // be holding the saved-FD reference if we're called during cleanup.
            data.withUnsafeBytes { buf in
                if let base = buf.baseAddress { _ = write(STDOUT_FILENO, base, buf.count) }
            }
            var newline: UInt8 = 0x0A
            _ = write(STDOUT_FILENO, &newline, 1)
        }
    }

    // MARK: - Output capture
    //
    // Redirect FDs 1 and 2 to temp files for the duration of `work()`, then
    // restore them and read back what was written. Captures both in-process
    // writes (FileHandle.standardOutput, print, stderr) and child-process
    // inherited streams (Process subprocesses spawned by `Run`).
    //
    // Temp files are used over pipes to sidestep buffer-deadlock when the
    // subcommand writes more than the pipe buffer (~64KB) before any drain.

    struct CapturedOutput {
        let exit: Int32
        let error: String?
        let stdoutData: Data
        let stderrData: Data
    }

    func captureOutput(_ work: () throws -> Int32) -> CapturedOutput {
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("occtkit-out-\(UUID().uuidString)")
        let errURL = tmp.appendingPathComponent("occtkit-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        let outFD = open(outURL.path, O_WRONLY)
        let errFD = open(errURL.path, O_WRONLY)
        guard outFD >= 0, errFD >= 0 else {
            if outFD >= 0 { close(outFD) }
            if errFD >= 0 { close(errFD) }
            return runWithoutCapture(work)
        }

        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        guard savedOut >= 0, savedErr >= 0 else {
            if savedOut >= 0 { close(savedOut) }
            if savedErr >= 0 { close(savedErr) }
            close(outFD)
            close(errFD)
            return runWithoutCapture(work)
        }
        if dup2(outFD, STDOUT_FILENO) < 0 || dup2(errFD, STDERR_FILENO) < 0 {
            // Put back whatever was redirected, then run uncaptured.
            dup2(savedOut, STDOUT_FILENO)
            dup2(savedErr, STDERR_FILENO)
            close(savedOut)
            close(savedErr)
            close(outFD)
            close(errFD)
            return runWithoutCapture(work)
        }
        close(outFD)
        close(errFD)

        var exitCode: Int32 = 0
        var error: String? = nil
        do {
            exitCode = try work()
        } catch let e {
            error = e.localizedDescription
            exitCode = 1
        }

        fflush(stdout)
        fflush(stderr)

        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        close(savedOut)
        close(savedErr)

        let outData = (try? Data(contentsOf: outURL)) ?? Data()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()
        return CapturedOutput(
            exit: exitCode, error: error, stdoutData: outData, stderrData: errData)
    }

    func runWithoutCapture(_ work: () throws -> Int32) -> CapturedOutput {
        do {
            let exitCode = try work()
            return CapturedOutput(
                exit: exitCode, error: nil, stdoutData: Data(), stderrData: Data())
        } catch {
            return CapturedOutput(
                exit: 1, error: error.localizedDescription, stdoutData: Data(), stderrData: Data())
        }
    }
#endif
