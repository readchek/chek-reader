// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
]

/// A format product: one target that depends on the core and nothing else.
func format(_ name: String) -> Target {
    .target(
        name: name,
        dependencies: ["ChekReaderCore"],
        swiftSettings: swiftSettings
    )
}

let package = Package(
    name: "ChekReader",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        // Everything an app needs for the formats in the default set.
        .library(name: "ChekReader", targets: ["ChekReader"]),

        // Pick-and-choose products. Apps that only need some formats
        // depend on these instead of the umbrella.
        .library(name: "ChekReaderCore", targets: ["ChekReaderCore"]),
        .library(name: "ChekReaderEPUB", targets: ["ChekReaderEPUB"]),
        .library(name: "ChekReaderPDF", targets: ["ChekReaderPDF"]),
        .library(name: "ChekReaderComics", targets: ["ChekReaderComics"]),
        .library(name: "ChekReaderText", targets: ["ChekReaderText"]),
        .library(name: "ChekReaderMOBI", targets: ["ChekReaderMOBI"]),
        .library(name: "ChekReaderFB2", targets: ["ChekReaderFB2"]),
        .library(name: "ChekReaderNavigator", targets: ["ChekReaderNavigator"]),
        .library(name: "ChekReaderUI", targets: ["ChekReaderUI"]),

        // Optional add-on. Not part of the umbrella, so apps that never
        // open CBR or CB7 never link it.
        .library(name: "ChekReaderArchives", targets: ["ChekReaderArchives"]),
    ],
    targets: [
        .target(name: "ChekReaderCore", swiftSettings: swiftSettings),

        format("ChekReaderEPUB"),
        format("ChekReaderPDF"),
        format("ChekReaderComics"),
        format("ChekReaderText"),
        format("ChekReaderMOBI"),
        format("ChekReaderFB2"),
        format("ChekReaderArchives"),

        .target(
            name: "ChekReaderNavigator",
            dependencies: ["ChekReaderCore"],
            // Compiled from Scripts/Reader; CI checks it matches the source.
            resources: [.copy("Resources/reader.js")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "ChekReaderUI",
            dependencies: ["ChekReaderCore", "ChekReaderNavigator"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "ChekReader",
            dependencies: [
                "ChekReaderCore",
                "ChekReaderEPUB",
                "ChekReaderPDF",
                "ChekReaderComics",
                "ChekReaderText",
                "ChekReaderMOBI",
                "ChekReaderFB2",
                "ChekReaderNavigator",
                "ChekReaderUI",
            ],
            swiftSettings: swiftSettings
        ),

        // Builds archives and books inside tests, so no fixtures are committed.
        .target(
            name: "ChekReaderTestSupport",
            dependencies: ["ChekReaderCore"],
            path: "Tests/ChekReaderTestSupport",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderCoreTests",
            dependencies: ["ChekReaderCore", "ChekReaderTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderEPUBTests",
            dependencies: ["ChekReaderCore", "ChekReaderEPUB", "ChekReaderTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderPDFTests",
            dependencies: ["ChekReaderCore", "ChekReaderPDF", "ChekReaderTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderComicsTests",
            dependencies: ["ChekReaderCore", "ChekReaderComics", "ChekReaderTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderTextTests",
            dependencies: ["ChekReaderCore", "ChekReaderText", "ChekReaderTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderFB2Tests",
            dependencies: ["ChekReaderCore", "ChekReaderFB2", "ChekReaderTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderNavigatorTests",
            dependencies: ["ChekReaderCore", "ChekReaderNavigator", "ChekReaderEPUB", "ChekReaderPDF", "ChekReaderComics", "ChekReaderTestSupport"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChekReaderTests",
            dependencies: ["ChekReader"],
            swiftSettings: swiftSettings
        ),
    ]
)
