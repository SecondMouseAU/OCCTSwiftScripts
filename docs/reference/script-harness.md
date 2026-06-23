---
title: Script harness & run
parent: CLI & API Reference
nav_order: 1
---

# Script harness & run

The `ScriptHarness` library — `ScriptContext`, `ManifestMetadata`, `Colors` — is the primary
author API for writing parametric CAD scripts. The `run` verb hosts those scripts headlessly,
caching an SPM workspace and building/executing them on demand.

## Entries

[`ScriptContext`](#scriptcontext-init) · [`add(Shape)`](#addshape) · [`add(Wire)`](#addwire) · [`add(Edge)`](#addedge) · [`addCompound`](#addcompound) · [`addGraph`](#addgraph) · [`addGraphsForAllShapes`](#addgraphsforallshapes) · [`emit`](#emit) · [`ManifestMetadata`](#manifestmetadata) · [`Colors`](#colors) · [`run`](#run)

---

## ScriptContext init

Initialize a script context; accumulates geometry and writes BREP + STEP files to the output
directory on `emit()`.

**Signature**

```swift
ScriptContext(exportSTEP: Bool = true, metadata: ManifestMetadata? = nil)
```

**Parameters**

| name | type | default | description |
|------|------|---------|-------------|
| `exportSTEP` | `Bool` | `true` | Whether to write a combined `output.step` file (disable to skip STEP for speed) |
| `metadata` | `ManifestMetadata?` | `nil` | Optional project metadata (name, revision, tags, notes) written into `manifest.json` |

**What it does** — Creates a new context, cleans the output directory (iCloud Drive
`~/Library/Mobile Documents/.../OCCTSwiftScripts/output/` if available, else
`~/.occtswift-scripts/output/`), and prepares to accumulate geometry.

**Example**

```swift
import OCCTSwift
import ScriptHarness

let ctx = ScriptContext(
    exportSTEP: true,
    metadata: ManifestMetadata(
        name: "Parametric Bracket",
        revision: "1.0",
        tags: ["fastener", "cast-aluminum"]
    )
)

let profile = Wire.rectangle(width: 20, height: 10)!
try ctx.add(profile, id: "sketch", color: ScriptContext.Colors.yellow)
```

**Notes** — `ScriptContext` is `Sendable` (thread-safe via internal NSLock). Output directory
is cleaned on init; if you call `ScriptContext()` multiple times in one script, only the final
`emit()` persists.

---

## `add(Shape)`

Add a solid, shell, compound, or face to the output; writes BREP immediately.

**Signature**

```swift
try ctx.add(
    _ shape: Shape,
    id: String? = nil,
    color: [Float]? = nil,
    name: String? = nil,
    roughness: Float? = nil,
    metallic: Float? = nil
) throws
```

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `shape` | `Shape` | yes | Any OCCTSwift shape (solid, shell, compound, face, etc.) |
| `id` | `String?` | no | Body identifier; default `"body-N"` where N is the add order |
| `color` | `[Float]?` | no | RGBA as `[r, g, b, a]` with values in 0–1 range |
| `name` | `String?` | no | Display name shown in the viewport |
| `roughness` | `Float?` | no | PBR roughness (reserved for future use) |
| `metallic` | `Float?` | no | PBR metallic value (reserved for future use) |

**What it does** — Writes the shape to `body-N.brep` immediately, records metadata in the
manifest, and appends to the internal shape list for later graph export or compound operations.

**Example**

```swift
let solid = Shape.box(width: 10, height: 10, depth: 10)!
let filleted = solid.filleted(radius: 1.0) ?? solid
try ctx.add(filleted, id: "bracket", color: [0.7, 0.7, 0.75, 1.0], name: "Main Bracket")
```

**Returns** — Throws `ScriptError` on BREP write failure.

**Notes** — Wire and Edge shapes should use the overloaded `add(_:Wire)` or `add(_:Edge)`
methods instead, which convert internally. BREP write is fast (~1 ms); STEP (optional) is
slower (~50 ms).

---

## `add(Wire)`

Add a wire profile or sketch to the output; displayed as wireframe.

**Signature**

```swift
try ctx.add(
    _ wire: Wire,
    id: String? = nil,
    color: [Float]? = nil,
    name: String? = nil
) throws
```

**Parameters** — Same as `add(Shape)`, minus `roughness`/`metallic`.

**What it does** — Converts the wire to a `Shape` via `Shape.fromWire(_:)` and adds it as a
wireframe body. Useful for sketches, sweep paths, or construction geometry.

**Example**

```swift
let profilePath = Wire.circle(radius: 5.0, center: SIMD3(0, 0, 0))!
try ctx.add(profilePath, id: "sweep-path", color: ScriptContext.Colors.cyan)
```

**Notes** — The wire's topology is preserved in BREP format, displayed as edges (no fill).

---

## `add(Edge)`

Add a single edge or curve to the output; displayed as wireframe.

**Signature**

```swift
try ctx.add(
    _ edge: Edge,
    id: String? = nil,
    color: [Float]? = nil,
    name: String? = nil
) throws
```

**Parameters** — Same as `add(Shape)`, minus `roughness`/`metallic`.

**What it does** — Converts the edge to a `Shape` via `Shape.fromEdge(_:)` and adds it as a
wireframe body. Useful for construction axes or curve references.

**Example**

```swift
let axis = Edge.line(from: SIMD3(0, 0, 0), to: SIMD3(0, 0, 100))!
try ctx.add(axis, id: "rotation-axis", color: ScriptContext.Colors.red)
```

---

## `addCompound`

Add multiple shapes as a single compound body.

**Signature**

```swift
try ctx.addCompound(
    _ shapes: [Shape],
    id: String? = nil,
    color: [Float]? = nil,
    name: String? = nil
) throws
```

**Parameters** — Same as `add(Shape)`, minus `roughness`/`metallic`.

**What it does** — Compounds the input shapes and writes as a single BREP body. Useful for
assemblies or multi-part results.

**Example**

```swift
let part1 = Shape.box(width: 10, height: 10, depth: 5)!
let part2 = Shape.cylinder(radius: 3, height: 20)!.translated(by: SIMD3(5, 0, 0))!
try ctx.addCompound([part1, part2], id: "assembly", color: ScriptContext.Colors.gray)
```

---

## `addGraph`

Export a topology graph as JSON and optionally SQLite.

**Signature**

```swift
try ctx.addGraph(
    _ graph: TopologyGraph,
    id: String? = nil,
    sourceBodyId: String? = nil,
    sqlite: Bool = true
) throws
```

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `graph` | `TopologyGraph` | yes | A topology graph built from a shape |
| `id` | `String?` | no | Graph identifier; default `"graph-N"` |
| `sourceBodyId` | `String?` | no | Body ID this graph was derived from (for reference) |
| `sqlite` | `Bool` | no | Also write a SQLite database (default `true`) |

**What it does** — Writes the graph as `graph-N.json` (BREPGraph v1 schema) and optionally
`graph-N.sqlite` for indexing and queries. Adds graph metadata to the manifest.

**Example**

```swift
let shape = Shape.box(width: 10, height: 10, depth: 10)!
try ctx.add(shape, id: "part")
if let graph = TopologyGraph(shape: shape) {
    try ctx.addGraph(graph, sourceBodyId: "part", sqlite: true)
}
```

---

## `addGraphsForAllShapes`

Build and export topology graphs for all shapes added so far.

**Signature**

```swift
try ctx.addGraphsForAllShapes(sqlite: Bool = true) throws
```

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `sqlite` | `Bool` | no | Also write SQLite databases (default `true`) |

**What it does** — Convenience method that iterates all accumulated shapes, builds a
`TopologyGraph` for each, and exports each to JSON + optional SQLite. Skips shapes that fail
to build a graph. Each graph is linked to its source body ID in the manifest.

**Example**

```swift
try ctx.add(shape1, id: "bracket")
try ctx.add(shape2, id: "fastener")
try ctx.addGraphsForAllShapes(sqlite: false)  // JSON only, skip SQLite for speed
try ctx.emit(description: "Parts with topology data")
```

---

## `emit`

Write `manifest.json` (trigger file) and optional combined `output.step`.

**Signature**

```swift
try ctx.emit(description: String? = nil) throws
```

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `description` | `String?` | no | Short description of the script output |

**What it does** — If `exportSTEP` is true, writes a single `output.step` file combining all
added shapes (for external tool interop). Writes `manifest.json` last — this is the **trigger
file** that the OCCTSwiftViewport file watcher listens to, so geometry is only visible after
`emit()` completes successfully.

**Returns** — Throws `ScriptError` on manifest or STEP write failure.

**Output files** (in order of creation)

- `body-0.brep`, `body-1.brep`, … (written by each `add()` call)
- `graph-0.json`, `graph-0.sqlite`, … (written by `addGraph()` calls)
- `output.step` (optional, written by `emit()` if `exportSTEP: true`)
- `manifest.json` (written by `emit()` last; watches file for changes)

**Example**

```swift
import OCCTSwift
import ScriptHarness

let ctx = ScriptContext()
let C = ScriptContext.Colors.self

let profile = Wire.rectangle(width: 20, height: 10)!
let solid = Shape.extrude(profile: profile, direction: SIMD3(0, 0, 1), length: 5)!
let final = solid.filleted(radius: 1.0) ?? solid

try ctx.add(profile, id: "sketch", color: C.yellow)
try ctx.add(final, id: "part", color: C.steel)
try ctx.emit(description: "Filleted rectangular extrusion")
```

**Notes** — Call `emit()` **last** after all geometry is added. Partial output (missing
`manifest.json`) will not trigger the viewport watcher, so failed scripts leave the previous
frame visible. Output directory is `~/.occtswift-scripts/output/` or iCloud Drive equivalent
(resolved at `ScriptContext` init time).

---

## `ManifestMetadata`

Project or part metadata carried through the manifest.

**Fields**

```swift
struct ManifestMetadata: Codable, Sendable {
    public let name: String                    // required
    public let revision: String?               // version or revision identifier
    public let dateCreated: Date?              // ISO 8601 timestamp
    public let dateModified: Date?             // ISO 8601 timestamp
    public let source: String?                 // URL, file path, or reference
    public let tags: [String]?                 // keywords (e.g., ["fastener", "stainless-steel"])
    public let notes: String?                  // freeform description
}
```

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `name` | `String` | yes | Project or part name |
| `revision` | `String?` | no | Version, revision, or build ID |
| `dateCreated` | `Date?` | no | Creation timestamp (encoded as ISO 8601) |
| `dateModified` | `Date?` | no | Last modification timestamp |
| `source` | `String?` | no | URL, file path, or source reference |
| `tags` | `[String]?` | no | Searchable keywords or categories |
| `notes` | `String?` | no | Long-form notes or description |

**Example**

```swift
let meta = ManifestMetadata(
    name: "Mounting Bracket Assembly",
    revision: "2.1",
    dateCreated: Date(timeIntervalSince1970: 0),
    source: "https://github.com/myorg/cad-designs",
    tags: ["fastener", "aluminum", "cast"],
    notes: "Mounting bracket for the secondary encoder. Cast aluminum with drilled holes."
)
let ctx = ScriptContext(metadata: meta)
```

---

## `Colors`

Predefined RGBA color constants for quick styling.

**Enum values**

```swift
ScriptContext.Colors.red      // [0.9, 0.2, 0.2, 1.0]
ScriptContext.Colors.green    // [0.2, 0.8, 0.3, 1.0]
ScriptContext.Colors.blue     // [0.3, 0.5, 0.9, 1.0]
ScriptContext.Colors.yellow   // [1.0, 0.9, 0.2, 1.0]
ScriptContext.Colors.orange   // [0.9, 0.5, 0.2, 1.0]
ScriptContext.Colors.purple   // [0.6, 0.3, 0.8, 1.0]
ScriptContext.Colors.cyan     // [0.2, 0.8, 0.9, 1.0]
ScriptContext.Colors.white    // [0.9, 0.9, 0.9, 1.0]
ScriptContext.Colors.gray     // [0.5, 0.5, 0.5, 1.0]
ScriptContext.Colors.steel    // [0.7, 0.7, 0.75, 1.0]  (PBR-friendly)
ScriptContext.Colors.brass    // [0.8, 0.7, 0.3, 1.0]   (warm metallic)
ScriptContext.Colors.copper   // [0.8, 0.5, 0.3, 1.0]   (warm metallic)
```

**Example**

```swift
let C = ScriptContext.Colors.self
try ctx.add(solid, id: "chassis", color: C.steel)
try ctx.add(fastener, id: "bolt", color: C.copper)
```

**Notes** — All colors are RGBA with alpha = 1.0. Use custom `[Float]` arrays for custom
colors: `[r, g, b, a]` with values in 0–1 range.

---

## `run`

Host a user Swift script headlessly via a cached SPM workspace.

**Input** — Flag form or `--serve` JSONL mode.

**Signature**

```bash
occtkit run <script.swift> [options]
```

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `<script.swift>` | path | yes | Path to a Swift source file to execute |
| `--format` | list | no | Output formats: `brep,step,graph-json,graph-sqlite` (default: `brep,step`) |
| `--output`, `-o` | path | no | Copy output directory to this path after run |
| `--serve` | flag | no | Read JSONL requests on stdin, emit JSONL envelopes on stdout |

**What it does** — Creates or updates a cached SPM workspace under
`~/.occtswift-scripts/runner-cache/workspace/`, copies the user script to `Sources/Script/main.swift`,
rewrites imports/settings as needed, runs `swift build && swift run Script`, and copies the
output directory on completion.

**Format control** — The `--format` list controls what `ScriptContext` writes:
- `brep` — individual body BREP files (always written)
- `step` — combined `output.step` (rewrites `ScriptContext()` to `ScriptContext(exportSTEP: false)`)
- `graph-json` — topology graphs as `graph-N.json` (injects `ctx.addGraphsForAllShapes(sqlite: false)` before emit)
- `graph-sqlite` — topology graphs as `graph-N.sqlite` (injects `ctx.addGraphsForAllShapes(sqlite: true)` before emit)

**Workspace resolution** — ScriptHarness dependency is auto-detected in order:
1. `$OCCTKIT_SCRIPTS_PATH` environment variable (if set and contains `Package.swift`)
2. Auto-detect from running binary's `argv[0]` (works for `swift run occtkit ...`)
3. Remote fallback: `from: "0.2.0"` tag from GitHub

**Example**

```bash
# Run a script with default output (BREP + STEP)
occtkit run my_design.swift

# Run with graphs, output to a specific directory
occtkit run my_design.swift --format brep,step,graph-json --output /tmp/results

# Service mode: read JSONL requests
printf '{"args":["test.swift"]}\n' | occtkit run --serve
```

**Example result**

```json
{
  "ok": true,
  "exit": 0,
  "stdout": "Script output: 2 bodies written to ~/.occtswift-scripts/output\n  STEP: output.step\n  Graphs: 1 topology graph(s)"
}
```

**Error handling** — Build or runtime errors are reported in `stderr` and exit code is non-zero.

```json
{
  "ok": false,
  "exit": 1,
  "stderr": "Build failed:\nerror: ...",
  "error": "Build failed:\nerror: ..."
}
```

**Notes** — First run is ~30 s (full SPM build of OCCTSwift + dependencies); subsequent runs
are ~1–2 s incremental. Output directory is resolved the same way as `ScriptContext`:
iCloud Drive `~/Library/Mobile Documents/.../OCCTSwiftScripts/output/` if available, else
`~/.occtswift-scripts/output/`. With `--serve`, the subcommand's stdout/stderr and any child
process output are captured *into* the envelope, not leaked to occtkit's own stdout.
