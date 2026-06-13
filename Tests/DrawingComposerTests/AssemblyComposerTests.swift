import Testing
import Foundation
import OCCTSwift
@testable import DrawingComposer

/// General-arrangement / assembly drawing support (OCCTSwiftScripts#50).
@Suite("Assembly composer")
struct AssemblyComposerTests {

    private func gaSpec() -> DrawingSpec {
        DrawingSpec(
            sheet: SheetSpec(size: .a3, orientation: .landscape,
                             projection: .third, scale: .auto),
            views: [ViewSpec(name: "front"), ViewSpec(name: "top"), ViewSpec(name: "right")]
        )
    }

    // Row-major 3×4 affine translation, matching Shape.transformed(matrix:).
    private func translation(_ x: Double, _ y: Double, _ z: Double) -> [Double] {
        [1, 0, 0, x,
         0, 1, 0, y,
         0, 0, 1, z]
    }

    @Test("Lays out multiple components and merges duplicates into BOM quantity")
    func multiComponentBOM() throws {
        let box = try #require(Shape.box(width: 20, height: 20, depth: 20))
        let pin = try #require(Shape.cylinder(radius: 4, height: 30))

        // Two box instances (same name → one BOM row, qty 2) + one pin.
        let components = [
            Composer.DrawingComponent(shape: box, name: "Plate", partNumber: "P-100"),
            Composer.DrawingComponent(shape: box, name: "Plate", partNumber: "P-100",
                                      transform: translation(40, 0, 0)),
            Composer.DrawingComponent(shape: pin, name: "Dowel Pin", partNumber: "P-200",
                                      material: "Steel"),
        ]

        let result = try Composer.render(spec: gaSpec(), components: components)

        #expect(result.componentCount == 3)
        // Two distinct parts → two BOM rows.
        #expect(result.partsList.count == 2)

        let plate = try #require(result.partsList.first { $0.partNumber == "P-100" })
        #expect(plate.number == 1)
        #expect(plate.quantity == 2)          // the two box instances merged
        #expect(plate.description == "Plate")

        let pinRow = try #require(result.partsList.first { $0.partNumber == "P-200" })
        #expect(pinRow.number == 2)
        #expect(pinRow.quantity == 1)
        #expect(pinRow.material == "Steel")

        // The DXF actually contains geometry: write it and check it's non-trivial.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ga-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        try result.writer.write(to: url)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 4_000, "GA DXF was only \(size) bytes — views may not have rendered")
    }

    @Test("Empty component list throws")
    func emptyThrows() {
        #expect(throws: (any Error).self) {
            _ = try Composer.render(spec: gaSpec(), components: [])
        }
    }

    @Test("A placement transform repositions a component without crashing")
    func transformApplied() throws {
        let box = try #require(Shape.box(width: 10, height: 10, depth: 10))
        let near = Composer.DrawingComponent(shape: box, name: "A")
        let far  = Composer.DrawingComponent(shape: box, name: "B",
                                             transform: translation(100, 0, 0))
        let result = try Composer.render(spec: gaSpec(), components: [near, far])
        #expect(result.componentCount == 2)
        #expect(result.partsList.count == 2)        // distinct names → two rows
        // Two separated boxes span a wider frame than one, so "auto" should pick
        // a scale ≤ 1:1 (i.e. a reduction). Just assert it produced a label.
        #expect(!result.scaleLabel.isEmpty)
    }
}
