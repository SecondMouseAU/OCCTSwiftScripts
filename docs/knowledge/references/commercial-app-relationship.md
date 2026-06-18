---
type: Reference
title: Relationship to the OCCTStudio commercial app
description: OCCTStudio (private, commercial) is built on this OSS repo and consumes its reconstruct feature-graph IR; this repo stays OSS and must not depend on the app.
resource: https://github.com/gsdali/OCCTStudio
tags: [reference, commercial, occtstudio, boundary]
timestamp: 2026-06-18T00:00:00Z
---

# Relationship

**OCCTStudio** (`gsdali/OCCTStudio`, private/commercial) is a freemium parametric-CAD app — a
B-Rep alternative to OpenSCAD/CadQuery/ManifoldCAD — built on the OCCTSwift stack. It consumes
this repo:

- OCCTStudio's portable DSL compiles to an IR that its **native adapter** translates to the
  JSON consumed by this repo's `reconstruct` verb (`FeatureReconstructor.buildJSON`). Changes
  to `reconstruct`'s schema affect the app's native adapter.
- The cookbook recipes (`recipes/01`–`07`) are the app's v0 acceptance set for the DSL/IR.

# Direction

Dependencies point **app → OSS, never the reverse.** This repo must never depend on OCCTStudio
(see [policies/open-source-boundary](/docs/knowledge/policies/open-source-boundary.md)). If a
capability seems shared, it lands here under LGPL and the app consumes it.

The app's own design (DSL grammar, IR schema, AI architecture, freemium/feature-flags) lives in
the OCCTStudio repo's `docs/DSL_DESIGN.md` and `docs/knowledge/` bundle, not here.
