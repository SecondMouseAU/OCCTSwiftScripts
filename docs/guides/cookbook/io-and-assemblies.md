---
title: Import, export & assemblies
parent: Cookbook
nav_order: 12
---

# Import, export & assemblies

This recipe walks four headless verbs in the order you'd use them for a real delivery: load a
native BREP into the viewer, import a neutral-format file (STEP / IGES / STL / OBJ), walk the
XCAF assembly tree to discover component IDs, and stamp the document with title-block and per-part
metadata. All four steps produce JSON you can pipe into further verbs.

Full flag and field lists live in the [I/O reference](../../reference/io.md) and the
[XCAF assemblies reference](../../reference/xcaf.md).

---

## 1. Load a native BREP — `load-brep`

The fastest path for geometry that already exists on disk (a previous script run, a Boolean result,
a reconstruction output). One BREP in, one manifest entry out.

```bash
occtkit load-brep /tmp/housing.brep \
  --emit-manifest /tmp/scene \
  --id housing \
  --color "#6670c0"
```

```json
{
  "bodyId": "housing",
  "isValid": true,
  "shapeType": "solid",
  "faceCount": 18,
  "edgeCount": 36,
  "vertexCount": 20,
  "boundingBox": {
    "min": [0.0, 0.0, 0.0],
    "max": [120.0, 60.0, 40.0]
  }
}
```

Side effect: `load-brep` writes `/tmp/scene/housing.brep` and `/tmp/scene/manifest.json`.
OCCTSwiftViewport's ScriptWatcher picks up the manifest automatically; the body appears in the
viewer under the id `"housing"`.

Pass `--allow-invalid` when loading an open shell or a reconstruction draft that hasn't been
healed yet — the validity gate is bypassed and the response's `isValid` field will be `false`.

---

## 2. Import STEP / IGES / STL / OBJ — `import`

`import` handles all four neutral formats. The format is inferred from the file extension unless
you pass `--format` explicitly.

```bash
occtkit import /tmp/bracket_assy.step \
  --emit-manifest /tmp/scene \
  --id-prefix bracket
```

```json
{
  "addedBodyIds": ["bracket_0"],
  "assembly": null,
  "warnings": []
}
```

### Preserving the XCAF assembly structure (STEP only)

Add `--preserve-assembly` to walk the XCAF document tree and write **one BREP per leaf node**,
preserving each component's name, transform, and color in the response.

```bash
occtkit import /tmp/bracket_assy.step \
  --emit-manifest /tmp/scene \
  --id-prefix bracket \
  --preserve-assembly
```

```json
{
  "addedBodyIds": ["bracket_0", "bracket_1", "bracket_2"],
  "assembly": {
    "rootId": "bracket_root",
    "components": [
      {
        "id": "bracket_0",
        "name": "BaseFrame",
        "transform": [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0],
        "color": [0.8, 0.8, 0.8, 1.0],
        "children": []
      },
      {
        "id": "bracket_1",
        "name": "MountingPlate",
        "transform": [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 15.0, 1.0],
        "color": [0.6, 0.6, 0.7, 1.0],
        "children": []
      },
      {
        "id": "bracket_2",
        "name": "Fastener",
        "transform": [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 30.0, 10.0, 0.0, 1.0],
        "color": null,
        "children": []
      }
    ]
  },
  "warnings": []
}
```

The `transform` field is a 4×4 matrix in column-major order (16 floats). `--preserve-assembly` is
STEP-only; passing it with IGES, STL, or OBJ emits a warning and falls back to single-body import.

---

## 3. Walk the XCAF tree — `inspect-assembly`

Before writing metadata you need the stable `label_<int64>` IDs that identify each component.
`inspect-assembly` reads a STEP or `.xbf` file without importing it into the scene.

```bash
occtkit inspect-assembly /tmp/bracket_assy.step --depth 2
```

```json
{
  "root": {
    "id": "label_1",
    "name": "BracketAssembly",
    "isAssembly": true,
    "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    "color": null,
    "material": null,
    "layer": null,
    "children": [
      {
        "id": "label_2",
        "name": "BaseFrame",
        "isAssembly": false,
        "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
        "color": [0.8, 0.8, 0.8, 1.0],
        "material": null,
        "layer": null,
        "children": [],
        "referredTo": null
      },
      {
        "id": "label_3",
        "name": "MountingPlate",
        "isAssembly": false,
        "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 15, 1],
        "color": [0.6, 0.6, 0.7, 1.0],
        "material": null,
        "layer": null,
        "children": [],
        "referredTo": null
      }
    ],
    "referredTo": null
  },
  "totalComponents": 3,
  "totalInstances": 3,
  "totalReferences": 0
}
```

`--depth N` caps the traversal so large assemblies don't flood the terminal. Omit it for an
unlimited walk. The `label_<int64>` IDs are stable for a given document and are the handle you
pass to `set-metadata --component-id` in the next step.

---

## 4. Write metadata — `set-metadata`

`set-metadata` writes title-block fields and arbitrary custom attributes onto the document or a
named component, saving to a new `.xbf` (binary OCAF). The input can be a STEP file or an `.xbf`
from a previous `set-metadata` run — you can chain calls to accumulate metadata.

### Document-level stamp

```bash
occtkit set-metadata /tmp/bracket_assy.step \
  --output /tmp/bracket_meta.xbf \
  --scope document \
  --title "Bracket Assembly" \
  --part-number "BKT-0017" \
  --revision "C" \
  --material "6061-T6 Aluminium" \
  --drawn-by "E. Lynch-Bell" \
  --custom-attr project=OCCTSwift-demo \
  --custom-attr approval=pending
```

```json
{
  "outputPath": "/tmp/bracket_meta.xbf",
  "applied": {
    "title": "Bracket Assembly",
    "drawnBy": "E. Lynch-Bell",
    "material": "6061-T6 Aluminium",
    "revision": "C",
    "partNumber": "BKT-0017",
    "project": "OCCTSwift-demo",
    "approval": "pending"
  }
}
```

### Component-level stamp

Using `label_3` (MountingPlate, discovered in step 3) as the target. Read from the `.xbf` written
above so the document-level stamp is preserved:

```bash
occtkit set-metadata /tmp/bracket_meta.xbf \
  --output /tmp/bracket_meta.xbf \
  --scope component \
  --component-id 3 \
  --title "Mounting Plate" \
  --part-number "MP-0003" \
  --revision "A" \
  --material "304 Stainless Steel" \
  --weight 0.42
```

```json
{
  "outputPath": "/tmp/bracket_meta.xbf",
  "applied": {
    "title": "Mounting Plate",
    "partNumber": "MP-0003",
    "revision": "A",
    "material": "304 Stainless Steel",
    "weight": "0.42"
  }
}
```

Reading from and writing to the same path accumulates metadata in a single file without losing
what was written in earlier passes. Run `inspect-assembly /tmp/bracket_meta.xbf` after each pass
to verify the attributes round-tripped correctly.
