---
type: reference
title: Dependency floors and history
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts
tags: [reference, dependencies, semver, floors]
description: Why each dependency floor is where it is, with the OCCTSwift 1.x to 3.0.0 bump history.
generated: { by: claude-code/sonnet-5, at: 2026-10-07 }
sources:
  - id: occtswiftscripts-118
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/118
    title: Bump OCCTSwift floor to 3.0.0
    author: human:gsdali
    last_modified: 2026-08-19
    usage_count: 2
  - id: occtswiftscripts-111
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/111
    title: Bump OCCTSwift floor to 2.0.0
    author: human:gsdali
    last_modified: 2026-08-19
    usage_count: 3
  - { id: occtswiftscripts-763, resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/763, usage_count: 1 }
  - { id: occtswiftscripts-642, resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/642, usage_count: 2 }
  - id: occtswift-377
    resource: https://github.com/SecondMouseAU/OCCTSwift/issues/377
    title: "Segmented duplication audit: programme record, deferred passes 2a to 5d"
    author: human:gsdali
    last_modified: 2026-09-21
    usage_count: 3
  - { id: occtswiftscripts-380, resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/380, usage_count: 1 }
  - id: occtswift-272
    resource: https://github.com/SecondMouseAU/OCCTSwift/issues/272
    title: Shape.drilled(at:direction:radius:depth:) ignores direction — bridge hardcodes the cylinder to +Z
    author: human:gsdali
    last_modified: 2026-07-18
    usage_count: 1
  - id: occtswift-335
    resource: https://github.com/SecondMouseAU/OCCTSwift/issues/335
    title: "rename: TopologyGraph → BRepGraph"
    author: human:gsdali
    last_modified: 2026-07-20
    usage_count: 1
  - id: occtswiftscripts-78
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/78
    title: "Migrate off deprecated TopologyGraph → BRepGraph (OCCTSwift #333)"
    author: human:gsdali
    last_modified: 2026-07-20
    usage_count: 1
  - { id: occtswiftscripts-169, resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/169, usage_count: 1 }
  - { id: occtswiftscripts-170, resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/170, usage_count: 1 }
  - { id: occtswiftscripts-171, resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/171, usage_count: 1 }
  - id: occtswiftscripts-45
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/45
    title: Bump OCCTSwiftViewport floor to 1.0.0 (Viewport v1.0.0 shipped 2026-05-08)
    author: human:gsdali
    last_modified: 2026-05-09
    usage_count: 1
  - id: occtswiftscripts-122
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/122
    title: Migrate to OCCTSwiftInteraction (blocks OCCTMCP#182)
    author: human:gsdali
    last_modified: 2026-08-19
    usage_count: 1
  - id: occtswiftscripts-42
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/42
    title: Bump OCCTSwiftTools to v0.6.0; consider OCCTSwiftIO for headless code paths
    author: human:gsdali
    last_modified: 2026-05-06
    usage_count: 1
  - id: occtswiftscripts-43
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/43
    title: "Bump OCCTSwiftTools floor to from: 0.6.0 (closes #42)"
    author: human:gsdali
    last_modified: 2026-05-06
    usage_count: 1
  - id: occtmcp-182
    resource: https://github.com/SecondMouseAU/OCCTMCP/issues/182
    title: Re-key SelectionRegistry on GraphUID
    author: human:gsdali
    last_modified: 2026-08-19
    usage_count: 1
  - id: occtswiftscripts-80
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/80
    title: OCCTSwiftIO cap (<1.1.0) in v1.5.0 conflicts with OCCTSwiftTools >=1.6.1's own OCCTSwiftIO >=1.7.0 requirement
    author: human:gsdali
    last_modified: 2026-07-20
    usage_count: 1
  - id: occtswiftscripts-69
    resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/69
    title: "OCCTSwiftIO dep uncapped (`from: \"1.0.0\"`) — floats to 1.5.0 and breaks resolution for lean consumers"
    author: human:gsdali
    last_modified: 2026-07-01
    usage_count: 1
usage_window: { from: 2026-06-22, to: 2026-10-07 }
---

# Dependency floors and history

Moved verbatim out of `CLAUDE.md` when the repo adopted the OKF 0.2 router layout.

The full cohort graduated to v1.0 on 2026-05-07 alongside OCCT 8.0.0 GA. SemVer-stable from these floors; only bump on documented breaking changes. Pre-1.0 dep history (which API landed in which 0.x tag) lives in git log; consult it when you actually need to support an older floor, otherwise treat the v1.0 surface as the contract.

- **OCCTSwift**: `https://github.com/SecondMouseAU/OCCTSwift.git` (>= 3.0.0; xcframework built against **OCCT 8.0.1**). The B-Rep kernel: ~400+ methods for parametric CAD, the full ISO drawings stack (Sheet/TitleBlock/ProjectionSymbol/Section2D/Hatch/AutoCentermarks/CuttingPlaneLine/CosmeticThread/SurfaceFinish/GDT/DetailView/DrawingScale), `FeatureReconstructor` for `reconstruct`, the `SheetMetal` namespace for `compose-sheet-metal`, and the XCAF surfaces (`AssemblyNode.labelId`, `Document.node(at:)`) for `inspect-assembly` / `set-metadata`. **Floored at v3.0.0** (OCCTSwiftScripts#118): a correctness/consolidation major (OCCT itself stays at 8.0.1; the kernel was only rebuilt to carry two patches the v2.0.0 asset was missing), not a wrapping one. Two breaking changes, both compile errors (see `docs/SEMVER.md#v300` in the OCCTSwift repo): (1) `Selector.SubShapeType.compsolid` renamed `.compSolid`, consolidating four drifted Swift mirrors of `TopAbs_ShapeEnum` onto `ShapeType`, zero source changes needed here, since this repo already spelled it `ShapeType.compSolid` (`LoadBrep.swift`, `Pattern.swift`, `RenderPreview.swift`), the surviving spelling. (2) `Shape.bounds`/`.size`/`.center`, `Wire.bounds`, `Edge.bounds`, `Face.bounds` (and `.exactBounds`, unused here) become `Optional`: they used to fabricate `(0,0,0)-(0,0,0)` for a shape with no bounding box, indistinguishable from a genuine zero-size shape at the world origin (`Shape.boundingBox`/`boundingBoxOptimal()` already behaved correctly and are unchanged). Every `.bounds` call site in this repo now unwraps: `QueryTopology.swift`/`LoadBrep.swift`/`MeasureDeviation.swift`/`RenderPreview.swift`/`Metrics.swift` throw a named `ScriptError` on a `nil` bounding box (a real error on a loaded BREP, not a state worth papering over with `?? .zero`), and the two recipe edge-selector predicates (`recipes/01-mounting-bracket`, `recipes/03-pipe-flange`) return `false` on a `nil` bounds rather than fabricate a match. `Tests/OcctkitCommandTests/OptionalBoundsTests.swift` regression-tests the throw path directly: it constructs a genuinely void shape (the intersection of two disjoint boxes) and asserts `LoadBrepCommand.buildResponse`/`MeasureDeviationCommand.defaultDeflection` throw rather than fabricate a zero-size box. The rest of the cohort (OCCTSwiftTools v1.6.4, OCCTSwiftMesh v1.7.5, OCCTSwiftIO v1.7.8,
OCCTSwiftAIS v1.3.2, the last of which also fixed its own 3 `.bounds` call sites in
`Dimension.swift`/`AreaSelection.swift`) shipped OCCTSwift-3.0.0-compatible releases the same day,
and this repo released as **v1.6.2**. That release briefly left `main`'s CI red anyway: the
checked-in `Package.resolved` was stale from before the 2.0.0 bump (`occtswift` pinned at
`1.17.0`, `occtswiftais` at `1.3.1`), and SwiftPM's resolver kept the broken `occtswiftais@1.3.1`
pin since it still satisfied every *manifest-declared* range even though its actual source didn't
compile against 3.0.0, manifest ranges can't see real source compatibility, so a merely-stale
lockfile silently locks in a broken transitive pin the moment the cohort catches up. Fixed in a
follow-up PR by regenerating `Package.resolved` from an isolated, sibling-free copy of this repo
(forcing genuine remote resolution instead of this repo's usual local-path substitution). See the
[full decision entry](../decisions/occtswift-3.0.0-floor-bump-blocked-on-cohort-releases.md) for
the timeline. Previously **floored at v2.0.0** (OCCTSwiftScripts#111): a correctness major (17 breaking changes to the public Swift API; see `docs/SEMVER.md#v200` in the OCCTSwift repo). Two fixes landed in this repo alongside that bump: (1) `ShapeAnalysisResult.selfIntersectionCount` was removed (#763; always `0`, never computed), so `Heal.swift`/`GraphValidate.swift` now report `hasSelfIntersection`/`selfIntersecting` as `Bool?` via the real, opt-in `Shape.analyze(selfIntersectionTimeout:)` check (`nil` = "not checked" by default, since the check is ~3000x an ordinary scan on pathological input and both verbs would run it twice), rather than the fabricated always-`0`/always-`false` the removed field silently produced. (2) AAG builds nodes from face **occurrences** (#642): `AAGNode.faceIndex` / `PocketFeature.floorFaceIndex`/`wallFaceIndices` / `detectHoles()`'s `faceIndex` / `AAGEdge.face1Index`/`face2Index` now index `Shape.orientedFaces()`, not the `Shape.faces()` `face[N]` scheme `query-topology` emits (the two agreed automatically pre-2.0.0, since `faces()` was itself occurrence-based then). `FeatureRecognize.swift` (both the `occtkit` command and the legacy standalone target), `GraphSelect.swift`, and `GraphML.swift` all cross-reference AAG output against that `face[N]` scheme and now resolve through the new `AAGNode.distinctFaceIndex` bridge; a no-op on any shape that shares no face (every single-solid part, the only kind this repo's pre-#111 tests exercised), so it only bites a multi-solid compound with a shared face, exactly the shape a caller runs `feature-recognize`/`graph-select`/`graph-ml` against to look for cross-solid structure. `Tests/OcctkitCommandTests/AAGFaceIndexTests.swift` regression-tests the fix directly against `graph-select`/`graph-ml`'s JSON output on a split-box-compound fixture. Before that, **floored at v1.17.0** (raised in d5d31e8 for the OCCTSwift#377/#380 Pass 1a duplication and bug-fix audit; also carries the `Shape.drilled` direction fix, OCCTSwift#272, which lands between 1.12.0 and 1.12.9 and corrected recipe 01's through-holes). Before that, **floored at v1.15.0**: v1.15.0 renamed the Swift wrapper class `TopologyGraph` → `BRepGraph` (OCCTSwift#335) to match the C++ package it wraps; this repo has migrated off the deprecated `TopologyGraph` typealias onto `BRepGraph` directly (OCCTSwiftScripts#78), so the floor must guarantee the `BRepGraph` symbol exists. Earlier, v1.7.0 realigned the BRepGraph wrapper to OCCT's redesigned graph model (definitions vs references/usages, persistent UIDs, controlled layers) and v1.7.1 made the derived graph reads real again: `adjacentFaces`/`faces(of:)`/`edges(of:)`/`sharedEdges`, `faceSameDomain`, `faceIsNaturalRestriction`, plus durable `UID`/`RefUID`/`ItemUID` identity. Our graph verbs (graph-validate/compact/dedup/ml, query-topology) build and run **unchanged** against it. Behaviour changes are **confined to the BRepGraph domain**: `edgeMaxContinuity`/`setEdgeRegularity` are now no-ops (use `Shape.maxContinuity` for continuity); `degenerated`/`closed`/`sameParameter`/`sameRange` setters no-op while their getters return the live derived value. The cookbook ergonomics relied on since v1.3.1, namely `Shape.circularPatternCut` (#169), orientation-normalised `Shape.sweep` + `orientedForward`/`signedVolume` (#170), `concaveEdges`/`convexEdges`/`edges(where:)` selectors (#171), are unchanged. The 2.0.0-bump-era cohort gap (OCCTSwiftIO/Tools/AIS/Mesh all still on their "repin to 1.17.0" floors, blocking remote resolution) resolved by 2026-08-10, when OCCTSwiftIO v1.7.7, OCCTSwiftTools v1.6.3, and OCCTSwiftMesh v1.7.3 each shipped their own "repin OCCTSwift to 2.0.0" release; see the v3.0.0 cohort-gap note above this paragraph for the current (unresolved as of this writing) equivalent.
- **OCCTSwiftViewport**: `https://github.com/gsdali/OCCTSwiftViewport.git` (>= 1.0.0). Provides `OffscreenRenderer`, `CameraState`, `DisplayMode`, `ViewportBody` for `render-preview`. Graduated to v1.0.0 on 2026-05-08, one day after the rest of the cohort; floor unblocked by Tools v1.0.2 (closes #45).
- **OCCTSwiftInteraction**: `https://github.com/SecondMouseAU/OCCTSwiftInteraction.git` (>= 0.1.0). Vends `OCCTSwiftTools` and `OCCTSwiftAIS` as two of its three SwiftPM targets/library products (the third, `OCCTSwiftCADKit`, the assembled SwiftUI viewport service, is not named by anything here and so never enters this build). **Migrated from the standalone `OCCTSwiftTools`/`OCCTSwiftAIS` repos** (OCCTSwiftScripts#122) after those two and `OCCTSwiftCADKit` merged into this one package (SecondMouseAU/ecosystem#42, #43): the three old repos are archived, not deleted, and their tags still resolve, but SwiftPM enforces target-name uniqueness across the whole transitive package graph before any per-consumer product pruning, so a graph containing both this repo and anything depending on `OCCTSwiftInteraction` directly (OCCTMCP, blocked on this for OCCTMCP#182) hit a hard resolution error, not a version-range conflict, until this repo's `occtDep` entries and `package:` labels moved off the old names. Per `OCCTSwiftInteraction`'s `docs/MIGRATION.md`, module names are unchanged: `import OCCTSwiftTools` / `import OCCTSwiftAIS` still work, since each target's identity was preserved across the merge. `OCCTSwiftTools` is the bridge layer between the B-Rep kernel and the Metal viewport: we use `CADFileLoader.shapeToBodyAndMetadata` in `render-preview` for Shape → `ViewportBody` conversion (both input bodies and highlight sub-shapes). `OCCTSwiftAIS` is used for the headless-friendly subset only: `Trihedron` / `WorkPlane` / `Axis` / `PointCloud` scene objects (each emits `[ViewportBody]` via `makeBodies()`) for `render-preview`'s `--show-axes` / `--show-workplane` overlays, plus the SubShape selection vocabulary for `--highlight face[N]/edge[M]/vertex[K]`. Selection / Manipulator / SwiftUI surfaces aren't relevant to a CLI. `Dimension` overlays render via a SwiftUI Canvas inside `MetalViewportView` and so can't reach `OffscreenRenderer`, so `--annotate-dimensions` is deferred (filed as OCCTSwiftViewport#26). Note: `OCCTSwiftAIS` re-exports a `DisplayMode` enum (3 cases) that collides with `OCCTSwiftViewport.DisplayMode` (6 cases); fully-qualify in `RenderPreview.swift` as `OCCTSwiftViewport.DisplayMode`.
- **OCCTSwiftMesh**: `https://github.com/gsdali/OCCTSwiftMesh.git` (>= 1.0.0). LGPL-2.1 wrapper that vendors `meshoptimizer` (BSD-2-Clause / MIT-equivalent) inside `OCCTMeshOptimizer` for QEM decimation. Powers `simplify-mesh` via `Mesh.simplified(_:)`. Smoothing / repair / remeshing are future work.
- **OCCTSwiftIO**: `https://github.com/gsdali/OCCTSwiftIO.git` (>= 1.7.5). Provides `BRepGraph.exportForML` / `exportJSON` via extension after OCCTSwift v0.171.0 hoisted them out of the kernel. **Pulled into the `GraphML` standalone target and the `graph-ml` verb only**; the rest of the package keeps its existing `ScriptManifest` type from `Sources/ScriptHarness/Manifest.swift` (which carries a `graphs` field that OCCTSwiftIO's `ScriptManifest` is missing). If a future verb wants progress-aware STEP loading via `ShapeLoader.load(from:format:progress:)`, broaden the dep then. **Floor raised from `>= 1.0.0, < 1.1.0` to `>= 1.7.5`** (OCCTSwiftScripts#80): the old cap (from #69, guarding against OCCTSwiftIO 1.1.0+'s heavy mesh-IO stack: SwiftPMX/SwiftX/ThreeMF/SwiftGLTF via a `MeshIO` target, plus SwiftJWW/SwiftDXF) became unsatisfiable once OCCTSwiftTools >=1.6.1 started requiring OCCTSwiftIO >=1.7.0 directly; any consumer depending on both packages at once (e.g. OCCTMCP) hit an unresolvable graph. Checked OCCTSwiftIO 1.7.5's manifest for a narrower product to preserve the cap's intent: it ships `OCCTSwiftIO` and `MeshIO` as separate library products, but the `OCCTSwiftIO` target has an unconditional target dependency on `MeshIO`, so the heavy stack is unavoidable via either product, and there's no BREP/STEP-only surface to depend on instead. Floored at 1.7.5 rather than the bare 1.7.0 Tools needs because 1.7.5 is OCCTSwiftIO's own `TopologyGraph` -> `BRepGraph` rename (mirroring OCCTSwift 1.15.0's rename above), and 1.7.1-1.7.4 are pure OCCTSwift-floor repins for crash/hang fixes already required transitively via our own OCCTSwift >=1.15.0 floor.
- **macOS 15+**, **Swift 6.0+**.
