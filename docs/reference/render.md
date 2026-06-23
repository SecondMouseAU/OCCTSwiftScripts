---
title: Render
parent: CLI & API Reference
nav_order: 10
---

# Render

Headless PNG rendering of one or more BREPs with configurable camera, display mode, background, and AIS overlays (axes, workplane, sub-shape highlights).

## Entries

[`render-preview`](#render-preview)

---

## `render-preview`

Render a headless PNG preview of one or more BREPs with camera presets, display modes, and AIS scene overlays.

**Input** — flag-form or JSON-form (stdin or argv path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<inputs>` / `inputs` | string[] | yes | One or more BREP paths; or a `--manifest` path (directory with `manifest.json`). |
| `--output` / `outputPath` | string | yes | Write path for the PNG file. |
| `--camera` / `camera` | enum | no | Camera preset: `iso` \| `front` \| `back` \| `top` \| `bottom` \| `left` \| `right`. Default: `iso`. |
| `--camera-position` / `cameraPosition` | float[3] | no | Explicit camera eye position `x,y,z`. Overrides preset. |
| `--camera-target` / `cameraTarget` | float[3] | no | Explicit look-at point `x,y,z`. Required if `--camera-position` is given. |
| `--camera-up` / `cameraUp` | float[3] | no | Camera up vector `x,y,z`. Default: `0,0,1`. |
| `--width` / `width` | integer | no | Output image width in pixels. Default: 800. |
| `--height` / `height` | integer | no | Output image height in pixels. Default: 600. |
| `--display-mode` / `displayMode` | enum | no | Rendering style: `shaded` \| `wireframe` \| `shaded-with-edges` \| `flat` \| `xray` \| `rendered`. Default: `shaded`. |
| `--background` / `background` | string | no | Background color: `light` \| `dark` \| `transparent` \| `#rrggbb` \| `#rrggbbaa`. Default: `light`. |
| `--show-axes` / `showAxes` | boolean | no | Overlay an AIS Trihedron (X/Y/Z axes). Default: false. |
| `--axes-position` / `axesPosition` | string | no | Trihedron anchor: `origin` \| `center` \| `outside` \| `x,y,z`. Default: `outside` (20% of bbox diagonal beyond bbox-min, keeps arrows visible). |
| `--show-workplane` / `showWorkplane` | enum | no | Overlay a construction plane: `xy` \| `yz` \| `xz`. |
| `--highlight` / `highlight` | string[] | no | Extract and highlight sub-shapes from the **first** input BREP: `face[N],edge[M],vertex[K]` (comma-separated). |
| `--highlight-color` / `highlightColor` | string | no | Sub-shape highlight color: `#rrggbb` \| `#rrggbbaa`. Default: `#ffa500` (orange). |

**Returns** — JSON envelope with the output PNG path and rendered image dimensions: `{ "outputPath": "...", "width": N, "height": N, "mimeType": "image/png" }`. Fails if the input BREP is invalid, Metal device is unavailable, or a highlighted sub-shape (face/edge/vertex) is not found on the source (warning to stderr, continues).

**Example**

```bash
occtkit render-preview part.brep --output /tmp/part.png --camera iso --display-mode shaded-with-edges --width 1200 --height 900 --show-axes --axes-position outside
```

```json
{
  "outputPath": "/tmp/part.png",
  "width": 1200,
  "height": 900,
  "mimeType": "image/png"
}
```

**Drives** — `OCCTSwiftViewport` `OffscreenRenderer` (camera presets, display modes, background); `OCCTSwiftTools` `CADFileLoader.shapeToBodyAndMetadata` (Shape → `ViewportBody` conversion); `OCCTSwiftAIS` `Trihedron` / `WorkPlane` (scene overlays); `Shape.subShape(type:index:)` (sub-shape extraction for `--highlight`).

**Notes** — `--highlight` extracts sub-shapes from the first input only (render multi-BREP scenes solo if highlighting in a specific body). Sub-shape IDs (`face[N]`, `edge[M]`, `vertex[K]`) match those emitted by `query-topology` for cross-reference. `--annotate-dimensions` (dimension overlays) is not yet implemented — filed upstream as `OCCTSwiftViewport#26`; the annotation path is reserved.
