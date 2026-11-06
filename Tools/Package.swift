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
            dependencies: [.product(name: "GeoCore", package: "GeoMapKit")]
        ),
        .executableTarget(
            name: "geomapkit",
            dependencies: [
                "ToolSupport",
                .product(name: "OSMPBF", package: "GeoMapKit"),
                .product(name: "GeoCore", package: "GeoMapKit"),
            ]
        ),
        .testTarget(name: "ToolSupportTests", dependencies: ["ToolSupport", .product(name: "GeoCore", package: "GeoMapKit")]),
    ],
    swiftLanguageModes: [.v6]
)
