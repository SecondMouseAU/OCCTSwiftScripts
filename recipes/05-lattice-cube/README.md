# 05 — Strut lattice cube

A 3D-printable cubic strut lattice — round struts running in all three axes, fused into one
solid. Shows `linearPattern` tiling and multi-body boolean union.

![Strut lattice cube](output.png)

## Parameters

| Name      | Default | Description                                  | Valid range          |
|-----------|---------|----------------------------------------------|----------------------|
| `cell`    | `10`    | Unit cell size (mm)                          | `> 2·strutR`         |
| `cells`   | `3`     | Cells per axis → `cells+1` strut lines       | `≥ 1`                |
| `strutR`  | `1.2`   | Strut radius (mm)                            | `> 0`, `< cell/2`    |

Overall edge length is `cell · cells` (default 30 mm); each direction has `cells+1` parallel
strut lines.

## Algorithm

For each axis, one **full-length** rod cylinder is built spanning the whole lattice, then
replicated across the other two axes with two chained `Shape.linearPattern` calls (a row,
then a grid). Using one continuous rod per line — rather than a strut per cell — means
adjacent cells share the same rod, so there are no duplicated, overlapping struts at cell
boundaries. The three axis-aligned rod grids are then fused with `Shape.union` into a single
watertight lattice.

## OCCTSwift APIs used

- `Shape.cylinder(at:direction:radius:height:)` — one strut rod per axis
- `Shape.linearPattern(direction:spacing:count:)` — tile a rod into a grid (chained twice)
- `Shape.union(_:)` — fuse the three rod grids into one solid
- `Shape.volume` — sanity print

## Gotchas

- `linearPattern` is 1D (one direction); tile a grid by chaining two calls on the result.
- Cost scales with `(cells+1)² · 3` struts and the final unions — keep `cells` modest
  (3–5) for fast iteration; large lattices fuse slowly.
- Full-length rods keep the union clean. Per-cell strut segments would pile coincident faces
  at every node and make the boolean slower and more fragile.
- This is a simple cubic (rods-only) lattice. Body-centred (BCC) or octet cells add diagonal
  struts — sweep them along `Wire.line` diagonals and union in the same way.
