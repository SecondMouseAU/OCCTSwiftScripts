// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Prefer a local sibling checkout (../<name>) when present, else the published URL, so the whole
// OCCT ecosystem SHARES the single OCCTSwift/Libraries/OCCT.xcframework instead of each repo
// extracting its own 1.3 GB copy. CI / fresh clones (no sibling) use the URL pin. `#filePath`-relative
// so it's independent of build CWD.
// Only trust a sibling checkout when THIS manifest is a real local dev clone, never when this
// manifest is itself a transitively-resolved SwiftPM checkout under a consumer's `.build/`. SwiftPM
// lays every dependency's checkout out flat under one shared `.build/checkouts/` directory, so once
// e.g. `.build/checkouts/OCCTSwiftIO` exists, `../OCCTSwiftIO` relative to
// `.build/checkouts/OCCTSwiftScripts` spuriously "exists" too, flipping this manifest's own
// declaration from url to path *during* the resolution process that created that checkout. SwiftPM
// then sees a non-deterministic manifest and reports the whole graph unresolvable ("exhausted
// attempts to resolve the dependencies graph") for every lean consumer that pulls this package in
// transitively: the actual mechanism behind ecosystem issue #69, beyond the OCCTSwiftIO version cap.
// Same guard OCCTSwiftIO adopted (2026-06-23, "don't path-link siblings when resolved under a
// consumer's .build"), kept as `/.build/` here for consistency across the fleet.
private func isRealLocalSibling(_ manifestDir: String, _ name: String) -> Bool {
    guard !manifestDir.contains("/.build/") else { return false }
    return FileManager.default.fileExists(atPath: manifestDir + "/../\(name)/Package.swift")
}

func occtDep(_ name: String, from version: String) -> Package.Dependency {
    let manifestDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    if isRealLocalSibling(manifestDir, name) {
        return .package(path: "../\(name)")
    }
    return .package(url: "https://github.com/SecondMouseAU/\(name).git", from: Version(version)!)
}

let package = Package(
    name: "OCCTSwiftScripts",
    platforms: [
        .macOS(.v15),
        // iOS so the library products (DrawingComposer, ScriptHarness) link
        // into downstream iOS apps (e.g. OCCTSwiftPartsAgent's SwiftUI app).
        // Floored at v18 to match the sibling cohort (Viewport/Tools/AIS
        // are .iOS(.v18)); OCCTSwift itself only needs v15. The executable
        // targets (occtkit, Script, the legacy Graph* tools) shell out via
        // Foundation.Process and aren't iOS-buildable, but SPM only compiles
        // a target when something reachable requires it: an iOS app linking
        // a library product never pulls the executables in. See #52.
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "ScriptHarness",
            targets: ["ScriptHarness"]
        ),
        .library(
            name: "DrawingComposer",
            targets: ["DrawingComposer"]
        ),
        .executable(
            name: "occtkit",
            targets: ["occtkit"]
        ),
    ],
    dependencies: [
        // Floored at v1.7.1 = OCCT 8.0.0p1. v1.7.0 realigned BRepGraph to OCCT's
        // redesigned graph model (definitions vs references/usages, persistent
        // UIDs, controlled layers); v1.7.1 made the derived graph reads real
        // again: `adjacentFaces`/`faces(of:)`/`edges(of:)`/`sharedEdges`,
        // `faceSameDomain`, `faceIsNaturalRestriction`: plus durable
        // UID/RefUID/ItemUID accessors. Behaviour changes vs the old model are
        // confined to the BRepGraph domain (see OCCTSwift docs/CHANGELOG v1.7.0):
        // edgeMaxContinuity/setEdgeRegularity are now no-ops (use
        // Shape.maxContinuity); SameParameter/SameRange/Degenerated/IsClosed
        // setters no-op but getters return the live derived value. The cookbook
        // ergonomics relied on since v1.3.1 (circularPatternCut #169, sweep
        // orientation #170, concave/convex/edges(where:) #171) are unchanged.
        // 1.8.0 adds Exporter.writeBREP(allowInvalid:) for the load-brep /
        // import `--allow-invalid` flags (OCCTMCP #41).
        // Bumped 1.12.9 -> 1.15.0 (OCCTSwiftScripts#78): v1.15.0 renamed the
        // Swift wrapper class `TopologyGraph` -> `BRepGraph` (OCCTSwift#335) to
        // match the C++ package it wraps. This repo has migrated its own
        // `TopologyGraph` references to `BRepGraph`, and the bare `BRepGraph`
        // symbol doesn't exist before v1.15.0 (only the deprecated typealias
        // does, starting there): the floor must track the rename, not just
        // permit it via the open `from:` range.
        // Bumped 1.17.0 -> 2.0.0 (OCCTSwiftScripts#111): a correctness major (17 breaking
        // changes to the public Swift API, OCCT absorbed to 8.0.1), not a wrapping one. Fixed
        // in this repo alongside the bump:
        //   - ShapeAnalysisResult.selfIntersectionCount removed (#763; always 0, never
        //     computed). Heal.swift / GraphValidate.swift now report `hasSelfIntersection` /
        //     `selfIntersecting` as Bool? via the real `analyze(selfIntersectionTimeout:)`
        //     check, opt-in (nil "not checked" by default, since the check is ~3000x an
        //     ordinary scan on pathological input), rather than the fabricated always-0/always-false
        //     the removed field silently produced.
        //   - AAG builds nodes from face occurrences (#642): AAGNode.faceIndex /
        //     PocketFeature.floorFaceIndex/wallFaceIndices / detectHoles()'s faceIndex /
        //     AAGEdge.face1Index/face2Index now index Shape.orientedFaces(), not the
        //     Shape.faces() `face[N]` scheme query-topology emits (they agreed automatically
        //     pre-2.0.0, since faces() was itself occurrence-based then). FeatureRecognize.swift
        //     (both the occtkit command and the legacy standalone target), GraphSelect.swift,
        //     and GraphML.swift all cross-reference AAG output against that `face[N]` scheme
        //     and now resolve through the new `AAGNode.distinctFaceIndex` bridge; no-op on any
        //     shape that shares no face, which is every fixture this repo's tests used before
        //     Tests/OcctkitCommandTests/AAGFaceIndexTests.swift (added alongside this bump)
        //     started exercising a real shared-face compound.
        // See docs/SEMVER.md#v200 in the OCCTSwift repo for the full break table.
        // Bumped 2.0.0 -> 3.0.0 (OCCTSwiftScripts#118): a correctness/consolidation major, OCCT
        // stays at 8.0.1 (kernel rebuilt to carry two patches the v2.0.0 asset was missing).
        // Two breaks, both compile errors:
        //   - `Selector.SubShapeType.compsolid` renamed `.compSolid`, consolidating four drifted
        //     Swift mirrors of TopAbs_ShapeEnum onto `ShapeType`. Zero hits here: this repo
        //     already spelled it `ShapeType.compSolid` (LoadBrep.swift, Pattern.swift,
        //     RenderPreview.swift), which was already the surviving spelling.
        //   - `Shape.bounds`/`.size`/`.center`, `Wire.bounds`, `Edge.bounds`, `Face.bounds` (and
        //     `.exactBounds`, unused here) become Optional: they used to fabricate
        //     `(0,0,0)-(0,0,0)` for a shape with no bounding box, indistinguishable from a
        //     genuine zero-size shape at the origin. Every `.bounds` call site in this repo now
        //     unwraps: query-topology/load-brep/measure-distance/render-preview/metrics throw a
        //     named ScriptError on a nil bounding box (a real error for a loaded BREP, not a
        //     state to paper over); the two recipe edge-selector predicates return `false` (guard
        //     against a mid-selection nil rather than fabricate a match).
        // See docs/SEMVER.md#v300 in the OCCTSwift repo for the full break table.
        //
        // The rest of the cohort has not yet released an OCCTSwift-3.0.0-compatible version as of
        // this bump (OCCTSwiftTools/Mesh/IO's latest releases all still cap `from: "2.0.0"`,
        // i.e. `.upToNextMajor` excludes 3.0.0; OCCTSwiftAIS transitively via Tools). `from:` pins
        // below are unaffected by this bump directly, but a fresh clone / CI cannot resolve the
        // full graph until they catch up, same situation as the 2.0.0 bump (see git history on
        // this comment block). Local builds against sibling checkouts work today because path
        // dependencies bypass semver ranges entirely.
        occtDep("OCCTSwift", from: "3.0.0"),
        // RenderPreview rasterizes through Viewport's OffscreenRenderer.
        // Floored at v1.0.4: v1.0.3 fixes an uncatchable quantize() crash on
        // body load (Viewport #30) and v1.0.4 makes the published Viewport
        // package dependency-free (broke the Viewport↔Tools cycle).
        occtDep("OCCTSwiftViewport", from: "1.0.4"),
        // OCCTSwiftTools and OCCTSwiftAIS merged into one package, OCCTSwiftInteraction, alongside
        // OCCTSwiftCADKit (SecondMouseAU/ecosystem#42, ecosystem#43). The three old repos are
        // archived, not deleted (their tags still resolve), but every consumer is asked to repin
        // per OCCTSwiftInteraction's docs/MIGRATION.md (OCCTSwiftScripts#122). Module names are
        // unchanged: `import OCCTSwiftTools` / `import OCCTSwiftAIS` still work, since each stays
        // its own SwiftPM target inside the merged package, so only the `package:` label on each
        // product below changes, not the dependency names in code or this repo's `import` lines.
        // We don't use OCCTSwiftCADKit (the SwiftUI-assembled viewport service) or name its
        // product, so its target never enters this build.
        //
        // OCCTSwiftTools is the kernel-to-renderer bridge: CADFileLoader.shapeToBodyAndMetadata in
        // RenderPreview, which legitimately needs Viewport, so the dep stays. We don't separately
        // depend on OCCTSwiftIO's own product because OCCTSwiftIO's ScriptManifest is missing the
        // `graphs` field our local Sources/ScriptHarness/Manifest.swift carries, the
        // topology-graph descriptors that ScriptContext.addGraph() and addGraphsForAllShapes()
        // emit. Swapping would silently lose that metadata for downstream OCCTSwiftViewport
        // ScriptWatcher consumers. If a future verb wants progress-aware STEP loading via
        // OCCTSwiftIO's ShapeLoader.load(from:format:progress:), add the dep then.
        //
        // OCCTSwiftAIS is used here for the headless-friendly subset only, Trihedron / WorkPlane
        // / Axis / PointCloud scene objects (each emits ViewportBody arrays via makeBodies()) and
        // the SubShape <-> ViewportBody plumbing for highlight overlays. Selection / Manipulator /
        // SwiftUI surfaces aren't relevant to a CLI; Dimension overlays render via a SwiftUI
        // Canvas inside MetalViewportView and so don't reach OffscreenRenderer.
        occtDep("OCCTSwiftInteraction", from: "0.1.0"),
        // OCCTSwiftMesh v1.0.0 graduated alongside OCCTSwift v1.0.0. Powers
        // the `simplify-mesh` verb.
        occtDep("OCCTSwiftMesh", from: "1.0.0"),
        // OCCTSwiftIO v1.0.0 graduated alongside OCCTSwift v1.0.0. Provides
        // BRepGraph.exportForML / exportJSON via extension after OCCTSwift
        // v0.171.0 hoisted them out of the kernel. Pulled into GraphML and
        // graphml verbs only: the rest of the package keeps its existing
        // ScriptManifest type (with the `graphs` field) from ScriptHarness.
        //
        // Was capped to the 1.0.x minor line (occtDepUpToNextMinor(from: "1.0.0"),
        // #69) because OCCTSwiftIO 1.1.0+ folds in a MeshIO target (SwiftPMX /
        // SwiftX / ThreeMF / SwiftGLTF, plus SwiftJWW / SwiftDXF for 2D vector
        // formats) that lean consumers didn't want in the graph. Raised to an
        // open floor (OCCTSwiftScripts#80): OCCTSwiftTools >=1.6.1 now requires
        // OCCTSwiftIO >=1.7.0 directly, so any consumer depending on both
        // OCCTSwiftScripts and OCCTSwiftTools at once (e.g. OCCTMCP) hit an
        // unsatisfiable version conflict against our <1.1.0 cap. Checked
        // OCCTSwiftIO 1.7.5's Package.swift for a narrower product that could
        // keep the cap's spirit: it now ships two library products,
        // `OCCTSwiftIO` and `MeshIO`, but the `OCCTSwiftIO` target itself
        // still lists `MeshIO` as a plain (unconditional) target dependency:
        // not a product a consumer can decline. So depending on just the
        // `OCCTSwiftIO` product still resolves and checks out the full
        // SwiftPMX/SwiftX/ThreeMF/SwiftGLTF stack; there's no BREP/STEP-only
        // product to opt into instead. Floored at 1.7.5 rather than the bare
        // 1.7.0 Tools needs: 1.7.5 is OCCTSwiftIO's own TopologyGraph ->
        // BRepGraph rename (mirroring OCCTSwift's 1.15.0 rename above and
        // OCCTSwiftTools 1.6.1 / OCCTSwiftAIS 1.3.1's), and 1.7.1-1.7.4 are
        // pure OCCTSwift-floor repins for the same OCCT kernel crash/hang
        // fixes (#298/#310/#317/#318/#323) already required transitively via
        // our own OCCTSwift >=1.15.0 floor above, no reason to admit an
        // OCCTSwiftIO minor that predates fixes we already require elsewhere
        // in the graph.
        occtDep("OCCTSwiftIO", from: "1.7.5"),
    ],
    targets: [
        .target(
            name: "ScriptHarness",
            dependencies: [
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Sources/ScriptHarness",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "Script",
            dependencies: [
                "ScriptHarness",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Sources/Script",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "OCCTRunner",
            path: "Sources/OCCTRunner",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "GraphValidate",
            dependencies: [
                "ScriptHarness",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Sources/GraphValidate",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GraphCompact",
            dependencies: [
                "ScriptHarness",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Sources/GraphCompact",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GraphDedup",
            dependencies: [
                "ScriptHarness",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Sources/GraphDedup",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GraphQuery",
            dependencies: [
                "ScriptHarness",
            ],
            path: "Sources/GraphQuery",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "GraphML",
            dependencies: [
                "ScriptHarness",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
                .product(name: "OCCTSwiftIO", package: "OCCTSwiftIO"),
            ],
            path: "Sources/GraphML",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "FeatureRecognize",
            dependencies: [
                "ScriptHarness",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Sources/FeatureRecognize",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DrawingComposer",
            dependencies: [
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Sources/DrawingComposer",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "occtkit",
            dependencies: [
                "ScriptHarness",
                "DrawingComposer",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
                .product(name: "OCCTSwiftViewport", package: "OCCTSwiftViewport"),
                .product(name: "OCCTSwiftTools", package: "OCCTSwiftInteraction"),
                .product(name: "OCCTSwiftAIS", package: "OCCTSwiftInteraction"),
                .product(name: "OCCTSwiftMesh", package: "OCCTSwiftMesh"),
                .product(name: "OCCTSwiftIO", package: "OCCTSwiftIO"),
            ],
            path: "Sources/occtkit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DrawingComposerTests",
            dependencies: [
                "DrawingComposer",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Tests/DrawingComposerTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OcctkitCommandTests",
            dependencies: [
                "occtkit",
                "ScriptHarness",
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            path: "Tests/OcctkitCommandTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
