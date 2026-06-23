---
title: DrawingComposer API
nav_order: 3
parent: Reference
---

# `DrawingComposer` library reference

`DrawingComposer` turns a `DrawingSpec` + a live `Shape` into a fully populated
`DXFWriter` (a complete multi-view ISO technical drawing). It is the in-process library
behind the `occtkit drawing-export` verb — for iOS apps and library consumers that can't
subprocess. The CLI and the library run the **same** composition logic; the CLI only adds
the BREP load and the DXF write.

```swift
.product(name: "DrawingComposer", package: "OCCTSwiftScripts"),
```

Source: [`Sources/DrawingComposer/`](https://github.com/SecondMouseAU/OCCTSwiftScripts/tree/main/Sources/DrawingComposer).

---

## `Composer.render`

```swift
public enum Composer {
    /// Single-part multi-view drawing.
    public static func render(spec: DrawingSpec, shape: Shape) throws -> DrawingComposerResult

    /// General-arrangement (assembly) drawing from explicit components.
    public static func render(spec: DrawingSpec,
                              components: [DrawingComponent]) throws -> DrawingComposerResult

    /// General-arrangement drawing from an XCAF assembly document
    /// (flattened to positioned leaf parts; leaf names drive the parts list).
    public static func render(spec: DrawingSpec, document: Document) throws -> DrawingComposerResult
}
```

The caller writes the result with `try result.writer.write(to: url)`.

### Single-part example

```swift
import OCCTSwift
import DrawingComposer

let shape = try Shape.loadBREP(fromPath: "part.brep")

let spec = DrawingSpec(
    sheet: SheetSpec(size: .a3, orientation: .landscape, projection: .third, scale: .auto),
    title: TitleBlockSpec(title: "Bracket", drawingNumber: "DRW-001",
                          material: "AlMg3", revision: "A"),
    views: [ViewSpec(name: "front"), ViewSpec(name: "top"), ViewSpec(name: "right")],
    dimensions: [
        DimensionSpec(view: "front", type: .linear, from: [0, 0], to: [40, 0],
                      offset: 10, label: "40")
    ]
)

let result = try Composer.render(spec: spec, shape: shape)
try result.writer.write(to: URL(fileURLWithPath: "bracket.dxf"))
print(result.scaleLabel, result.viewCount, result.sectionCount, result.detailCount)
```

<!-- drawing-export TODO: embed bracket.dxf rendered to PNG -->

### Assembly (general-arrangement) example

```swift
let result = try Composer.render(spec: spec, components: [
    Composer.DrawingComponent(shape: housing, name: "Housing", partNumber: "P-001", material: "Cast iron"),
    Composer.DrawingComponent(shape: shaft,   name: "Shaft",   partNumber: "P-002", material: "Steel",
                              transform: [1,0,0,20, 0,1,0,0, 0,0,1,0])   // row-major 3×4 placement
])
try result.writer.write(to: URL(fileURLWithPath: "ga.dxf"))
// → numbered balloons on the front view + a merged PARTS LIST (qty summed per partNumber/name)
```

---

## `DrawingComposerResult`

```swift
public struct DrawingComposerResult: Sendable {
    public let writer: DXFWriter
    public let scaleLabel: String           // e.g. "1:2" (ISO 5455 snapped when scale == .auto)
    public let viewCount: Int
    public let sectionCount: Int
    public let detailCount: Int
    public let componentCount: Int          // 1 for single-shape; N for general-arrangement
    public let partsList: [BillOfMaterials.Item]   // empty for single-shape
}
```

---

## `DrawingSpec` schema

`DrawingSpec` is `Codable` — the same JSON the `drawing-export` verb reads. Source:
[`Spec.swift`](https://github.com/SecondMouseAU/OCCTSwiftScripts/blob/main/Sources/DrawingComposer/Spec.swift).

```swift
public struct DrawingSpec: Codable, Sendable {
    public var shape: String?              // path to BREP — CLI only (ignored by render(spec:shape:))
    public var output: String?             // path for output DXF — CLI only
    public var sheet: SheetSpec
    public var title: TitleBlockSpec?      // omitted → no title block
    public var views: [ViewSpec]           // typically 3 orthographic views
    public var sections: [SectionSpec]?
    public var centerlines: AutoToggle?    // .auto | .none (default .auto)
    public var centermarks: CentermarkRequest?   // "auto" | "none" | [explicit]
    public var cosmeticThreads: [CosmeticThreadSpec]?   // ISO 6410
    public var surfaceFinish: [SurfaceFinishSpec]?      // ISO 1302
    public var gdt: [GDTSpec]?             // ISO 1101 feature control frames
    public var detailViews: [DetailViewSpec]?
    public var dimensions: [DimensionSpec]?
    public var deflection: Double?         // tessellation deflection (default 0.1)
}
```

### Sheet

```swift
public struct SheetSpec: Codable, Sendable {
    public var size: PaperSizeName          // a0 | a1 | a2 | a3 | a4
    public var orientation: OrientationName // landscape | portrait
    public var projection: ProjectionAngleName  // first | third
    public var scale: ScaleSpec             // "auto" or "n:d" (e.g. "1:2")
    public var border: Bool?
    public var projectionSymbol: Bool?
}
```

`ScaleSpec` decodes from a string: `"auto"` (ISO 5455 snapped to fit) or `"n:d"`.

### Title block (ISO 7200)

```swift
public struct TitleBlockSpec: Codable, Sendable {
    public var title: String
    public var drawingNumber, owner, creator, approver, documentType: String?
    public var dateOfIssue, revision, sheetNumber, language, material, weight: String?
}
```

### Views, sections, details

```swift
public struct ViewSpec: Codable, Sendable {
    public var name: String                 // "front" | "top" | "right" | ... (drives layout)
    public var direction: [Double]?         // optional explicit projection direction
}

public struct SectionSpec: Codable, Sendable {
    public var name: String
    public var plane: PlaneSpec             // { origin: [x,y,z], normal: [x,y,z] }
    public var labelOnView: String?         // parent view to draw the cutting-plane line on
    public var viewDirection: [Double]?
    public var hatchAngle: Double?          // radians, default π/4
    public var hatchSpacing: Double?        // mm, default 3
}

public struct DetailViewSpec: Codable, Sendable {
    public var name: String
    public var fromView: String
    public var centre: [Double]             // [x,y] in parent view space
    public var radius: Double
    public var scale: Double
    public var placement: [Double]?         // [x,y] on the sheet
}
```

### Annotations

```swift
public enum CentermarkRequest { case auto, off, explicit([CentermarkSpec]) }   // JSON: "auto"|"none"|[...]

public struct CosmeticThreadSpec: Codable, Sendable {   // ISO 6410
    public var view: String
    public var axisStart, axisEnd: [Double]   // [x,y]
    public var majorDiameter, pitch: Double
    public var callout: String?
}

public struct SurfaceFinishSpec: Codable, Sendable {    // ISO 1302
    public var view: String
    public var position, leaderTo: [Double]   // [x,y]
    public var ra: Double
    public var symbol: String?   // any | machiningRequired | machiningProhibited
    public var method: String?
}

public struct GDTSpec: Codable, Sendable {              // ISO 1101
    public var view: String
    public var position: [Double]             // [x,y]
    public var symbol: String                 // perpendicularity | flatness | …
    public var tolerance: String
    public var datums: [String]?
    public var leaderTo: [Double]?
}
```

### Dimensions

```swift
public struct DimensionSpec: Codable, Sendable {
    public var view: String
    public var type: DimensionKind            // linear | radial | diameter | angular
    // linear:   from, to ([x,y]); offset?
    // radial/diameter: centre ([x,y]), radius; leaderAngle?
    // angular:  vertex, ray1, ray2 ([x,y]); arcRadius?
    public var from, to, centre, vertex, ray1, ray2: [Double]?
    public var offset, radius, leaderAngle, arcRadius: Double?
    public var label: String?
}
```

---

## Full JSON spec example (for `drawing-export`)

```json
{
  "shape": "part.brep",
  "output": "sheet.dxf",
  "sheet": { "size": "a3", "orientation": "landscape", "projection": "third", "scale": "auto" },
  "title": { "title": "Bracket", "drawingNumber": "DRW-001", "material": "AlMg3", "revision": "A" },
  "views": [ { "name": "front" }, { "name": "top" }, { "name": "right" } ],
  "sections": [
    { "name": "A-A", "plane": { "origin": [0,0,0], "normal": [0,1,0] }, "labelOnView": "front" }
  ],
  "dimensions": [
    { "view": "front", "type": "linear", "from": [0,0], "to": [40,0], "offset": 10, "label": "40" }
  ]
}
```

```bash
echo '{ ... spec above ... }' | drawing-export
# or
drawing-export spec.json
```

<!-- drawing-export TODO: embed sheet.dxf rendered to PNG -->
