// RegistryCoverageTests.swift
// OcctkitCommandTests
//
// Guard against a verb being registered with no test at all. 24 of 29 verbs once had none and
// nothing noticed. Adding a verb to `Registry.all` now fails here until a test names its type,
// or it is listed in `exempt` with a reason someone can challenge.

import Foundation
import Testing

@testable import occtkit

@Suite("occtkit registry coverage")
struct RegistryCoverageTests {

    /// Verbs that no in-process test drives, and why.
    ///
    /// Keep the reasons accurate: an entry here is a known gap, not an approval.
    private static let exempt: [String: String] = [
        "RenderPreviewCommand": "needs a Metal device, which CI runners do not reliably have"
    ]

    private func testSources() throws -> String {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension == "swift" && $0.lastPathComponent != "RegistryCoverageTests.swift"
        }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    @Test("every registered verb is named by at least one test, or exempted with a reason")
    func everyVerbHasATest() throws {
        let sources = try testSources()
        var untested: [String] = []
        for verb in Registry.all {
            let typeName = String(describing: verb)
            if Self.exempt[typeName] != nil { continue }
            if !sources.contains("\(typeName)") { untested.append("\(verb.name) (\(typeName))") }
        }
        #expect(untested.isEmpty, "verbs with no test: \(untested.joined(separator: ", "))")
    }

    @Test("every exemption still names a registered verb")
    func exemptionsAreCurrent() {
        let registered = Set(Registry.all.map { String(describing: $0) })
        for name in Self.exempt.keys {
            #expect(registered.contains(name), "stale exemption \(name)")
        }
    }
}
