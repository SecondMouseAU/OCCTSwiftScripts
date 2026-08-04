---
type: repo
title: OCCTSwiftScripts
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts
tags: [cad, occt, cli, occtkit, scripting, headless, drawings, mcp, kernel]
description: occtkit CLI plus ScriptHarness: a script-iteration harness and headless OCCTSwift verbs (graph, drawings, analysis, mesh), OCCTMCP-ready.
timestamp: 2026-06-22
---

# OCCTSwiftScripts

> A script harness for rapid iteration on OCCTSwift parametric geometry, the OCCTSwift equivalent of
> CadQuery / OpenSCAD, plus **occtkit**, a single multi-call CLI bundling 29 headless verbs
> (topology graph, DXF / ISO-128 drawing export, feature recognition, analysis, mesh, XCAF). Every
> verb accepts flag- or JSON-form input and a generic `--serve` JSONL mode used by OCCTMCP.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** [OCCTSwift](https://github.com/SecondMouseAU/OCCTSwift) (B-Rep kernel), [OCCTSwiftViewport](https://github.com/SecondMouseAU/OCCTSwiftViewport) (offscreen render for `render-preview`), [OCCTSwiftTools](https://github.com/SecondMouseAU/OCCTSwiftTools) (Shape ↔ ViewportBody bridge), [OCCTSwiftAIS](https://github.com/SecondMouseAU/OCCTSwiftAIS) (headless scene-object overlays), [OCCTSwiftMesh](https://github.com/SecondMouseAU/OCCTSwiftMesh) (`simplify-mesh`), and [OCCTSwiftIO](https://github.com/SecondMouseAU/OCCTSwiftIO) (`graph-ml` feature export).
- **Feeds:** headless / agent consumers. OCCTMCP and any JSON-driven tooling drive its verbs via `--serve`; the `ScriptHarness` and `DrawingComposer` library products link into downstream apps (e.g. the viewport ScriptWatcher and OCCTSwiftPartsAgent).

This is the **single knowledge store** for this repo. `CLAUDE.md` at the repo root stays the
detailed implementation quick reference; durable policies, decisions, and cross-cutting context
live here. Record them as OKF entries plus a [`log.md`](log.md) line, not only in chat or commit
messages.

## Boundary

LGPL-2.1, open source, depending only on open-source Swift packages. See
[policies/open-source-boundary](policies/open-source-boundary.md). The commercial **OCCTStudio**
app consumes this repo's `reconstruct` verb but lives in a separate private repo; see
[references/commercial-app-relationship](references/commercial-app-relationship.md).

## Components

See [`components/`](components/index.md) for the public surface.

## References

See [`references/`](references/index.md) for the workflow guide, recipes cookbook, package index, and upstream links.

## Decisions

See [`decisions/`](decisions/index.md) for recorded engineering decisions and their rationale.

## Policies

- [Query `context` first for OCCT / OCCTSwift docs](policies/context-first.md)
- [Documentation updates are mandatory](policies/docs-current.md)
- [No em-dashes, banned words in prose](policies/writing-style.md)
- [Search before building](policies/search-before-building.md)
- [Open-source boundary](policies/open-source-boundary.md)
- [Code structure](policies/code-structure.md)
- [Issue labels and project-board tracking](policies/issue-tracking.md)

## History

See [`log.md`](log.md) for the date-grouped change history of this bundle.
