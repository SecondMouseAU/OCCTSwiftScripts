# 01 — Mounting bracket

An L-shaped mounting bracket with a rounded inside corner and four through-holes
(two per leg). A good first look at sketch → extrude → drill.

![Mounting bracket](output.png)

## Parameters

| Name           | Default | Description                                   | Valid range        |
|----------------|---------|-----------------------------------------------|--------------------|
| `legLength`    | `50`    | Length of each leg from the heel (mm)         | `> 2·thickness`    |
| `thickness`    | `5`     | Material thickness of each leg (mm)           | `> 0`              |
| `width`        | `40`    | Bracket width / extrusion depth (mm)          | `> 0`              |
| `filletRadius` | `8`     | Inside-corner radius (mm)                     | `0 … legLength−thickness` |
| `holeRadius`   | `3.5`   | Mounting-hole radius (mm)                     | `> 0`, fits in leg |

## Algorithm

The L cross-section is built as a closed polygon in the XY plane. The single concave
vertex (the inside corner) is rounded **on the wire** with `Wire.filleted2D` before any
3D work — this is far more robust than picking the corresponding edge on the solid by
index after extrusion. The rounded profile is extruded along Z into a prism, then four
holes are cut: two through the base leg (drilled along Y) and two through the upright leg
(drilled along X). Each drill starts 1 mm outside the entry face and over-runs the exit
by 1 mm so the resulting cut faces are clean and coincident-face artifacts are avoided.

## OCCTSwift APIs used

- `Wire.polygon(_:closed:)` — L-shaped cross-section
- `Wire.filleted2D(vertexIndex:radius:)` — round the inside corner on the 2D profile
- `Shape.extrude(profile:direction:length:)` — profile → prism
- `Shape.drilled(at:direction:radius:depth:)` — the four through-holes
- `Shape.volume` — sanity print

## Gotchas

- `Wire.filleted2D` takes a **vertex index** into the polygon point list; if you reorder
  the points, update the index (the inside corner is index `3` here).
- Drill start points sit *outside* the part and `depth` over-runs the thickness so the
  hole punches fully through; drilling exactly on a face can leave a sliver.
- The bracket is a single solid emitted as `body-0` (the reference `output.brep`).
