import FeatureStore
import Foundation
import GeoCore

/// The cut of a Watch copy of the open map, around the middle of the view.
enum WatchCut {
    /// The box of a square around a position.
    ///
    /// - Parameters:
    ///   - center: The middle.
    ///   - kilometres: The side of the square in kilometres (a degree of latitude is 111.32 km; a degree of longitude is
    ///     shorter by the cosine of the latitude).
    static func area(around center: Coordinate, kilometres: Double) -> BoundingBox {
        let latitudeHalf = kilometres / 2 / 111.32
        let longitudeHalf = latitudeHalf / max(cos(center.latitude * .pi / 180), 0.01)
        return BoundingBox(
            south: max(center.latitude - latitudeHalf, -85), west: max(center.longitude - longitudeHalf, -180),
            north: min(center.latitude + latitudeHalf, 85), east: min(center.longitude + longitudeHalf, 179.999))
    }

    /// Cuts the copy to a file in the temporary folder, ready to be added to the library. Reads and writes files: not for the main thread.
    ///
    /// - Returns: The file and what the cut came to.
    /// - Throws: ``RegionCutError``.
    static func cut(source: any CellSource, named name: String, around center: Coordinate, kilometres: Double) throws -> (url: URL, report: CutReport) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("watch-cut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name) Watch \(Int(kilometres)) km.gmk")
        let report = try RegionCutter(source: source).cut(area: area(around: center, kilometres: kilometres), to: url)
        return (url, report)
    }

    /// A sentence for a cut that failed.
    static func sentence(for error: Error) -> String {
        switch error as? RegionCutError {
        case .tooLarge(let cells, let limit): "That area is too large for the Watch: \(cells) cells, the limit is \(limit)."
        case .emptyArea: "The map has nothing for the Watch in this area. Move the map to where it has data."
        case .invalidArea: "That area is not valid."
        case .store(let inner): "The map could not be read or written: \(inner)"
        case nil: error.localizedDescription
        }
    }
}
