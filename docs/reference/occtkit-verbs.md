---
title: occtkit verb reference
nav_order: 1
parent: Reference
---

# `occtkit` verb reference

`occtkit` is a single multi-call (busybox-style) binary that bundles **29 headless
verbs**. Every verb is grounded in a `Subcommand` type under
[`Sources/occtkit/Commands/`](https://github.com/SecondMouseAU/OCCTSwiftScripts/tree/main/Sources/occtkit/Commands).
This page documents each verb's purpose, its JSON / flag inputs, the JSON it writes
to stdout, and a runnable CLI example.

## Invocation styles

A verb can be invoked four ways (all equivalent):

```bash
occtkit graph-validate body.brep              # umbrella binary + verb
graph-validate body.brep                       # installed per-verb symlink (make install)
swift run occtkit graph-validate body.brep     # from a checkout, no install
```

Every verb also accepts:

- **Flag form** — positional paths + `--flags` as documented per verb below.
- **JSON form** — a JSON request on **stdin**, or a `*.json` file path as the first argv.
- **`--serve` mode** — a JSONL request loop: each stdin line is `{"args":[...]}` and
  the response is one JSONL envelope per request:
  `{"ok":bool,"exit":int,"stdout":str,"stderr":str,"error":str?}`. The subcommand's own
  stdout/stderr (including child-process output) is captured *into* the envelope, not
  leaked. This is how [OCCTMCP](https://github.com/SecondMouseAU/OCCTMCP) drives occtkit.

```bash
# --serve: one envelope per request line
printf '{"args":["a.brep"]}\n{"args":["b.brep"]}\n' | occtkit graph-validate --serve
```

`occtkit --help` prints every verb with its one-line summary.

> Stable topology IDs. Many verbs reference faces/edges/vertices by the canonical
> `face[N]` / `edge[N]` / `vertex[N]` scheme, where `N` is the index in
> `Shape.faces()` / `.edges()` / `.vertices()` iteration order. These indices are
> deterministic for a given BREP file, so an ID returned by `query-topology` can be
> fed straight into `render-preview --highlight` or `feature-recognize`'s `topologyRefs`.

---

## Verb index

| Domain | Verbs |
|---|---|
| Script host | [`run`](#run) |
| Topology graph | [`graph-validate`](#graph-validate), [`graph-compact`](#graph-compact), [`graph-dedup`](#graph-dedup), [`graph-query`](#graph-query), [`graph-ml`](#graph-ml), [`graph-select`](#graph-select) |
| Introspection | [`feature-recognize`](#feature-recognize), [`metrics`](#metrics), [`query-topology`](#query-topology), [`measure-distance`](#measure-distance), [`measure-deviation`](#measure-deviation) |
| Drawings & export | [`dxf-export`](#dxf-export), [`drawing-export`](#drawing-export) |
| Composition | [`reconstruct`](#reconstruct), [`compose-sheet-metal`](#compose-sheet-metal) |
| Construction | [`transform`](#transform), [`boolean`](#boolean), [`pattern`](#pattern) |
| I/O | [`load-brep`](#load-brep), [`import`](#import) |
| Engineering analysis | [`check-thickness`](#check-thickness), [`analyze-clearance`](#analyze-clearance), [`heal`](#heal) |
| Mesh | [`mesh`](#mesh), [`simplify-mesh`](#simplify-mesh) |
| Render | [`render-preview`](#render-preview) |
| XCAF | [`inspect-assembly`](#inspect-assembly), [`set-metadata`](#set-metadata) |

---

## Script host

### `run`

Run an arbitrary user `.swift` file as an OCCTSwift script, via a cached SPM workspace
under `~/.occtswift-scripts/runner-cache/workspace/`. The script links `ScriptHarness`
(resolved as a path dep from `$OCCTKIT_SCRIPTS_PATH`, else auto-detected from the binary,
else the published tag).

**Flags:** `--format <list>` (any of `brep`, `step`, `graph-json`, `graph-sqlite`;
default `brep,step`) · `--output, -o <dir>` (copy the output dir after the run).

When `graph-json` / `graph-sqlite` are requested, `try ctx.addGraphsForAllShapes(...)`
is injected before `emit`. When `step` is absent, `ScriptContext(exportSTEP: false)` is used.

```bash
occtkit run recipes/01-mounting-bracket/main.swift --format brep,graph-sqlite --output /tmp/out
```

---

## Topology graph

### `graph-validate`

Validate a BREP's topology graph and surface a structured health record.

**Input:** `graph-validate <shape.brep>`
**Output:** `{ isValid, errorCount, warningCount, healthRecord }` where `healthRecord`
carries `{ isValid, shapeType, freeEdgeCount, nakedVertexCount, smallEdgeCount,
smallFaceCount, selfIntersecting, errors }` (populated from `Shape.analyze()`;
`nakedVertexCount` is always `0` — OCCTSwift does not expose it).

```bash
graph-validate body.brep
```

### `graph-compact`

Compact a graph (drop unreferenced nodes) and write a rebuilt BREP.

**Input:** `graph-compact <in.brep> <out.brep>`
**Output:** a compaction report `{ nodesBefore, ... , output }`.

```bash
graph-compact in.brep out.brep
```

### `graph-dedup`

Deduplicate shared surface/curve geometry and write a rebuilt BREP.

**Input:** `graph-dedup <in.brep> <out.brep>`
**Output:** a dedup report including `output`.

```bash
graph-dedup in.brep out.brep
```

### `graph-query`

Emit a JSON topology summary from a **BREPGraph SQLite** database (the `.sqlite` produced
by `ScriptContext.addGraph(..., sqlite: true)` / `occtkit run --format graph-sqlite`).

**Input:** `graph-query <graph.sqlite>`
**Output:** `{ summary{solids,shells,faces,wires,edges,vertices,coedges,boundaryEdges,
nonManifoldEdges,degenerateEdges,openShells}, counts{freeEdges,openWires,facesWithHoles},
valence{face,vertex} }`.

```bash
graph-query graph.sqlite
```

### `graph-ml`

Export the topology graph plus UV-grid face samples and edge-curve samples as
ML-friendly JSON (UV-Net / B-rep GNN feature export, via `OCCTSwiftIO`).

**Input:** `graph-ml <shape.brep> [--uv-samples N] [--edge-samples N]`
(defaults: `--uv-samples 16`, `--edge-samples 32`).
**Output:** `{ vertexPositions, edgeBoundaryFlags, edgeManifoldFlags, faceAdjacentFaces,
faceToFace, faceToEdge, edgeToVertex, faces[], edges[], faceAdjacency[], sampling }` —
COO adjacency matrices, per-face position/normal/curvature grids, and a convexity-attributed
face-adjacency graph (`convexity` ∈ `convex|concave|smooth`).

```bash
graph-ml part.brep --uv-samples 16 --edge-samples 32 > part.json
```

### `graph-select`

Direct B-rep graph adjacency / selection queries — the "pointer" primitive behind
DSL selectors and B-rep GNN selection (no full graph export needed).

**Input:** `graph-select <shape.brep> --query <type> [ids]`. Queries:
`face-neighbors --face N` · `edge-faces --edge M` · `vertex-edges --vertex K` ·
`face-adjacency` · `edges-class --class boundary|non-manifold|seam|degenerate`.
Face indices follow `shape.faces()` order (AAG); edge/vertex indices are TopologyGraph indices.
**Output:** per-query JSON tagged with `query`, e.g. `face-neighbors` returns
`{ face, isPlanar, isVertical, isHorizontal, normal, neighbors[{face,convexity,sharedEdgeCount}] }`.

```bash
graph-select part.brep --query face-neighbors --face 0
graph-select part.brep --query edges-class --class boundary
```

---

## Introspection

### `feature-recognize`

Detect pockets and holes via AAG (Attributed Adjacency Graph) heuristics.

**Input:** `feature-recognize <shape.brep>`
**Output:** `{ pockets[], holes[], features[] }`. Each `features[]` entry has
`{ id, kind ("pocket"|"hole"), confidence (1.0 — rule-based), params, topologyRefs }`,
where `topologyRefs` use the `face[N]` scheme.

```bash
feature-recognize bracket.brep
```

### `metrics`

Volume / surface area / centre of mass / bounding box / principal axes for a BREP.
Pure read, no file output. `volume`, `centerOfMass`, `principalAxes` come from
`Shape.volumeInertia` (solid-only; `null` otherwise).

**Flag form:** `metrics <input.brep> [--metrics volume,surfaceArea,centerOfMass,boundingBox,boundingBoxOptimal,principalAxes]`
(omit `--metrics` for all except `boundingBoxOptimal`, which is opt-in).
**JSON form:** `{ "inputBrep": "...", "metrics": [...] }`
**Output:** `{ volume?, surfaceArea?, centerOfMass?, boundingBox?, boundingBoxOptimal?, principalAxes? }`.

```bash
metrics part.brep --metrics volume,boundingBox
echo '{"inputBrep":"part.brep"}' | occtkit metrics
```

### `query-topology`

Find faces / edges / vertices matching criteria; return stable IDs for downstream calls.

**Flag form:** `query-topology <input.brep> --entity face|edge|vertex [--filter '<json>'] [--limit N]`
**JSON form:** `{ "inputBrep": "...", "entity": "face", "filter": {...}, "limit": N }`
**Filter keys (all optional, AND-combined):** `surfaceType` (face), `curveType` (edge),
`minArea`/`maxArea`, `minLength`/`maxLength`, `normalDirection`+`normalTolerance`.
**Output:** `{ entity, results[{id,surfaceType?,curveType?,area?,length?,centerOfMass,normal?,boundingBox}], total, truncated }`.

```bash
query-topology part.brep --entity face --filter '{"surfaceType":"cylinder"}' --limit 50
```

### `measure-distance`

Minimum distance and contacts between two BREPs (or a BREP and a point). Wraps
`Shape.allDistanceSolutions(to:maxSolutions:)`.

**Flag form:** `measure-distance <a.brep> <b.brep> [--from-ref <ref>] [--to-ref <ref>] [--compute-contacts]`.
Refs (v1): `point:x,y,z` or omit for the whole shape.
**JSON form:** `{ "a": "...", "b": "...", "fromRef": "...", "toRef": "...", "computeContacts": true }`
**Output:** `{ minDistance, isParallel, contacts[{fromPoint,toPoint,distance}] }`.

```bash
measure-distance a.brep b.brep --compute-contacts
```

### `measure-deviation`

Directed + symmetric surface deviation (one-sided / symmetric Hausdorff) between two
BREPs — the fidelity metric a mesh→analytic reconstruction check needs. Mesh-based
(tessellate both, project samples onto triangles).

**Flag form:** `measure-deviation <a.brep> <b.brep> [--deflection D] [--max-samples N]`
(`--deflection` default: 0.5% of the a-shape bbox diagonal; `--max-samples` default 20000).
**JSON form:** `{ "a": "...", "b": "...", "deflection": D, "maxSamples": N }`
**Output:** `{ deflection, fromToTo{max,rms,mean,worstPoint,samples}, toToFrom{...}, symmetricHausdorff }`.

```bash
measure-deviation source.brep reconstructed.brep --deflection 0.05
```

---

## Drawings & export

### `dxf-export`

Project a BREP along a view direction (hidden-line-removed) and write a single-view
DXF R12. Wraps `Exporter.writeDXF(shape:to:viewDirection:deflection:)`.

**Input:** `dxf-export <shape.brep> <out.dxf> [--view x,y,z] [--deflection D]`
(`--view` default `0,0,1` top-down; `--deflection` default `0.1`).
**Output:** `{ output, view, deflection }`.

```bash
dxf-export bracket.brep bracket.dxf --view 0,0,1
```

<!-- drawing-export TODO: embed the rendered DXF preview for bracket.dxf -->

### `drawing-export`

Compose a complete **ISO 128-30 multi-view technical drawing** as DXF R12 — ISO 5457
border + centring marks, ISO 7200 title block, ISO 5456-2 projection symbol, HLR
orthographic views, auto-hatched section views (ISO 128-50), cutting-plane lines
(ISO 128-40), auto-centerlines/centermarks, ISO 6410 cosmetic threads, ISO 1302
surface-finish symbols, ISO 1101 GD&T frames, detail views, and user dimensions.
CLI wrapper around the `DrawingComposer` library's `Composer.render(spec:shape:)`.

**Input:** a `DrawingSpec` JSON on stdin or a file path. The CLI additionally requires
`shape` (path to BREP) and `output` (path for the DXF) inside the spec. See
[DrawingComposer.md](DrawingComposer.md) for the full schema.
**Output:** `{ output, sheet, projection, scale, viewCount, sectionCount, detailCount }`.

```bash
echo '{"shape":"part.brep","output":"sheet.dxf","sheet":{"size":"a3","orientation":"landscape","projection":"third","scale":"auto"},"title":{"title":"Part"},"views":[{"name":"front"},{"name":"top"},{"name":"right"}]}' | drawing-export
```

<!-- drawing-export TODO: embed sheet.dxf rendered to PNG -->

---

## Composition

### `reconstruct`

Build a BREP from a JSON `[FeatureSpec]` payload via OCCTSwift's `FeatureReconstructor`.

**Request schema (JSON object):** `outputDir` (required), `outputName?` (default
`"reconstructed"`), `inputBrep?` (a starting body, registered under `@input` for
boolean/fillet/chamfer references), `features[]` — each with a `kind` discriminator
(`revolve` | `extrude` | `hole` | `thread` | `fillet` | `chamfer` | `boolean`) and
snake_case fields.
**Output:** `{ shape: "<path>.brep"|null, fulfilled[], skipped[{id,stage,reason,detail}], annotations[{id,kind,detail}] }`.
Exit code `2` when no shape was produced from a non-empty feature list.

```bash
echo '{"outputDir":"/tmp/out","outputName":"shaft","features":[{"kind":"revolve","id":"shaft","profile_points_2d":[[0,0],[10,0],[10,40],[0,40]],"axis_origin":[0,0,0],"axis_direction":[0,0,1],"angle_deg":360}]}' | reconstruct
```

### `compose-sheet-metal`

Compose a sheet-metal BREP from a JSON spec via OCCTSwift's `SheetMetal.Builder`.

**Request schema:** `outputDir` (required), `outputName?` (default `"sheet-metal"`),
`thickness`, `flanges[{id,profile:[[x,y]...],origin:[x,y,z],uAxis:[x,y,z],vAxis?:[x,y,z],normal:[x,y,z]}]`,
`bends?[{from,to,radius}]`.
**Output:** `{ shape, flanges, bends }`.

```bash
echo '{"outputDir":"/tmp/out","thickness":2,"flanges":[{"id":"base","profile":[[0,0],[60,0],[60,40],[0,40]],"origin":[0,0,0],"uAxis":[1,0,0],"normal":[0,0,1]}]}' | compose-sheet-metal
```

---

## Construction

### `transform`

Apply translate → rotate → uniform-scale to a BREP, in declared order. Writes a new BREP.
(OCCTSwift's `scaled(by:)` is uniform-only; non-uniform scale is rejected.)

**Flag form:** `transform <input.brep> --output <out.brep> [--translate x,y,z]
[--rotate-axis-angle x,y,z,radians | --rotate-euler-xyz x,y,z] [--scale s]`
(axis-angle and euler are mutually exclusive).
**JSON form:** `{ "inputBrep": "...", "outputPath": "...", "translate": [x,y,z],
"rotateAxisAngle": [x,y,z,rad] | "rotateEulerXyz": [x,y,z], "scale": s|[x,y,z] }`
**Output:** `{ outputPath, trsf: [16 floats — column-major 4×4] }`.

```bash
transform in.brep --output out.brep --translate 10,0,0 --rotate-axis-angle 0,0,1,1.5708
```

### `boolean`

Boolean op (`union` | `subtract` | `intersect` | `split`) between two BREPs. `split`
wraps its pieces in a compound.

**Flag form:** `boolean --op <op> --a <a.brep> --b <b.brep> --output <out.brep>`
**JSON form:** `{ "op": "...", "a": "...", "b": "...", "outputPath": "..." }`
**Output:** `{ outputPath, volume?, isValid, warnings[] }`.

```bash
boolean --op subtract --a block.brep --b hole.brep --output cut.brep
```

### `pattern`

Mirror / linear / circular pattern of a BREP, written as one BREP per instance
(`pattern_0.brep`, `pattern_1.brep`, ...) into `--output-dir`.

**Flag form:** `pattern <input.brep> --kind mirror|linear|circular --output-dir <dir> [kind flags]`
— mirror: `--plane xy|yz|zx | --plane ox,oy,oz;nx,ny,nz`; linear: `--direction x,y,z --spacing s --count n`;
circular: `--axis-origin x,y,z --axis-direction x,y,z --total-count n [--total-angle radians]`.
**JSON form:** `{ "inputBrep": "...", "kind": "...", "outputDir": "...", ... }`
**Output:** `{ outputPaths[], totalCount }`.

```bash
pattern bolt.brep --kind circular --axis-origin 0,0,0 --axis-direction 0,0,1 --total-count 6 --output-dir /tmp/bolts
```

---

## I/O

### `load-brep`

Load a `.brep` and write a single-body `ScriptManifest` (`<id>.brep` + `manifest.json`)
so OCCTSwiftViewport's ScriptWatcher picks it up — a no-compile equivalent of a one-line
`ctx.add(...) + ctx.emit(...)` script.

**Flag form:** `load-brep <input.brep> --emit-manifest <dir> [--id <bodyId>] [--color <hex>] [--allow-invalid]`
**JSON form:** `{ "inputBrep": "...", "emitManifest": "...", "id": "...", "color": "#rrggbb|#rrggbbaa", "allowInvalid": bool }`
**Output:** `{ bodyId, isValid, shapeType, faceCount, edgeCount, vertexCount, boundingBox{min,max} }`.

```bash
load-brep part.brep --emit-manifest ~/.occtswift-scripts/output --color "#7799bb"
```

### `import`

Multi-format CAD import (STEP / IGES / STL / OBJ); writes one BREP per top-level body +
a manifest. `--preserve-assembly` (STEP only) walks the XCAF assembly tree.

**Flag form:** `import <input> --emit-manifest <dir> [--format auto|step|iges|stl|obj]
[--id-prefix <p>] [--preserve-assembly] [--heal-on-import] [--allow-invalid]`
(`--heal-on-import` is accepted but currently a no-op with a warning).
**JSON form:** `{ "inputPath": "...", "emitManifest": "...", "format": "...", "idPrefix": "...", "preserveAssembly": bool, ... }`
**Output:** `{ addedBodyIds[], assembly{rootId,components[...]}|null, warnings[] }`.

```bash
import widget.step --emit-manifest /tmp/out --preserve-assembly
```

---

## Engineering analysis

### `check-thickness`

Wall-thickness analysis: sample each face on a UV grid, cast an inward ray, report
min / max / mean thickness and flag thin regions. Pure read.

**Flag form:** `check-thickness <input.brep> [--min-acceptable d] [--sampling-density coarse|medium|fine]`
(grid 4 / 8 / 16; default `medium`).
**JSON form:** `{ "inputBrep": "...", "minAcceptable": d, "samplingDensity": "..." }`
**Output:** `{ minThickness?, maxThickness?, meanThickness?, thinRegions[{centerPoint,thickness,faceRefs}], samples }`.

```bash
check-thickness shell.brep --min-acceptable 1.5 --sampling-density fine
```

### `analyze-clearance`

Pairwise interference / minimum-clearance check between two or more BREPs. When a pair's
min distance is 0, also reports the interference volume (solid×solid).

**Flag form:** `analyze-clearance <a.brep> <b.brep> [<c.brep>...] [--min-clearance d] [--max-contacts N] [--no-contacts]`
**JSON form:** `{ "inputs": ["a.brep","b.brep",...], "minClearance": d, "maxContacts": N, "computeContacts": bool }`
**Output:** `{ pairs[{a,b,minDistance,intersects,belowMinClearance?,contacts[],interferenceVolume?}] }`.

```bash
analyze-clearance shaft.brep housing.brep --min-clearance 0.5
```

### `heal`

Heal imported / non-watertight geometry via OCCTSwift's `ShapeFixer`. Writes a new BREP
and reports before/after stats. (Per-fix `--fix-*` flags are accepted for forward
compatibility but currently coalesce into precision tuning.)

**Flag form:** `heal <input.brep> --output <out.brep> [--tolerance d] [--max-tolerance d]
[--min-tolerance d] [--fix-small-edges] [--fix-small-faces] [--fix-gaps]
[--fix-self-intersection] [--fix-orientation] [--unify-domain]`
**JSON form:** `{ "inputBrep": "...", "outputPath": "...", "tolerance": d, ... }`
**Output:** `{ outputPath, before{...}, after{...}, fixes{smallEdgesFixed,smallFacesFixed,freeEdgesClosed,selfIntersectionsResolved}, warnings[] }`.

```bash
heal imported.brep --output healed.brep --tolerance 0.01
```

---

## Mesh

### `mesh`

Generate a triangle mesh from a BREP via `BRepMesh_IncrementalMesh`; report counts +
quality metrics. Geometry is returned inline up to 100K triangles, else written to
`--output` (`.stl` / `.obj`).

**Flag form:** `mesh <input.brep> [--linear-deflection d] [--angular-deflection d]
[--parallel] [--output <path.stl|.obj>] [--no-return-geometry]`
(defaults: linear `0.1`, angular `0.5`).
**JSON form:** `{ "inputBrep": "...", "linearDeflection": d, "angularDeflection": d, "parallel": bool, "outputPath": "...", "returnGeometry": bool }`
**Output:** `{ triangleCount, vertexCount, quality{minAspectRatio,meanAspectRatio,degenerateTriangles,nonManifoldEdges}, geometry?{vertices,indices}, outputPath? }`.

```bash
mesh part.brep --linear-deflection 0.05 --output part.stl
```

### `simplify-mesh`

QEM mesh decimation to a target triangle count, via `OCCTSwiftMesh`'s `Mesh.simplified(_:)`.

**Flag form:** `simplify-mesh <input.brep> (--target-triangle-count N | --target-reduction R)
[--preserve-boundary] [--preserve-topology] [--max-hausdorff-distance d]
[--linear-deflection d] [--angular-deflection d] --output <path.stl|.obj>`
**JSON form:** `{ "inputBrep": "...", "outputPath": "...", "targetTriangleCount": N | "targetReduction": R, ... }`
**Output:** `{ beforeTriangleCount, afterTriangleCount, qualityDelta{meanAspectRatioDelta,hausdorffDistance}, outputPath }`.

```bash
simplify-mesh part.brep --target-reduction 0.5 --output part-lod.obj
```

---

## Render

### `render-preview`

Render a PNG preview of one or more BREPs at a named camera angle, headless, via
OCCTSwiftViewport's `OffscreenRenderer`. **This repo owns `render-preview`** — it is the
ecosystem's way to embed 3D previews in docs and reports.

**Flag form:** `render-preview <brep>... --output <png>
[--camera iso|front|back|top|bottom|left|right]
[--camera-position x,y,z --camera-target x,y,z [--camera-up x,y,z]]
[--width N] [--height N]
[--display-mode shaded|wireframe|shaded-with-edges|flat|xray|rendered]
[--background light|dark|transparent|#hex]
[--show-axes] [--axes-position origin|center|outside|x,y,z]
[--show-workplane xy|yz|xz]
[--highlight face[N],edge[M],vertex[K]] [--highlight-color #hex]`
(defaults: `--camera iso`, `--width 800`, `--height 600`, `--display-mode shaded`,
`--background light`).
**JSON form:** `{ "inputs": ["a.brep",...], "outputPath": "...", "camera": "iso", "width": N, ... }`
**Output:** `{ outputPath, width, height, mimeType: "image/png" }`.

```bash
render-preview part.brep --output part.png --camera iso --display-mode shaded-with-edges
render-preview part.brep --output hl.png --highlight 'face[3],edge[7]' --highlight-color '#ffa500'
```

<!-- 3D render TODO: render-preview output for part.png -->

---

## XCAF

### `inspect-assembly`

Walk an XCAF document's assembly tree and report hierarchy + per-component metadata.
Inputs auto-detected by extension: `.step`/`.stp` and `.xbf` (OCAF binary) carry the tree;
`.brep` returns a degenerate single-node response.

**Flag form:** `inspect-assembly <input> [--depth N]`
**JSON form:** `{ "inputPath": "...", "depth": N }`
**Output:** `{ root{id,name,isAssembly,transform,color?,...,children[],referredTo?}, totalComponents, totalInstances, totalReferences }`.
Stable label IDs are `label_<int64>` and round-trip into `set-metadata --component-id`.

```bash
inspect-assembly gearbox.step --depth 3
```

### `set-metadata`

Write document- or component-level XCAF metadata onto an OCAF document and save it as
`.xbf`. (STEP write-back is not done in v1.) Title-block keys at document scope:
`title / drawnBy / material / weight / revision / partNumber`.

**Flag form:** `set-metadata <input> --output <out.xbf> [--scope document|component]
[--component-id <int64>] [--title <s>] [--drawn-by <s>] [--material <s>] [--weight <n>]
[--revision <s>] [--part-number <s>] [--custom-attr key=value]` (repeatable).
**JSON form:** `{ "inputPath": "...", "outputPath": "...", "scope": "document", "title": "...", "customAttrs": {"k":"v"} }`
**Output:** `{ outputPath, applied{key:value} }`.

```bash
set-metadata gearbox.step --output gearbox.xbf --title "Gearbox" --material "EN-GJL-250" --revision B
```
