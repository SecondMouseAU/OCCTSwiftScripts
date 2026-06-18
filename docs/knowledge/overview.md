---
type: Project
title: OCCTSwiftScripts overview
description: OSS script harness for rapid OCCTSwift geometry iteration plus the headless occtkit CLI of reusable verbs for downstream consumers.
resource: /
tags: [project, overview, occtkit, oss]
timestamp: 2026-06-18T00:00:00Z
---

# What this is

A script harness for rapid OCCTSwift geometry iteration — the OCCTSwift equivalent of CadQuery
or OpenSCAD — plus a headless CLI (`occtkit`) bundling reusable verbs (graph-validate,
reconstruct, drawing-export, render-preview, …) for downstream consumers (OCCTMCP, the
OCCTStudio app, Python pipelines).

The full architecture, the verb inventory, the `--serve` protocol, and the dependency cohort
are documented in detail in **`CLAUDE.md`** — that remains the source of truth for
implementation detail. This bundle holds the durable, cross-cutting knowledge.

# Boundary

LGPL-2.1, OSS, depends only on open-source Swift packages. See
[policies/open-source-boundary](policies/open-source-boundary.md). The commercial **OCCTStudio**
app consumes this repo's `reconstruct` verb but lives in a separate private repo — see
[references/commercial-app-relationship](references/commercial-app-relationship.md).
