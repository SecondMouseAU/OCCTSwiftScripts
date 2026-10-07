// AAGFaceIndexTests.swift
// OcctkitCommandTests
//
// Regression coverage for OCCTSwiftScripts#111 / OCCTSwift#642 (v2.0.0): `AAG` builds its
// node set from `Shape.orientedFaces()` (an OCCURRENCE index) rather than `Shape.faces()`
// (the deduplicated index the `face[N]` scheme `query-topology` emits, and the one
// `graph-select` / `graph-ml` are documented to align with). On a shape with a face shared
// between two solids in a compound the two index spaces diverge; before the #111 fix,
// `graph-select --query face-adjacency` and `graph-ml`'s `faceAdjacency` both leaked AAG's
// raw occurrence indices straight into a `face[N]`-shaped response, silently naming (or, for
// graph-ml, dangling-referencing) the wrong face.
//
// Fixture: the split-box compound from OCCTSwift's own `Face.orientedFaces()` /
// `AAGNode.distinctFaceIndex` doc comments: a plain 10mm box split by a horizontal plane
// and recompounded, so the cut face is shared by both halves. Chosen deliberately to match
// the upstream repro exactly, rather than a fixture invented for this test, since the
// upstream doc comments already pin the expected counts (11 distinct faces, 12 occurrences).

import Foundation
import OCCTSwift
import Testing

@testable import occtkit

// .serialized plus `VerbHarness`'s process-wide capture lock: every test below redirects the
// process's real fd 1 (stdout) via dup2 to capture a Subcommand's JSON output.
@Suite("occtkit AAG face-index consistency (#111)", .serialized)
struct AAGFaceIndexTests {

    /// A 10mm box split through z=4, recompounded so the cut face is shared by both halves.
    /// `compound.faces().count == 11` (distinct); `compound.orientedFaces().count == 12`
    /// (occurrences: the shared wall counted once per owning solid). Matches
    /// `OCCTSwift/Sources/OCCTSwift/Face.swift`'s own `orientedFaces()` doc example.
    private func splitBoxCompound() throws -> Shape {
        let box = try #require(Shape.box(width: 10, height: 10, depth: 10))
        let halves = try #require(box.split(atPlane: SIMD3(0, 0, 4), normal: SIMD3(0, 0, 1)))
        return try #require(Shape.compound(halves))
    }

    private func writeTempBREP(_ shape: Shape) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aag-face-index-\(UUID().uuidString).brep")
        try Exporter.writeBREP(shape: shape, to: url)
        return url
    }

    private func captureStdout(_ block: () throws -> Int32) throws -> String {
        try VerbHarness.captureStdout(block)
    }

    // Minimal Decodable mirrors of GraphSelectCommand's (Encodable-only) wire responses, so
    // this test validates the actual JSON contract a caller sees, not merely Swift-level
    // structural equality with the production type.
    private struct FaceAdjacencyWire: Decodable {
        let faceCount: Int
        let adjacencies: [FaceAdjWire]
    }
    private struct FaceAdjWire: Decodable {
        let face1: Int
        let face2: Int
    }
    private struct FaceNeighborsWire: Decodable {
        let face: Int
        let neighbors: [NeighborWire]
        let warning: String?
    }
    private struct NeighborWire: Decodable { let face: Int }

    @Test("Fixture sanity: shared cut face gives 11 distinct faces over 12 occurrences")
    func fixtureMatchesUpstreamDocExample() throws {
        let compound = try splitBoxCompound()
        #expect(compound.faces().count == 11)
        #expect(compound.orientedFaces().count == 12)
    }

    @Test("graph-select face-adjacency reports shape.faces()-relative indices, not AAG occurrences")
    func faceAdjacencyUsesDistinctIndices() throws {
        let compound = try splitBoxCompound()
        let url = try writeTempBREP(compound)
        defer { try? FileManager.default.removeItem(at: url) }

        let stdout = try captureStdout {
            try GraphSelectCommand.run(args: [url.path, "--query", "face-adjacency"])
        }
        let response = try JSONDecoder().decode(FaceAdjacencyWire.self, from: Data(stdout.utf8))

        // Before #111's fix this was `aag.nodes.count` == 12 (the occurrence count); it must
        // now match the distinct-face count `query-topology`'s own `face[N]` scheme uses.
        #expect(response.faceCount == compound.faces().count)
        #expect(response.faceCount == 11)

        // Every edge must reference the shape.faces() index space (never the raw occurrence
        // index the un-fixed code emitted).
        for adj in response.adjacencies {
            #expect(adj.face1 >= 0 && adj.face1 < response.faceCount)
            #expect(adj.face2 >= 0 && adj.face2 < response.faceCount)
        }

        // The two occurrences of the shared cut face must have collapsed onto ONE distinct
        // index: ground-truth this against AAG directly (not against the JSON, which is
        // exactly what could hide the bug if the fix were a no-op).
        let aag = AAG(shape: compound)
        let byDistinctIndex = Dictionary(grouping: aag.nodes.indices) {
            aag.nodes[$0].distinctFaceIndex
        }
        let sharedFaces = byDistinctIndex.filter { $0.value.count > 1 }
        #expect(sharedFaces.count == 1)
        #expect(sharedFaces.first?.value.count == 2)

        // In-range is not enough: a leaked occurrence index is usually still < faceCount. The
        // response must equal, pair for pair, what AAG says once each endpoint is mapped through
        // `distinctFaceIndex`. Reverting the #111 fix in the verb changes this set (every face
        // after the shared one shifts by one), so this is the assertion that fails on a revert.
        func key(_ a: Int, _ b: Int) -> String { "\(min(a, b))-\(max(a, b))" }
        let expected = Set(
            aag.edges.map {
                key(
                    aag.nodes[$0.face1Index].distinctFaceIndex,
                    aag.nodes[$0.face2Index].distinctFaceIndex)
            })
        let actual = Set(response.adjacencies.map { key($0.face1, $0.face2) })
        #expect(actual == expected)
        let leaksPossible = aag.edges.contains {
            $0.face1Index != aag.nodes[$0.face1Index].distinctFaceIndex
                || $0.face2Index != aag.nodes[$0.face2Index].distinctFaceIndex
        }
        #expect(
            leaksPossible,
            "fixture must have at least one occurrence index that differs from its distinct index")
    }

    @Test("graph-select face-neighbors on a shared face resolves via the distinct index and warns")
    func faceNeighborsWarnsOnSharedFace() throws {
        let compound = try splitBoxCompound()
        let url = try writeTempBREP(compound)
        defer { try? FileManager.default.removeItem(at: url) }

        let aag = AAG(shape: compound)
        let byDistinctIndex = Dictionary(grouping: aag.nodes.indices) {
            aag.nodes[$0].distinctFaceIndex
        }
        let sharedDistinctIndex = try #require(byDistinctIndex.first { $0.value.count > 1 }?.key)

        let stdout = try captureStdout {
            try GraphSelectCommand.run(args: [
                url.path, "--query", "face-neighbors", "--face", "\(sharedDistinctIndex)",
            ])
        }
        let response = try JSONDecoder().decode(FaceNeighborsWire.self, from: Data(stdout.utf8))

        #expect(response.face == sharedDistinctIndex)
        // A shared face must be disclosed, not silently resolved to an arbitrary side.
        #expect(response.warning != nil)
        for n in response.neighbors {
            #expect(n.face >= 0 && n.face < compound.faces().count)
        }
        // Exact set, mapped through `distinctFaceIndex`: in-range alone passes on a leaked
        // occurrence index. The verb answers for the first occurrence of the shared face.
        let firstOccurrence = try #require(
            aag.nodes.indices.first { aag.nodes[$0].distinctFaceIndex == sharedDistinctIndex })
        let expected = Set(
            aag.neighbors(of: firstOccurrence).map { aag.nodes[$0].distinctFaceIndex })
        #expect(Set(response.neighbors.map(\.face)) == expected)
    }

    @Test("graph-select face-neighbors on a face past the shared one reports distinct indices")
    func faceNeighborsPastTheSharedFace() throws {
        let compound = try splitBoxCompound()
        let url = try writeTempBREP(compound)
        defer { try? FileManager.default.removeItem(at: url) }

        // Pick a face whose neighbours' occurrence indices differ from their distinct indices:
        // one past the shared face, in the second solid. A query on a face before the shift
        // cannot tell a leaked occurrence index from a distinct one. Also required to be the
        // first occurrence of its distinct index, since that is the occurrence the verb answers for.
        let aag = AAG(shape: compound)
        func distinctNeighbours(_ occurrence: Int) -> Set<Int> {
            Set(aag.neighbors(of: occurrence).map { aag.nodes[$0].distinctFaceIndex })
        }
        let occurrence = try #require(
            aag.nodes.indices.first { occ in
                aag.nodes.indices.first {
                    aag.nodes[$0].distinctFaceIndex == aag.nodes[occ].distinctFaceIndex
                }
                    == occ && Set(aag.neighbors(of: occ)) != distinctNeighbours(occ)
            }, "fixture must contain a face whose neighbours' indices shift")
        let distinct = aag.nodes[occurrence].distinctFaceIndex

        let stdout = try captureStdout {
            try GraphSelectCommand.run(args: [
                url.path, "--query", "face-neighbors", "--face", "\(distinct)",
            ])
        }
        let response = try JSONDecoder().decode(FaceNeighborsWire.self, from: Data(stdout.utf8))

        #expect(Set(response.neighbors.map(\.face)) == distinctNeighbours(occurrence))
    }

    @Test("graph-ml's faceAdjacency never dangling-references past faces.count")
    func graphMLFaceAdjacencyStaysInBounds() throws {
        let compound = try splitBoxCompound()
        let url = try writeTempBREP(compound)
        defer { try? FileManager.default.removeItem(at: url) }

        // A positive but tiny grid: sampleFaceUVGrid(uSamples: 0, ...) returns nil per face,
        // which compactMap silently drops, so 0 would make `faces` empty for the wrong reason.
        let stdout = try captureStdout {
            try GraphMLCommand.run(args: [url.path, "--uv-samples", "2", "--edge-samples", "2"])
        }
        // GraphMLCommand.Payload is already Codable in production; decode it directly rather
        // than a mirror, since faces[] and faceAdjacency[] both need to agree it's the SAME type.
        let payload = try JSONDecoder().decode(GraphMLCommand.Payload.self, from: Data(stdout.utf8))

        #expect(payload.faces.count == compound.faces().count)
        #expect(!payload.faceAdjacency.isEmpty)
        for adj in payload.faceAdjacency {
            // Before #111's fix these were raw AAG occurrence indices: on this fixture that
            // means an edge naming occurrence 11 (0-based, the 12th occurrence) would dangle
            // past `faces.count == 11`, a node this payload's own faces[] array never emits.
            #expect(adj.face1 >= 0 && adj.face1 < payload.faces.count)
            #expect(adj.face2 >= 0 && adj.face2 < payload.faces.count)
        }
    }
}
