// ImportExportVerbTests.swift
// OcctkitCommandTests
//
// Coverage for the file-format verbs: `import`, `dxf-export`, `inspect-assembly`,
// `set-metadata`, `simplify-mesh`. Each writes or reads a real file, so the assertions read the
// artefact back rather than trusting the JSON envelope.

import Foundation
import OCCTSwift
import ScriptHarness
import Testing

@testable import occtkit

@Suite("occtkit file-format verbs", .serialized)
struct ImportExportVerbTests {

    private func cubeFiles(in dir: URL) throws -> (brep: String, step: URL, stl: URL) {
        let cube = try VerbHarness.box()
        let brep = try VerbHarness.writeBREP(cube, named: "cube", in: dir)
        let step = dir.appendingPathComponent("cube.step")
        let stl = dir.appendingPathComponent("cube.stl")
        try Exporter.writeSTEP(shape: cube, to: step)
        try Exporter.writeSTL(shape: cube, to: stl)
        return (brep, step, stl)
    }

    // MARK: import

    @Test("import of a STEP cube emits one BREP body that round-trips to a 1000mm3 solid")
    func importStep() throws {
        let dir = try VerbHarness.makeTempDir("import")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try cubeFiles(in: dir)
        let emit = dir.appendingPathComponent("emit")

        let json = try VerbHarness.runJSON(
            ImportCommand.self, [files.step.path, "--emit-manifest", emit.path])

        let ids = try #require(json["addedBodyIds"] as? [String])
        #expect(ids.count == 1)
        let body = emit.appendingPathComponent("\(ids[0]).brep").path
        #expect(abs(try #require(GraphIO.loadBREP(at: body).volume) - 1000) < 1e-2)
        #expect(
            FileManager.default.fileExists(
                atPath: emit.appendingPathComponent("manifest.json").path))
    }

    @Test("import of an STL cube produces a body")
    func importStl() throws {
        let dir = try VerbHarness.makeTempDir("import")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try cubeFiles(in: dir)
        let emit = dir.appendingPathComponent("emit")

        let json = try VerbHarness.runJSON(
            ImportCommand.self, [files.stl.path, "--emit-manifest", emit.path])

        #expect((json["addedBodyIds"] as? [String])?.count == 1)
    }

    @Test("import rejects an unrecognised extension without --format")
    func importUnknownExtension() throws {
        let dir = try VerbHarness.makeTempDir("import")
        defer { try? FileManager.default.removeItem(at: dir) }
        let odd = dir.appendingPathComponent("part.xyz")
        try Data("not geometry".utf8).write(to: odd)

        VerbHarness.expectFailure(
            ImportCommand.self,
            [odd.path, "--emit-manifest", dir.appendingPathComponent("e").path],
            containing: "Cannot auto-detect format")
    }

    // MARK: dxf-export

    @Test("dxf-export writes a DXF with line entities and echoes the view and deflection")
    func dxfExport() throws {
        let dir = try VerbHarness.makeTempDir("dxf")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try cubeFiles(in: dir)
        let out = dir.appendingPathComponent("cube.dxf").path

        let json = try VerbHarness.runJSON(
            DXFExportCommand.self, [files.brep, out, "--view", "0,1,0", "--deflection", "0.5"])

        #expect(json["view"] as? [Double] == [0, 1, 0])
        #expect(abs(try VerbHarness.number(json, "deflection") - 0.5) < 1e-9)
        let dxf = try String(contentsOfFile: out, encoding: .utf8)
        #expect(dxf.contains("ENTITIES"))
        #expect(dxf.contains("LINE"))
    }

    @Test(
        "dxf-export projects along the requested view, so different views give different drawings")
    func dxfViewChangesProjection() throws {
        let dir = try VerbHarness.makeTempDir("dxf")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Non-cubic: a cube projects to the same square from every axis.
        let brep = try VerbHarness.writeBREP(
            try VerbHarness.box(10, 20, 30), named: "block", in: dir)
        let top = dir.appendingPathComponent("top.dxf").path
        let side = dir.appendingPathComponent("side.dxf").path

        try VerbHarness.run(DXFExportCommand.self, [brep, top, "--view", "0,0,1"])
        try VerbHarness.run(DXFExportCommand.self, [brep, side, "--view", "1,0,0"])

        let topDXF = try String(contentsOfFile: top, encoding: .utf8)
        let sideDXF = try String(contentsOfFile: side, encoding: .utf8)
        #expect(topDXF != sideDXF)
    }

    // MARK: inspect-assembly

    @Test("inspect-assembly of a BREP is a single non-assembly node")
    func inspectBrep() throws {
        let dir = try VerbHarness.makeTempDir("inspect")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try cubeFiles(in: dir)

        let json = try VerbHarness.runJSON(InspectAssemblyCommand.self, [files.brep])

        #expect(try VerbHarness.number(json, "totalComponents") == 1)
        let root = try #require(json["root"] as? [String: Any])
        #expect(root["isAssembly"] as? Bool == false)
        #expect((root["children"] as? [Any])?.isEmpty == true)
    }

    @Test("inspect-assembly of a STEP cube reports one component with a label id")
    func inspectStep() throws {
        let dir = try VerbHarness.makeTempDir("inspect")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try cubeFiles(in: dir)

        let json = try VerbHarness.runJSON(InspectAssemblyCommand.self, [files.step.path])

        #expect(try VerbHarness.number(json, "totalComponents") == 1)
        let root = try #require(json["root"] as? [String: Any])
        #expect((root["id"] as? String)?.hasPrefix("label_") == true)
    }

    // MARK: set-metadata

    @Test("set-metadata writes an XBF and reports every attribute it applied")
    func setMetadata() throws {
        let dir = try VerbHarness.makeTempDir("metadata")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try cubeFiles(in: dir)
        let out = dir.appendingPathComponent("tagged.xbf").path

        let json = try VerbHarness.runJSON(
            SetMetadataCommand.self,
            [
                files.step.path, "--output", out, "--title", "Widget", "--material", "Steel",
                "--custom-attr", "supplier=Acme",
            ])

        let applied = try #require(json["applied"] as? [String: String])
        #expect(applied["title"] == "Widget")
        #expect(applied["material"] == "Steel")
        #expect(applied["supplier"] == "Acme")
        #expect(FileManager.default.fileExists(atPath: out))
        // The XBF must reopen as a document.
        let reread = try VerbHarness.runJSON(InspectAssemblyCommand.self, [out])
        #expect(try VerbHarness.number(reread, "totalComponents") >= 1)
    }

    // MARK: simplify-mesh

    @Test("simplify-mesh halves a sphere's triangle count and writes an STL")
    func simplifySphere() throws {
        let dir = try VerbHarness.makeTempDir("simplify")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sphere = try #require(Shape.sphere(radius: 10))
        let input = try VerbHarness.writeBREP(sphere, named: "sphere", in: dir)
        let out = dir.appendingPathComponent("sphere.stl").path

        let json = try VerbHarness.runJSON(
            SimplifyMeshCommand.self, [input, "--target-reduction", "0.5", "--output", out])

        let before = try VerbHarness.number(json, "beforeTriangleCount")
        let after = try VerbHarness.number(json, "afterTriangleCount")
        #expect(before > 100)
        #expect(after < before * 0.55 && after > before * 0.45, "after \(after) of \(before)")
        #expect(FileManager.default.fileExists(atPath: out))
        #expect(try VerbHarness.number(json, "qualityDelta", "hausdorffDistance") > 0)
    }

    @Test("simplify-mesh requires exactly one target")
    func simplifyNeedsATarget() throws {
        let dir = try VerbHarness.makeTempDir("simplify")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sphere = try #require(Shape.sphere(radius: 10))
        let input = try VerbHarness.writeBREP(sphere, named: "sphere", in: dir)
        let out = dir.appendingPathComponent("sphere.stl").path

        #expect(throws: (any Error).self) {
            try VerbHarness.run(SimplifyMeshCommand.self, [input, "--output", out])
        }
        #expect(throws: (any Error).self) {
            try VerbHarness.run(
                SimplifyMeshCommand.self,
                [
                    input, "--target-reduction", "0.5", "--target-triangle-count", "100",
                    "--output", out,
                ])
        }
    }
}
