---
title: CLI & API Reference
nav_order: 3
has_children: true
---

# OCCTSwiftScripts Reference

A **detailed, per-family reference** for OCCTSwiftScripts — one page per *family*, every entry
documented: what it does, its parameters (CLI flags and/or JSON-schema fields), what it returns,
a runnable example call with an example result, and the OCCTSwift call behind it.

OCCTSwiftScripts has two surfaces:

- the **`ScriptHarness` library** (`ScriptContext`, `ManifestMetadata`, `Colors`) used inside a
  Swift script and the **`run`** verb that hosts those scripts headlessly, and
- the **`occtkit` CLI** — a busybox-style multi-call binary of **29 verbs**. Run a verb as
  `occtkit <verb> ...`, `swift run occtkit <verb> ...`, or via an installed symlink
  (`make install`). Every verb takes **flag-form OR JSON-form** input and supports a generic
  **`--serve`** JSONL mode.

This complements the other docs:
- [Cookbook](../guides/cookbook/) — *task-oriented* recipes that chain these verbs and the script API.
- [README verb table](https://github.com/gsdali/OCCTSwiftScripts#occtkit-cli) — the one-line catalog.

## Page layout

One file `docs/reference/<family>.md` per family. Each page:

```markdown
---
title: <Family>
parent: CLI & API Reference
nav_order: <n>
---

# <Family>

<1–3 sentences: what this family is for and when you reach for it.>

## Entries

[`verb-a`](#verb-a) · [`verb-b`](#verb-b) · …

---

## `verb-name`     ← one `##` per verb / API entry, in the page's order

<one-line summary — what it does.>

**Input** — flag-form, JSON-form (stdin or argv path), or both. Note `--serve` if relevant.

**Parameters**

| name | type | required | description |
|------|------|:--------:|-------------|
| `--output` / `output` | string | yes | … |
| `--kind` / `kind` | enum | yes | one of `linear` \| `circular` \| `mirror` |

<omit the table if the verb takes no parameters; say "No parameters.">

**Returns** — <what the JSON envelope / output files contain; note error conditions.>

**Example**

​```bash
occtkit verb-name in.brep --output out.brep --kind circular
​```
​```json
// example result (stdout JSON)
{ "ok": true, "outputs": ["out.brep"] }
​```

**Drives** — the OCCTSwift / library call behind it. *(omit if not applicable)*
**Notes** — gotchas / cross-references. *(omit if none)*
```

## Entry rules (the contract)

1. **Parameters come from the actual source** — read the verb's file under
   `Sources/occtkit/Commands/<Verb>.swift` (and the `ScriptContext` API from
   `Sources/ScriptHarness/`). Flag names, JSON field names, types, defaults, and which are
   required must match the code. **Do not invent or rename parameters.**
2. **Every verb in the family gets one `##` section**, in the order listed on the page.
3. **Note the input modes** — most verbs accept flag-form and JSON-form; say so, and mention
   `--serve` where the verb is commonly driven that way (e.g. by OCCTMCP).
4. **Examples must be faithful** — only real flags / fields, correct types, realistic paths
   (a `bodyId` like `"part"`, a path under `/tmp`). Mark illustrative result JSON as an example;
   don't over-specify exact numbers you can't know.
5. **No invention.** Behaviour comes from the source, the [README](https://github.com/gsdali/OCCTSwiftScripts),
   and `CLAUDE.md`. If a detail is unclear, state it briefly — don't fabricate.
6. **Concise.** Reference, not prose: one summary line, a parameter table, returns, one example.

## Families

| Page | Entries |
|------|---------|
| [Script harness & run](script-harness.md) | `ScriptContext` (`add`, `addCompound`, `addGraph`, `emit`), `ManifestMetadata`, `Colors`, the `run` verb |
| [Topology graph](topology-graph.md) | graph-validate, graph-compact, graph-dedup, graph-query, graph-ml, graph-select |
| [Drawings & export](drawings.md) | dxf-export, drawing-export |
| [Composition](composition.md) | reconstruct, compose-sheet-metal |
| [Construction](construction.md) | transform, boolean, pattern |
| [Introspection & measurement](introspection.md) | metrics, query-topology, measure-distance, measure-deviation, feature-recognize |
| [I/O](io.md) | load-brep, import |
| [Engineering analysis](engineering.md) | check-thickness, analyze-clearance, heal |
| [Mesh](mesh.md) | mesh, simplify-mesh |
| [Render](render.md) | render-preview |
| [XCAF assemblies](xcaf.md) | inspect-assembly, set-metadata |
