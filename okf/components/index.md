---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts
tags: [index, api, cli]
description: OCCTSwiftScripts public products — the occtkit CLI plus the ScriptHarness and DrawingComposer libraries.
timestamp: 2026-06-22
---

# Components

`OCCTSwiftScripts` exposes three public products:

- **`occtkit`** (executable) — a single multi-call binary bundling ~26 headless verbs across domains:
  - **Script host** — `run`
  - **Topology graph** — `graph-validate`, `graph-compact`, `graph-dedup`, `graph-query`, `graph-ml`
  - **Drawings & export** — `dxf-export`, `drawing-export` (full ISO 128-30 multi-view DXF R12)
  - **Composition** — `compose-sheet-metal`, `reconstruct`
  - **Construction** — `transform`, `boolean`, `pattern`
  - **Introspection** — `metrics`, `query-topology`, `measure-distance`, `measure-deviation`, `feature-recognize`
  - **I/O** — `load-brep`, `import`
  - **Engineering analysis** — `check-thickness`, `analyze-clearance`, `heal`
  - **Mesh** — `mesh`, `simplify-mesh`; **Render** — `render-preview`; **XCAF** — `inspect-assembly`, `set-metadata`
  - Each verb takes flag- or JSON-form input and a generic `--serve` JSONL request/envelope mode (OCCTMCP).
- **`ScriptHarness`** (library) — `ScriptContext` for parametric scripts: stage `Shape` / `Wire` / `Edge` bodies
  with id / color / name, emit `.brep` files + combined `output.step` + `manifest.json` for the viewport watcher.
- **`DrawingComposer`** (library) — in-process drawing composition backing `drawing-export`.

Deprecated per-verb standalone executables (`GraphValidate`, `OCCTRunner`, `GraphML`, etc.) still exist but
print a deprecation notice; migrate to the equivalent `occtkit <verb>` subcommand.
