---
type: repo
title: OCCTSwiftScripts
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts
tags: [cad, occt, cli, occtkit, scripting, headless, drawings, mcp, kernel]
description: occtkit CLI plus ScriptHarness — a script-iteration harness and headless OCCTSwift verbs (graph, drawings, analysis, mesh), OCCTMCP-ready.
timestamp: 2026-06-22
---

# OCCTSwiftScripts

> A script harness for rapid iteration on OCCTSwift parametric geometry — the OCCTSwift equivalent of
> CadQuery / OpenSCAD — plus **occtkit**, a single multi-call CLI bundling ~26 headless verbs
> (topology graph, DXF / ISO-128 drawing export, feature recognition, analysis, mesh, XCAF). Every
> verb accepts flag- or JSON-form input and a generic `--serve` JSONL mode used by OCCTMCP.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** [OCCTSwift](https://github.com/SecondMouseAU/OCCTSwift) (B-Rep kernel), [OCCTSwiftViewport](https://github.com/SecondMouseAU/OCCTSwiftViewport) (offscreen render for `render-preview`), [OCCTSwiftTools](https://github.com/SecondMouseAU/OCCTSwiftTools) (Shape ↔ ViewportBody bridge), [OCCTSwiftAIS](https://github.com/SecondMouseAU/OCCTSwiftAIS) (headless scene-object overlays), [OCCTSwiftMesh](https://github.com/SecondMouseAU/OCCTSwiftMesh) (`simplify-mesh`), and [OCCTSwiftIO](https://github.com/SecondMouseAU/OCCTSwiftIO) (`graph-ml` feature export).
- **Feeds:** headless / agent consumers — OCCTMCP and any JSON-driven tooling drive its verbs via `--serve`; the `ScriptHarness` and `DrawingComposer` library products link into downstream apps (e.g. the viewport ScriptWatcher and OCCTSwiftPartsAgent).

## Components

See [`components/`](components/index.md) for the public surface.

## References

See [`references/`](references/index.md) for the workflow guide, recipes cookbook, package index, and upstream links.

## Policies

- [Query `context` first for OCCT / OCCTSwift docs](policies/context-first.md)
- [Documentation updates are mandatory](policies/docs-current.md)
