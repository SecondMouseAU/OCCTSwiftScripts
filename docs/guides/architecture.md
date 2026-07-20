---
title: Architecture
nav_order: 5
---

# Architecture

OCCTSwiftScripts is two things in one package: a **CadQuery/OpenSCAD-style script harness** for
authoring OCCTSwift geometry, and a **headless `occtkit` CLI** of reusable verbs that downstream
consumers (notably [OCCTMCP](https://github.com/gsdali/OCCTMCP) and Python pipelines) drive over a
JSON protocol.

**Open-source boundary.** LGPL-2.1, depending only on open-source Swift packages (the OCCTSwift
cohort). There are no closed-source transitive dependencies — 2D constraint solving (the former
`solve-sketch` verb) was removed when the closed-source solver dependency was dropped; downstream
consumers that need it wire their own solver outside `occtkit`.

## Targets

| Target | Kind | Role |
|--------|------|------|
| **ScriptHarness** | library | `ScriptContext` — accumulates geometry, writes BREP per `add()`, writes `manifest.json` on `emit()`. Also `BREPGraphJSONExporter` / `BREPGraphSQLiteExporter` and `GraphIO` (shared argv/BREP/JSON helpers used by every verb). Importable by external packages. |
| **Script** | executable | `Sources/Script/main.swift` — the user-editable iteration scratchpad. |
| **DrawingComposer** | library | The multi-view ISO drawing orchestrator (`Composer.render(spec:shape:)`) behind `drawing-export`; usable directly without the CLI. |
| **occtkit** | executable | The multi-call umbrella binary — 29 verbs, dispatched by `argv[0]` basename (installed symlinks) or first positional arg. |
| Standalone verb targets | executables | `OCCTRunner`, `GraphValidate`, … — **deprecated**, preserved for downstream compatibility; each prints a stderr notice. |

## The script output pipeline

For a script run (via `swift run Script` or `occtkit run`):

```
ScriptContext.add(shape)  ──>  body-N.brep            (~1ms each)
       │                       (+ optional graph-N.json / .sqlite)
       ▼
ScriptContext.emit()      ──>  output.step            (optional combined export)
                          ──>  manifest.json          (written LAST)
                                    │
                          kqueue watcher (OCCTSwiftViewport demo app)
                                    │
                              viewport live-reloads
```

`manifest.json` is written **last** on purpose: a partial failure leaves the previous frame visible
in the viewport rather than a half-written manifest. BREP is the primary format (~1 ms/body vs
~50 ms for STEP); STEP export is optional (`ScriptContext(exportSTEP: false)`, or `occtkit run
--format`).

## occtkit: one binary, many verbs

`occtkit` is busybox-style. A single binary dispatches a verb three ways:

- installed symlink: `graph-validate body.brep`
- umbrella: `occtkit graph-validate body.brep`
- from a checkout: `swift run occtkit graph-validate body.brep`

Adding a verb is one file in `Sources/occtkit/Commands/` conforming to the `Subcommand` protocol,
plus one entry in `Registry.all` (`Sources/occtkit/Subcommand.swift`). The 29 verbs group into:
topology graph, drawings & export, composition (reconstruct / sheet-metal), construction, introspection
& measurement, I/O, engineering analysis, mesh, render, and XCAF. See the [Reference](../reference/).

### Input modes and the `--serve` envelope

Every verb accepts **flag-form** input (matching the README), **JSON-form** input (a JSON object on
stdin or a file-path argv), and a generic **`--serve`** mode. In `--serve`, the verb reads JSONL
`{"args":[...]}` requests on stdin and writes one JSONL **envelope** per request:

```json
{"ok": true,  "exit": 0, "stdout": "...", "stderr": "", "error": null}
{"ok": false, "exit": 1, "stdout": "",    "stderr": "...", "error": "message"}
```

The subcommand's own stdout/stderr (and any inherited child-process output, e.g. `swift build`
invoked by `run`) are captured *into* the envelope via per-request FD redirection — they do not leak
to occtkit's own stdout. EOF on stdin → exit 0. This is implemented once in
`Sources/occtkit/main.swift`, so every verb supports it identically, and it is how OCCTMCP launches
`occtkit` as a long-lived service. Because of this, **verbs throw rather than `exit()`** — a failed
request returns an error envelope and the loop continues.

## Where this sits in the ecosystem

OCCTSwiftScripts depends on the OCCTSwift cohort and is depended on by OCCTMCP:

```
OCCTSwift            B-Rep kernel (~400+ methods), ISO drawings, FeatureReconstructor, SheetMetal, XCAF
 ├─ OCCTSwiftViewport   OffscreenRenderer / CameraState / DisplayMode  → render-preview
 ├─ OCCTSwiftTools      CADFileLoader (Shape → ViewportBody)            → render-preview
 ├─ OCCTSwiftAIS        Trihedron / WorkPlane / SubShape selection      → render-preview overlays
 ├─ OCCTSwiftMesh       meshoptimizer QEM decimation                    → simplify-mesh
 └─ OCCTSwiftIO         BRepGraph.exportForML                           → graph-ml
        │
   OCCTSwiftScripts  ── ScriptHarness + DrawingComposer + occtkit (29 verbs)
        │
     OCCTMCP         ── drives occtkit verbs over the --serve JSONL protocol
```

See the [OCCTSwift ecosystem map](https://github.com/gsdali/OCCTSwift/blob/main/docs/ecosystem.md)
for the full family. Internal, durable project knowledge (policies, decisions, the relationship to
the commercial OCCTStudio app) lives in the OKF bundle under `docs/knowledge/` — not part of this
published site.
