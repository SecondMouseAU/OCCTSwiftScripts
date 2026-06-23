---
title: Introspection & measurement
parent: Cookbook
nav_order: 7
---

# Introspection & measurement

A read-only inspection workflow on an existing BREP: compute physical properties, pull
stable topology IDs with a filter, measure the minimum gap between two bodies, certify a
reconstruction against a source mesh, and detect features — all without touching the geometry.

Full flag and field documentation: [Introspection & measurement reference](../../reference/introspection.md).

---

## 1. Compute metrics

Retrieve volume, surface area, and bounding box in one call.

```bash
occtkit metrics flange.brep --metrics volume,surfaceArea,boundingBoxOptimal
```

```json
{
  "volume": 18432.6,
  "surfaceArea": 7804.1,
  "centerOfMass": null,
  "boundingBox": null,
  "boundingBoxOptimal": { "min": [-40.0, -30.0, 0.0], "max": [40.0, 30.0, 49.0] },
  "principalAxes": null
}
```

**`boundingBox` vs `boundingBoxOptimal`** — the default `boundingBox` (via OCCT's `Bnd_Box`)
encloses the control-point hull of B-spline faces, which over-reports extents on curved
geometry by 1–2 % or more. `boundingBoxOptimal` calls `BRepBndLib::AddOptimal` and samples
the exact surfaces for a tight envelope. It is excluded from the default-all set — list it
explicitly. Use it whenever the bbox drives a fit-check or clearance decision.

---

## 2. Query topology

Find faces (or edges, or vertices) matching a filter and retrieve their stable index-based IDs.

### All planar faces

```bash
occtkit query-topology flange.brep --entity face --filter '{"surfaceType":"plane"}'
```

```json
{
  "entity": "face",
  "results": [
    { "id": "face[0]", "surfaceType": "plane", "area": 2400.0,
      "centerOfMass": [0.0, 0.0, 49.0], "normal": [0.0, 0.0, 1.0],
      "boundingBox": { "min": [-40.0, -30.0, 49.0], "max": [40.0, 30.0, 49.0] } },
    { "id": "face[1]", "surfaceType": "plane", "area": 2400.0,
      "centerOfMass": [0.0, 0.0, 0.0],  "normal": [0.0, 0.0, -1.0],
      "boundingBox": { "min": [-40.0, -30.0, 0.0],  "max": [40.0, 30.0, 0.0] } }
  ],
  "total": 2,
  "truncated": false
}
```

### Faces above an area threshold

Combine `surfaceType` and `minArea` in the same filter object — all filter keys are
AND-combined:

```bash
occtkit query-topology flange.brep --entity face \
  --filter '{"surfaceType":"plane","minArea":500}' --limit 10
```

```json
{
  "entity": "face",
  "results": [
    { "id": "face[0]", "surfaceType": "plane", "area": 2400.0,
      "centerOfMass": [0.0, 0.0, 49.0], "normal": [0.0, 0.0, 1.0],
      "boundingBox": { "min": [-40.0, -30.0, 49.0], "max": [40.0, 30.0, 49.0] } }
  ],
  "total": 1,
  "truncated": false
}
```

Returned IDs like `face[0]` are stable across loads of the same BREP. They align directly
with the `topologyRefs` returned by `feature-recognize` (step 4 below).

---

## 3. Measure distance vs measure deviation — choose the right tool

| Goal | Command | What it returns |
|------|---------|-----------------|
| Clearance check — is there a gap between two bodies? | `measure-distance` | Minimum gap in model units (≈0 for touching or overlapping bodies) |
| Fidelity certification — how closely does a reconstruction match a source mesh? | `measure-deviation` | Directed + symmetric surface Hausdorff; `≈0` is **not** a meaningful answer to the fidelity question |

### Minimum gap (`measure-distance`)

Use this for assembly clearance: confirm two mating parts do not interfere and quantify
the gap between them.

```bash
occtkit measure-distance shaft.brep bearing.brep --compute-contacts
```

```json
{
  "minDistance": 0.05,
  "isParallel": false,
  "contacts": [
    {
      "fromPoint": [12.5,  0.0, 30.0],
      "toPoint":   [12.55, 0.0, 30.0],
      "distance": 0.05
    }
  ]
}
```

`minDistance: 0.05` — a 0.05 mm clearance remains. `--compute-contacts` returns up to 32
closest-point pairs; omit it when you only need the scalar gap.

**Do not use `measure-distance` for fidelity.** When a reconstruction overlaps its source
mesh the result is `minDistance: 0.0` — no information about surface match quality.

### Surface deviation (`measure-deviation`)

Use this to certify that a B-rep reconstruction is within tolerance of a scan or reference
mesh. The two direction statistics tell a complete story:

- **`fromToTo`** — reconstruction surface vs. reference. High `max` here means the
  reconstruction extends **beyond** the reference (over-extension).
- **`toToFrom`** — reference surface vs. reconstruction. High `max` here means parts of
  the reference that the reconstruction **does not cover** (under-coverage).
- **`symmetricHausdorff`** — `max(fromToTo.max, toToFrom.max)`: the single worst-case in
  either direction. Compare this against your tolerance spec.

```bash
occtkit measure-deviation recon.brep source_mesh.brep --deflection 0.1
```

```json
{
  "deflection": 0.1,
  "fromToTo": {
    "max": 0.18, "rms": 0.06, "mean": 0.04,
    "worstPoint": [42.1, 7.3, 0.0], "samples": 1500
  },
  "toToFrom": {
    "max": 0.22, "rms": 0.08, "mean": 0.05,
    "worstPoint": [41.9, 7.1, 0.0], "samples": 1500
  },
  "symmetricHausdorff": 0.22
}
```

`symmetricHausdorff: 0.22` against a 0.25 mm tolerance spec — pass. The `worstPoint`
coordinates tell you exactly where to look in the viewport.

`--deflection` controls tessellation fineness (model units). The default is 0.5 % of the
shape A bounding-box diagonal — usually a good starting point. Reduce it for a tighter
bound at higher compute cost. `--max-samples` (default 20 000) caps samples per direction.

---

## 4. Recognize features

Detect pockets and holes via OCCTSwift's attributed adjacency graph (AAG) heuristics.
The `feature-recognize` verb accepts only a single positional BREP argument — no flags.

```bash
occtkit feature-recognize flange.brep
```

```json
{
  "pockets": [
    {
      "floorFaceIndex": 10, "wallFaceIndices": [11, 12, 13],
      "zLevel": 0.0, "depth": 5.0, "isOpen": false,
      "bounds": { "min": [0.0, 0.0, -5.0], "max": [20.0, 20.0, 0.0] }
    }
  ],
  "holes": [
    { "faceIndex": 4, "radius": 3.0, "depth": 12.0 },
    { "faceIndex": 5, "radius": 3.0, "depth": 12.0 }
  ],
  "features": [
    {
      "id": "feat[0]", "kind": "pocket", "confidence": 1.0,
      "params": { "zLevel": 0.0, "depth": 5.0, "isOpen": 0.0, "pocketIndex": 0.0 },
      "topologyRefs": ["face[10]", "face[11]", "face[12]", "face[13]"]
    },
    {
      "id": "feat[1]", "kind": "hole", "confidence": 1.0,
      "params": { "radius": 3.0, "depth": 12.0, "holeIndex": 0.0 },
      "topologyRefs": ["face[4]"]
    },
    {
      "id": "feat[2]", "kind": "hole", "confidence": 1.0,
      "params": { "radius": 3.0, "depth": 12.0, "holeIndex": 1.0 },
      "topologyRefs": ["face[5]"]
    }
  ]
}
```

Use the `features` array as the primary output: the `face[N]` refs in `topologyRefs`
align directly with the IDs from `query-topology`, so you can cross-reference feature
membership with surface type or area without reindexing. The top-level `pockets` and
`holes` arrays carry the same data in a legacy shape for backward compatibility.

AAG detection is rule-based and deterministic (`confidence` is always `1.0`).

---

## Putting it together

A typical read-only pipeline on a freshly built BREP:

```bash
# 1. Physical properties
occtkit metrics part.brep --metrics volume,surfaceArea,boundingBoxOptimal

# 2. Find large planar faces (mounting pads, datum planes)
occtkit query-topology part.brep --entity face \
  --filter '{"surfaceType":"plane","minArea":200}'

# 3. Confirm clearance to a mating part
occtkit measure-distance part.brep mating.brep --compute-contacts

# 4. Certify against source mesh (after reconstruction)
occtkit measure-deviation part.brep source_scan.brep

# 5. Feature inventory
occtkit feature-recognize part.brep
```

Full parameter reference: [Introspection & measurement](../../reference/introspection.md).
