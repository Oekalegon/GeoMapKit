// swift-tools-version: 6.2

import PackageDescription

// Command-line tools for GeoMapKit. A separate package so the executable never
// becomes part of the library's watchOS/iOS builds.

let package = Package(
    name: "GeoMapKitTools",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "..")],
    targets: [
        // Argument parsing and formatting, kept apart from the executable so it can be tested.
        .target(
            name: "ToolSupport",
            dependencies: [.product(name: "GeoCore", package: "GeoMapKit"), .product(name: "MapBuilder", package: "GeoMapKit")]
        ),
        // The commands: they run the library and return reports, so they can be tested.
        .target(
            name: "ToolCommands",
            dependencies: [
                "ToolSupport",
                .product(name: "OSMPBF", package: "GeoMapKit"),
                .product(name: "GeoCore", package: "GeoMapKit"),
                .product(name: "FeatureStore", package: "GeoMapKit"),
                .product(name: "FeatureStoreBuilder", package: "GeoMapKit"),
                .product(name: "MapStyle", package: "GeoMapKit"),
                .product(name: "MapRender", package: "GeoMapKit"),
                .product(name: "Regions", package: "GeoMapKit"),
                .product(name: "MapBuilder", package: "GeoMapKit"),
                .product(name: "Tracks", package: "GeoMapKit"),
            ]
        ),
        // A Mac test app for MapView: swift run mapviewer [file.gmk].
        .executableTarget(
            name: "mapviewer",
            dependencies: [
                .product(name: "GeoCore", package: "GeoMapKit"), .product(name: "FeatureStore", package: "GeoMapKit"),
                .product(name: "MapStyle", package: "GeoMapKit"), .product(name: "MapUI", package: "GeoMapKit"),
                .product(name: "MapRender", package: "GeoMapKit"), .product(name: "FeatureStoreBuilder", package: "GeoMapKit"),
            ]
        ),
        // A thin executable: parse the command line, call ToolCommands, print.
        .executableTarget(
            name: "geomapkit",
            dependencies: [
                "ToolSupport", "ToolCommands", .product(name: "FeatureStoreBuilder", package: "GeoMapKit"), .product(name: "Regions", package: "GeoMapKit"),
                .product(name: "GeoCore", package: "GeoMapKit"),
            ]
        ),
        .testTarget(name: "ToolSupportTests", dependencies: ["ToolSupport", .product(name: "GeoCore", package: "GeoMapKit")]),
        .testTarget(
            name: "ToolCommandsTests",
            dependencies: [
                "ToolCommands", .product(name: "OSMPBF", package: "GeoMapKit"), .product(name: "GeoCore", package: "GeoMapKit"),
                .product(name: "FeatureStore", package: "GeoMapKit"), .product(name: "FeatureStoreBuilder", package: "GeoMapKit"), .product(name: "MapStyle", package: "GeoMapKit"),
                .product(name: "Regions", package: "GeoMapKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
