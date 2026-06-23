---
title: Drawings & export
parent: CLI & API Reference
nav_order: 3
---

# Drawings & export

Project and export BREP geometry to DXF R12 drawings. The `dxf-export` verb performs hidden-line-removed orthographic projection along a view direction; `drawing-export` composes a complete ISO 128-30 multi-view technical drawing with title block, sections, dimensions, and GD&T annotations.

## Entries

[`dxf-export`](#dxf-export) · [`drawing-export`](#drawing-export)

---

## `dxf-export`

Project a shape along a view direction and write DXF R12.

**Input** — flag-form only (`positional input.brep output.dxf [--view x,y,z] [--deflection D]`).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `--view` | `x,y,z` | no | View direction for orthographic projection (default `0,0,1` = top-down along +Z) |
| `--deflection` | double | no | Tessellation deflection for wire/edge rendering (default `0.1` mm) |

**Returns** — A JSON envelope with `output` (file path), `view` (the direction used as `[x, y, z]`), and `deflection`. The DXF R12 file is written using hidden-line-removed projection.

**Example**

```bash
occtkit dxf-export bracket.brep bracket.dxf --view 0,0,1 --deflection 0.05
```

```json
{
  "output": "bracket.dxf",
  "view": [0, 0, 1],
  "deflection": 0.05
}
```

**Drives** — `OCCTSwift.Exporter.writeDXF(shape:to:viewDirection:deflection:)` (v0.138+).

**Notes** — Wraps hidden-line-removed projection; useful for single orthogonal views or quick exports. For multi-view technical drawings with sections and annotations, use `drawing-export`.

---

## `drawing-export`

Compose a complete ISO 128-30 multi-view technical drawing with border, title block, projection symbol, sections, dimensions, and GD&T annotations. Output is DXF R12.

**Input** — JSON spec on stdin or file path argument. The spec has optional `shape` (path to input BREP, required by CLI but omitted by in-process callers) and `output` (required by CLI; in-process callers return a `DrawingComposerResult` instead). All other fields drive the drawing layout and annotation.

**Parameters** — See [DrawingSpec schema](https://github.com/gsdali/OCCTSwiftScripts/blob/main/Sources/DrawingComposer/Spec.swift) for full field definitions. Key top-level fields:

| name | type | required | description |
|------|------|:--------:|-------------|
| `shape` | string | yes (CLI) | Path to input BREP file |
| `output` | string | yes (CLI) | Path for output DXF R12 file |
| `sheet` | object | yes | Paper size, orientation (`landscape`\|`portrait`), projection angle (`first`\|`third`), scale (`"auto"` or `"N:D"`), border toggle, projection-symbol toggle |
| `title` | object | no | Title-block metadata: `title`, `drawingNumber`, `owner`, `creator`, `approver`, `documentType`, `dateOfIssue`, `revision`, `sheetNumber`, `language`, `material`, `weight` |
| `views` | array | yes | List of orthographic views, each with `name` and optional custom `direction` (default ISO standard directions) |
| `sections` | array | no | Cross-section views, each specifying `name`, `plane` (origin + normal), and optional `hatchAngle`, `hatchSpacing`, `viewDirection` |
| `centerlines` | enum | no | `"auto"` (default) or `"none"` — auto-generate revolution axes |
| `centermarks` | mixed | no | `"auto"`, `"none"`, or an explicit array of `{view, x, y, extent?}` for circular features |
| `cosmeticThreads` | array | no | ISO 6410 thread overlays: `{view, axisStart, axisEnd, majorDiameter, pitch, callout?}` |
| `surfaceFinish` | array | no | ISO 1302 surface-finish symbols: `{view, position, leaderTo, ra, symbol?, method?}` |
| `gdt` | array | no | ISO 1101 GD&T feature-control frames: `{view, position, symbol, tolerance, datums?, leaderTo?}` |
| `detailViews` | array | no | Zoomed close-ups: `{name, fromView, centre, radius, scale, placement?}` |
| `dimensions` | array | no | Explicit dimensions: `{view, type, from?, to?, offset?, ...}` per `DimensionKind` (`linear`\|`radial`\|`diameter`\|`angular`) |
| `deflection` | double | no | Tessellation deflection (default `0.1` mm) |

**Returns** — A JSON envelope with `output` (DXF path), `sheet` (paper size + orientation), `projection` (first- or third-angle), `scale` (readable label), `viewCount`, `sectionCount`, `detailCount`. The DXF R12 file contains the complete drawing: ISO 5457 border, ISO 7200 title block, ISO 5456-2 projection symbol (if enabled), HLR orthographic views, auto-hatched sections, cutting-plane lines, auto-centerlines, auto-centermarks, cosmetic threads, surface-finish symbols, GD&T frames, and detail callouts.

**Example**

```bash
cat > drawing.json <<'EOF'
{
  "shape": "shaft.brep",
  "output": "shaft_drawing.dxf",
  "sheet": {
    "size": "a3",
    "orientation": "landscape",
    "projection": "third",
    "scale": "1:2"
  },
  "title": {
    "title": "Drive Shaft Assembly",
    "drawingNumber": "DRV-001-A",
    "material": "Steel 1045",
    "revision": "1"
  },
  "views": [
    {"name": "front"},
    {"name": "top"},
    {"name": "right"}
  ],
  "centerlines": "auto",
  "centermarks": "auto"
}
EOF

drawing-export drawing.json
```

```json
{
  "output": "shaft_drawing.dxf",
  "sheet": "A3 landscape",
  "projection": "third",
  "scale": "1:2",
  "viewCount": 3,
  "sectionCount": 0,
  "detailCount": 0
}
```

**Drives** — `DrawingComposer.Composer.render(spec:shape:)` and downstream OCCTSwift ISO primitives: `Sheet.render` (border + title block + projection symbol), `Drawing.project` (per-view HLR), `Drawing.transformed` + `Drawing.bounds` (layout and autoscale), `Shape.section2DView` (hatched sections), `Drawing.addCuttingPlaneLine`, `Drawing.addAutoCentrelines` / `addAutoCentermarks` (ISO 128-40), `DrawingAnnotation.cosmeticThreadSide` (ISO 6410), `.surfaceFinish` (ISO 1302), `.featureControlFrame` (ISO 1101), `Drawing.detailView`, and `DrawingScale.preferred` (ISO 5455 standard scales).

**Notes** — In-process callers (`import DrawingComposer`) call `Composer.render(spec:shape:)` directly; the CLI wrapper exists only to serve JSON-driven consumers (OCCTMCP, Python pipelines). The spec's `shape` and `output` fields are only used by the CLI. Section hatching angle and spacing default to π/4 radians (45°) and 3 mm. The ISO projection symbol is drawn only when `sheet.projectionSymbol` is `true` (omitted or `null` defaults to `true` for A1–A4; A0 defaults to `false`). For sub-entity highlighting or enrichment (e.g. face plane keys for coplanar relationships), use the in-process API with a custom `ShapeEnricher`; the CLI surface does not expose that hook.

