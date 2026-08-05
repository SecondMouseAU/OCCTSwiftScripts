// swift-tools-version: 6.0
import PackageDescription

// Minimal standalone repro for OCCTSwiftScripts#108 / OCCTSwift#702: depends
// only on OCCTSwift, pinned to the exact version the parent repo's
// Package.resolved is pinned to (1.17.0), so this reproduces on the same
// build the parent spike measured against.
let package = Package(
    name: "ThruSectionsSaddleRepro",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/SecondMouseAU/OCCTSwift.git", exact: "1.17.0")
    ],
    targets: [
        .executableTarget(
            name: "ThruSectionsSaddleRepro",
            dependencies: [
                .product(name: "OCCTSwift", package: "OCCTSwift")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
