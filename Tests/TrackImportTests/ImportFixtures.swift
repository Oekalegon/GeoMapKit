import FeatureStore
import Foundation
import GeoCore
import Testing

@testable import FeatureStoreBuilder

/// A small map and GPX files for the tests of the batch importer.
enum ImportFixtures {
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// A map with one path of about 560 m along 60° N, from 10.0° E to 10.01° E, in one cell.
    static func map() throws -> FeatureStoreFile {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 59.9, west: 9.9, north: 60.1, east: 10.1), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 60.0, longitude: 10.005), zoom: 13))
        try writer.add(
            StoredFeature(
                classID: FeatureClass.path.rawValue, kind: .line, objectType: .way, objectID: 7,
                parts: [GeometryPart(points: [PackedPoint(longitude: 100_000_000, latitude: 600_000_000), PackedPoint(longitude: 100_100_000, latitude: 600_000_000)])]),
            band: .detail, cell: cell)
        return try FeatureStoreFile(data: try writer.data())
    }

    /// A GPX file along the path, a fix about every 11 m, 4 s apart, the first `first` seconds after `start`.
    static func gpx(name: String, first: Double = 0, timed: Bool = true, east: ClosedRange<Double> = 0...100) -> String {
        let count = Int((east.upperBound - east.lowerBound) * 5.6 / 11)
        let formatter = ISO8601DateFormatter()
        let points = (0...count).map { index -> String in
            let longitude = 10 + (east.lowerBound + (east.upperBound - east.lowerBound) * Double(index) / Double(count)) * 0.0001
            let time = timed ? "<time>\(formatter.string(from: start.addingTimeInterval(first + Double(index) * 4)))</time>" : ""
            return "<trkpt lat=\"60.0\" lon=\"\(longitude)\">\(time)</trkpt>"
        }
        return "<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"test\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(name)</name><trkseg>\(points.joined())</trkseg></trk></gpx>"
    }

    /// A folder with files, and the folder's cleanup is the caller's.
    static func folder(_ files: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        return directory
    }
}
