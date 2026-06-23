---
title: Getting started
nav_order: 4
---

# Getting started

This page covers building OCCTSwiftScripts, running your first script with live viewport reload,
and installing the `occtkit` CLI.

## Prerequisites

- macOS 15+
- Swift 6.0+ / Xcode 16+

No external setup is needed beyond a Swift toolchain — OCCTSwift bundles a pre-built OCCT
xcframework, so the first build resolves and compiles the cohort (~30 s cold; ~1–2 s incremental
thereafter) without a C++ source build.

---

## Build

```bash
git clone https://github.com/SecondMouseAU/OCCTSwiftScripts.git
cd OCCTSwiftScripts
swift build                  # first build ~30s, incremental ~1-2s
```

---

## Your first script

Edit `Sources/Script/main.swift`. The minimal shape is always: make a `ScriptContext`, build
geometry with the OCCTSwift API, `add` each body, then `emit`.

```swift
import OCCTSwift
import ScriptHarness

let ctx = ScriptContext()
let C = ScriptContext.Colors.self

let box = Shape.box(width: 60, height: 40, depth: 20)!
let plate = box.drilled(at: SIMD3(30, 20, -1), direction: SIMD3(0, 0, 1),
                        radius: 6, depth: 22)!

try ctx.add(plate, id: "plate", color: C.steel, name: "Drilled plate")
try ctx.emit(description: "60×40×20 plate with a Ø12 through-hole")
```

Run it:

```bash
swift run Script
```

This writes one `body-N.brep` per `add()`, a combined `output.step`, and `manifest.json` (written
last) to the output directory. To run an arbitrary `.swift` file headlessly (no editing of
`Sources/Script/main.swift`), use `occtkit run my_script.swift`.

### Output location

The output directory is resolved in this order:

1. iCloud Drive: `~/Library/Mobile Documents/com~apple~CloudDocs/OCCTSwiftScripts/output/`
2. Local fallback: `~/.occtswift-scripts/output/`

It is cleaned on each `ScriptContext` init.

---

## Live viewport reload

In the **OCCTSwiftViewport** demo app (macOS), open the sidebar:
**File & Tools → Script Watcher → toggle on.** The watcher uses a `kqueue` watch on
`manifest.json`; each `swift run Script` re-emits the manifest and the viewport reloads the bodies
automatically. The edit → run → see loop is the CadQuery/OpenSCAD-style core of the harness.

---

## Install the `occtkit` CLI

`occtkit` is a single multi-call binary that bundles all 29 headless verbs. Install it (with
busybox-style per-verb symlinks) to your `PATH`:

```bash
make install                 # installs to /usr/local/bin
make install PREFIX=$HOME/.local
```

Then run any verb by name, or via the umbrella binary, or straight from the build tree:

```bash
graph-validate body.brep                       # via installed symlink
occtkit graph-validate body.brep               # via the umbrella binary
swift run occtkit graph-validate body.brep     # from a checkout, no install
occtkit --help                                 # list all verbs
make uninstall
```

Every verb accepts **flag-form** or **JSON-form** input (JSON on stdin or as an argv path), plus a
generic **`--serve`** mode that reads JSONL `{"args":[...]}` requests and writes one JSONL envelope
per request — used by OCCTMCP and any other JSON-driven consumer.

```bash
# JSON-form on stdin
echo '{"inputBrep":"part.brep","metrics":["volume","boundingBox"]}' | occtkit metrics

# --serve: one envelope per request line
printf '{"args":["a.brep"]}\n{"args":["b.brep"]}\n' | occtkit graph-validate --serve
```

### Render a preview (this repo owns `render-preview`)

```bash
occtkit render-preview part.brep --output part.png --camera iso --display-mode shaded-with-edges
```

<!-- 3D render TODO: render-preview output for part.png -->

---

## Next steps

- **[occtkit verb reference](../reference/occtkit-verbs.md)** — all 29 verbs: purpose, flags, JSON I/O, runnable examples.
- **[ScriptHarness API](../reference/ScriptHarness.md)** — the `ScriptContext` output pipeline, with runnable Swift snippets.
- **[DrawingComposer API](../reference/DrawingComposer.md)** — the multi-view ISO drawing library behind `drawing-export`.
- **[Cookbook](../guides/cookbook/)** — task-oriented recipes for authoring, drawings, measurement, reconstruction, and more.
- **[Architecture](architecture.md)** — the targets, the output pipeline, the `--serve` envelope, and the ecosystem.
