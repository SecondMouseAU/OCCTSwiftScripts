// SceneDirectoryTests.swift
// OcctkitCommandTests
//
// A run pointed at a host's scene or stage directory must leave the host's files alone, write
// its manifest atomically, merge rather than replace on import, and mark a failed run (#143, #144).

import Foundation
import ScriptHarness
import Testing

@testable import occtkit

@Suite("scene directory handling", .serialized)
struct SceneDirectoryTests {

    private func manifestObject(in dir: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent("manifest.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: ScriptContext (#143)

    @Test("a run into a stage directory leaves every other file alone and leaves no marker")
    func stageDirectoryKeepsHostFiles() throws {
        let dir = try VerbHarness.makeTempDir("stage")
        defer { try? FileManager.default.removeItem(at: dir) }
        let hostFile = dir.appendingPathComponent("annotations.json")
        let hostBody = dir.appendingPathComponent("body-7.brep")
        try Data("host".utf8).write(to: hostFile)
        try Data("host".utf8).write(to: hostBody)

        let ctx = ScriptContext(exportSTEP: false, outputDirectory: dir)
        try ctx.add(try VerbHarness.box(), id: "box")
        try ctx.emit(description: "stage")

        #expect(try String(contentsOf: hostFile, encoding: .utf8) == "host")
        #expect(try String(contentsOf: hostBody, encoding: .utf8) == "host")
        #expect(
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("body-0.brep").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: dir.appendingPathComponent(ManifestIO.failureMarkerFilename).path))
        #expect((try manifestObject(in: dir)["bodies"] as? [[String: Any]])?.count == 1)
    }

    @Test("a failed run leaves a readable marker, and the next successful emit removes it")
    func failureMarker() throws {
        let dir = try VerbHarness.makeTempDir("stage")
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent(ManifestIO.failureMarkerFilename)

        let failing = ScriptContext(exportSTEP: false, outputDirectory: dir)
        try failing.fail("boolean cut returned nil")
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Any])
        #expect(json["message"] as? String == "boolean cut returned nil")

        let retry = ScriptContext(exportSTEP: false, outputDirectory: dir)
        try retry.add(try VerbHarness.box())
        try retry.emit()
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: Manifest merge (#144)

    @Test("import into a directory with a manifest keeps its bodies and manifest-level fields")
    func importMerges() throws {
        let dir = try VerbHarness.makeTempDir("merge")
        defer { try? FileManager.default.removeItem(at: dir) }
        let scene = dir.appendingPathComponent("scene")
        try FileManager.default.createDirectory(at: scene, withIntermediateDirectories: true)
        let existing = """
            {"version":1,"timestamp":"2026-01-01T00:00:00Z","description":"kept",
             "hostField":"survives",
             "metadata":{"name":"Bracket"},
             "bodies":[{"id":"old","file":"old.brep","format":"brep"}],
             "graphs":[{"id":"g","file":"graph-0.json"}]}
            """
        try Data(existing.utf8).write(to: scene.appendingPathComponent("manifest.json"))
        let brep = try VerbHarness.writeBREP(try VerbHarness.box(), named: "cube", in: dir)

        _ = try VerbHarness.runJSON(LoadBrepCommand.self, [brep, "--emit-manifest", scene.path])

        let merged = try manifestObject(in: scene)
        let ids = (merged["bodies"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
        #expect(ids == ["old", "cube"])
        #expect(merged["description"] as? String == "kept")
        #expect(merged["hostField"] as? String == "survives")
        #expect((merged["metadata"] as? [String: Any])?["name"] as? String == "Bracket")
        #expect((merged["graphs"] as? [[String: Any]])?.count == 1)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: scene.path).sorted()
                == ["cube.brep", "manifest.json"])
    }

    @Test("importing the same id again replaces that body rather than duplicating it")
    func importReplacesSameId() throws {
        let dir = try VerbHarness.makeTempDir("merge")
        defer { try? FileManager.default.removeItem(at: dir) }
        let scene = dir.appendingPathComponent("scene")
        let brep = try VerbHarness.writeBREP(try VerbHarness.box(), named: "cube", in: dir)

        for _ in 0..<2 {
            _ = try VerbHarness.runJSON(
                LoadBrepCommand.self, [brep, "--emit-manifest", scene.path])
        }

        #expect((try manifestObject(in: scene)["bodies"] as? [[String: Any]])?.count == 1)
    }

    @Test("a manifest that is not a JSON object is refused, not overwritten")
    func refusesGarbage() throws {
        let dir = try VerbHarness.makeTempDir("merge")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("manifest.json")
        try Data("[1,2]".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            try ManifestIO.merge(ScriptManifest(description: nil, bodies: []), into: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "[1,2]")
    }
}
