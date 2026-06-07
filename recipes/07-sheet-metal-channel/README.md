# 07 — Sheet-metal U-channel

A folded sheet-metal U-channel — a base plate with two walls bent up on opposite edges —
built with OCCTSwift's `SheetMetal` composition API.

![Sheet-metal U-channel](output.png)

## Parameters

| Name         | Default | Description                              | Valid range          |
|--------------|---------|------------------------------------------|----------------------|
| `width`      | `80`    | Base size in X / wall width (mm)         | `> 0`                |
| `depth`      | `50`    | Base size in Y, between the walls (mm)   | `> 2·bendRadius`     |
| `wallHeight` | `25`    | Wall height (mm)                         | `> 0`                |
| `thickness`  | `1.5`   | Sheet thickness (mm)                     | `> 0`                |
| `bendRadius` | `2.0`   | Inside bend radius (mm)                  | `> 0`                |

## Algorithm

Each face is a `SheetMetal.Flange`: a 2D `profile` placed in 3D by an `origin`, an in-plane
`uAxis` and `vAxis`, and a `normal` along which the thickness is extruded. The base lies in
the XY plane; the two walls sit on the `y = 0` and `y = depth` edges, run the full width in
`+X` (`uAxis`), rise in `+Z` (`vAxis`), and extrude their thickness outward (`normal`). Two
`SheetMetal.Bend`s join the base to each wall with an inside radius, and
`SheetMetal.Builder.build` extrudes the flanges and rounds the bend regions into one solid.

## OCCTSwift APIs used

- `SheetMetal.Flange(id:profile:origin:normal:uAxis:vAxis:)` — each face
- `SheetMetal.Bend(from:to:radius:)` — base→wall folds
- `SheetMetal.Builder(thickness:).build(flanges:bends:)` — fold into one solid
- `Shape.volume` — sanity print

## Gotchas

- **Set `vAxis` explicitly.** It defaults to `cross(normal, uAxis)`, which points *downward*
  for some edges — a wall would then fold below the base and the bend fillet fails. Give
  every wall `vAxis = (0,0,1)`.
- **Walls must span the full base edge.** Narrowing a wall (corner relief) or insetting its
  origin makes the bend fillet fail — the builder rounds the whole shared edge.
- **No shared corners.** The builder folds chains and *opposite* flanges (U-channel,
  Z-bracket), but two walls meeting at a corner fail the corner fillet — so a four-wall tray
  / closed box is not buildable this way today. A U-channel is the robust canonical part.
- The `build` call `throws`; surface `SheetMetal.BuildError` (it is `CustomStringConvertible`)
  rather than force-unwrapping.
