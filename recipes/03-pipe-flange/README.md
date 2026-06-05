# 03 — Pipe flange

A raised-face pipe flange with a bolt circle, built by revolving a half-section and
patterning a single bolt hole around the axis. Shows revolve + circular pattern + chamfer.

![Pipe flange](output.png)

## Parameters

| Name               | Default | Description                          | Valid range                |
|--------------------|---------|--------------------------------------|----------------------------|
| `boreRadius`       | `25`    | Through-bore radius (mm)             | `> 0`, `< raisedRadius`    |
| `outerRadius`      | `75`    | Flange outer radius (mm)             | `> raisedRadius`           |
| `thickness`        | `15`    | Flange disk thickness (mm)           | `> 0`                      |
| `raisedRadius`     | `50`    | Raised-face outer radius (mm)        | `boreRadius … outerRadius` |
| `raisedHeight`     | `2`     | Raised-face height above disk (mm)   | `> 0`                      |
| `boltCircleRadius` | `60`    | Bolt-circle radius (mm)              | `raisedRadius … outerRadius` |
| `boltCount`        | `8`     | Number of bolt holes                 | `≥ 2`                      |
| `boltRadius`       | `7`     | Bolt-hole radius (mm)                | `> 0`, holes don't overlap |

## Algorithm

The flange is a surface of revolution. Its half-section is drawn in the XY plane as a
closed polygon of `(radius, axial)` pairs — bore wall, back face, OD, disk front, the
raised-face step, and back to the bore — with every radius `≥ boreRadius` so the profile
never crosses the axis. It is revolved a full turn about the **Y axis** (the bore axis).
The bolt holes are then drilled one-by-one at evenly-spaced angles around the bolt circle
(in the XZ plane, since the axis is Y). Finally a small all-edge chamfer breaks the sharp
corners; it falls back to the un-chamfered body if the blend fails.

## OCCTSwift APIs used

- `Wire.polygon(_:closed:)` — the `(radius, axial)` half-section
- `Shape.revolve(profile:axisOrigin:axisDirection:angle:)` — surface of revolution
- `Shape.drilled(at:direction:radius:depth:)` — the bolt holes (one per angle)
- `Shape.chamfered(distance:)` — edge break (optional)

## Gotchas

- The revolve axis is **Y**, so the half-section uses `x` for radius and `y` for axial
  position. Revolving an XY profile about Z would sweep a flat disk, not a solid.
- Keep every profile radius `≥ boreRadius`: a profile that touches or crosses the axis
  produces a degenerate or self-intersecting revolution.
- `chamfered(distance:)` blends **all** edges. On a flange with many bolt-hole edges this
  can be slow or fail; the recipe guards it with `?? flange` so the body still emits.
- **`Shape.circularPattern` patterns the whole *body*, not a feature.** Using it here would
  produce 8 overlapping copies of the entire flange (≈8× the volume), not 8 holes — so the
  recipe drills each hole in a loop instead. A feature-level circular pattern (pattern a
  hole/pocket around an axis) is filed as an OCCTSwift ergonomic-gap request.
