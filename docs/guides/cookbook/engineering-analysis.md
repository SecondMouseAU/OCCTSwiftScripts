---
title: Engineering analysis
parent: Cookbook
nav_order: 11
---

# Engineering analysis

A DFM-style workflow for three headless verbs: check wall thickness against a
manufacturing floor, confirm clearance and flag interference between mating
bodies, and heal imported geometry that arrives non-watertight. All three verbs
are pure read-then-write — they take BREPs from disk and emit JSON on stdout.

Full flag and return-value details: [Engineering analysis reference](../../reference/engineering.md).

---

## 1. Wall-thickness check

`check-thickness` UV-grid samples each face and casts an inward ray to the
opposite wall. Use `--sampling-density fine` (16×16 per face) for a casting or
injection-mould submission; `coarse` (4×4) for a quick sanity pass on large
bodies.

```bash
occtkit check-thickness housing.brep \
    --min-acceptable 1.5 \
    --sampling-density fine
```

```json
{
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

`minThickness: 1.1` is below the 1.5 mm floor. The `thinRegions` array gives
the world-space `centerPoint` and `faceRefs` for every flagged sample — take
those coordinates back to your modeller to thicken the wall at `face[3]`.

---

## 2. Clearance and interference check

`analyze-clearance` runs all pairwise gap checks in one call. Pass
`--min-clearance` to tag every pair whose gap falls below a design rule; when
two solids overlap, `interferenceVolume` reports the volume of the intersection.

```bash
occtkit analyze-clearance shaft.brep housing.brep bearing.brep \
    --min-clearance 0.1
```

```json
{
  "pairs": [
    {
      "a": "shaft.brep",
      "b": "housing.brep",
      "minDistance": 0.05,
      "intersects": false,
      "belowMinClearance": true,
      "contacts": [
        { "fromPoint": [10.0, 0.0, 5.0], "toPoint": [10.05, 0.0, 5.0], "distance": 0.05 }
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
    },
    {
      "a": "housing.brep",
      "b": "bearing.brep",
      "minDistance": 0.8,
      "intersects": false,
      "belowMinClearance": false,
      "contacts": [],
      "interferenceVolume": null
    }
  ]
}
```

The shaft–bearing pair has `intersects: true` and `interferenceVolume: 2.3` mm³ —
a real clash that needs fixing. The shaft–housing gap of 0.05 mm is within spec
tolerance but tagged `belowMinClearance: true` because it is under the 0.1 mm
design rule. Add `--no-contacts` to suppress point details and speed up large
assemblies.

---

## 3. Heal imported geometry

Geometry imported from STEP or IGES often arrives with free edges, small slivers,
or invalid orientation. Run `heal` to apply OCCT ShapeFix and write a repaired
BREP, then compare the before/after snapshots to confirm the repair.

**Before heal — snapshot the raw import:**

```bash
occtkit check-thickness imported.brep --sampling-density coarse
```

```json
{ "minThickness": null, "maxThickness": null, "meanThickness": null,
  "thinRegions": [], "samples": 0 }
```

No samples returned: the shape is not watertight, so inward rays escape without
hitting an opposite wall.

**Heal:**

```bash
occtkit heal imported.brep --output imported_healed.brep --tolerance 0.01
```

```json
{
  "outputPath": "/tmp/imported_healed.brep",
  "before": {
    "faceCount": 24, "edgeCount": 72,
    "freeEdgeCount": 3, "smallEdgeCount": 2, "smallFaceCount": 1,
    "selfIntersectionCount": 0, "isValid": false
  },
  "after": {
    "faceCount": 24, "edgeCount": 72,
    "freeEdgeCount": 0, "smallEdgeCount": 0, "smallFaceCount": 0,
    "selfIntersectionCount": 0, "isValid": true
  },
  "fixes": {
    "smallEdgesFixed": 2, "smallFacesFixed": 1,
    "freeEdgesClosed": 3, "selfIntersectionsResolved": 0
  },
  "warnings": []
}
```

`isValid: true` and `freeEdgeCount: 0` in the `after` snapshot confirm the shell
is closed. `fixes.freeEdgesClosed: 3` accounts for all three violations from the
before snapshot.

**After heal — re-run the thickness check:**

```bash
occtkit check-thickness imported_healed.brep \
    --min-acceptable 1.5 \
    --sampling-density fine
```

The healed BREP now returns real thickness statistics, and you can feed it
straight into `analyze-clearance` alongside mating parts.

---

## What next?

- Verify surface fidelity against a source mesh →
  [Introspection & measurement](introspection-and-measurement.md)
- Export the healed BREP to STEP for downstream CAD →
  [Import, export & assemblies](io-and-assemblies.md)
- Full flag reference for all three verbs →
  [Engineering analysis reference](../../reference/engineering.md)
