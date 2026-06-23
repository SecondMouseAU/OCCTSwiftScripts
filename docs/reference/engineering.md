---
title: Engineering analysis
parent: CLI & API Reference
nav_order: 8
---

# Engineering analysis

Manufacturing-readiness checks and geometry repair: wall-thickness analysis for sheet metal, casting, or 3D-printing; pairwise clearance and interference checks between assembly components; and ShapeFixer-based healing of imported or non-watertight geometry.

## Entries

[`check-thickness`](#check-thickness) · [`analyze-clearance`](#analyze-clearance) · [`heal`](#heal)

---

## `check-thickness`

UV-grid sample each face and cast an inward ray to the opposite wall; reports min/max/mean thickness and flags all samples below a minimum acceptable threshold.

**Input** — Flag-form or JSON-form (stdin or argv path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<input.brep>` | path | yes | Input BREP file |
| `--min-acceptable` / `minAcceptable` | number | no | Thickness threshold; samples below this are flagged as thin regions |
| `--sampling-density` / `samplingDensity` | enum | no | Grid density per face: `coarse` (4×4) \| `medium` (8×8, default) \| `fine` (16×16) |

**Returns** — JSON object with `minThickness`, `maxThickness`, `meanThickness` (or `null` if no samples), `thinRegions` (array of flagged sample locations), and `samples` (count).

**Example**

```bash
occtkit check-thickness part.brep --min-acceptable 1.5 --sampling-density fine
```
```json
{
  "ok": true,
  "minThickness": 1.1,
  "maxThickness": 4.8,
  "meanThickness": 2.9,
  "thinRegions": [
    {
      "centerPoint": [10.5, 20.3, 5.1],
      "thickness": 1.1,
      "faceRefs": ["face[3]"]
    }
  ],
  "samples": 256
}
```

**Drives** — `Face.uvBounds`, `Face.point(atU:v:)`, `Face.normal(atU:v:)`, `Shape.intersectLine(origin:direction:)`.

**Notes** — `fine` increases accuracy at the cost of speed; use `coarse` for a quick sanity check on large bodies.

---

## `analyze-clearance`

Pairwise minimum-distance and interference check between two or more BREPs; each pair gets a `minDistance` and optional contact points, with `interferenceVolume` reported when bodies intersect.

**Input** — Flag-form or JSON-form (stdin or argv path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<a.brep> [<b.brep> ...]` | paths | yes | Two or more input BREP files |
| `--min-clearance` / `minClearance` | number | no | Threshold; pairs below this set `belowMinClearance: true` |
| `--max-contacts` / `maxContacts` | integer | no | Maximum contact points per pair (default: 32) |
| `--no-contacts` / `computeContacts: false` | flag | no | Omit contact point details |

**Returns** — JSON object with `pairs` array. Each pair contains: `a`, `b` (file paths), `minDistance`, `intersects` (bool), `belowMinClearance` (bool or `null` if no threshold), `contacts` (array of point pairs), `interferenceVolume` (volume of overlap, or `null` for non-solid pairs or when not intersecting).

**Example**

```bash
occtkit analyze-clearance shaft.brep housing.brep bearing.brep --min-clearance 0.1
```
```json
{
  "ok": true,
  "pairs": [
    {
      "a": "shaft.brep",
      "b": "housing.brep",
      "minDistance": 0.05,
      "intersects": false,
      "belowMinClearance": true,
      "contacts": [
        {
          "fromPoint": [10.0, 0.0, 5.0],
          "toPoint": [10.05, 0.0, 5.0],
          "distance": 0.05
        }
      ],
      "interferenceVolume": null
    },
    {
      "a": "shaft.brep",
      "b": "bearing.brep",
      "minDistance": 0.0,
      "intersects": true,
      "belowMinClearance": true,
      "contacts": [],
      "interferenceVolume": 2.3
    }
  ]
}
```

**Drives** — `Shape.allDistanceSolutions(to:)`, `Shape.intersection(_:)`, `Shape.volume`.

**Notes** — A `minDistance` of 0 means bodies touch; negative values indicate interference (overlap). `interferenceVolume` is meaningful only for solid×solid pairs.

---

## `heal`

Heal imported or non-watertight geometry via OCCT ShapeFixer; reports before/after `Shape.analyze()` snapshots so the caller can verify the heal changed something.

**Input** — Flag-form or JSON-form (stdin or argv path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<input.brep>` | path | yes | Input BREP file |
| `--output` / `outputPath` | path | yes | Output BREP file |
| `--tolerance` / `tolerance` | number | no | Precision target for `ShapeFixer.setPrecision()` |
| `--max-tolerance` / `maxTolerance` | number | no | Maximum tolerance for `ShapeFixer.setMaxTolerance()` |
| `--min-tolerance` / `minTolerance` | number | no | Minimum tolerance for `ShapeFixer.setMinTolerance()` |
| `--fix-small-edges` / `fixSmallEdges` | flag | no | Accepted for forward compat; currently coalesces into precision tuning |
| `--fix-small-faces` / `fixSmallFaces` | flag | no | Accepted for forward compat; currently coalesces into precision tuning |
| `--fix-gaps` / `fixGaps` | flag | no | Accepted for forward compat; currently coalesces into precision tuning |
| `--fix-self-intersection` / `fixSelfIntersection` | flag | no | Accepted for forward compat; currently coalesces into precision tuning |
| `--fix-orientation` / `fixOrientation` | flag | no | Accepted for forward compat; currently coalesces into precision tuning |
| `--unify-domain` / `unifyDomain` | flag | no | Accepted for forward compat; currently coalesces into precision tuning |

**Returns** — JSON object with `outputPath`, `before` and `after` health snapshots (each with `faceCount`, `edgeCount`, `freeEdgeCount`, `smallEdgeCount`, `smallFaceCount`, `selfIntersectionCount`, `isValid`), `fixes` (counts of resolved issues), and `warnings` (array).

**Example**

```bash
occtkit heal imported.brep --output imported_healed.brep --tolerance 0.01
```
```json
{
  "ok": true,
  "outputPath": "/tmp/imported_healed.brep",
  "before": {
    "faceCount": 24,
    "edgeCount": 72,
    "freeEdgeCount": 3,
    "smallEdgeCount": 2,
    "smallFaceCount": 1,
    "selfIntersectionCount": 0,
    "isValid": false
  },
  "after": {
    "faceCount": 24,
    "edgeCount": 72,
    "freeEdgeCount": 0,
    "smallEdgeCount": 0,
    "smallFaceCount": 0,
    "selfIntersectionCount": 0,
    "isValid": true
  },
  "fixes": {
    "smallEdgesFixed": 2,
    "smallFacesFixed": 1,
    "freeEdgesClosed": 3,
    "selfIntersectionsResolved": 0
  },
  "warnings": []
}
```

**Drives** — `ShapeFixer` (`setPrecision`, `setMaxTolerance`, `setMinTolerance`, `perform`), `Shape.analyze()`, `Shape.isValid`.

**Notes** — Per-fix `--fix-*` flags are accepted today for forward compatibility with the issue spec but currently all coalesce into `ShapeFixer`'s precision tuning. Granular per-fix gating awaits an upstream OCCTSwift API. If `ShapeFixer.perform()` reports no changes, both snapshots may be identical.
