---
title: Mesh
parent: CLI & API Reference
nav_order: 9
---

# Mesh

Triangle tessellation from B-rep solids via BRepMesh_IncrementalMesh, and QEM-based mesh decimation via OCCTSwiftMesh. Reach for this family when you need a lightweight mesh export, quality metrics on tessellation, or low-polygon LOD versions.

## Entries

[`mesh`](#mesh) · [`simplify-mesh`](#simplify-mesh)

---

## `mesh`

Generate a triangle mesh from a BREP; report counts and quality metrics.

**Input** — flag-form, JSON-form (stdin or file path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputBrep` / `<input.brep>` | string | yes | Path to input BREP file. |
| `linearDeflection` / `--linear-deflection` | number | no | Maximum linear chord deviation (default 0.1). |
| `angularDeflection` / `--angular-deflection` | number | no | Maximum angular deviation in radians (default 0.5). |
| `parallel` / `--parallel` | boolean | no | Use parallel mesh generation (default false). |
| `outputPath` / `--output` | string | no | Write mesh to `.stl` or `.obj` file. Omit to return inline geometry (up to 100K triangles). |
| `returnGeometry` / `--return-geometry` | boolean | no | Inline triangle geometry in response (default true). Ignored if triangle count exceeds 100K or `--output` is supplied. |

**Returns** — JSON envelope with `triangleCount`, `vertexCount`, quality metrics (`minAspectRatio`, `meanAspectRatio`, `degenerateTriangles`, `nonManifoldEdges`), optional inline `geometry` (vertices/indices arrays as `[Float]`/`[UInt32]`), and optional `outputPath`.

**Example**

```bash
occtkit mesh part.brep --linear-deflection 0.05 --parallel
```
```json
{
  "triangleCount": 2450,
  "vertexCount": 1234,
  "quality": {
    "minAspectRatio": 1.08,
    "meanAspectRatio": 2.34,
    "degenerateTriangles": 0,
    "nonManifoldEdges": 0
  },
  "geometry": {
    "vertices": [0.0, 0.0, 0.0, 1.5, 0.2, 0.1, ...],
    "indices": [0, 1, 2, 1, 2, 3, ...]
  },
  "outputPath": null
}
```

**Drives** — `Shape.mesh(parameters:)` (OCCTSwift BRepMesh_IncrementalMesh wrapper); `Exporter.writeSTL` / `writeOBJ` for file output.

**Notes** — Aspect ratio ≥ 1 (longest-edge / shortest-edge per triangle); lower is better. Degenerate triangles have near-zero shortest edge (collinear or repeated vertices). Non-manifold edges are undirected edges shared by != 2 triangles. When triangle count exceeds 100K threshold or `--output` is supplied, inline geometry is suppressed and a file path is returned instead.

---

## `simplify-mesh`

Decimate a mesh to a target triangle count via QEM (quadric error metrics).

**Input** — flag-form, JSON-form (stdin or file path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputBrep` / `<input.brep>` | string | yes | Path to input BREP file. |
| `outputPath` / `--output` | string | yes | Write simplified mesh to `.stl` or `.obj` file. |
| `targetTriangleCount` / `--target-triangle-count` | integer | no | Absolute triangle count target. Exactly one of `targetTriangleCount` or `targetReduction` required. |
| `targetReduction` / `--target-reduction` | number | no | Fraction of triangles to remove (0.0–1.0, e.g., 0.5 removes half). Exactly one of `targetTriangleCount` or `targetReduction` required. |
| `preserveBoundary` / `--preserve-boundary` | boolean | no | Lock boundary edges during decimation (default true). |
| `preserveTopology` / `--preserve-topology` | boolean | no | Prevent changes that alter mesh genus (default true). |
| `maxHausdorffDistance` / `--max-hausdorff-distance` | number | no | Quality gate; abort if achieved Hausdorff error exceeds this distance. |
| `linearDeflection` / `--linear-deflection` | number | no | Linear chord deviation for initial tessellation (default 0.1). |
| `angularDeflection` / `--angular-deflection` | number | no | Angular deviation for initial tessellation in radians (default 0.5). |

**Returns** — JSON envelope with `beforeTriangleCount`, `afterTriangleCount`, `qualityDelta` (meanAspectRatioDelta, hausdorffDistance in input mesh units), and `outputPath`.

**Example**

```bash
occtkit simplify-mesh part.brep --target-reduction 0.7 --preserve-boundary --output part_lod.obj
```
```json
{
  "beforeTriangleCount": 8400,
  "afterTriangleCount": 2520,
  "qualityDelta": {
    "meanAspectRatioDelta": 0.15,
    "hausdorffDistance": 0.08
  },
  "outputPath": "part_lod.obj"
}
```

**Drives** — `Mesh.simplified(_:)` (OCCTSwiftMesh QEM decimator via vendored meshoptimizer).

**Notes** — Exactly one of `--target-triangle-count` or `--target-reduction` must be supplied; the verb will throw if both/neither are present or values are out of valid ranges. Mean aspect ratio delta is post-mesh minus pre-mesh, so positive values indicate quality improvement. Hausdorff distance measures geometric deviation between original and decimated meshes.
