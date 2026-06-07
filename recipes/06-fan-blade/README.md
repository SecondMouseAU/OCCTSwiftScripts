# 06 — Twisted fan blade

A single tapered, twisted fan/propeller blade lofted through NACA airfoil sections and fused
to a hub boss. The canonical "loft through changing cross-sections" recipe.

![Twisted fan blade](output.png)

## Parameters

| Name           | Default | Description                                   | Valid range        |
|----------------|---------|-----------------------------------------------|--------------------|
| `span`         | `60`    | Blade length along Z (mm)                      | `> 0`              |
| `rootChord`    | `30`    | Chord at the root (mm)                         | `> 0`              |
| `taper`        | `0.45`  | Tip chord = `rootChord·(1−taper)`             | `0 … 0.9`          |
| `thickness`    | `0.12`  | Airfoil max thickness as a fraction of chord  | `0.05 … 0.2`       |
| `twistRootDeg` | `32`    | Section twist at the root (degrees)           | any                |
| `twistTipDeg`  | `8`     | Section twist at the tip (degrees)            | any                |
| `sections`     | `6`     | Number of lofted sections                     | `≥ 2`              |
| `stations`     | `12`    | Chordwise sample points per surface           | `≥ 6`              |

## Algorithm

A symmetric NACA airfoil is generated once in chord-normalised coordinates: the half-thickness
`yt(x) = 5·t·(0.2969√x − 0.1260x − 0.3516x² + 0.2843x³ − 0.1015x⁴)`, sampled with cosine
spacing (points cluster at the leading edge). The closed loop runs upper surface LE→TE then
lower surface TE→LE. For each spanwise section this base airfoil is scaled by the (tapering)
chord, rotated in its own plane by the (interpolated) twist angle, and lifted to its Z station
— built as a `Wire.polygon3D`. Every section has the **same point count in the same order**, so
`Shape.loft` correspondence is unambiguous. The lofted solid is then fused to a hub cylinder.

## OCCTSwift APIs used

- `Wire.polygon3D(_:closed:)` — each twisted, scaled airfoil section
- `Shape.loft(profiles:solid:)` — sweep the solid through the sections
- `Shape.cylinder(at:direction:radius:height:)` + `Shape.union(_:)` — the hub boss
- `Shape.volume` — sanity print

## Gotchas

- **Loft matches profiles by vertex index.** All sections must share the same point count and
  ordering — generate them from one base loop, only transforming the points. Mismatched counts
  give twisted/torn surfaces (and, before OCCTSwift v1.3.2, could crash `ThruSections`).
- Keep the trailing edge slightly open (the NACA TE is non-zero here); a perfectly closed TE
  makes the upper/lower TE points coincide and degenerates the section wire.
- Large twist deltas between few sections can self-intersect the loft. Add more `sections` if
  a steeply twisted blade fails or pinches.
- This is a single blade. A full rotor = this blade `circularPattern`ed about the hub axis.
