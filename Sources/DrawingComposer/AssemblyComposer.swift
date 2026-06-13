// AssemblyComposer.swift
// Multi-shape / assembly overloads for `Composer.render` (OCCTSwiftScripts#50).
//
// The single-shape `render(spec:shape:)` lays out orthographic views of one
// part. A general-arrangement (GA) sheet instead shows several components
// together in shared views, keyed to a parts list by numbered balloons.
//
// Feeding `Shape.compound([...])` to the single-shape API loses per-part
// identity in the views (no way to balloon individual components). These
// overloads keep each component distinct: every component is projected
// separately, the views share one scale + placement frame so the parts sit in
// their assembled positions, and each component is keyed to a `BillOfMaterials`
// row by a numbered balloon.
//
// What's intentionally NOT carried over from the single-shape path (the spec's
// per-view `sections` / `detailViews` / `dimensions` / manual annotations are
// keyed to a single drawing per named view, which doesn't map onto N drawings
// per view): only auto centrelines / centermarks are applied, per component.

import Foundation
import OCCTSwift
import simd

extension Composer {

    /// One component of a general-arrangement drawing: a shape plus the
    /// identity that drives its parts-list row and balloon.
    public struct DrawingComponent: Sendable {
        public var shape: Shape
        public var name: String
        public var partNumber: String?
        public var material: String?
        /// Optional 12-element row-major 3×4 affine placement applied to `shape`
        /// before projection (its assembled position). `nil` → project the
        /// shape as-is (already positioned). Mirrors `Shape.transformed(matrix:)`.
        public var transform: [Double]?

        public init(shape: Shape,
                    name: String,
                    partNumber: String? = nil,
                    material: String? = nil,
                    transform: [Double]? = nil) {
            self.shape = shape
            self.name = name
            self.partNumber = partNumber
            self.material = material
            self.transform = transform
        }
    }

    /// Compose a general-arrangement drawing laying out `components` in shared
    /// views, with a numbered balloon per part and a parts-list (BOM) table.
    ///
    /// Components sharing the same `partNumber` (or, when absent, the same
    /// `name`) merge into one BOM row with summed quantity, while every instance
    /// is still drawn in its assembled position. Item numbers are assigned in
    /// first-appearance order.
    public static func render(spec: DrawingSpec,
                              components: [DrawingComponent]) throws -> DrawingComposerResult {
        guard !components.isEmpty else {
            throw DrawingComposerError.shapeBuildFailed("render(spec:components:) needs at least one component")
        }
        let deflection = spec.deflection ?? 0.1
        let projectionAngle = spec.sheet.projection.upstream
        let paperSize = spec.sheet.size.upstream
        let orientation = spec.sheet.orientation.upstream

        // Apply each component's placement (if any) so parts project in their
        // assembled positions.
        let positioned: [Shape] = components.map { c in
            if let t = c.transform, let moved = c.shape.transformed(matrix: t) { return moved }
            return c.shape
        }

        // Project every component for every requested view.
        // perView[name] = [(componentIndex, ViewItem)]
        var perView: [String: [(idx: Int, item: ViewItem)]] = [:]
        for (idx, shape) in positioned.enumerated() {
            for item in MultiViewLayout.project(shape, views: spec.views, deflection: deflection) {
                perView[item.name, default: []].append((idx, item))
            }
        }
        guard !perView.isEmpty else { throw DrawingComposerError.noViewsProjected }

        // Synthetic per-view items carrying the *combined* bounds drive scale +
        // placement so the whole assembly fits and the views stay aligned.
        var combined: [ViewItem] = []
        for view in spec.views {
            guard let comps = perView[view.name], !comps.isEmpty else { continue }
            let bounds = unionBounds(comps.compactMap { $0.item.bounds })
            combined.append(ViewItem(name: view.name,
                                     direction: comps[0].item.direction,
                                     drawing: comps[0].item.drawing,
                                     bounds: bounds))
        }
        guard !combined.isEmpty else { throw DrawingComposerError.noViewsProjected }

        // Drawing scale + sheet (border + title block + projection symbol).
        let sheetSize = paperSize.size(in: orientation)
        let drawableArea = (width: sheetSize.x - 30, height: sheetSize.y - 80)
        let drawScale = chooseScale(spec.sheet.scale, items: combined, drawableArea: drawableArea)
        let scaleLabel = formatDrawingScale(drawScale)

        let sheet = Sheet(size: paperSize,
                          orientation: orientation,
                          projection: projectionAngle,
                          title: spec.title?.upstream(scale: scaleLabel),
                          scale: scaleLabel)
        let writer = DXFWriter(deflection: deflection)
        if spec.sheet.border ?? true { sheet.render(into: writer) }

        let inner = sheet.innerFrame
        let centre = SIMD2((inner.min.x + inner.max.x) / 2,
                           inner.min.y + (inner.max.y - inner.min.y - 60) / 2 + 60)
        let placed = MultiViewLayout.place(items: combined,
                                           angle: projectionAngle,
                                           sheetCentre: centre,
                                           scale: drawScale)

        // Auto centrelines / centermarks, per component (the only spec-driven
        // annotations that map onto N-drawings-per-view).
        applyAutoCenterAnnotations(perView: perView, positioned: positioned, spec: spec)

        // Render every component's projected drawing at its view's shared frame.
        for view in spec.views {
            guard let comps = perView[view.name], let p = placed[view.name] else { continue }
            for (_, item) in comps {
                writer.collectFromDrawing(item.drawing.transformed(translate: p.translate, scale: p.scale))
            }
            if let bb = p.item.bounds {
                let centreX = (bb.min.x + bb.max.x) / 2
                let yBelow = bb.min.y - 5
                let labelPos = SIMD2(centreX * p.scale + p.translate.x,
                                     yBelow * p.scale + p.translate.y)
                writer.addText(view.name.uppercased(), at: labelPos, height: 4.0, layer: "TEXT")
            }
        }

        // Parts list: merge by partNumber ?? name, summing quantities, numbered
        // in first-appearance order. `firstIdx` keeps the representative instance
        // for ballooning.
        var order: [String] = []
        var groups: [String: (item: BillOfMaterials.Item, firstIdx: Int)] = [:]
        for (idx, c) in components.enumerated() {
            let key = c.partNumber ?? c.name
            if var g = groups[key] {
                g.item.quantity += 1
                groups[key] = g
            } else {
                let number = order.count + 1
                groups[key] = (BillOfMaterials.Item(number: number,
                                                    partNumber: c.partNumber,
                                                    description: c.name,
                                                    quantity: 1,
                                                    material: c.material),
                               idx)
                order.append(key)
            }
        }
        let bomItems = order.compactMap { groups[$0]?.item }

        // Balloons on the anchor view (front preferred), one per BOM row at the
        // representative instance's projected centroid.
        let anchorName = perView["front"] != nil ? "front" : (spec.views.first?.name ?? "")
        if let anchorComps = perView[anchorName], let p = placed[anchorName] {
            let itemByIdx = Dictionary(anchorComps.map { ($0.idx, $0.item) },
                                       uniquingKeysWith: { first, _ in first })
            for key in order {
                guard let g = groups[key],
                      let item = itemByIdx[g.firstIdx],
                      let bb = item.bounds else { continue }
                let cx = (bb.min.x + bb.max.x) / 2
                let cy = (bb.min.y + bb.max.y) / 2
                let target = SIMD2(cx * p.scale + p.translate.x, cy * p.scale + p.translate.y)
                let balloon = SIMD2(target.x, target.y + 12)   // 12 mm clear of the part, sheet space
                drawBalloon(into: writer, number: g.item.number, centre: balloon, target: target, radius: 4)
            }
        }

        // BOM table in the top-right of the sheet, above the title block.
        sheet.renderBOM(BillOfMaterials(items: bomItems, title: "PARTS LIST"), into: writer)

        return DrawingComposerResult(writer: writer,
                                     scaleLabel: scaleLabel,
                                     viewCount: combined.count,
                                     sectionCount: 0,
                                     detailCount: 0,
                                     componentCount: components.count,
                                     partsList: bomItems)
    }

    /// Compose a general-arrangement drawing from an XCAF assembly `document`,
    /// flattening it to its positioned leaf parts. Leaf names drive the parts
    /// list; identical names merge into one BOM row with summed quantity.
    public static func render(spec: DrawingSpec, document: Document) throws -> DrawingComposerResult {
        var components: [DrawingComponent] = []
        var unnamed = 0

        func walk(_ nodes: [AssemblyNode]) {
            for node in nodes {
                // `node.shape` is the geometry with its location applied; it is
                // nil for pure-assembly nodes (matches Document.shapesWithColors).
                if let shape = node.shape {
                    let name: String
                    if let n = node.name, !n.isEmpty {
                        name = n
                    } else {
                        unnamed += 1
                        name = "PART \(unnamed)"
                    }
                    components.append(DrawingComponent(shape: shape, name: name))
                }
                walk(node.children)
            }
        }
        walk(document.rootNodes)

        guard !components.isEmpty else {
            throw DrawingComposerError.shapeBuildFailed("assembly document has no leaf geometry to draw")
        }
        return try render(spec: spec, components: components)
    }

    // MARK: - Helpers

    static func applyAutoCenterAnnotations(perView: [String: [(idx: Int, item: ViewItem)]],
                                           positioned: [Shape],
                                           spec: DrawingSpec) {
        let wantCentrelines = (spec.centerlines ?? .auto) == .auto
        let wantCentermarks: Bool = {
            if case .auto = (spec.centermarks ?? .auto) { return true }
            return false
        }()
        guard wantCentrelines || wantCentermarks else { return }
        for comps in perView.values {
            for (idx, item) in comps {
                let shape = positioned[idx]
                if wantCentrelines {
                    _ = item.drawing.addAutoCentrelines(from: shape,
                                                        viewDirection: item.direction,
                                                        overshoot: 5,
                                                        tolerance: 1e-6,
                                                        bounds: item.bounds)
                }
                if wantCentermarks {
                    _ = item.drawing.addAutoCentermarks(from: shape,
                                                        viewDirection: item.direction,
                                                        extent: 8,
                                                        minRadius: 0,
                                                        bounds: item.bounds)
                }
            }
        }
    }

    static func unionBounds(_ bs: [(min: SIMD2<Double>, max: SIMD2<Double>)])
        -> (min: SIMD2<Double>, max: SIMD2<Double>)? {
        guard var lo = bs.first?.min, var hi = bs.first?.max else { return nil }
        for b in bs.dropFirst() {
            lo = simd_min(lo, b.min)
            hi = simd_max(hi, b.max)
        }
        return (lo, hi)
    }

    /// Draw a constant-size (sheet-space) balloon: numbered circle + leader to
    /// the part. Mirrors the upstream `DrawingAnnotation.balloon` rendering but
    /// in sheet coordinates so the balloon doesn't scale with the drawing.
    static func drawBalloon(into writer: DXFWriter,
                            number: Int,
                            centre: SIMD2<Double>,
                            target: SIMD2<Double>,
                            radius: Double) {
        writer.addCircle(centre: centre, radius: radius, layer: "DIMENSION")
        writer.addText(String(number),
                       at: SIMD2(centre.x - radius * 0.4, centre.y - radius * 0.5),
                       height: radius * 0.9, layer: "TEXT")
        let dir = target - centre
        let len = simd_length(dir)
        if len > 1e-9 {
            let exit = centre + (dir / len) * radius
            writer.addLine(from: exit, to: target, layer: "DIMENSION")
        }
    }
}
