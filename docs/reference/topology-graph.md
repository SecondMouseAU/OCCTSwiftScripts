---
title: Topology graph
parent: CLI & API Reference
nav_order: 2
---

# Topology graph

Low-level B-rep graph operations that work directly on an absolute BREP file path. Use these when you need raw topology analysis, graph compaction, ML export, or local adjacency queries — they operate on the pure topology without scene or geometry enrichment.

## Entries

[`graph-validate`](#graph-validate) · [`graph-compact`](#graph-compact) · [`graph-dedup`](#graph-dedup) · [`graph-query`](#graph-query) · [`graph-ml`](#graph-ml) · [`graph-select`](#graph-select)

---

## `graph-validate`

Validate a BREP shape's topology graph and surface a structured health record.

**Input** — flag-form (positional BREP path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<shape.brep>` | string | yes | Path to the BREP file to validate. |

**Returns** — Topology validity report with `isValid` / `errorCount` / `warningCount` and a `healthRecord` containing shape type, free-edge count, small-edge count, small-face count, and self-intersection status.

**Example**

```bash
occtkit graph-validate shape.brep
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

**Drives** — `BRepGraph.validate()` + `Shape.analyze()`.

---

## `graph-compact`

Compact a graph by dropping unreferenced nodes; writes the rebuilt BREP to `<out.brep>`.

**Input** — flag-form (positional BREP paths).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<in.brep>` | string | yes | Path to the source BREP file. |
| `<out.brep>` | string | yes | Path where the compacted BREP will be written. |

**Returns** — Node counts before and after (total nodes, then per-type removal counts: vertices, edges, faces), plus the output path.

**Example**

```bash
occtkit graph-compact shape.brep shape_compact.brep
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
  "output": "shape_compact.brep"
}
```

**Drives** — `BRepGraph.compact()`.

---

## `graph-dedup`

Deduplicate shared surface and curve geometry in a BREP's topology graph; writes the rebuilt BREP to `<out.brep>`.

**Input** — flag-form (positional BREP paths).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<in.brep>` | string | yes | Path to the source BREP file. |
| `<out.brep>` | string | yes | Path where the deduplicated BREP will be written. |

**Returns** — Deduplication statistics: count of canonical surfaces and curves, and count of references rewritten to point to those canonicals.

**Example**

```bash
occtkit graph-dedup assembly.brep assembly_dedup.brep
```
```json
{
  "canonicalSurfaces": 8,
  "canonicalCurves": 12,
  "surfaceRewrites": 3,
  "curveRewrites": 5,
  "output": "assembly_dedup.brep"
}
```

**Drives** — `BRepGraph.deduplicate()`.

---

## `graph-query`

Emit a JSON topology summary from a BREPGraph SQLite database.

**Input** — flag-form (positional SQLite path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<graph.sqlite>` | string | yes | Path to the BREPGraph SQLite file (produced by `ScriptContext.addGraph()` with `sqlite: true`). |

**Returns** — Topology summary (solid/shell/face/wire/edge/vertex/coedge counts, boundary/non-manifold/degenerate edge counts, open shell count), edge and vertex valence statistics (max, mean, count), and computed counts (free edges, open wires, faces with holes).

**Example**

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
    "face": { "max": 4, "mean": 3.5, "count": 8 },
    "vertex": { "max": 3, "mean": 3.0, "count": 8 }
  }
}
```

**Drives** — SQLite query over `topology_summary` / `free_edges` / `open_wires` / `faces_with_holes` / `face_valence` / `vertex_valence` views.

**Notes** — Requires a BREPGraph SQLite file produced by `ScriptContext.addGraph(..., sqlite: true)`. JSON-form SQLite queries are not supported.

---

## `graph-ml`

Export a BREP's topology graph and UV/edge samples as ML-friendly JSON.

**Input** — flag-form with optional sample-count tuning.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<shape.brep>` | string | yes | Path to the BREP file. |
| `--uv-samples` | integer | no | Face UV grid density (default 16, produces 16×16 grid per face). |
| `--edge-samples` | integer | no | Edge curve sample count (default 32). |

**Returns** — ML-ready JSON containing vertex positions, edge boundary/manifold flags, face adjacency indices, face-to-face / face-to-edge / edge-to-vertex COO matrices, per-face UV grid with positions/normals/Gaussian/mean curvatures, per-edge curve samples, and an attributed face-adjacency block with convexity per dihedral + shared-edge count.

**Example**

```bash
occtkit graph-ml shape.brep --uv-samples 12 --edge-samples 24
```
```json
{
  "vertexPositions": [[0,0,0], [1,0,0], ...],
  "edgeBoundaryFlags": [true, false, ...],
  "edgeManifoldFlags": [true, true, ...],
  "faceAdjacentFaces": [[1,2], [0,3], ...],
  "faceToFace": { "sources": [0, 0, 1], "targets": [1, 2, 0] },
  "faceToEdge": { "sources": [0, 0, 1], "targets": [2, 3, 5] },
  "edgeToVertex": { "sources": [0, 1, 1], "targets": [0, 1, 2] },
  "faces": [{ "index": 0, "uSamples": 12, "vSamples": 12, "positions": [...], "normals": [...], "gaussianCurvatures": [...], "meanCurvatures": [...] }, ...],
  "edges": [{ "index": 0, "samples": [[0,0,0], [0.1,0,0], ...] }, ...],
  "faceAdjacency": [
    { "face1": 0, "face2": 1, "convexity": "convex", "sharedEdgeCount": 1 },
    { "face1": 1, "face2": 3, "convexity": "concave", "sharedEdgeCount": 1 }
  ],
  "sampling": { "uvSamples": 12, "edgeSamples": 24 }
}
```

**Drives** — `BRepGraph.exportForML()` + `AAG` (Attributed Adjacency Graph).

**Notes** — Face indices in `faceAdjacency` follow `shape.faces()` order (the same `face[N]` scheme `query-topology` emits). Convexity is a property of the dihedral between two faces: `"convex"` (outward-pointing), `"concave"` (inward), or `"smooth"` (near-zero curvature).

---

## `graph-select`

Query B-rep graph adjacency and selection — return a focused neighbourhood rather than a full graph dump.

**Input** — flag-form with required `--query` and optional adjacency/class selector flags.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<shape.brep>` | string | yes | Path to the BREP file. |
| `--query` | string | yes | One of `face-neighbors` \| `edge-faces` \| `vertex-edges` \| `face-adjacency` \| `edges-class`. |
| `--face` | integer | no | Face index (required for `face-neighbors`). Follows `shape.faces()` order. |
| `--edge` | integer | no | Edge index (required for `edge-faces`). BRepGraph index. |
| `--vertex` | integer | no | Vertex index (required for `vertex-edges`). BRepGraph index. |
| `--class` | string | no | Edge class filter (required for `edges-class`): one of `boundary` \| `non-manifold` \| `seam` \| `degenerate`. |

**Returns** — Depends on `--query`:
- `face-neighbors` — adjacent face indices with convexity and shared-edge count per adjacency.
- `edge-faces` — face indices on both sides of the edge, plus start/end vertices and boundary/manifold flags.
- `vertex-edges` — edge indices incident to the vertex.
- `face-adjacency` — full attributed face-adjacency graph (gAAG) for the shape.
- `edges-class` — indices of all edges matching the given class.

**Example**

```bash
occtkit graph-select shape.brep --query face-neighbors --face 2
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
    { "face": 0, "convexity": "convex", "sharedEdgeCount": 1 },
    { "face": 3, "convexity": "concave", "sharedEdgeCount": 1 }
  ]
}
```

**Drives** — `AAG` (face queries) and `BRepGraph` (edge/vertex queries).

**Notes** — Face indices follow `shape.faces()` order (the `face[N]` scheme from `query-topology`). Edge and vertex indices are BRepGraph indices. The correct secondary parameter to supply depends on `--query`: `--face` for `face-neighbors`, `--edge` for `edge-faces`, `--vertex` for `vertex-edges`, `--class` for `edges-class`; none needed for `face-adjacency`.
