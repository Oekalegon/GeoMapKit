// swift-tools-version: 6.2

import PackageDescription

// GeoMapKit v1 scope: map rendering only (see docs/design/architecture.md).
// Every library target must build for iOS, iPadOS, macOS and watchOS.
// Routing and tracks are added in later versions.

let package = Package(
    name: "GeoMapKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .watchOS(.v26),
    ],
    products: [
        .library(name: "GeoCore", targets: ["GeoCore"]),
        .library(name: "OSMPBF", targets: ["OSMPBF"]),
        .library(name: "FeatureStore", targets: ["FeatureStore"]),
        .library(name: "MapStyle", targets: ["MapStyle"]),
        .library(name: "MapRender", targets: ["MapRender"]),
        .library(name: "Regions", targets: ["Regions"]),
    ],
    targets: [
        // Web Mercator maths, tile coordinates, geometry.
        .target(name: "GeoCore"),

        // PBF reader, area cutting, OSMDataSource.
        .target(name: "OSMPBF", dependencies: ["GeoCore"]),

        // Own spatially gridded feature store: writer, memory-mapped reader.
        .target(name: "FeatureStore", dependencies: ["GeoCore"]),

        // Style model with zoom-dependent values.
        .target(name: "MapStyle"),

        // Renderer protocol and the Canvas / Core Graphics backend.
        .target(name: "MapRender", dependencies: ["GeoCore", "FeatureStore", "MapStyle"]),

        // Region manifest, downloads, attribution.
        .target(name: "Regions", dependencies: ["GeoCore", "FeatureStore"]),

        .testTarget(name: "GeoCoreTests", dependencies: ["GeoCore"]),
    ],
    swiftLanguageModes: [.v6]
)
