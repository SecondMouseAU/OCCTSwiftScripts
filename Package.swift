// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Prefer a local sibling checkout (../<name>) when present, else the published URL — so the whole
// OCCT ecosystem SHARES the single OCCTSwift/Libraries/OCCT.xcframework instead of each repo
// extracting its own 1.3 GB copy. CI / fresh clones (no sibling) use the URL pin. `#filePath`-relative
// so it's independent of build CWD.
func occtDep(_ name: String, from version: String) -> Package.Dependency {
    let manifestDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    if FileManager.default.fileExists(atPath: manifestDir + "/../\(name)/Package.swift") {
        return .package(path: "../\(name)")
    }
    return .package(url: "https://github.com/gsdali/\(name).git", from: Version(version)!)
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
        // a target when something reachable requires it — an iOS app linking
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
        // again — `adjacentFaces`/`faces(of:)`/`edges(of:)`/`sharedEdges`,
        // `faceSameDomain`, `faceIsNaturalRestriction` — plus durable
        // UID/RefUID/ItemUID accessors. Behaviour changes vs the old model are
        // confined to the BRepGraph domain (see OCCTSwift docs/CHANGELOG v1.7.0):
        // edgeMaxContinuity/setEdgeRegularity are now no-ops (use
        // Shape.maxContinuity); SameParameter/SameRange/Degenerated/IsClosed
        // setters no-op but getters return the live derived value. The cookbook
        // ergonomics relied on since v1.3.1 (circularPatternCut #169, sweep
        // orientation #170, concave/convex/edges(where:) #171) are unchanged.
        // 1.8.0 adds Exporter.writeBREP(allowInvalid:) for the load-brep /
        // import `--allow-invalid` flags (OCCTMCP #41).
        occtDep("OCCTSwift", from: "1.8.0"),
        // RenderPreview rasterizes through Viewport's OffscreenRenderer.
        // Floored at v1.0.4: v1.0.3 fixes an uncatchable quantize() crash on
        // body load (Viewport #30) and v1.0.4 makes the published Viewport
        // package dependency-free (broke the Viewport↔Tools cycle).
        occtDep("OCCTSwiftViewport", from: "1.0.4"),
        // OCCTSwiftTools v1.0.0 graduated alongside OCCTSwift v1.0.0. We use
        // Tools for the bridge-layer CADFileLoader.shapeToBodyAndMetadata in
        // RenderPreview, which legitimately needs Viewport, so the Tools dep
        // stays. We don't separately depend on OCCTSwiftIO because
        // OCCTSwiftIO's ScriptManifest is missing the `graphs` field our
        // local Sources/ScriptHarness/Manifest.swift carries — the
        // topology-graph descriptors that ScriptContext.addGraph() and
        // addGraphsForAllShapes() emit. Swapping would silently lose that
        // metadata for downstream OCCTSwiftViewport ScriptWatcher consumers.
        // If a future verb wants progress-aware STEP loading via
        // OCCTSwiftIO's ShapeLoader.load(from:format:progress:), add the dep
        // then.
        occtDep("OCCTSwiftTools", from: "1.1.1"),
        // OCCTSwiftAIS v1.0.0 graduated alongside OCCTSwift v1.0.0. Used
        // here for the headless-friendly subset only — Trihedron / WorkPlane
        // / Axis / PointCloud scene objects (each emits ViewportBody arrays
        // via makeBodies()) and the SubShape ↔ ViewportBody plumbing for
        // highlight overlays. Selection / Manipulator / SwiftUI surfaces
        // aren't relevant to a CLI; Dimension overlays render via a SwiftUI
        // Canvas inside MetalViewportView and so don't reach OffscreenRenderer.
        occtDep("OCCTSwiftAIS", from: "1.0.2"),
        // OCCTSwiftMesh v1.0.0 graduated alongside OCCTSwift v1.0.0. Powers
        // the `simplify-mesh` verb.
        occtDep("OCCTSwiftMesh", from: "1.0.0"),
        // OCCTSwiftIO v1.0.0 graduated alongside OCCTSwift v1.0.0. Provides
        // TopologyGraph.exportForML / exportJSON via extension after OCCTSwift
        // v0.171.0 hoisted them out of the kernel. Pulled into GraphML and
        // graphml verbs only — the rest of the package keeps its existing
        // ScriptManifest type (with the `graphs` field) from ScriptHarness.
        occtDep("OCCTSwiftIO", from: "1.0.0"),
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
                .product(name: "OCCTSwiftTools", package: "OCCTSwiftTools"),
                .product(name: "OCCTSwiftAIS", package: "OCCTSwiftAIS"),
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
    ]
)
