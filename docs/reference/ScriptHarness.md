---
title: ScriptHarness API
nav_order: 2
parent: Reference
---

# `ScriptHarness` library reference

`ScriptHarness` is the SPM library product behind the script workflow. Its core type,
`ScriptContext`, accumulates geometry built with the **full OCCTSwift API**, writes each
body as a BREP file, optionally writes a combined STEP, and emits a `manifest.json` that
OCCTSwiftViewport's ScriptWatcher live-reloads.

```swift
.product(name: "ScriptHarness", package: "OCCTSwiftScripts"),
```

Source: [`Sources/ScriptHarness/`](https://github.com/SecondMouseAU/OCCTSwiftScripts/tree/main/Sources/ScriptHarness).

---

## `ScriptContext`

```swift
public final class ScriptContext: Sendable {
    public let exportSTEP: Bool
    public let metadata: ManifestMetadata?

    public init(exportSTEP: Bool = true, metadata: ManifestMetadata? = nil)
}
```

The init resolves the output directory (and **cleans** it):

1. iCloud Drive — `~/Library/Mobile Documents/com~apple~CloudDocs/OCCTSwiftScripts/output/` if present, else
2. Local — `~/.occtswift-scripts/output/`.

(On iOS/sandboxed platforms it writes into the app's Documents directory.)

### Minimal lifecycle

A script always: make a context → build geometry → `add` each body → `emit` **last**.

```swift
import OCCTSwift
import ScriptHarness

let ctx = ScriptContext()
let C = ScriptContext.Colors.self

// Sketch a profile
let profile = Wire.rectangle(width: 20, height: 10)!
try ctx.add(profile, id: "sketch", color: C.yellow)

// Extrude → fillet
let solid = Shape.extrude(profile: profile, direction: SIMD3(0, 0, 1), length: 5)!
let filleted = solid.filleted(radius: 1.0)!
try ctx.add(filleted, id: "body", color: C.blue)

// Boolean cut
let hole = Shape.cylinder(radius: 3, height: 10)!.translated(by: SIMD3(5, 0, -1))!
let result = filleted.subtracting(hole)!
try ctx.add(result, id: "final", color: C.steel)

try ctx.emit(description: "Filleted plate with hole")
```

Run it from a checkout with `swift run Script`, or run any `.swift` file headlessly with
`occtkit run <file>.swift`.

---

## Adding geometry

`ScriptContext.add` is overloaded for `Shape`, `Wire`, and `Edge`. Wire/edge inputs are
converted to a `Shape` internally (BREP preserves the topology; the viewport draws them as
wireframe). Each `add` writes `body-N.brep` immediately.

```swift
// Shape (solids, shells, compounds, faces)
public func add(_ shape: Shape, id: String? = nil, color: [Float]? = nil,
                name: String? = nil, roughness: Float? = nil, metallic: Float? = nil) throws

// Wire (profiles, sketches, sweep paths)
public func add(_ wire: Wire, id: String? = nil, color: [Float]? = nil, name: String? = nil) throws

// Edge
public func add(_ edge: Edge, id: String? = nil, color: [Float]? = nil, name: String? = nil) throws

// Multiple shapes → one compound (assembly results)
public func addCompound(_ shapes: [Shape], id: String? = nil,
                        color: [Float]? = nil, name: String? = nil) throws
```

| Parameter | Type | Notes |
|-----------|------|-------|
| `id` | `String?` | Body identifier (default `"body-N"`) |
| `color` | `[Float]?` | RGBA `[r,g,b,a]`, 0–1 |
| `name` | `String?` | Display name |
| `roughness` / `metallic` | `Float?` | PBR (reserved; Shape overload only) |

```swift
try ctx.add(shape, id: "part", color: C.steel, name: "Bracket")   // solid
try ctx.add(wire,  id: "sketch", color: C.yellow)                  // wireframe
try ctx.addCompound([a, b], id: "assembly", color: C.gray)         // compound
```

---

## Topology graphs

`ScriptContext` can also export topology graphs (JSON + optional SQLite) alongside bodies.
These are consumed by `occtkit graph-query` and the viewport's graph tooling.

```swift
public func addGraph(_ graph: TopologyGraph, id: String? = nil,
                     sourceBodyId: String? = nil, sqlite: Bool = true) throws

/// Build + export a TopologyGraph for every shape added so far.
public func addGraphsForAllShapes(sqlite: Bool = true) throws
```

```swift
try ctx.add(part, id: "part")
try ctx.addGraphsForAllShapes(sqlite: true)   // → graph-0.json + graph-0.sqlite
try ctx.emit(description: "part + topology graph")
```

> `occtkit run <file>.swift --format graph-json,graph-sqlite` injects
> `addGraphsForAllShapes(...)` for you, so plain scripts need not call it.

---

## Emit

```swift
public func emit(description: String? = nil) throws
```

Call **last**. It writes (in order): a combined `output.step` (only when `exportSTEP` and
there are shapes), then `manifest.json` **last** — so a partial failure leaves the prior
frame intact and the watcher only triggers on a complete frame.

```swift
let ctx = ScriptContext(exportSTEP: false)   // BREP only, faster (no STEP)
// ... add bodies ...
try ctx.emit(description: "My parametric design")
```

---

## Predefined colors

`ScriptContext.Colors` exposes `[Float]` RGBA constants:

```swift
let C = ScriptContext.Colors.self
// .red .green .blue .yellow .orange .purple .cyan .white .gray .steel .brass .copper
try ctx.add(shape, color: C.steel)
```

---

## Manifest types

`emit` serialises a `ScriptManifest`. These `Codable`/`Sendable` types are public, so
in-process consumers can read or build manifests directly.

```swift
public struct ScriptManifest: Codable, Sendable {
    public let version: Int            // default 1
    public let timestamp: Date
    public let description: String?
    public let bodies: [BodyDescriptor]
    public let graphs: [GraphDescriptor]?
    public let metadata: ManifestMetadata?
}

public struct BodyDescriptor: Codable, Sendable {
    public let id: String?
    public let file: String            // e.g. "body-0.brep"
    public let format: String          // "brep"
    public let name: String?
    public let color: [Float]?         // RGBA
    public let roughness: Float?
    public let metallic: Float?
}

public struct GraphDescriptor: Codable, Sendable {
    public let id: String
    public let file: String            // e.g. "graph-0.json"
    public let sourceBodyId: String?
    public let stats: GraphStats?      // faces/edges/vertices/shells/solids
}

public struct ManifestMetadata: Codable, Sendable {
    public let name: String
    public let revision: String?
    public let dateCreated: Date?
    public let dateModified: Date?
    public let source: String?
    public let tags: [String]?
    public let notes: String?
}
```

Attach part metadata at construction time:

```swift
let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "L-Bracket", revision: "A", source: "parametric script", tags: ["bracket", "demo"]
))
```

---

## Errors

```swift
public enum ScriptError: Error, LocalizedError {
    case conversionFailed(String)   // e.g. Wire → Shape failed
    case message(String)
}
```

Fallible OCCTSwift factories return optionals — unwrap with `guard let`/`if let` in real
code, or a trailing `!` only in throwaway scripts. `ScriptContext.add` throws
`ScriptError.conversionFailed` when a Wire/Edge/compound conversion fails.
