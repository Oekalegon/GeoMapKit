import FeatureStore
import Foundation
import GeoCore
@testable import MapLibrary

/// Small files for the map tests.
enum MapTestSupport {
    /// The area the test maps cover: around Vaduz.
    static let area = BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7)

    /// A new empty folder in the temporary directory.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-maps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A valid, empty store file covering `box`, written to `folder`.
    @discardableResult
    static func storeFile(named name: String = "vaduz.gmk", in folder: URL, box: BoundingBox = area) throws -> URL {
        let writer = FeatureStoreWriter(boundingBox: box, attribution: "© OpenStreetMap contributors, ODbL")
        let url = folder.appendingPathComponent(name)
        try writer.write(to: url)
        return url
    }

    /// A library in a new folder, with its own defaults so the tests don't share a selection.
    @MainActor
    static func library() throws -> (MapLibrary, URL) {
        let root = try folder()
        let defaults = UserDefaults(suiteName: "geomapkit-maps-\(UUID().uuidString)")!
        return (MapLibrary(root: root, defaults: defaults), root)
    }
}
