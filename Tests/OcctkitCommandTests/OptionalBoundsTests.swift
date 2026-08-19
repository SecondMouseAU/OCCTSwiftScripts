// OptionalBoundsTests.swift
// OcctkitCommandTests
//
// Regression coverage for OCCTSwiftScripts#118 / OCCTSwift#943 (v3.0.0): `Shape.bounds` (and
// the other five affected accessors) went from fabricating `(0,0,0)-(0,0,0)` on a shape with
// no bounding box to returning `nil`. Every call site in this repo that reads a bounding box
// off a loaded shape now has to unwrap that `Optional` instead of silently reporting a bogus
// zero-size box. This locks in the unwrap-and-throw behaviour directly, rather than relying on
// the recipe smoke suite (which only exercises the "has real bounds" path).

import Foundation
import OCCTSwift
import ScriptHarness
import Testing

@testable import occtkit

@Suite("occtkit bounds-Optional handling (#118)")
struct OptionalBoundsTests {

    /// The intersection of two boxes with no overlap: a valid, well-formed empty `Shape`
    /// (`BRepAlgoAPI_Common` on disjoint inputs succeeds with an empty result rather than
    /// failing) whose `Bnd_Box` is void, so every affected accessor reports `nil` per OCCTSwift
    /// v3.0.0's own migration note.
    private func voidShape() throws -> Shape {
        let a = try #require(Shape.box(width: 1, height: 1, depth: 1))
        let bOrigin = try #require(Shape.box(width: 1, height: 1, depth: 1))
        let b = try #require(bOrigin.translated(by: SIMD3(1000, 1000, 1000)))
        return try #require(a.intersection(b))
    }

    @Test(
        "Two disjoint boxes' intersection has no bounding box (sanity check for the fixture itself)"
    )
    func voidShapeHasNilBounds() throws {
        let shape = try voidShape()
        #expect(shape.bounds == nil)
    }

    @Test("LoadBrepCommand.buildResponse throws, not fabricates, on a shape with no bounding box")
    func loadBrepThrowsOnVoidBounds() throws {
        let shape = try voidShape()
        #expect(throws: ScriptError.self) {
            _ = try LoadBrepCommand.buildResponse(bodyId: "body_0", shape: shape)
        }
    }

    @Test("MeasureDeviationCommand.defaultDeflection throws, not fabricates, on a void shape")
    func defaultDeflectionThrowsOnVoidBounds() throws {
        let shape = try voidShape()
        #expect(throws: ScriptError.self) {
            _ = try MeasureDeviationCommand.defaultDeflection(for: shape)
        }
    }
}
