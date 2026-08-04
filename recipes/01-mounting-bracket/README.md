# 01: Mounting bracket

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
a prism. The reentrant vertex at `(thickness, thickness)` extrudes to exactly one concave
edge: a straight line parallel to the extrusion axis. That is the edge this recipe fillets,
adding a rounded blend that fills part of the sharp inside corner. It is selected
**geometrically**, with `Shape.edges(where:)`, not with `Shape.concaveEdges()`: on this
shape that call returns a different pair of edges (see Gotchas), so the selector checks
directly for a line edge parallel to Z sitting at `(thickness, thickness)`. This tracks the
corner as parameters change without a fragile edge index. The fillet is applied *before*
drilling so the selector only ever sees the corner edge, not a drilled hole's rim. Finally
four holes are cut: two through the base leg (drilled along Y) and two through the upright
leg (drilled along X). Each drill starts 1 mm outside the entry face and over-runs the exit
by 1 mm so the resulting cut faces are clean and coincident-face artifacts are avoided.

## OCCTSwift APIs used

- `Wire.polygon(_:closed:)`: L-shaped cross-section
- `Shape.extrude(profile:direction:length:)`: profile → prism
- `Shape.edges(where:)`: select the inside-corner edge geometrically (OCCTSwift v1.2.1)
- `Shape.filleted(edges:radius:)`: round that edge
- `Shape.drilled(at:direction:radius:depth:)`: the four through-holes
- `Shape.volume`: sanity print, and the check that the fillet actually ran

## Gotchas

- **`Shape.concaveEdges()` picks the wrong edges on this shape.** It returns two edges
  instead of one: the top-cap boundary segments at `z = width` where each wall meets the
  end face (each running the leg length, not the extrusion width), rather than the true
  reentrant edge. Those two are bounded by the 5 mm leg thickness, so a fillet on them fails
  above roughly that radius; that mismatch is what let `filletRadius = 8` silently no-op
  behind a `?? prism` fallback for as long as this recipe used `concaveEdges()`
  (OCCTSwiftScripts #105). The true inside-corner edge has no such limit (its bound is
  `legLength − thickness`, 45 mm here), which is why the same `filletRadius = 8` works fine
  once the correct edge is selected.
- **A concave fillet adds material, it does not remove it.** Rounding the inside corner
  fills part of the sharp reentrant point with a blend, so `bracket.volume` after the
  fillet is *larger* than the prism's, by `filletRadius² · (1 − π/4) · width`. Do not expect
  a volume decrease as evidence the fillet ran; check the increase against that formula
  instead.
- Fillet **before** drilling: a drilled hole's rim sitting near the corner could otherwise
  confuse a looser selector. Filleting first keeps the selection to just the inside corner.
- Drill start points sit *outside* the part and `depth` over-runs the thickness so the
  hole punches fully through; drilling exactly on a face can leave a sliver.
- The bracket is a single solid emitted as `body-0` (the reference `output.brep`).
