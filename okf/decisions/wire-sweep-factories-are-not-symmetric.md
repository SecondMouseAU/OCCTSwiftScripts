---
type: decision
title: Wire-profile sweep factories are not symmetric about what they return
description: Shape.extrude faces a wire for you and returns a solid; Shape.revolve and Shape.sweep given a wire return a shell. Face the wire first, and assert solidCount rather than trusting shapeType or a positive volume.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/100
tags: [decision, occtswift, topology, recipes, solids]
timestamp: 2026-08-05
---

# Decision

When a sweep factory is given a **wire** and a solid is wanted, face the wire first. Do not
assume the factory does it.

| Call | Returns |
|---|---|
| `Shape.extrude(profile: wire, ...)` | **solid** (faces the wire for you) |
| `Shape.loft(profiles: [...], solid: true)` | **solid** |
| `Shape.revolve(profile: wire, ...)` | **shell** |
| `Shape.face(from: wire)?.revolved(...)` | **solid** |
| `Shape.sweep(profile: wire, along:)` | **shell** (`BRepOffsetAPI_MakePipe` never caps ends) |
| `Shape.pipeShell(spine:profile:mode:solid: true)` | **solid** |

None of this is an OCCTSwift bug. Revolving or sweeping a *curve* legitimately produces a
surface, and `BRepOffsetAPI_MakePipe` genuinely has no capping option. The trap is that
neighbouring factories with near-identical signatures return different topological kinds, and
nothing in the signature says so.

# How to check

Assert `shape.subShapeCount(ofType: .solid) >= 1`.

Do **not** assert `shapeType == .solid`: a compound wrapping one solid is the normal, healthy
result of `circularPatternCut`, and that assertion would reject it. The `metrics` verb exposes
this as `solidCount`.

Do **not** rely on volume being positive. A **closed** shell returns a correct positive volume
from `GProp`, and an open one returns a plausible but meaningless number. That is precisely why
this went unnoticed.

# Why

Two shipped cookbook recipes emitted shells while documenting themselves as solids:

- `recipes/03-pipe-flange/` revolved a wire.
- `recipes/02-helical-spring/` swept one.

Neither was caught, because `Scripts/recipe-check.sh` asserted only that volume was greater than
zero, and both shells satisfied that.

The flange case shows why a shell is not a cosmetic problem. Its bolt-circle
`circularPatternCut` against the non-solid blank silently under-cut: it removed 6157.52 mm3 of
the correct 18472.57 mm3, so **two thirds of the bolt holes were missing** while every metric the
suite measured looked healthy.

The same pattern is what broke Route B in the bevel gear spike ([#86](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/86)):
a shell blank produced disconnected surface patches under boolean subtraction, with a nil or
negative volume, and it took step-by-step measurement to see that the blank rather than
`circularPatternCut` was at fault.

# Consequences

`Scripts/recipe-check.sh` asserts `solidCount >= 1` on every emitted recipe body, and compares
`solidCount` against the committed reference so a topology regression that preserves volume is
caught too.

`docs/SCRIPT_WORKFLOW.md`'s profile cheat sheet now annotates each factory with what it returns,
since that list sitting on consecutive lines is exactly where the wrong assumption forms.
