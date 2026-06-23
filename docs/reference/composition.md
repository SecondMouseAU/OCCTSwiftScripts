---
title: Composition
parent: CLI & API Reference
nav_order: 4
---

# Composition

Build BREP models from JSON feature specifications or sheet-metal specs. Both verbs are JSON-driven (request on stdin or file path) and write a BREP output.

## Entries

[`reconstruct`](#reconstruct) · [`compose-sheet-metal`](#compose-sheet-metal)

---

## `reconstruct`

Build a BREP from a JSON `[FeatureSpec]` via FeatureReconstructor.

**Input** — JSON request on stdin or file path. Both forms supported.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `outputDir` | string | yes | Path where the rebuilt BREP is written |
| `outputName` | string | no | File stem (default `"reconstructed"`) |
| `inputBrep` | string | no | Path to a starting BREP. Seeds `BuildContext.current` and registers it under `@input` for boolean/fillet/chamfer references |
| `features` | array | yes | Array of feature entries, each with a `kind` discriminator and snake_case fields |

**Feature kinds and fields** — each feature entry has a `kind` discriminator:

- `revolve` — `id` (string), `profile_points_2d` (array of `[x, y]`), `axis_origin` (`[x, y, z]`), `axis_direction` (`[x, y, z]`), `angle_deg` (number)
- `extrude` — `id`, `profile_points_2d`, `direction` (`[x, y, z]`), `length` (number)
- `hole` — `id`, `center` (`[x, y, z]`), `direction` (`[x, y, z]`), `radius` (number), `depth` (number)
- `thread` — `id`, `spec` (string), `hole_ref` (string), `length` (number, optional)
- `fillet` — `id`, `edges` (array of edge IDs), `radius` (number)
- `chamfer` — `id`, `edges`, `distance` (number)
- `boolean` — `id`, `op` (`"union"` | `"subtract"` | `"intersection"`), `left` (string, often `"@input"`), `right` (string)

**Returns** — JSON object with:
- `shape` — path to output BREP file, or `null` if build failed
- `fulfilled` — array of feature IDs that succeeded
- `skipped` — array of objects with `id`, `stage`, `reason` (`under_determined` | `occt_failure` | `unresolved_ref` | `unsupported`), and optional `detail`
- `annotations` — array of objects with `id`, `kind` (`"thread"`), and optional `detail`

**Example**

```bash
cat > /tmp/revolve.json <<'EOF'
{
  "outputDir": "/tmp/out",
  "outputName": "shaft",
  "features": [
    {
      "kind": "revolve",
      "id": "shaft",
      "profile_points_2d": [[0,0], [10,0], [10,40], [0,40]],
      "axis_origin": [0,0,0],
      "axis_direction": [0,0,1],
      "angle_deg": 360
    }
  ]
}
EOF
reconstruct /tmp/revolve.json
```

```json
{
  "shape": "/tmp/out/shaft.brep",
  "fulfilled": ["shaft"],
  "skipped": [],
  "annotations": []
}
```

**Drives** — `OCCTSwift.FeatureReconstructor.buildJSON(_:inputBody:)` (v0.147+; `inputBody:` parameter added v0.152; `boolean` JSON decoder branch added v0.152.1).

**Notes** — When `inputBrep` is supplied, hole/fillet/chamfer entries cut/finish the loaded body directly; additive features (extrude/revolve) union onto it. Use `{"kind":"boolean","op":"subtract","left":"@input","right":<id>}` entries to express non-circular pocket cuts that reference the seeded body.

---

## `compose-sheet-metal`

Compose a sheet-metal BREP from a JSON spec via SheetMetal.Builder.

**Input** — JSON request on stdin or file path. Both forms supported.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `outputDir` | string | yes | Path where the composed BREP is written |
| `outputName` | string | no | File stem (default `"sheet-metal"`) |
| `thickness` | number | yes | Sheet thickness |
| `flanges` | array | yes | Array of flange objects, each with `id` (string), `profile` (array of `[x, y]` points), `origin` (`[x, y, z]`), `uAxis` (`[x, y, z]`), `vAxis` (`[x, y, z]`, optional; defaults to cross(`normal`, `uAxis`)), `normal` (`[x, y, z]`) |
| `bends` | array | no | Array of bend objects, each with `from` (flange id), `to` (flange id), `radius` (number). Defaults to `[]` |

**Returns** — JSON object with:
- `shape` — absolute path to output BREP file
- `flanges` — count of flanges composed
- `bends` — count of bends applied

**Example**

```bash
cat > /tmp/channel.json <<'EOF'
{
  "outputDir": "/tmp/out",
  "outputName": "u_channel",
  "thickness": 2.0,
  "flanges": [
    {
      "id": "base",
      "profile": [[0,0], [100,0], [100,50], [0,50]],
      "origin": [0,0,0],
      "uAxis": [1,0,0],
      "normal": [0,0,1]
    },
    {
      "id": "left_wall",
      "profile": [[0,0], [0,50], [25,50], [25,0]],
      "origin": [0,0,0],
      "uAxis": [0,1,0],
      "normal": [-1,0,0]
    }
  ],
  "bends": [
    {"from": "base", "to": "left_wall", "radius": 2.0}
  ]
}
EOF
compose-sheet-metal /tmp/channel.json
```

```json
{
  "shape": "/tmp/out/u_channel.brep",
  "flanges": 2,
  "bends": 1
}
```

**Drives** — `OCCTSwift.SheetMetal.Builder(thickness:).build(flanges:bends:)` (v0.151+; bend step awareness added v0.153).

**Notes** — Kept separate from `reconstruct` because SheetMetal lives in its own upstream namespace. The split also reserves room for the planned reverse direction (bent BREP → flat cutting pattern).
