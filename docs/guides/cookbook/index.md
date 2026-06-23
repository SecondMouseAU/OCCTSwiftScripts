---
title: Cookbook
nav_order: 2
has_children: true
---

# OCCTSwiftScripts Cookbook

Task-oriented, **example-rich** recipes for working with OCCTSwiftScripts — both the
CadQuery/OpenSCAD-style **script harness** and the headless **`occtkit`** CLI. One page per area:
a short bit of prose, then the actual **Swift script** or **`occtkit` invocation** — with example
output — chained into a real workflow. Figures are rendered by `occtkit render-preview` (or the
recipe's own `output.png`) and committed under `images/`.

This is the *usage* counterpart to the per-family [Reference](../../reference/); recipes link to the
reference rather than restating every flag.

## Conventions

- **Show real, runnable steps.** Each step is a ```` ```swift ```` script (for the harness) or a
  ```` ```bash ```` `occtkit` command, optionally followed by a ```` ```json ```` **example
  result**. Use only real API / flags (see the [Reference](../../reference/) or the source) — never
  invent fields.
- **Script harness first for authoring, occtkit for headless verbs.** Reach for the script
  (`Sources/Script/main.swift` + `swift run Script`) to author geometry; reach for `occtkit` verbs
  for graph / drawings / reconstruct / measurement / I/O that run headlessly and feed pipelines.
- **One canonical place per topic.** Recipes hold *workflow*; per-entry detail lives in the
  [reference](../../reference/), and the design rationale in [Architecture](../architecture.md).
  Link, don't duplicate.
- **Note `--serve` where it matters.** When a verb is typically driven as a JSONL service (e.g. by
  OCCTMCP), say so and show the envelope shape.

## Figures

Figures come from the same code the page shows: build geometry with a script (or a typed verb),
then `occtkit render-preview ... --output docs/guides/cookbook/images/<name>.png`, and embed it with
`![alt](images/<name>.png)`. Several recipes reuse the committed renders from the worked
[`recipes/`](https://github.com/gsdali/OCCTSwiftScripts/tree/main/recipes) folder. Because the
picture comes from the same script the page shows, code and figure don't drift.

## Pages

- [Script iteration](script-iteration.md) — the edit → `swift run Script` → live-viewport loop, `ScriptContext`, colors, metadata, and the BREP/STEP/manifest output pipeline.
- [Authoring geometry](authoring-geometry.md) — build a real part end-to-end against the full OCCTSwift API (sketch → extrude → fillet → drill).
- [Sweeps, lofts & patterns](sweeps-lofts-patterns.md) — helix/pipe sweeps, lofted sections, and linear/circular patterns (spring, fan blade, lattice).
- [Gallery & 2D views](gallery-and-2d-views.md) — the gallery pattern: 3D solid + 2D cross-section + HLR projected views + programmatic dimensions.
- [occtkit CLI basics](occtkit-cli.md) — the multi-call binary, install + symlinks, flag-form vs JSON-form input, and the `--serve` JSONL envelope.
- [Construction](construction.md) — the `transform` / `boolean` / `pattern` verbs as headless, file-in/file-out pure functions.
- [Introspection & measurement](introspection-and-measurement.md) — `metrics`, `query-topology`, `measure-distance` / `measure-deviation`, and `feature-recognize`.
- [Technical drawings](drawings.md) — `drawing-export` (multi-view ISO sheet → DXF) and `dxf-export` (single HLR view).
- [Reconstruction & sheet metal](reconstruction-and-sheet-metal.md) — `reconstruct` (JSON feature list → BREP) and `compose-sheet-metal` (flanges + bends → folded part).
- [Topology graph](topology-graph.md) — validate / compact / dedup the B-rep graph, export ML-friendly JSON, and local adjacency selection.
- [Engineering analysis](engineering-analysis.md) — wall-thickness checks, pairwise clearance / interference, and shape healing.
- [Import, export & assemblies](io-and-assemblies.md) — load BREP, import STEP/IGES/STL/OBJ, and walk / edit XCAF assemblies (`inspect-assembly` / `set-metadata`).
- [Mesh & render](mesh-and-render.md) — tessellate and decimate meshes, and produce headless PNG previews with overlays.
