---
title: Topology graph
parent: Cookbook
nav_order: 10
---

# Topology graph

The typical pipeline for a BREP you have just exported or received from an importer: validate its topology, compact it, dedup shared geometry, then query or export it for downstream analysis or ML training.

All six commands operate on an **absolute BREP file path** or, in the case of `graph-query`, on a BREPGraph SQLite file. Full parameter tables are in the [Topology graph reference](../../reference/topology-graph.md).

---

## 1. Validate — topology health record

[`graph-validate`](../../reference/topology-graph.md#graph-validate) checks the shape without touching the file.

```bash
occtkit graph-validate bracket.brep
```

```json
{
  "isValid": true,
  "errorCount": 0,
  "warningCount": 2,
  "healthRecord": {
    "isValid": true,
    "shapeType": "solid",
    "freeEdgeCount": 0,
    "nakedVertexCount": 0,
    "smallEdgeCount": 1,
    "smallFaceCount": 0,
    "selfIntersecting": false,
    "errors": []
  }
}
```

If `isValid` is `false`, examine the `healthRecord.errors` list. A shape with topology errors can still be loaded for measurement but compact and dedup on an invalid shape may produce further corruption — fix or heal before proceeding.

---

## 2. Compact — drop unreferenced nodes

[`graph-compact`](../../reference/topology-graph.md#graph-compact) rebuilds the shape and removes nodes that nothing references — common after Boolean operations and healing. Pass a distinct output path to preserve the original.

```bash
occtkit graph-compact bracket.brep bracket_compact.brep
```

```json
{
  "nodesBefore": 42,
  "nodesAfter": 38,
  "removed": {
    "vertices": 0,
    "edges": 2,
    "faces": 1
  },
  "output": "bracket_compact.brep"
}
```

---

## 3. Dedup — merge shared surface/curve geometry

[`graph-dedup`](../../reference/topology-graph.md#graph-dedup) detects geometrically identical surfaces and curves and merges them into single graph nodes. This reduces file size and produces a cleaner attributed adjacency graph (gAAG) for feature recognition and ML export.

```bash
occtkit graph-dedup bracket_compact.brep bracket_clean.brep
```

```json
{
  "canonicalSurfaces": 8,
  "canonicalCurves": 12,
  "surfaceRewrites": 3,
  "curveRewrites": 5,
  "output": "bracket_clean.brep"
}
```

The three steps above chain naturally: validate → compact → dedup gives you a clean BREP ready for query or ML export.

---

## 4. Query a BREPGraph SQLite database

[`graph-query`](../../reference/topology-graph.md#graph-query) reads a BREPGraph SQLite file — produced by `ScriptContext.addGraph(..., sqlite: true)` inside a script — and emits a topology summary.

```bash
occtkit graph-query graph-0.sqlite
```

```json
{
  "summary": {
    "solids": 1,
    "shells": 1,
    "faces": 6,
    "wires": 6,
    "edges": 12,
    "vertices": 8,
    "coedges": 24,
    "boundaryEdges": 0,
    "nonManifoldEdges": 0,
    "degenerateEdges": 0,
    "openShells": 0
  },
  "counts": {
    "freeEdges": 0,
    "openWires": 0,
    "facesWithHoles": 0
  },
  "valence": {
    "face":   { "max": 4, "mean": 3.5, "count": 8 },
    "vertex": { "max": 3, "mean": 3.0, "count": 8 }
  }
}
```

This command requires a SQLite file; it does not accept a BREP path directly.

---

## 5. ML export — full graph with UV and edge samples

[`graph-ml`](../../reference/topology-graph.md#graph-ml) exports the full topology graph augmented with per-face UV grids (positions, normals, Gaussian and mean curvatures), per-edge curve samples, COO adjacency matrices, and an attributed face-adjacency block. Use `--uv-samples` and `--edge-samples` to tune sampling density (defaults: 16 and 32).

```bash
occtkit graph-ml bracket_clean.brep --uv-samples 12 --edge-samples 24
```

```json
{
  "vertexPositions": [[0,0,0], [1,0,0]],
  "edgeBoundaryFlags": [false, false],
  "edgeManifoldFlags": [true, true],
  "faceAdjacentFaces": [[1,2], [0,3]],
  "faceToFace":   { "sources": [0,0,1], "targets": [1,2,0] },
  "faceToEdge":   { "sources": [0,0,1], "targets": [2,3,5] },
  "edgeToVertex": { "sources": [0,1,1], "targets": [0,1,2] },
  "faces": [
    {
      "index": 0, "uSamples": 12, "vSamples": 12,
      "positions": [[0,0,0]], "normals": [[0,0,1]],
      "gaussianCurvatures": [0.0], "meanCurvatures": [0.0]
    }
  ],
  "edges": [{ "index": 0, "samples": [[0,0,0],[0.1,0,0]] }],
  "faceAdjacency": [
    { "face1": 0, "face2": 1, "convexity": "convex",  "sharedEdgeCount": 1 },
    { "face1": 1, "face2": 3, "convexity": "concave", "sharedEdgeCount": 1 }
  ],
  "sampling": { "uvSamples": 12, "edgeSamples": 24 }
}
```

Face indices in `faceAdjacency` and `faceAdjacentFaces` follow `shape.faces()` order — the same `face[N]` scheme `query-topology` emits. Convexity is a property of the dihedral angle between two faces: `"convex"` (outward-pointing), `"concave"` (inward), or `"smooth"` (near-zero).

---

## 6. Local adjacency selection

[`graph-select`](../../reference/topology-graph.md#graph-select) answers focused neighbourhood questions without dumping the full graph. The `--query` flag selects the mode.

| `--query` | required secondary flag | returns |
|-----------|------------------------|---------|
| `face-neighbors` | `--face N` | adjacent faces + convexity + shared-edge count + face plane info |
| `edge-faces` | `--edge M` | face indices on both sides, start/end vertices, boundary/manifold flags |
| `vertex-edges` | `--vertex K` | edge indices incident to the vertex |
| `face-adjacency` | — | full attributed gAAG (faceCount + all adjacencies) |
| `edges-class` | `--class <kind>` | matching edge indices; `kind` = `boundary` \| `non-manifold` \| `seam` \| `degenerate` |

**Face neighbours with convexity:**

```bash
occtkit graph-select bracket_clean.brep --query face-neighbors --face 2
```

```json
{
  "query": "face-neighbors",
  "face": 2,
  "isPlanar": true,
  "isVertical": false,
  "isHorizontal": true,
  "normal": [0, 1, 0],
  "neighbors": [
    { "face": 0, "convexity": "convex",  "sharedEdgeCount": 1 },
    { "face": 3, "convexity": "concave", "sharedEdgeCount": 1 }
  ]
}
```

**Find all boundary edges:**

```bash
occtkit graph-select bracket_clean.brep --query edges-class --class boundary
```

```json
{
  "query": "edges-class",
  "class": "boundary",
  "edges": [7, 11, 14]
}
```

Face indices follow `shape.faces()` order; edge and vertex indices are TopologyGraph indices.

---

## Reference

- [Topology graph](../../reference/topology-graph.md) — full parameter tables for all six commands.
- [Introspection & measurement](introspection-and-measurement.md) — `query-topology` and `measure-distance` (scene-aware wrappers).
