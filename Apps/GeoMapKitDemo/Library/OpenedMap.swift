import FeatureStore
import Foundation
import GeoCore

/// A map that is open: where its cells come from, where to look first, and the access to a linked folder, which is given back when
/// the map is closed.
final class OpenedMap: @unchecked Sendable {
    let id: String
    let source: any CellSource
    /// The middle of the map, and a zoom that shows it.
    let center: Coordinate
    let zoom: Double
    private let accessed: [URL]

    init(id: String, source: any CellSource, center: Coordinate, zoom: Double, accessed: [URL] = []) {
        self.id = id
        self.source = source
        self.center = center
        self.zoom = zoom
        self.accessed = accessed
    }

    deinit {
        for url in accessed { url.stopAccessingSecurityScopedResource() }
    }
}
