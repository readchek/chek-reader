// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
]

/// libarchive, which the optional archives add-on links for CBR and CB7.
/// Apple platforms get it as a prebuilt static XCFramework from
/// Lakr233/libarchive.xcframework, which the Linux job can't use, so Linux
/// links the system library (`apt-get install libarchive-dev`).
#if os(Linux)
let libarchivePackages: [Package.Dependency] = []
let libarchiveTargets: [Target] = [
    .systemLibrary(name: "CLibArchive", pkgConfig: "libarchive", providers: [.apt(["libarchive-dev"])]),
]
let libarchive: Target.Dependency = "CLibArchive"
#else
let libarchivePackages: [Package.Dependency] = [
    .package(url: "https://github.com/Lakr233/libarchive.xcframework.git", exact: "1.0.1"),
]
let libarchiveTargets: [Target] = []
let libarchive: Target.Dependency = .product(name: "ArchiveKit", package: "libarchive.xcframework")
#endif

/// String Catalogs compile on Apple platforms only. SwiftPM on Linux has no
/// rule for them, so they're left out there rather than warned about.
#if os(Linux)
let catalogExclusions = ["Resources/Localizable.xcstrings"]
let catalogResources: [Resource] = []
#else
let catalogExclusions: [String] = []
let catalogResources: [Resource] = [.process("Resources/Localizable.xcstrings")]
#endif

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
    dependencies: libarchivePackages,
    targets: libarchiveTargets + [
        .target(name: "ChekReaderCore", swiftSettings: swiftSettings),

        format("ChekReaderEPUB"),
        format("ChekReaderPDF"),
        format("ChekReaderComics"),
        format("ChekReaderText"),
        format("ChekReaderMOBI"),
        format("ChekReaderFB2"),
        .target(
            name: "ChekReaderArchives",
            dependencies: ["ChekReaderCore", "ChekReaderComics", libarchive],
            swiftSettings: swiftSettings
        ),

        .target(
            name: "ChekReaderNavigator",
            dependencies: ["ChekReaderCore"],
            // Compiled from Scripts/Reader; CI checks it matches the source.
            exclude: catalogExclusions,
            resources: [.copy("Resources/reader.js")] + catalogResources,
            swiftSettings: swiftSettings
        ),
        .target(
            name: "ChekReaderUI",
            dependencies: ["ChekReaderCore", "ChekReaderNavigator"],
            exclude: catalogExclusions,
            resources: catalogResources,
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
            name: "ChekReaderArchivesTests",
            dependencies: ["ChekReaderCore", "ChekReaderArchives", "ChekReaderTestSupport", libarchive],
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
            name: "ChekReaderMOBITests",
            dependencies: ["ChekReaderCore", "ChekReaderMOBI", "ChekReaderTestSupport"],
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
