# 03: Pipe flange

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
closed polygon of `(radius, axial)` pairs, bore wall, back face, OD, disk front, the
raised-face step, and back to the bore, with every radius `≥ boreRadius` so the profile
never crosses the axis. The section is faced with `Shape.face(from:)`, and the **face**
(not the wire) is revolved a full turn about the **Y axis** (the bore axis), which is
what closes the result into a solid rather than a shell (see Gotchas). The bolt circle
is cut with `Shape.circularPatternCut`: a single cylindrical hole tool is built at the
bolt-circle radius (oriented along Y), then patterned `boltCount` times around the axis
and subtracted as one compound. Finally a small all-edge chamfer breaks the sharp
corners; it falls back to the un-chamfered body if the blend fails.

## OCCTSwift APIs used

- `Wire.polygon(_:closed:)`: the `(radius, axial)` half-section
- `Shape.face(from:)`: face the half-section before revolving
- `Shape.revolved(axisOrigin:axisDirection:)`: surface of revolution (on the faced section)
- `Shape.cylinder(at:direction:radius:height:)`: the bolt-hole tool
- `Shape.circularPatternCut(tool:axisPoint:axisDirection:count:angle:)`: the bolt circle (OCCTSwift v1.3.1)
- `Shape.chamfered(distance:)`: edge break (optional)

## Gotchas

- **Face the wire before revolving it.** `Shape.revolve(profile: wire, ...)` revolves
  the curve itself and returns a **shell**, not a solid, this is standard
  `BRepPrimAPI_MakeRevol` behaviour on a wire, not an OCCTSwift bug (OCCTSwiftScripts
  #100). `Shape.face(from: wire)` followed by `face.revolved(...)` gives a solid with
  the same volume. `Shape.extrude(profile: wire, ...)` faces the wire for you and so does
  not have this trap, `Shape.revolve(profile: wire, ...)` does; the two aren't symmetric.
- The revolve axis is **Y**, so the half-section uses `x` for radius and `y` for axial
  position. Revolving an XY profile about Z would sweep a flat disk, not a solid.
- Keep every profile radius `≥ boreRadius`: a profile that touches or crosses the axis
  produces a degenerate or self-intersecting revolution.
- `chamfered(distance:)` blends **all** edges. On a flange with many bolt-hole edges this
  can be slow or fail; the recipe guards it with `?? flange` so the body still emits.
- Use `circularPatternCut`, **not** `circularPattern`, for the bolt circle. `circularPattern`
  patterns the whole *body*, applied to a holed flange it produces overlapping flange copies
  (≈8× the volume) with the holes filled in. `circularPatternCut` patterns the *tool* and
  subtracts it, which is the feature-level behaviour you want here.
