---
title: Home
nav_order: 1
---

# OCCTSwiftScripts documentation

A **script harness** for rapid iteration on [OCCTSwift](https://github.com/gsdali/OCCTSwift)
parametric geometry — the OCCTSwift answer to **CadQuery / OpenSCAD**. Edit a Swift script
using the *full OCCTSwift API*, run it, and see the result live in the
[OCCTSwiftViewport](https://github.com/gsdali/OCCTSwiftViewport) demo app (the file watcher
auto-reloads on each run). Bundled alongside is **`occtkit`**, a headless multi-call CLI of
**29 reusable verbs** (topology graph, ISO drawings, reconstruction, sheet metal, construction,
introspection, mesh, render, I/O, XCAF) used by [OCCTMCP](https://github.com/gsdali/OCCTMCP)
and other downstream pipelines.

```swift
import OCCTSwift
import ScriptHarness

let ctx = ScriptContext()
let C = ScriptContext.Colors.self

let box = Shape.box(width: 60, height: 40, depth: 20)!
let drilled = box.drilled(at: SIMD3(30, 20, -1), direction: SIMD3(0, 0, 1),
                          radius: 6, depth: 22)!

try ctx.add(drilled, id: "plate", color: C.steel, name: "Drilled plate")
try ctx.emit(description: "60×40×20 plate with a Ø12 through-hole")
```

```bash
swift run Script                 # build + run Sources/Script/main.swift → live viewport reload
```

## Cookbook

Task-oriented, example-rich recipes — short prose plus the actual Swift script (or `occtkit`
invocation) and a rendered figure. The **[Cookbook index](guides/cookbook/)** lists every area:

[Script iteration](guides/cookbook/script-iteration.md) ·
[Authoring geometry](guides/cookbook/authoring-geometry.md) ·
[Sweeps, lofts & patterns](guides/cookbook/sweeps-lofts-patterns.md) ·
[Gallery & 2D views](guides/cookbook/gallery-and-2d-views.md) ·
[occtkit CLI basics](guides/cookbook/occtkit-cli.md) ·
[Construction](guides/cookbook/construction.md) ·
[Introspection & measurement](guides/cookbook/introspection-and-measurement.md) ·
[Technical drawings](guides/cookbook/drawings.md) ·
[Reconstruction & sheet metal](guides/cookbook/reconstruction-and-sheet-metal.md) ·
[Topology graph](guides/cookbook/topology-graph.md) ·
[Engineering analysis](guides/cookbook/engineering-analysis.md) ·
[Import, export & assemblies](guides/cookbook/io-and-assemblies.md) ·
[Mesh & render](guides/cookbook/mesh-and-render.md)

## Reference

- **[CLI & API Reference](reference/)** — per-family detail: the `ScriptContext` / `ScriptHarness`
  API, and every `occtkit` verb's flags, JSON schema, what it returns, an example call + result,
  and the OCCTSwift call behind it.
- [README verb table](https://github.com/gsdali/OCCTSwiftScripts#occtkit-cli) — the one-line catalog.

## Guides & concepts

- [Getting started](guides/getting-started.md) — build, run your first script, wire up the live viewport, install `occtkit`.
- [Architecture](guides/architecture.md) — the targets (ScriptHarness / Script / DrawingComposer / occtkit), the output pipeline, the `--serve` envelope, and where this sits in the OCCTSwift ecosystem.

## Project

- Source & issues: [github.com/gsdali/OCCTSwiftScripts](https://github.com/gsdali/OCCTSwiftScripts)
- Part of the [OCCTSwift ecosystem](https://github.com/gsdali/OCCTSwift/blob/main/docs/ecosystem.md). LGPL-2.1, open-source deps only. SemVer-stable from v1.0.0.
