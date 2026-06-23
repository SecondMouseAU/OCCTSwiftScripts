---
title: XCAF assemblies
parent: CLI & API Reference
nav_order: 11
---

# XCAF assemblies

Tools for traversing assembly hierarchies in OCAF documents and writing document- or component-scoped metadata (title blocks, part numbers, custom attributes) back to XCAF-aware formats. Use these when inspecting assembly structure, round-tripping metadata, or stamping documents with revision info.

## Entries

[`inspect-assembly`](#inspect-assembly) · [`set-metadata`](#set-metadata)

---

## `inspect-assembly`

Walk an XCAF document's assembly tree; report names, colors, transforms, and per-component metadata.

**Input** — flag-form, JSON-form (stdin or file path), or `.brep` (degenerate single-node response).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputPath` | string | yes | Path to `.step` / `.stp` / `.xbf` (OCAF binary) file, or `.brep` (produces single-node response since BREPs carry no XCAF metadata). |
| `depth` | integer | no | Maximum tree depth to traverse; omit for unlimited. |

**Returns** — A JSON tree with a synthetic root if multiple top-level shapes exist, or the single top-level `Node` if one root. Each `Node` carries stable `label_<int64>` IDs, names, 4×4 transforms (16-element float array, column-major), optional RGBA colors, `isAssembly` / `isReference` flags, and a `referredTo` field when the node points to another component. Counts of total components, instances, and references at the document scope. Returns an error if the file cannot be loaded.

**Example**

```bash
occtkit inspect-assembly assembly.step --depth 2
```
```json
{
  "root": {
    "id": "label_0",
    "name": "Assembly",
    "isAssembly": true,
    "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    "color": null,
    "material": null,
    "layer": null,
    "children": [
      {
        "id": "label_1",
        "name": "Base",
        "isAssembly": false,
        "transform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
        "color": [0.7, 0.7, 0.8, 1.0],
        "material": null,
        "layer": null,
        "children": [],
        "referredTo": null
      }
    ],
    "referredTo": null
  },
  "totalComponents": 2,
  "totalInstances": 2,
  "totalReferences": 0
}
```

**Drives** — `Document.rootNodes` → `AssemblyNode.children` tree walk; `AssemblyNode.labelId` (stable int64 identifier for round-trip to `set-metadata --component-id`); `AssemblyNode.isReference` / `AssemblyNode.referredNode` for reference tracking.

---

## `set-metadata`

Write document- or component-level XCAF metadata onto an OCAF document; save as `.xbf` (binary OCAF format).

**Input** — flag-form, JSON-form (stdin or file path).

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `inputPath` | string | yes | Path to `.step` / `.stp` / `.xbf` input file. |
| `outputPath` | string | yes | Output `.xbf` path (created if it does not exist). |
| `scope` | `document` \| `component` | no | Scope for metadata write: document-level (title-block fields on the main label) or component-level (on a specific node). Default `document`. |
| `componentId` | integer | no | Stable int64 label ID (from `inspect-assembly` output, e.g., `label_5` → `5`) when `scope=component`. Required if scope is `component`. |
| `title` | string | no | Assembly or component title (stored as `TDataStd_NamedData` at document scope; also sets `TDataStd_Name` when scope is `component`). |
| `drawnBy` | string | no | Author or drafter name. |
| `material` | string | no | Material identifier. |
| `weight` | number | no | Weight value (stored as `TDataStd_Real`). |
| `revision` | string | no | Revision string (e.g., `"B"`, `"2.1"`). |
| `partNumber` | string | no | Part number identifier. |
| `customAttr` | key=value | no | Arbitrary named-string attribute (repeatable; write `--custom-attr key=value --custom-attr k2=v2`). |

**Returns** — The output `.xbf` path and a dictionary of all applied metadata fields (canonical keys + custom attrs) keyed by name. Returns an error if the input file cannot be loaded, the component ID does not exist, or the output path is not writable.

**Example**

```bash
occtkit set-metadata assembly.step --output assembly_meta.xbf \
  --scope document \
  --title "Mounting Bracket" \
  --part-number "MB-0042" \
  --revision "B" \
  --material "6061-T6 Aluminium" \
  --drawn-by "E. Lynch-Bell" \
  --custom-attr project=demo --custom-attr approval=pending
```
```json
{
  "outputPath": "assembly_meta.xbf",
  "applied": {
    "title": "Mounting Bracket",
    "drawnBy": "E. Lynch-Bell",
    "material": "6061-T6 Aluminium",
    "weight": "",
    "revision": "B",
    "partNumber": "MB-0042",
    "project": "demo",
    "approval": "pending"
  }
}
```

**Drives** — `Document.node(at:)` lookup by `componentId` (int64); `AssemblyNode.setNamedString()` / `.setNamedReal()` / `.setName()` to write `TDataStd_NamedData` and `TDataStd_Name` attributes; `Document.defineAllFormats()` and `Document.setStorageFormat("BinXCAF")` to persist XCAF metadata to the binary format.

**Notes** — The output is always `.xbf` (binary OCAF), regardless of input format, because STEP roundtrip via the OCCTSwift exporter does not expose a one-call "write custom named-data" path in v1. Use `inspect-assembly` on the output `.xbf` to verify the metadata round-tripped correctly. Canonical keys (`title`, `drawnBy`, `material`, `weight`, `revision`, `partNumber`) are stored on the document's main label at document scope; custom attrs (via `--custom-attr key=value`) are stored as arbitrary named strings on the same target.
