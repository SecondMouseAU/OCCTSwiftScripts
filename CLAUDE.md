# CLAUDE.md

**Start at [`okf/index.md`](okf/index.md)**, this repo's OKF 0.2 knowledge bundle: what the repo
is, what it depends on, its components, and the mandatory policies. Read the one page a task
needs, when it needs it. Do not read the bundle up front, and never `@`-import it: `@` inlines a
file into every session, which is the cost this layout exists to avoid.

Read the policy a task touches. All nine are mandatory (`okf/policies/`):

| Before you | Read |
|---|---|
| touch an OCCT or OCCTSwift API | [`okf/policies/context-first.md`](okf/policies/context-first.md) |
| write a new type, helper, or tool | [`okf/policies/search-before-building.md`](okf/policies/search-before-building.md) |
| add a file, or split one | [`okf/policies/code-structure.md`](okf/policies/code-structure.md) |
| write prose, a comment, a commit or a PR body | [`okf/policies/writing-style.md`](okf/policies/writing-style.md) |
| open an issue | [`okf/policies/issue-tracking.md`](okf/policies/issue-tracking.md) |
| ship or release a change | [`okf/policies/docs-current.md`](okf/policies/docs-current.md) |
| write or change a test | [`okf/policies/prove-the-test-fails.md`](okf/policies/prove-the-test-fails.md) |
| format or name anything | [`okf/policies/code-style.md`](okf/policies/code-style.md) |
| propose a verb or dependency | [`okf/policies/open-source-boundary.md`](okf/policies/open-source-boundary.md) |

`Scripts/policy-check.sh` (CI: `docs-consistency.yml`) fails the build if this table, `okf/index.md`
and `okf/policies/` disagree, so a new policy file must be linked from both and the count above bumped.

---

Everything below is what a session in this checkout needs in hand. Durable what and why lives in
`okf/`: [targets and per-verb design](okf/references/occtkit-architecture.md),
[dependency floors and history](okf/references/dependencies.md), and
[`docs/SCRIPT_WORKFLOW.md`](docs/SCRIPT_WORKFLOW.md) for the script iteration workflow.

## Project

OCCTSwiftScripts is a script harness for rapid OCCTSwift geometry iteration (the OCCTSwift equivalent
of CadQuery or OpenSCAD), plus a headless CLI, `occtkit`, bundling reusable verbs for downstream
consumers (OCCTMCP, Python pipelines). `occtkit --verbs` is the authoritative verb list; the
per-verb reference is `docs/reference/occtkit-verbs.md`.

**Open-source boundary**: LGPL-2.1, depends only on open-source Swift packages. Never add a
dependency on a closed-source project; downstream closed-source consumers wire their own.

## Build and test

```bash
swift build                                  # First build ~30s, incremental ~1-2s
swift test                                   # swift-testing suites in Tests/
swift run Script                             # Build & execute Sources/Script/main.swift
swift run occtkit <subcommand> [args...]     # Run any verb directly from the build tree
make install [PREFIX=...]                    # Release build + install occtkit + verb symlinks to $PREFIX/bin
```

Formatting is `swift-format lint --strict` (blocking CI); see `okf/policies/code-style.md`.
New and changed behavior needs a test, and every new test is run once with its subject broken
(`okf/policies/prove-the-test-fails.md`).

## Invariants

- **Swift 6 strict concurrency**: all targets use `.swiftLanguageMode(.v6)`. `ScriptContext` is `Sendable` via a private NSLock-based `LockedArray`.
- **Colors** are `[Float]` RGBA (0–1), with predefined constants on `ScriptContext.Colors` (e.g., `.steel`, `.brass`, `.copper`).
- **Geometry types accepted by `ScriptContext.add()`**: `Shape` (solids/shells/compounds/faces), `Wire`, `Edge` (the latter two are converted via `Shape.fromWire`/`Shape.fromEdge`).
- **BREP over STEP**: BREP is the primary format (~1ms vs ~50ms for STEP). STEP export is optional (`ScriptContext(exportSTEP: false)` to disable; `occtkit run --format` controls it via source rewriting).
- **BRepGraph export**: `ctx.addGraph(_)` writes `graph-N.json` (BREPGraph v1) and optionally `graph-N.sqlite`. `ctx.addGraphsForAllShapes(sqlite:)` is a convenience for batch export.
- **occtkit verbs throw, never `exit()`**: required so `--serve` can recover and continue. Use `ScriptError.message(...)` (in `ScriptContext.swift`) for ad-hoc failures; `GraphIO` helpers throw on every failure path. Standalone wrappers catch + exit 1 in their own `main.swift`.
- **Adding a new verb** = one file in `Sources/occtkit/Commands/` plus one entry in `Registry.all` (`Sources/occtkit/Subcommand.swift`). Standalone targets should not gain new verbs; they exist only for legacy compatibility.
