---
title: I/O
parent: CLI & API Reference
nav_order: 7
---

# I/O

Load BREP files and multi-format CAD imports into the geometry workspace; both verbs write a `ScriptManifest` into `--emit-manifest` so OCCTSwiftViewport's ScriptWatcher picks them up. Use when ingesting existing geometry or bringing in STEP/IGES/STL/OBJ models.

## Entries

[`load-brep`](#load-brep) · [`import`](#import)

---

## `load-brep`

Load a `.brep` file and emit a manifest entry for OCCTSwiftViewport.

**Input** — Flag form or JSON form (stdin or argv path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputBrep` / `--emit-manifest` | string | yes | Path to the `.brep` file to load; manifest output directory. |
| `--id` / `id` | string | no | Body ID to assign; auto-generated from filename if omitted. |
| `--color` / `color` | string | no | Hex colour `#rrggbb` or `#rrggbbaa` (0–255 per channel); omit for default. |
| `--allow-invalid` / `allowInvalid` | boolean | no | Load a topologically invalid shape as-is; default `false`. |

**Returns** — JSON envelope with `bodyId`, `isValid`, `shapeType` (lowercase: `solid`, `shell`, `compound`, `face`, `wire`, `edge`, `vertex`), `faceCount`, `edgeCount`, `vertexCount`, `boundingBox` (`{ min: [...], max: [...] }`). Side effect: writes `<bodyId>.brep` and `manifest.json` to `--emit-manifest` directory.

**Example**

```bash
occtkit load-brep /tmp/part.brep --emit-manifest /tmp/output --id mypart --color "#a0a0c0"
```

```json
{
  "bodyId": "mypart",
  "isValid": true,
  "shapeType": "solid",
  "faceCount": 6,
  "edgeCount": 12,
  "vertexCount": 8,
  "boundingBox": {
    "min": [0.0, 0.0, 0.0],
    "max": [100.0, 50.0, 25.0]
  }
}
```

**Drives** — `GraphIO.loadBREP` + `GraphIO.writeBREP` + `ScriptManifest` emission.

---

## `import`

Multi-format CAD import (STEP / IGES / STL / OBJ); writes bodies to manifest for OCCTSwiftViewport.

**Input** — Flag form or JSON form (stdin or argv path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputPath` / (positional) | string | yes | Path to the input file. |
| `--emit-manifest` / `emitManifest` | string | yes | Manifest output directory. |
| `--format` / `format` | enum | no | One of `auto` \| `step` \| `iges` \| `stl` \| `obj`; default `auto` (inferred from extension). |
| `--id-prefix` / `idPrefix` | string | no | Prefix for auto-generated body IDs; default `"imported"`. |
| `--preserve-assembly` / `preserveAssembly` | boolean | no | Walk XCAF tree and write one BREP per leaf node with names/transforms/colors (STEP only); default `false`. |
| `--heal-on-import` / `healOnImport` | boolean | no | Accepted in v1 but currently no-op with warning; real behaviour arrives with the `heal` verb. Default `false`. |
| `--allow-invalid` / `allowInvalid` | boolean | no | Load topologically invalid shapes as-is; default `false`. |

**Returns** — JSON envelope with `addedBodyIds` (string array of body IDs written), `assembly` (object with `rootId` and `components` tree, or `null` if `--preserve-assembly` was not set or file is not STEP), `warnings` (string array). Side effect: writes one `<id>.brep` per body and `manifest.json` to `--emit-manifest` directory.

**Example**

```bash
occtkit import /tmp/bracket.step --emit-manifest /tmp/output --preserve-assembly --id-prefix bracket
```

```json
{
  "addedBodyIds": ["bracket_0", "bracket_1", "bracket_2"],
  "assembly": {
    "rootId": "bracket_root",
    "components": [
      {
        "id": "bracket_0",
        "name": "base",
        "transform": [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0],
        "color": [0.8, 0.8, 0.8, 1.0],
        "children": []
      }
    ]
  },
  "warnings": []
}
```

**Drives** — Format dispatch via `Shape.loadSTEP` / `Shape.loadIGES` / `Shape.loadSTL` / `Shape.loadOBJ`; assembly walk via `Document.loadSTEP` + `AssemblyNode` tree; `ScriptManifest` emission.

**Notes** — `--preserve-assembly` is STEP-only for v1; passing it with non-STEP files emits a warning and falls back to single-body import. Transform field is a 4×4 column-major matrix flattened to 16 floats. `--heal-on-import` is a forward-compatibility placeholder; the actual heal logic is deferred (see `heal` verb in [Engineering analysis](engineering.md)).
