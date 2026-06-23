---
title: Construction
parent: CLI & API Reference
nav_order: 5
---

# Construction

Pure functions that modify BREP geometry: translate, rotate, scale, apply boolean set operations, and generate mirror/pattern instances. Reach for these when you need geometric mutation without features or assemblies.

## Entries

[`transform`](#transform) · [`boolean`](#boolean) · [`pattern`](#pattern)

---

## `transform`

Apply translation, rotation (axis-angle or Euler XYZ), and/or uniform scale to a BREP.

**Input** — flag-form, JSON-form (stdin or file path), or both. Supports `--serve`.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `--output` / `outputPath` | string | yes | Output BREP path. |
| `--translate` / `translate` | number[3] | no | Translation vector `[dx, dy, dz]` in mm. |
| `--rotate-axis-angle` / `rotateAxisAngle` | number[4] | no | Axis-angle rotation `[axisX, axisY, axisZ, radians]`. |
| `--rotate-euler-xyz` / `rotateEulerXyz` | number[3] | no | Euler rotation `[rx, ry, rz]` in radians; extrinsic XYZ order. |
| `--scale` / `scale` | number | no | Uniform scale factor (non-uniform rejected). |

**Returns** — `{ "outputPath": "...", "trsf": [16 floats] }` where `trsf` is the column-major 4×4 transformation matrix. Transforms compose in order: translate → rotateAxisAngle → rotateEulerXyz → scale.

**Example**

```bash
occtkit transform in.brep --output out.brep --translate 10,20,30 --rotate-axis-angle 0,0,1,1.5708 --scale 2.0
```
```json
{ "ok": true, "outputs": ["out.brep"], "trsf": [2.0, 0, 0, 0, ...] }
```

**Drives** — `OCCTSwift.Shape.translated` / `.rotated` / `.scaled`.

**Notes** — OCCTSwift's `scaled(by:)` is uniform-only; non-uniform `--scale x,y,z` fails with a clear error. Euler XYZ decomposes to three sequential axis-angle rotations (around X, then Y, then Z).

---

## `boolean`

Boolean set operation (union, subtract, intersect, split) between two BREPs.

**Input** — flag-form, JSON-form (stdin or file path), or both. Supports `--serve`.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `--op` / `op` | enum | yes | Operation: one of `union` \| `subtract` \| `intersect` \| `split`. |
| `--a` / `a` | string | yes | Path to the first (base) BREP. |
| `--b` / `b` | string | yes | Path to the second (tool) BREP. |
| `--output` / `outputPath` | string | yes | Output BREP path. |

**Returns** — `{ "outputPath": "...", "volume": <double|null>, "isValid": <bool>, "warnings": [<string>...] }`. Volume is `null` for non-solid results (compounds, open shells). Split wraps its pieces in a compound; downstream consumers decompose via `Shape.subShapes` if needed.

**Example**

```bash
occtkit boolean --op union --a base.brep --b tool.brep --output result.brep
```
```json
{ "ok": true, "outputPath": "result.brep", "volume": 1250.5, "isValid": true, "warnings": [] }
```

**Drives** — `OCCTSwift.Shape.union` / `.subtracting` / `.intersection` / `.split`.

**Notes** — Split that produces a single piece emits a warning. Non-manifold inputs and non-intersecting geometries surface as errors.

---

## `pattern`

Mirror through a plane, or create a linear or circular pattern, decomposing the result into individual BREP files.

**Input** — flag-form, JSON-form (stdin or file path), or both. Supports `--serve`.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `--kind` / `kind` | enum | yes | Pattern type: one of `mirror` \| `linear` \| `circular`. |
| `--output-dir` / `outputDir` | string | yes | Output directory. |
| `--plane` / `plane` | string | no | (mirror only) Preset plane `xy` \| `yz` \| `zx`, or explicit `ox,oy,oz;nx,ny,nz` (origin; normal). |
| `--planeOrigin` | number[3] | no | (mirror only, JSON) Plane origin `[x, y, z]`. Defaults to `[0, 0, 0]`. |
| `--planeNormal` | number[3] | no | (mirror only, JSON) Plane normal `[nx, ny, nz]`. Required if `plane` not set. |
| `--direction` / `direction` | number[3] | no | (linear only) Direction vector `[dx, dy, dz]`. |
| `--spacing` / `spacing` | number | no | (linear only) Distance between instances. |
| `--count` / `count` | integer | no | (linear only) Number of instances (≥ 1). |
| `--axis-origin` / `axisOrigin` | number[3] | no | (circular only) Axis origin `[x, y, z]`. |
| `--axis-direction` / `axisDirection` | number[3] | no | (circular only) Axis direction `[x, y, z]`. |
| `--total-count` / `totalCount` | integer | no | (circular only) Total number of instances (≥ 1). |
| `--total-angle` / `totalAngle` | number | no | (circular only) Total rotation in radians. Defaults to 0 (complete circle: 2π / totalCount per instance). |

**Returns** — `{ "outputPaths": ["pattern_0.brep", "pattern_1.brep", ...], "totalCount": <int> }`. Each pattern instance is written as `pattern_N.brep` in the output directory.

**Example**

```bash
occtkit pattern in.brep --kind linear --output-dir /tmp/pattern --direction 1,0,0 --spacing 50 --count 3
```
```json
{ "ok": true, "outputPaths": ["/tmp/pattern/pattern_0.brep", "/tmp/pattern/pattern_1.brep", "/tmp/pattern/pattern_2.brep"], "totalCount": 3 }
```

**Drives** — `OCCTSwift.Shape.mirrored` / `.linearPattern` / `.circularPattern`.

**Notes** — Mirror emits one file (`pattern_0.brep`); the original is not re-emitted. Linear and circular patterns decompose the compound result via `subShapes` to recover individual instances. Circular default `totalAngle: 0` means a full 360° circle divided equally among `totalCount` instances.
