---
title: Introspection & measurement
parent: CLI & API Reference
nav_order: 6
---

# Introspection & measurement

Pure-read verbs that sample geometry without modification: compute physical properties, query topology by entity type and filter, measure distances and surface deviation, and recognize features. Reach for these after a script builds a body to extract ground-truth numbers before deciding what to change next.

## Entries

[`metrics`](#metrics) · [`query-topology`](#query-topology) · [`measure-distance`](#measure-distance) · [`measure-deviation`](#measure-deviation) · [`feature-recognize`](#feature-recognize)

---

## `metrics`

Volume, surface area, center of mass, bounding box, and principal axes for a BREP.

**Input** — flag-form or JSON-form (stdin or file path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputBrep` / positional | string | yes | Path to input BREP file |
| `--metrics` / `metrics` | string[] | no | Subset to compute (comma-separated in flag form, array in JSON). Default: all except `boundingBoxOptimal`. Items: `volume`, `surfaceArea`, `centerOfMass`, `boundingBox`, `boundingBoxOptimal`, `principalAxes` |

**Returns** — JSON object keyed by requested metric name. `boundingBox` and `boundingBoxOptimal` each return `{ min: [x,y,z], max: [x,y,z] }`. `centerOfMass` returns `[x,y,z]`. `principalAxes` returns `{ axes: [[...], [...], [...]], moments: [...] }` (three orthogonal unit vectors and their corresponding inertia moments). Omitted metrics return `null`. Note: `volumeInertia` is solid-only; for non-solids, volume / centerOfMass / principalAxes may be `null`.

**Example**

```bash
occtkit metrics housing.brep --metrics volume,surfaceArea,boundingBoxOptimal
```
```json
{
  "volume": 5890.3,
  "surfaceArea": 2104.7,
  "centerOfMass": null,
  "boundingBox": null,
  "boundingBoxOptimal": { "min": [0.0, 0.0, 0.0], "max": [25.0, 20.0, 15.0] },
  "principalAxes": null
}
```

**Drives** — `Shape.volumeInertia`, `Shape.surfaceArea`, `Shape.bounds`, `Shape.boundingBoxOptimal()`.

**Notes** — `boundingBox` (via `Bnd_Box`) encloses the control-point hull for curved B-spline faces and over-reports extents. Use `boundingBoxOptimal` (`BRepBndLib::AddOptimal`) for the tight envelope, at a small extra compute cost. `boundingBoxOptimal` is intentionally excluded from the default-all set — list it explicitly if needed.

---

## `query-topology`

Find faces, edges, or vertices matching optional filters; return stable index-based IDs.

**Input** — flag-form or JSON-form (stdin or file path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputBrep` / positional | string | yes | Path to input BREP file |
| `--entity` / `entity` | enum | yes | Entity kind: `face`, `edge`, or `vertex` |
| `--filter` / `filter` | object | no | Optional AND-combined filters. For faces: `surfaceType` (plane, cylinder, cone, sphere, torus, bezierSurface, bsplineSurface, surfaceOfRevolution, surfaceOfExtrusion, offsetSurface, other), `minArea`, `maxArea`, `normalDirection` ([x,y,z]), `normalTolerance` (radians, default 0.05). For edges: `curveType` (line, circle, ellipse, hyperbola, parabola, bezierCurve, bsplineCurve, offsetCurve, other), `minLength`, `maxLength`. Passed as JSON object in both flag and JSON forms |
| `--limit` / `limit` | integer | no | Maximum results to return. Default: no limit |

**Returns** — JSON object with `entity` (the type queried), `results` (array of matched topology entries), `total` (count of all matches before limit), and `truncated` (boolean). Each result includes `id` (stable ID like `face[0]`), surface/curve type, area/length, `centerOfMass` ([x,y,z] bounding box center), normal (faces only, unit vector at UV midpoint), and bounding box.

**Example**

```bash
occtkit query-topology bracket.brep --entity face --filter '{"surfaceType":"plane","minArea":100}' --limit 10
```
```json
{
  "entity": "face",
  "results": [
    {
      "id": "face[0]",
      "surfaceType": "plane",
      "curveType": null,
      "area": 400.0,
      "length": null,
      "centerOfMass": [0.0, 0.0, 10.0],
      "normal": [0.0, 0.0, 1.0],
      "boundingBox": { "min": [-10.0, -10.0, 10.0], "max": [10.0, 10.0, 10.0] }
    },
    {
      "id": "face[2]",
      "surfaceType": "plane",
      "curveType": null,
      "area": 400.0,
      "length": null,
      "centerOfMass": [0.0, 0.0, -10.0],
      "normal": [0.0, 0.0, -1.0],
      "boundingBox": { "min": [-10.0, -10.0, -10.0], "max": [10.0, 10.0, -10.0] }
    }
  ],
  "total": 2,
  "truncated": false
}
```

**Drives** — `Shape.faces()`, `.edges()`, `.vertices()` iteration with per-entity type classification and bounding box.

**Notes** — Returned IDs like `face[0]` are stable across loads of the same BREP and can be passed to other geometry tools that accept entity refs. Normal is computed at the UV midpoint of the face and normalized.

---

## `measure-distance`

Minimum distance and optional contact pairs between two BREPs (or a BREP and a point).

**Input** — flag-form or JSON-form (stdin or file path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `a` / positional 1 | string | yes | Path to first BREP file |
| `b` / positional 2 | string | yes | Path to second BREP file |
| `--from-ref` / `fromRef` | string | no | Optional ref for shape A. Format: `point:x,y,z` (synthesized vertex) or omit for whole shape. Sub-entity refs deferred |
| `--to-ref` / `toRef` | string | no | Optional ref for shape B. Same formats as `fromRef` |
| `--compute-contacts` / `computeContacts` | boolean | no | Also return up to 32 contact pairs (closest point pairs). Default: false |

**Returns** — JSON object with `minDistance` (minimum gap in model units; ≈0 for touching or overlapping), `isParallel` (always false for shape-shape; reserved for future edge-edge ops), and `contacts` (array of contact pairs if requested, else empty). Each contact has `fromPoint` and `toPoint` ([x,y,z]) and `distance`.

**Example**

```bash
occtkit measure-distance shaft.brep bearing.brep --compute-contacts
```
```json
{
  "minDistance": 0.05,
  "isParallel": false,
  "contacts": [
    {
      "fromPoint": [12.5, 0.0, 30.0],
      "toPoint": [12.55, 0.0, 30.0],
      "distance": 0.05
    }
  ]
}
```

**Drives** — `Shape.allDistanceSolutions(to:maxSolutions:)`.

**Notes** — This is the **minimum gap** metric, not surface deviation. For bodies touching or overlapping, the result is ≈0; it does not indicate the amount of overlap. For comparing a reconstruction against a reference mesh, use `measure-deviation` instead. Sub-entity refs (`face[N]`, `edge[N]`, `vertex[N]`) are on the roadmap; for now, shape-vs-shape distance already includes contact points that can be matched to faces/edges via `query-topology`.

---

## `measure-deviation`

Directed and symmetric surface deviation (Hausdorff distance) between two BREPs.

**Input** — flag-form or JSON-form (stdin or file path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `a` / positional 1 | string | yes | Path to source BREP (e.g., reconstruction) |
| `b` / positional 2 | string | yes | Path to reference BREP (e.g., source mesh) |
| `--deflection` / `deflection` | number | no | Mesh linear deflection in model units (smaller = finer tessellation = tighter bound). Default: 0.5% of shape A's bounding box diagonal |
| `--max-samples` / `maxSamples` | integer | no | Maximum source surface samples per direction (stride-subsampled). Default: 20000 |

**Returns** — JSON object with `deflection` (the mesh parameter used), `fromToTo` (directed deviation from source to reference: over-extension check), `toToFrom` (directed deviation from reference to source: under-coverage check), and `symmetricHausdorff` (worst-case max in either direction). Each directional stat has `max`, `rms`, `mean`, `worstPoint` ([x,y,z]), and `samples` (count). All distances in model units.

**Example**

```bash
occtkit measure-deviation recon.brep source_mesh.brep --deflection 0.1
```
```json
{
  "deflection": 0.1,
  "fromToTo": {
    "max": 0.18,
    "rms": 0.06,
    "mean": 0.04,
    "worstPoint": [42.1, 7.3, 0.0],
    "samples": 1500
  },
  "toToFrom": {
    "max": 0.22,
    "rms": 0.08,
    "mean": 0.05,
    "worstPoint": [41.9, 7.1, 0.0],
    "samples": 1500
  },
  "symmetricHausdorff": 0.22
}
```

**Drives** — per-shape tessellation (via `Shape.mesh(parameters:)`), KD-tree nearest-neighbor, and point-to-triangle distance (Ericson "Real-Time Collision Detection" §5.1.5).

**Notes** — Unlike `measure-distance` (minimum gap, ≈0 for overlaps), this samples tessellated surfaces and reports worst/RMS/mean deviation in both directions. `fromToTo` detects over-extension (reconstruction sticks out); `toToFrom` detects under-coverage (reference has uncovered surface). Fidelity scales with `deflection` — reduce for tighter bounds at higher compute cost. Load invalid in-progress reconstructions with `--allow-invalid` before calling this (passed to the load step).

---

## `feature-recognize`

Detect pockets and holes via attributed adjacency graph (AAG) heuristics.

**Input** — single BREP positional argument (flag-form only; no JSON mode).

**Parameters** — No parameters (other than the BREP input path).

**Returns** — JSON object with three top-level keys: `pockets` (array of detected pockets), `holes` (array of detected holes), and `features` (unified view with kind discriminator and face[N] refs aligned with `query-topology`). Each pocket has `floorFaceIndex`, `wallFaceIndices`, `zLevel`, `depth`, `isOpen`, and `bounds` (min/max). Each hole has `faceIndex`, `radius`, `depth`. Each feature has `id`, `kind` ("pocket" or "hole"), `confidence` (always 1.0; AAG is rule-based, not probabilistic), `params` (key-value dict with metric details), and `topologyRefs` (array of face[N] IDs).

**Example**

```bash
occtkit feature-recognize flange.brep
```
```json
{
  "pockets": [
    {
      "floorFaceIndex": 10,
      "wallFaceIndices": [11, 12, 13],
      "zLevel": 0.0,
      "depth": 5.0,
      "isOpen": false,
      "bounds": { "min": [0.0, 0.0, -5.0], "max": [20.0, 20.0, 0.0] }
    }
  ],
  "holes": [
    {
      "faceIndex": 4,
      "radius": 3.0,
      "depth": 12.0
    },
    {
      "faceIndex": 5,
      "radius": 3.0,
      "depth": 12.0
    }
  ],
  "features": [
    {
      "id": "feat[0]",
      "kind": "pocket",
      "confidence": 1.0,
      "params": { "zLevel": 0.0, "depth": 5.0, "isOpen": 0.0, "pocketIndex": 0.0 },
      "topologyRefs": ["face[10]", "face[11]", "face[12]", "face[13]"]
    },
    {
      "id": "feat[1]",
      "kind": "hole",
      "confidence": 1.0,
      "params": { "radius": 3.0, "depth": 12.0, "holeIndex": 0.0 },
      "topologyRefs": ["face[4]"]
    }
  ]
}
```

**Drives** — `AAG` (attributed adjacency graph) heuristic detection for pockets and holes.

**Notes** — The `features` array is the primary OCCTMCP-friendly output with stable `face[N]` refs. The legacy `pockets` and `holes` arrays coexist for backward compatibility. AAG detection is rule-based and deterministic (no probabilistic scoring). For the full graph-level feature recognition with BRepGraph output and node IDs, see the Topology graph family's [`feature-recognize`](topology-graph.md#feature-recognize) verb (different from this lightweight per-body variant).
