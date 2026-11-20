import FeatureStore
import Foundation
import GeoCore
import TrackMatching

/// Line networks of a map for tracks, kept so that a thousand tracks in one area do not read the same cells a thousand times.
///
/// The area of a track is widened by a margin and rounded outwards to a grid, so tracks in the same neighbourhood share one network.
/// The few networks that were used last are kept; a network is not small (every edge of the area), so the number is low.
public actor ActivityNetworks {
    private let source: any CellSource
    private let classes: Set<UInt8>
    private let margin: Double
    private let grid: Double
    private let capacity: Int
    private var kept: [(key: BoundingBox, network: LineNetwork)] = []

    /// Creates a provider.
    ///
    /// - Parameters:
    ///   - source: The map.
    ///   - classes: The feature classes that count as lines.
    ///   - margin: The distance, in metres, that the area of a track is widened by, so that lines just outside it can be matched.
    ///   - grid: The size in degrees to which the area is rounded outwards.
    ///   - capacity: How many networks are kept (at least 1).
    public init(
        source: any CellSource, classes: Set<UInt8> = LineNetwork.travelClasses, margin: Double = 300, grid: Double = 0.05, capacity: Int = 3
    ) {
        self.source = source
        self.classes = classes
        self.margin = max(margin, 0)
        self.grid = grid > 0 ? grid : 0.05
        self.capacity = max(capacity, 1)
    }

    /// The network for a track.
    ///
    /// - Parameter box: The box of the track.
    /// - Throws: ``LineNetworkError`` (a box that is too large to read), and the errors of the map.
    public func network(for box: BoundingBox) throws -> LineNetwork {
        let key = snapped(box)
        if let index = kept.firstIndex(where: { $0.key == key }) {
            let entry = kept.remove(at: index)
            kept.append(entry)
            return entry.network
        }
        let network = try LineNetwork(source: source, box: key, classes: classes)
        kept.append((key, network))
        if kept.count > capacity { kept.removeFirst(kept.count - capacity) }
        return network
    }

    /// The box widened by the margin and rounded outwards to the grid.
    private func snapped(_ box: BoundingBox) -> BoundingBox {
        let latitudeMargin = margin / 111_320
        let middle = (box.south + box.north) / 2
        let longitudeMargin = margin / (111_320 * max(cos(middle * .pi / 180), 0.05))
        func down(_ value: Double) -> Double { (value / grid).rounded(.down) * grid }
        func up(_ value: Double) -> Double { (value / grid).rounded(.up) * grid }
        return BoundingBox(
            south: max(down(box.south - latitudeMargin), -85), west: max(down(box.west - longitudeMargin), -180),
            north: min(up(box.north + latitudeMargin), 85), east: min(up(box.east + longitudeMargin), 180))
    }
}
