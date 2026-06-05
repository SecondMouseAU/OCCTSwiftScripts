# 02 — Helical compression spring

A constant-pitch, round-wire compression spring built by sweeping a circular section
along a helical path. The canonical "sweep a profile along a 3D curve" recipe.

![Helical compression spring](output.png)

## Parameters

| Name          | Default | Description                              | Valid range          |
|---------------|---------|------------------------------------------|----------------------|
| `wireDia`     | `4`     | Round-wire diameter (mm)                 | `> 0`, `< outsideDia`|
| `outsideDia`  | `40`    | Coil outside diameter (mm)               | `> wireDia`          |
| `pitch`       | `12`    | Axial distance between coils (mm)        | `> wireDia`          |
| `activeCoils` | `6`     | Number of active turns                   | `> 0`                |

Mean coil radius is derived: `meanRadius = (outsideDia − wireDia) / 2`.

## Algorithm

The coil centre-line is a helix about Z (`Wire.helix`). The wire cross-section is a
circle placed at the helix start point `(meanRadius, 0, 0)` and oriented perpendicular to
the start tangent `(0, R, pitch/2π)`. The section is then swept along the helix with
`Shape.sweep` (which wraps `BRepOffsetAPI_MakePipe`). To get a solid with outward-facing
normals (positive volume), the section's normal is pointed *against* the tangent — sweeping
along `+tangent` produces a geometrically correct but reverse-oriented solid.

## OCCTSwift APIs used

- `Wire.helix(radius:pitch:turns:)` — the coil centre-line
- `Wire.circle(origin:normal:radius:)` — the wire cross-section
- `Shape.sweep(profile:along:)` — pipe-sweep the section along the helix
- `Shape.volume` — sanity print

## Gotchas

- The section circle **must** sit on the spine start and face along the tangent, or the
  pipe sweep fails. Don't leave it at the origin.
- Sweep orientation matters: building along `+tangent` yields a negative-volume (reversed)
  solid. Flip the section normal — as done here — for a correctly-oriented body. (Filed
  upstream as a request for an orientation-normalising sweep / `Shape.reversed()` helper.)
- Ground/closed/squared ends are **out of scope** — this is an open-coil spring. Closed
  ends need either a variable-pitch helix or an end-grinding boolean.
- `Wire.helix` uses `turns:` (a coil count), **not** a `height:`. Free length ≈ `pitch ·
  activeCoils`.
