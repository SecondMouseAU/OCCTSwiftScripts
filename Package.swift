// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OCCTSwiftScripts",
    platforms: [
        .macOS(.v15)
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
        // OCCTSwift v1.0.0 pins to OCCT 8.0.0 GA (2026-05-07). v1.0.1 ships
        // the TopologyGraph.NodeKind fix (Product/Occurrence raw values were
        // missing, so rootNodes silently returned [] for any graph with
        // assembly roots). SemVer-stable from this floor.
        .package(url: "https://github.com/gsdali/OCCTSwift.git", from: "1.0.3"),
        // RenderPreview rasterizes through Viewport's OffscreenRenderer.
        // Floored at v1.0.4: v1.0.3 fixes an uncatchable quantize() crash on
        // body load (Viewport #30) and v1.0.4 makes the published Viewport
        // package dependency-free (broke the Viewport↔Tools cycle).
        .package(url: "https://github.com/gsdali/OCCTSwiftViewport.git", from: "1.0.4"),
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
        .package(url: "https://github.com/gsdali/OCCTSwiftTools.git", from: "1.1.1"),
        // OCCTSwiftAIS v1.0.0 graduated alongside OCCTSwift v1.0.0. Used
        // here for the headless-friendly subset only — Trihedron / WorkPlane
        // / Axis / PointCloud scene objects (each emits ViewportBody arrays
        // via makeBodies()) and the SubShape ↔ ViewportBody plumbing for
        // highlight overlays. Selection / Manipulator / SwiftUI surfaces
        // aren't relevant to a CLI; Dimension overlays render via a SwiftUI
        // Canvas inside MetalViewportView and so don't reach OffscreenRenderer.
        .package(url: "https://github.com/gsdali/OCCTSwiftAIS.git", from: "1.0.2"),
        // OCCTSwiftMesh v1.0.0 graduated alongside OCCTSwift v1.0.0. Powers
        // the `simplify-mesh` verb.
        .package(url: "https://github.com/gsdali/OCCTSwiftMesh.git", from: "1.0.0"),
        // OCCTSwiftIO v1.0.0 graduated alongside OCCTSwift v1.0.0. Provides
        // TopologyGraph.exportForML / exportJSON via extension after OCCTSwift
        // v0.171.0 hoisted them out of the kernel. Pulled into GraphML and
        // graphml verbs only — the rest of the package keeps its existing
        // ScriptManifest type (with the `graphs` field) from ScriptHarness.
        .package(url: "https://github.com/gsdali/OCCTSwiftIO.git", from: "1.0.0"),
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
    ]
)
