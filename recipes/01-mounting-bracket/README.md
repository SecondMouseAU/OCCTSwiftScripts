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

The L cross-section is built as a closed polygon in the XY plane and extruded along Z into
a prism. The inside corner is then rounded by filleting the solid's **concave edge**,
located geometrically with `Shape.concaveEdges()` — no fragile edge-index bookkeeping, and
it tracks the corner as parameters change. The fillet is applied *before* drilling so
`concaveEdges()` returns only the reentrant corner. Finally four holes are cut: two through
the base leg (drilled along Y) and two through the upright leg (drilled along X). Each drill
starts 1 mm outside the entry face and over-runs the exit by 1 mm so the resulting cut faces
are clean and coincident-face artifacts are avoided.

## OCCTSwift APIs used

- `Wire.polygon(_:closed:)` — L-shaped cross-section
- `Shape.extrude(profile:direction:length:)` — profile → prism
- `Shape.concaveEdges()` — find the reentrant inside-corner edge (OCCTSwift v1.3.1)
- `Shape.filleted(edges:radius:)` — round that edge
- `Shape.drilled(at:direction:radius:depth:)` — the four through-holes
- `Shape.volume` — sanity print

## Gotchas

- Fillet **before** drilling: `concaveEdges()` classifies *every* concave edge, and a
  drilled hole's rim can read as concave. Filleting first keeps the selection to just the
  inside corner. (Tighten `concaveEdges(angle:)` if a near-flat junction sneaks in.)
- Drill start points sit *outside* the part and `depth` over-runs the thickness so the
  hole punches fully through; drilling exactly on a face can leave a sliver.
- The bracket is a single solid emitted as `body-0` (the reference `output.brep`).
